import 'package:livekit_client/livekit_client.dart' as lk;

import '../errors.dart';
import '../transport/realtime.dart';
import '../transport/rest_client.dart';
import 'call_session.dart' show RtcSession, LiveKitCreds;

/// A multi-party meeting (MP1–MP8). Backed by `POST /meetings/:id/token` → a LiveKit room.
/// Per-speaker transcript / participant / AI-output events arrive on the VoxaClient
/// meetingTranscript / meetingParticipant / meetingOutput streams once joined.
class MeetingSession extends RtcSession {
  MeetingSession._(super.room, super.id, super.realtime, this._rest, this._body, {super.video, super.autoRejoin});

  final VoxaRest _rest;
  final Map<String, dynamic> _body;

  static Future<LiveKitCreds> _token(VoxaRest rest, String meetingId, Map<String, dynamic> body) async {
    final res = await rest.post('/meetings/$meetingId/token', body);
    final wsUrl = res['wsUrl'] as String?;
    final token = res['token'] as String?;
    if (wsUrl == null || token == null) {
      throw const VoxaError(VoxaErrorCode.connection, 'Backend did not return a meeting LiveKit token/wsUrl');
    }
    return (wsUrl: wsUrl, token: token);
  }

  /// [autoRejoin] (default true): re-join automatically after an unexpected drop.
  static Future<MeetingSession> join({
    required VoxaRest rest,
    required VoxaRealtime realtime,
    required String meetingId,
    bool video = false,
    String? displayName,
    String? role,
    String? language,
    bool autoRejoin = true,
  }) async {
    final body = <String, dynamic>{
      if (displayName != null) 'name': displayName,
      if (role != null) 'role': role,
      if (language != null) 'language': language,
    };
    final creds = await _token(rest, meetingId, body);

    final room = lk.Room();
    try {
      await room.connect(creds.wsUrl, creds.token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (video) await room.localParticipant?.setCameraEnabled(true);
    } catch (e) {
      await room.dispose();
      throw VoxaError(VoxaErrorCode.media, 'Failed to join the meeting room', cause: e);
    }
    realtime.joinMeeting(meetingId);
    return MeetingSession._(room, meetingId, realtime, rest, body, video: video, autoRejoin: autoRejoin);
  }

  @override
  Future<LiveKitCreds> fetchCreds() => _token(_rest, id, _body);

  @override
  void rejoinRealtime() => realtime.joinMeeting(id);

  @override
  Future<void> end() async {
    await stopRejoin();
    realtime.leaveMeeting(id);
    try {
      await room.disconnect();
    } finally {
      await room.dispose();
    }
  }
}
