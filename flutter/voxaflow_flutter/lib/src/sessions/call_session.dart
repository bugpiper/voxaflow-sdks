import 'package:livekit_client/livekit_client.dart' as lk;

import '../errors.dart';
import '../models/models.dart' show VoxaConnectionState;
import '../transport/realtime.dart';
import '../transport/rest_client.dart';
import 'rejoin.dart';

/// Fresh LiveKit credentials for a session's room.
typedef LiveKitCreds = ({String wsUrl, String token});

/// Base for media sessions (call/meeting). Wraps a LiveKit [lk.Room] and exposes
/// the unified device-control surface. Use [room] for advanced LiveKit access.
///
/// Auto-rejoin (default on): after an unexpected drop (locked phone, backgrounded app, lost
/// network) the session re-joins the same room with a fresh token and the user's current mic/cam,
/// Google-Meet style. Watch [connectionState]; call [rejoinNow] to retry immediately.
abstract class RtcSession {
  RtcSession(this.room, this.id, this.realtime, {bool video = false, bool autoRejoin = true}) : _wantCam = video {
    _rejoin = RejoinController(join: _freshJoin, onRejoined: rejoinRealtime, autoRejoin: autoRejoin);
    _listener = room.createListener()
      ..on<lk.RoomReconnectingEvent>((_) => _rejoin.onReconnecting())
      ..on<lk.RoomReconnectedEvent>((_) => _rejoin.onReconnected())
      ..on<lk.RoomDisconnectedEvent>((e) => _rejoin.onDisconnected(e.reason));
  }

  late final RejoinController _rejoin;
  late final lk.EventsListener<lk.RoomEvent> _listener;
  bool _wantMic = true;
  bool _wantCam;

  /// Media connection state of THIS session (distinct from VoxaClient.connectionState, which is
  /// the realtime socket): connected → (reconnecting → connected)* → disconnected.
  Stream<VoxaConnectionState> get connectionState => _rejoin.states;
  VoxaConnectionState get state => _rejoin.state;

  /// Each auto-rejoin try, as it starts.
  Stream<VoxaRejoinAttempt> get rejoinAttempts => _rejoin.attempts;

  /// 1-based number of the current auto-rejoin try (0 when not rejoining) — for "(attempt n)" UI.
  int get rejoinAttemptNumber => _rejoin.attempt;

  /// Retry now: cuts the back-off wait short, or restarts after auto-rejoin gave up. No-op while connected.
  void rejoinNow() => _rejoin.rejoinNow();

  /// Fetch fresh credentials for this session's room.
  Future<LiveKitCreds> fetchCreds();

  /// Re-subscribe the realtime socket after a rejoin.
  void rejoinRealtime();

  /// New token → connect the same Room (UI listeners survive) → restore mic/cam.
  Future<void> _freshJoin() async {
    try {
      final c = await fetchCreds();
      await room.connect(c.wsUrl, c.token);
    } catch (_) {
      try {
        await room.disconnect();
      } catch (_) {}
      rethrow;
    }
    try {
      if (_wantMic) await _me?.setMicrophoneEnabled(true);
    } catch (_) {}
    try {
      if (_wantCam) await _me?.setCameraEnabled(true);
    } catch (_) {}
  }

  /// Stop auto-rejoin and listeners. Subclasses call this first in [end].
  Future<void> stopRejoin() async {
    _rejoin.cancel();
    await _listener.dispose();
    await _rejoin.dispose();
  }

  /// Underlying LiveKit room (escape hatch for advanced use — `get lkRoom`).
  final lk.Room room;

  /// callId or meetingId.
  final String id;

  /// Internal: used to (un)subscribe the realtime data channel for this session.
  final VoxaRealtime realtime;

  lk.Room get lkRoom => room;
  lk.LocalParticipant? get _me => room.localParticipant;

  Future<void> setMicEnabled(bool on) async {
    _wantMic = on;
    await _me?.setMicrophoneEnabled(on);
  }

  Future<void> setMuted(bool muted) => setMicEnabled(!muted);
  Future<void> setCameraEnabled(bool on) async {
    _wantCam = on;
    await _me?.setCameraEnabled(on);
  }

  Future<void> startScreenShare() async => _me?.setScreenShareEnabled(true);
  Future<void> stopScreenShare() async => _me?.setScreenShareEnabled(false);

  /// Hold = stop sending mic (caller hears nothing); resume re-enables it.
  Future<void> hold() => setMicEnabled(false);
  Future<void> resume() => setMicEnabled(true);

  Future<void> end();
}

/// A 1:1 / queue call. Backed by `POST /rtc/token` → a LiveKit room. Transcript,
/// entities, suggestions and form updates for this call arrive on the VoxaClient
/// event streams once joined.
class CallSession extends RtcSession {
  CallSession._(super.room, super.id, super.realtime, this._rest, this._name, {super.video, super.autoRejoin});

  final VoxaRest _rest;
  final String? _name;

  static Future<LiveKitCreds> _token(VoxaRest rest, String callId, String? name) async {
    final res = await rest.post('/rtc/token', {
      'callId': callId,
      if (name != null) 'name': name,
    });
    final wsUrl = res['wsUrl'] as String?;
    final token = res['token'] as String?;
    if (wsUrl == null || token == null) {
      throw const VoxaError(VoxaErrorCode.connection, 'Backend did not return a LiveKit token/wsUrl');
    }
    return (wsUrl: wsUrl, token: token);
  }

  /// [autoRejoin] (default true): re-join automatically after an unexpected drop.
  static Future<CallSession> start({
    required VoxaRest rest,
    required VoxaRealtime realtime,
    required String callId,
    bool video = false,
    String? name,
    bool autoRejoin = true,
  }) async {
    final creds = await _token(rest, callId, name);

    final room = lk.Room();
    try {
      await room.connect(creds.wsUrl, creds.token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (video) await room.localParticipant?.setCameraEnabled(true);
    } catch (e) {
      await room.dispose();
      throw VoxaError(VoxaErrorCode.media, 'Failed to join the call room', cause: e);
    }

    // Subscribe to this call's data events (transcript/entities/form) + replay.
    realtime.joinCall(callId);
    return CallSession._(room, callId, realtime, rest, name, video: video, autoRejoin: autoRejoin);
  }

  @override
  Future<LiveKitCreds> fetchCreds() => _token(_rest, id, _name);

  @override
  void rejoinRealtime() => realtime.joinCall(id);

  @override
  Future<void> end() async {
    await stopRejoin();
    realtime.leaveCall(id);
    try {
      await room.disconnect();
    } finally {
      await room.dispose();
    }
  }
}
