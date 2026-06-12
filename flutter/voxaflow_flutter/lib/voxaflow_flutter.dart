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
export 'src/native/voxa_callkit.dart' show VoxaCallKit, VoxaIncomingCall, VoxaCallAction, VoxaCallActionType;
export 'src/models/models.dart';

// Prebuilt UI (Material). Drop-in call screens + widgets so apps don't hand-build
// the in-call / incoming / mini-overlay surfaces.
export 'src/ui/voxa_call_theme.dart' show VoxaCallTheme;
export 'src/ui/voxa_call_controls.dart' show VoxaCallControlBar, VoxaControlButton;
export 'src/ui/voxa_video_view.dart'
    show VoxaParticipantTile, voxaCameraTrack, voxaScreenShareTrack, voxaParticipantLabel;
export 'src/ui/voxa_call_screen.dart' show VoxaCallScreen;
export 'src/ui/voxa_incoming_call_screen.dart' show VoxaIncomingCallScreen;
export 'src/ui/voxa_call_overlay.dart' show VoxaCallOverlay, VoxaCallOverlayController;
