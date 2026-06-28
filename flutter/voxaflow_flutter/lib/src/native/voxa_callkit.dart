import 'dart:math';

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
  // CallKit identifies every call by a **UUID**. Voxa callIds are NOT UUIDs, and
  // flutter_callkit_incoming force-unwraps `UUID(uuidString: id)!` — a non-UUID
  // id makes it unwrap nil and crash (EXC_BREAKPOINT) the moment a ring shows.
  // So map each Voxa callId ↔ a generated UUID: pass the UUID to CallKit, carry
  // the real callId in `extra`, and translate native actions back to it.
  static final Map<String, String> _callIdToUuid = {};
  static final Map<String, String> _uuidToCallId = {};

  // callIds marked connected. iOS flutter_callkit_incoming 2.5.8's setCallConnected
  // re-issues a CXAnswerCallAction (CallManager.connectedCall), which the plugin
  // re-emits as ACTION_CALL_ACCEPT — a *spurious second accept*. Tracking connected
  // calls lets [_map] downgrade that echo to `connected`, so it never re-triggers a
  // consumer's accept→join (which would duplicate-join the room and double-answer).
  static final Set<String> _connected = {};

  static String _uuidFor(String callId) => _callIdToUuid.putIfAbsent(callId, () {
        final u = _genUuid();
        _uuidToCallId[u] = callId;
        return u;
      });

  static String _genUuid() {
    final r = Random();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }

  static CallKitParams _params(VoxaIncomingCall c) => CallKitParams(
        id: _uuidFor(c.callId),
        nameCaller: c.callerName,
        appName: c.appName,
        avatar: c.avatar,
        handle: c.handle,
        type: c.video ? 1 : 0,
        extra: {...?c.extra, 'voxaCallId': c.callId},
      );

  /// Show the native INCOMING call UI (ringing).
  static Future<void> showIncoming(VoxaIncomingCall call) =>
      FlutterCallkitIncoming.showCallkitIncoming(_params(call));

  /// Show the native OUTGOING/active call UI (so the OS reflects an ongoing call).
  static Future<void> startOutgoing(VoxaIncomingCall call) =>
      FlutterCallkitIncoming.startCall(_params(call));

  /// Mark the call connected — call this right after the Voxa LiveKit room is joined.
  /// NOTE (iOS, flutter_callkit_incoming 2.5.8): this re-issues a CXAnswerCallAction,
  /// so the plugin emits a duplicate `accepted` event; [_connected] + [_map] absorb it.
  static Future<void> setConnected(String callId) {
    _connected.add(callId);
    return FlutterCallkitIncoming.setCallConnected(_uuidFor(callId));
  }

  /// End one call's system UI.
  static Future<void> end(String callId) {
    _connected.remove(callId);
    return FlutterCallkitIncoming.endCall(_uuidFor(callId));
  }

  /// End all system call UI (e.g. on logout).
  static Future<void> endAll() {
    _connected.clear();
    return FlutterCallkitIncoming.endAllCalls();
  }

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
    // Translate CallKit's UUID back to the real Voxa callId: prefer the value we
    // stashed in `extra` (survives a cold-start push), else the in-memory map.
    final rawId = (body['id'] ?? '').toString();
    final extra = body['extra'];
    final callId = (extra is Map ? extra['voxaCallId']?.toString() : null) ??
        _uuidToCallId[rawId] ??
        rawId;
    var type = switch (e.event) {
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
    // Swallow the duplicate `accepted` that setCallConnected synthesizes on iOS:
    // if this call is already connected, surface it as `connected`, not a fresh accept.
    if (type == VoxaCallActionType.accepted && _connected.contains(callId)) {
      type = VoxaCallActionType.connected;
    }
    return VoxaCallAction(type, callId, body);
  }
}
