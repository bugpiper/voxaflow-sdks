/// Voxa Flow client SDK for Flutter.
///
/// Wraps `livekit_client` (media) + the Voxa realtime/REST API (transcripts,
/// entities, suggestions, chat) behind one unified, capability-gated client.
library voxaflow_flutter;

export 'src/voxa_client.dart' show VoxaClient, VoxaConfig;
export 'src/capabilities.dart' show Capability, TokenProfile;
export 'src/errors.dart' show VoxaError, VoxaErrorCode;
export 'src/sessions/call_session.dart' show CallSession, RtcSession;
export 'src/sessions/chat_session.dart' show ChatSession;
export 'src/sessions/meeting_session.dart' show MeetingSession;
export 'src/models/models.dart';
