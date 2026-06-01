import 'package:livekit_client/livekit_client.dart' as lk;

import '../errors.dart';
import '../transport/realtime.dart';
import '../transport/rest_client.dart';
import 'call_session.dart' show RtcSession;

/// A multi-party meeting (MP1–MP8). Backed by `POST /meetings/:id/token` → a LiveKit room.
/// Per-speaker transcript / participant / AI-output events arrive on the VoxaClient
/// meetingTranscript / meetingParticipant / meetingOutput streams once joined.
class MeetingSession extends RtcSession {
  MeetingSession._(super.room, super.id, super.realtime);

  static Future<MeetingSession> join({
    required VoxaRest rest,
    required VoxaRealtime realtime,
    required String meetingId,
    bool video = false,
    String? displayName,
    String? role,
    String? language,
  }) async {
    final res = await rest.post('/meetings/$meetingId/token', {
      if (displayName != null) 'name': displayName,
      if (role != null) 'role': role,
      if (language != null) 'language': language,
    });
    final wsUrl = res['wsUrl'] as String?;
    final token = res['token'] as String?;
    if (wsUrl == null || token == null) {
      throw const VoxaError(VoxaErrorCode.connection, 'Backend did not return a meeting LiveKit token/wsUrl');
    }

    final room = lk.Room();
    try {
      await room.connect(wsUrl, token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (video) await room.localParticipant?.setCameraEnabled(true);
    } catch (e) {
      await room.dispose();
      throw VoxaError(VoxaErrorCode.media, 'Failed to join the meeting room', cause: e);
    }
    realtime.joinMeeting(meetingId);
    return MeetingSession._(room, meetingId, realtime);
  }

  @override
  Future<void> end() async {
    realtime.leaveMeeting(id);
    try {
      await room.disconnect();
    } finally {
      await room.dispose();
    }
  }
}
