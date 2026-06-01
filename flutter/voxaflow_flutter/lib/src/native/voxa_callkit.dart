import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

/// Describes a call for the native call UI.
class VoxaIncomingCall {
  const VoxaIncomingCall({
    required this.callId,
    required this.callerName,
    this.video = false,
    this.handle = '',
    this.avatar,
    this.appName = 'Voxa',
    this.extra,
  });

  /// The Voxa callId/meetingId to (re)join when accepted.
  final String callId;
  final String callerName;
  final bool video;
  final String handle;
  final String? avatar;
  final String appName;
  final Map<String, dynamic>? extra;
}

enum VoxaCallActionType {
  incoming,
  started,
  accepted,
  declined,
  ended,
  timedOut,
  connected,
  callback,
  muted,
  held,
  pushTokenUpdated,
  unknown,
}

/// A native call action the user/OS took (accept/decline/end/…), plus the callId it
/// applies to. Wire `accepted` → `VoxaClient.startCall(callId: …)` / `joinMeeting`, and
/// `declined`/`ended`/`timedOut` → end the Voxa session + `VoxaCallKit.end(callId)`.
class VoxaCallAction {
  const VoxaCallAction(this.type, this.callId, this.body);
  final VoxaCallActionType type;
  final String callId;
  final Map<String, dynamic> body;
}

/// Native call experience (CallKit on iOS; full-screen incoming notification +
/// ConnectionService on Android) for the Voxa Flow SDK, built on
/// [flutter_callkit_incoming]. Use it ALONGSIDE [VoxaClient]: show the system call UI,
/// then join/end the Voxa room when the user accepts/declines.
///
/// In-call audio routing (AVAudioSession on iOS, AudioManager on Android) is handled by
/// the LiveKit/WebRTC layer once you connect a room; CallKit owns activation on iOS.
/// See the SDK README "Native call setup" for the required Info.plist / manifest / VoIP-push
/// wiring (this class is the Dart surface; the OS integration needs that native config).
///
/// Mobile-only — not available on web (use `@voxaflow/web-core` there).
class VoxaCallKit {
  static CallKitParams _params(VoxaIncomingCall c) => CallKitParams(
        id: c.callId,
        nameCaller: c.callerName,
        appName: c.appName,
        avatar: c.avatar,
        handle: c.handle,
        type: c.video ? 1 : 0,
        extra: c.extra ?? <String, dynamic>{},
      );

  /// Show the native INCOMING call UI (ringing).
  static Future<void> showIncoming(VoxaIncomingCall call) =>
      FlutterCallkitIncoming.showCallkitIncoming(_params(call));

  /// Show the native OUTGOING/active call UI (so the OS reflects an ongoing call).
  static Future<void> startOutgoing(VoxaIncomingCall call) =>
      FlutterCallkitIncoming.startCall(_params(call));

  /// Mark the call connected — call this right after the Voxa LiveKit room is joined.
  static Future<void> setConnected(String callId) => FlutterCallkitIncoming.setCallConnected(callId);

  /// End one call's system UI.
  static Future<void> end(String callId) => FlutterCallkitIncoming.endCall(callId);

  /// End all system call UI (e.g. on logout).
  static Future<void> endAll() => FlutterCallkitIncoming.endAllCalls();

  /// Calls the OS currently shows (use on relaunch to reconcile state).
  static Future<dynamic> activeCalls() => FlutterCallkitIncoming.activeCalls();

  /// The iOS VoIP-push (PushKit) device token, for registering with your push backend.
  static Future<dynamic> voipPushToken() => FlutterCallkitIncoming.getDevicePushTokenVoIP();

  /// Native call actions (accept/decline/ended/…). Subscribe once at app start.
  static Stream<VoxaCallAction> get actions =>
      FlutterCallkitIncoming.onEvent.where((e) => e != null).map((e) => _map(e!));

  /// Parse a push payload (APNs/FCM data) into an incoming call and show it. Provide
  /// [fromPayload] to map your own payload schema; the default reads
  /// callId / callerName / video / handle.
  static Future<void> handleIncomingPush(
    Map<String, dynamic> payload, {
    VoxaIncomingCall Function(Map<String, dynamic>)? fromPayload,
  }) =>
      showIncoming((fromPayload ?? _defaultFromPayload)(payload));

  static VoxaIncomingCall _defaultFromPayload(Map<String, dynamic> p) => VoxaIncomingCall(
        callId: (p['callId'] ?? p['id'] ?? '').toString(),
        callerName: (p['callerName'] ?? p['caller'] ?? 'Incoming call').toString(),
        video: p['video'] == true || p['video'] == 'true',
        handle: (p['handle'] ?? '').toString(),
        extra: p,
      );

  static VoxaCallAction _map(CallEvent e) {
    final body = (e.body is Map) ? Map<String, dynamic>.from(e.body as Map) : <String, dynamic>{};
    final callId = (body['id'] ?? '').toString();
    final type = switch (e.event) {
      Event.actionCallIncoming => VoxaCallActionType.incoming,
      Event.actionCallStart => VoxaCallActionType.started,
      Event.actionCallAccept => VoxaCallActionType.accepted,
      Event.actionCallDecline => VoxaCallActionType.declined,
      Event.actionCallEnded => VoxaCallActionType.ended,
      Event.actionCallTimeout => VoxaCallActionType.timedOut,
      Event.actionCallConnected => VoxaCallActionType.connected,
      Event.actionCallCallback => VoxaCallActionType.callback,
      Event.actionCallToggleMute => VoxaCallActionType.muted,
      Event.actionCallToggleHold => VoxaCallActionType.held,
      Event.actionDidUpdateDevicePushTokenVoip => VoxaCallActionType.pushTokenUpdated,
      _ => VoxaCallActionType.unknown,
    };
    return VoxaCallAction(type, callId, body);
  }
}
