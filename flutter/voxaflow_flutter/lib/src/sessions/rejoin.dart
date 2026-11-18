// Meet-style auto-rejoin (shared semantics on all 5 platforms — see CONTRACT.md "Auto-rejoin").
//
// When a call drops for a reason that isn't an intentional end (phone locked / app backgrounded,
// network lost, media node restarted), the session does a FRESH join — new token, connect, restore
// the user's current mic/cam — with backoff, waiting until the app is in the foreground, and waking
// early when the app resumes or `rejoinNow()` is called. Gives up after 10 minutes of continuous
// failure → `disconnected`.
//
// Network-online detection: Flutter has no built-in connectivity signal (that needs the
// connectivity_plus plugin, which we don't force on hosts). Offline attempts fail fast at the token
// fetch, so the loop still converges; apps that already use connectivity_plus can call
// `session.rejoinNow()` when connectivity returns to retry instantly.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart' show DisconnectReason;

import '../models/models.dart' show VoxaConnectionState;

/// Disconnects that mean "this call is over for you" — never rejoin.
/// (livekit_client 2.x has no separate roomClosed; roomDeleted covers it.)
const _terminalReasons = {
  DisconnectReason.clientInitiated, // the user left / end() was called
  DisconnectReason.duplicateIdentity, // joined again from another device
  DisconnectReason.participantRemoved, // removed by the agent/host
  DisconnectReason.roomDeleted, // call ended / room closed
};

bool shouldAutoRejoin(DisconnectReason? reason) => reason == null || !_terminalReasons.contains(reason);

/// Wait before attempt i (0-based). The last value repeats forever.
const rejoinDelaysMs = [500, 2000, 5000, 10000, 20000, 30000];

/// Stop auto-retrying after this long of continuous failure.
const rejoinGiveUp = Duration(minutes: 10);

Duration rejoinDelay(int attemptIndex) =>
    Duration(milliseconds: rejoinDelaysMs[attemptIndex < rejoinDelaysMs.length ? attemptIndex : rejoinDelaysMs.length - 1]);

enum RejoinOutcome { joined, gaveUp, cancelled }

/// The pure loop. [sleep] may resolve early (see [Waker]); [waitReady] resolves once the app is
/// in the foreground.
Future<RejoinOutcome> runRejoinLoop({
  required Future<void> Function() join,
  required Future<void> Function(Duration) sleep,
  required Future<void> Function() waitReady,
  required bool Function() cancelled,
  DateTime Function()? now,
  void Function(int attempt, Duration delay)? onAttempt,
  Duration Function(int attemptIndex) delayFor = rejoinDelay,
  Duration giveUpAfter = rejoinGiveUp,
}) async {
  final clock = now ?? DateTime.now;
  final start = clock();
  for (var i = 0;; i++) {
    if (cancelled()) return RejoinOutcome.cancelled;
    await sleep(delayFor(i));
    if (cancelled()) return RejoinOutcome.cancelled;
    await waitReady();
    if (cancelled()) return RejoinOutcome.cancelled;
    // Reported right before the try; the delay is the wait before the next try if this one fails.
    onAttempt?.call(i + 1, delayFor(i + 1));
    try {
      await join();
      return cancelled() ? RejoinOutcome.cancelled : RejoinOutcome.joined;
    } catch (_) {
      if (cancelled()) return RejoinOutcome.cancelled;
      if (clock().difference(start) >= giveUpAfter) return RejoinOutcome.gaveUp;
    }
  }
}

/// A sleep that [wake] can cut short — wired to app-resume and rejoinNow().
class Waker {
  final _pending = <Completer<void>>{};

  Future<void> sleep(Duration d) {
    final c = Completer<void>();
    _pending.add(c);
    final t = Timer(d, () {
      if (_pending.remove(c)) c.complete();
    });
    return c.future.whenComplete(t.cancel);
  }

  /// Resolves on the next [wake].
  Future<void> next() {
    final c = Completer<void>();
    _pending.add(c);
    return c.future;
  }

  void wake() {
    final all = [..._pending];
    _pending.clear();
    for (final c in all) {
      if (!c.isCompleted) c.complete();
    }
  }
}

/// "Can we attempt now?" — foreground (and online, where the platform can tell).
abstract class RejoinReadiness {
  bool get isReady;
  Future<void> waitReady();
  void dispose();
}

/// Foreground readiness from the Flutter app lifecycle; resuming wakes the [Waker].
class LifecycleReadiness with WidgetsBindingObserver implements RejoinReadiness {
  LifecycleReadiness(this._waker) {
    WidgetsBinding.instance.addObserver(this);
  }
  final Waker _waker;

  @override
  bool get isReady {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _waker.wake();
  }

  @override
  Future<void> waitReady() async {
    while (!isReady) {
      await _waker.next();
    }
  }

  @override
  void dispose() => WidgetsBinding.instance.removeObserver(this);
}

/// An auto-rejoin try is starting ([attempt], 1-based); if it fails the next comes [nextDelay] later.
class VoxaRejoinAttempt {
  const VoxaRejoinAttempt(this.attempt, this.nextDelay);
  final int attempt;
  final Duration nextDelay;
  @override
  String toString() => 'VoxaRejoinAttempt($attempt, $nextDelay)';
}

/// The session-side state machine (LiveKit-free so it's unit-tested). RtcSession feeds it room
/// events and supplies [join] (fresh token → connect → restore mic/cam).
class RejoinController {
  RejoinController({
    required Future<void> Function() join,
    required void Function() onRejoined,
    RejoinReadiness? readiness,
    Waker? waker,
    this.autoRejoin = true,
    Duration Function(int)? delayFor,
    Duration? giveUpAfter,
  })  : _join = join,
        _onRejoined = onRejoined,
        _waker = waker ?? Waker(),
        _delayFor = delayFor ?? rejoinDelay,
        _giveUpAfter = giveUpAfter ?? rejoinGiveUp {
    _readiness = readiness;
  }

  final Future<void> Function() _join;
  final void Function() _onRejoined;
  final Waker _waker;
  final bool autoRejoin;
  final Duration Function(int) _delayFor;
  final Duration _giveUpAfter;
  RejoinReadiness? _readiness;

  final _states = StreamController<VoxaConnectionState>.broadcast(sync: true);
  final _attempts = StreamController<VoxaRejoinAttempt>.broadcast(sync: true);
  VoxaConnectionState _state = VoxaConnectionState.connected;
  bool _ended = false;
  bool _rejoining = false;
  int _attempt = 0;

  /// 1-based number of the current auto-rejoin try (0 when not rejoining).
  int get attempt => _attempt;

  Stream<VoxaConnectionState> get states => _states.stream;
  Stream<VoxaRejoinAttempt> get attempts => _attempts.stream;
  VoxaConnectionState get state => _state;

  void _set(VoxaConnectionState s) {
    if (_state == s) return;
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  void onReconnecting() => _set(VoxaConnectionState.reconnecting);
  void onReconnected() => _set(VoxaConnectionState.connected);

  Future<void> onDisconnected(DisconnectReason? reason) async {
    if (_ended || _rejoining) return;
    if (!autoRejoin || !shouldAutoRejoin(reason)) {
      _set(VoxaConnectionState.disconnected);
      return;
    }
    await _start();
  }

  /// Retry now: cut the current wait short, or restart after give-up. No-op while connected.
  void rejoinNow() {
    if (_ended) return;
    if (_rejoining) {
      _waker.wake();
    } else if (_state == VoxaConnectionState.disconnected) {
      unawaited(_start());
    }
  }

  /// The user left — stop any loop for good.
  void cancel() {
    _ended = true;
    _waker.wake();
    _readiness?.dispose();
    _set(VoxaConnectionState.disconnected);
  }

  Future<void> dispose() async {
    cancel();
    await _states.close();
    await _attempts.close();
  }

  Future<void> _start() async {
    if (_ended || _rejoining) return;
    _rejoining = true;
    _attempt = 0;
    _set(VoxaConnectionState.reconnecting);
    _readiness ??= LifecycleReadiness(_waker);
    final outcome = await runRejoinLoop(
      join: _join,
      sleep: _waker.sleep,
      waitReady: _readiness!.waitReady,
      cancelled: () => _ended,
      delayFor: _delayFor,
      giveUpAfter: _giveUpAfter,
      onAttempt: (a, d) {
        _attempt = a;
        if (!_attempts.isClosed) _attempts.add(VoxaRejoinAttempt(a, d));
      },
    );
    _rejoining = false;
    _attempt = 0;
    if (outcome == RejoinOutcome.joined) {
      _onRejoined();
      _set(VoxaConnectionState.connected);
    } else if (outcome == RejoinOutcome.gaveUp) {
      _set(VoxaConnectionState.disconnected);
    }
  }
}
