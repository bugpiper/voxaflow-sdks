// Meet-style auto-rejoin — pure logic (no LiveKit media). Mirrors web-core test/rejoin.test.ts
// + test/session.test.ts so all platforms pin the same semantics (CONTRACT.md "Auto-rejoin").

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' show DisconnectReason;
import 'package:voxaflow_flutter/src/sessions/rejoin.dart';
import 'package:voxaflow_flutter/voxaflow_flutter.dart' show VoxaConnectionState;

/// Fake clock: sleep advances time instantly.
class FakeClock {
  Duration t = Duration.zero;
  final slept = <Duration>[];
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(t.inMilliseconds);
  Future<void> sleep(Duration d) async {
    slept.add(d);
    t += d;
  }
}

/// Readiness the test controls.
class FakeReadiness implements RejoinReadiness {
  FakeReadiness({this.ready = true});
  bool ready;
  final _waiters = <Completer<void>>[];
  @override
  bool get isReady => ready;
  @override
  Future<void> waitReady() async {
    while (!ready) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
  }

  void becomeReady() {
    ready = true;
    for (final c in [..._waiters]) {
      c.complete();
    }
    _waiters.clear();
  }

  @override
  void dispose() {}
}

Future<void> pump([int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('shouldAutoRejoin', () {
    test('rejoins after connection/network loss', () {
      for (final r in [
        null,
        DisconnectReason.unknown,
        DisconnectReason.serverShutdown,
        DisconnectReason.stateMismatch,
        DisconnectReason.joinFailure,
        DisconnectReason.disconnected,
        DisconnectReason.signalingConnectionFailure,
        DisconnectReason.reconnectAttemptsExceeded,
      ]) {
        expect(shouldAutoRejoin(r), isTrue, reason: '$r');
      }
    });
    test('never rejoins an intentional end', () {
      for (final r in [
        DisconnectReason.clientInitiated,
        DisconnectReason.duplicateIdentity,
        DisconnectReason.participantRemoved,
        DisconnectReason.roomDeleted,
      ]) {
        expect(shouldAutoRejoin(r), isFalse, reason: '$r');
      }
    });
  });

  test('rejoinDelay: schedule then 30s forever', () {
    expect(rejoinDelaysMs, [500, 2000, 5000, 10000, 20000, 30000]);
    expect([0, 1, 2, 3, 4, 5, 6, 50].map((i) => rejoinDelay(i).inMilliseconds).toList(),
        [500, 2000, 5000, 10000, 20000, 30000, 30000, 30000]);
    expect(rejoinGiveUp, const Duration(minutes: 10));
  });

  group('runRejoinLoop', () {
    test('first attempt succeeds → joined', () async {
      final c = FakeClock();
      var joins = 0;
      final r = await runRejoinLoop(
          join: () async => joins++, sleep: c.sleep, waitReady: () async {}, cancelled: () => false, now: c.now);
      expect(r, RejoinOutcome.joined);
      expect(joins, 1);
    });

    test('retries on the schedule, reporting each attempt', () async {
      final c = FakeClock();
      var joins = 0;
      final attempts = <List<int>>[];
      final r = await runRejoinLoop(
        join: () async {
          if (++joins < 3) throw Exception('net');
        },
        sleep: c.sleep,
        waitReady: () async {},
        cancelled: () => false,
        now: c.now,
        onAttempt: (a, d) => attempts.add([a, d.inMilliseconds]),
      );
      expect(r, RejoinOutcome.joined);
      expect(c.slept.map((d) => d.inMilliseconds), [500, 2000, 5000]);
      expect(attempts, [
        [1, 500],
        [2, 2000],
        [3, 5000]
      ]);
    });

    test('keeps trying 30s apart and gives up only after 10 minutes', () async {
      final c = FakeClock();
      var joins = 0;
      final r = await runRejoinLoop(
        join: () async {
          joins++;
          throw Exception('down');
        },
        sleep: c.sleep,
        waitReady: () async {},
        cancelled: () => false,
        now: c.now,
      );
      expect(r, RejoinOutcome.gaveUp);
      expect(c.t >= rejoinGiveUp, isTrue);
      expect(c.t < rejoinGiveUp + const Duration(seconds: 30), isTrue);
      expect(joins > rejoinDelaysMs.length, isTrue);
    });

    test('waits for readiness before every attempt', () async {
      final c = FakeClock();
      final order = <String>[];
      await runRejoinLoop(
        join: () async => order.add('join'),
        sleep: c.sleep,
        waitReady: () async => order.add('ready'),
        cancelled: () => false,
        now: c.now,
      );
      expect(order, ['ready', 'join']);
    });

    test('stops once cancelled (user left)', () async {
      final c = FakeClock();
      var left = false;
      var joins = 0;
      final r = await runRejoinLoop(
        join: () async {
          joins++;
          left = true;
          throw Exception('x');
        },
        sleep: c.sleep,
        waitReady: () async {},
        cancelled: () => left,
        now: c.now,
      );
      expect(r, RejoinOutcome.cancelled);
      expect(joins, 1);
    });
  });

  group('Waker', () {
    test('sleep resolves on the timer', () async {
      final w = Waker();
      var done = false;
      unawaited(w.sleep(const Duration(milliseconds: 30)).then((_) => done = true));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(done, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(done, isTrue);
    });
    test('wake() cuts a pending sleep short', () async {
      final w = Waker();
      var done = false;
      unawaited(w.sleep(const Duration(seconds: 30)).then((_) => done = true));
      w.wake();
      await pump();
      expect(done, isTrue);
    });
  });

  group('RejoinController', () {
    late int joins;
    late int failNext;
    late int rejoined;
    late FakeReadiness readiness;

    RejoinController make({bool autoRejoin = true, Duration Function(int)? delay}) {
      joins = 0;
      failNext = 0;
      rejoined = 0;
      readiness = FakeReadiness();
      return RejoinController(
        join: () async {
          joins++;
          if (failNext > 0) {
            failNext--;
            throw Exception('offline');
          }
        },
        onRejoined: () => rejoined++,
        readiness: readiness,
        autoRejoin: autoRejoin,
        // Compress the schedule so tests run in real time: 1ms per scheduled second.
        delayFor: delay ?? (i) => Duration(microseconds: rejoinDelay(i).inMilliseconds),
        giveUpAfter: const Duration(milliseconds: 200),
      );
    }

    test('unexpected drop → reconnecting → fresh join → connected (+ realtime re-subscribed)', () async {
      final c = make();
      final states = <VoxaConnectionState>[];
      c.states.listen(states.add);
      await c.onDisconnected(DisconnectReason.signalingConnectionFailure);
      await pump();
      expect(states, [VoxaConnectionState.reconnecting, VoxaConnectionState.connected]);
      expect(joins, 1);
      expect(rejoined, 1);
    });

    test('intentional end → disconnected, no rejoin', () async {
      for (final r in [DisconnectReason.clientInitiated, DisconnectReason.roomDeleted]) {
        final c = make();
        await c.onDisconnected(r);
        await pump();
        expect(c.state, VoxaConnectionState.disconnected);
        expect(joins, 0);
      }
    });

    test('autoRejoin:false → disconnected on any drop', () async {
      final c = make(autoRejoin: false);
      await c.onDisconnected(DisconnectReason.signalingConnectionFailure);
      expect(c.state, VoxaConnectionState.disconnected);
      expect(joins, 0);
    });

    test('LiveKit\'s own short resume maps to reconnecting → connected', () {
      final c = make();
      c.onReconnecting();
      expect(c.state, VoxaConnectionState.reconnecting);
      c.onReconnected();
      expect(c.state, VoxaConnectionState.connected);
    });

    test('waits while not ready (backgrounded) and attempts once foregrounded', () async {
      final c = make();
      readiness.ready = false;
      unawaited(c.onDisconnected(DisconnectReason.unknown));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(joins, 0);
      readiness.becomeReady();
      await pump();
      expect(joins, 1);
      expect(c.state, VoxaConnectionState.connected);
    });

    test('rejoinNow() cuts the back-off wait short', () async {
      final c = make(delay: (_) => const Duration(seconds: 30));
      failNext = 0;
      unawaited(c.onDisconnected(DisconnectReason.unknown));
      await pump();
      expect(joins, 0); // still waiting 30s
      c.rejoinNow();
      await pump();
      expect(joins, 1);
      expect(c.state, VoxaConnectionState.connected);
    });

    test('gives up → disconnected; rejoinNow() then starts a new loop', () async {
      final c = make();
      failNext = 1 << 30;
      await c.onDisconnected(DisconnectReason.unknown);
      expect(c.state, VoxaConnectionState.disconnected);
      final n = joins;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(joins, n); // really stopped
      failNext = 0;
      c.rejoinNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.state, VoxaConnectionState.connected);
    });

    test('cancel() (end/leave) during the loop stops it', () async {
      final c = make();
      failNext = 1 << 30;
      unawaited(c.onDisconnected(DisconnectReason.unknown));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      c.cancel();
      final n = joins;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(joins, n);
      expect(c.state, VoxaConnectionState.disconnected);
    });
  });

  testWidgets('LifecycleReadiness: not ready when paused; resume wakes the waker', (tester) async {
    final w = Waker();
    final r = LifecycleReadiness(w);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(r.isReady, isFalse);
    var woke = false;
    unawaited(w.sleep(const Duration(hours: 1)).then((_) => woke = true));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(r.isReady, isTrue);
    expect(woke, isTrue);
    r.dispose();
  });
}
