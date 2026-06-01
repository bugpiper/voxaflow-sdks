import 'package:livekit_client/livekit_client.dart' as lk;

import '../errors.dart';
import '../transport/realtime.dart';
import '../transport/rest_client.dart';

/// Base for media sessions (call/meeting). Wraps a LiveKit [lk.Room] and exposes
/// the unified device-control surface. Use [room] for advanced LiveKit access.
abstract class RtcSession {
  RtcSession(this.room, this.id, this.realtime);

  /// Underlying LiveKit room (escape hatch for advanced use — `get lkRoom`).
  final lk.Room room;

  /// callId or meetingId.
  final String id;

  /// Internal: used to (un)subscribe the realtime data channel for this session.
  final VoxaRealtime realtime;

  lk.Room get lkRoom => room;
  lk.LocalParticipant? get _me => room.localParticipant;

  Future<void> setMicEnabled(bool on) async => _me?.setMicrophoneEnabled(on);
  Future<void> setMuted(bool muted) => setMicEnabled(!muted);
  Future<void> setCameraEnabled(bool on) async => _me?.setCameraEnabled(on);
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
  CallSession._(super.room, super.id, super.realtime);

  static Future<CallSession> start({
    required VoxaRest rest,
    required VoxaRealtime realtime,
    required String callId,
    bool video = false,
    String? name,
  }) async {
    final Map<String, dynamic> res;
    try {
      res = await rest.post('/rtc/token', {
        'callId': callId,
        if (name != null) 'name': name,
      });
    } on VoxaError {
      rethrow;
    }

    final wsUrl = res['wsUrl'] as String?;
    final token = res['token'] as String?;
    if (wsUrl == null || token == null) {
      throw const VoxaError(VoxaErrorCode.connection, 'Backend did not return a LiveKit token/wsUrl');
    }

    final room = lk.Room();
    try {
      await room.connect(wsUrl, token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (video) await room.localParticipant?.setCameraEnabled(true);
    } catch (e) {
      await room.dispose();
      throw VoxaError(VoxaErrorCode.media, 'Failed to join the call room', cause: e);
    }

    // Subscribe to this call's data events (transcript/entities/form) + replay.
    realtime.joinCall(callId);
    return CallSession._(room, callId, realtime);
  }

  @override
  Future<void> end() async {
    realtime.leaveCall(id);
    try {
      await room.disconnect();
    } finally {
      await room.dispose();
    }
  }
}
