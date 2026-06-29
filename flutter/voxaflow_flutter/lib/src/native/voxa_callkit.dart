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
    this.backgroundColor,
    this.accentColor,
    this.textColor,
    this.notificationChannelName,
    this.ringtonePath,
    this.logo,
  });

  /// The Voxa callId/meetingId to (re)join when accepted.
  final String callId;
  final String callerName;
  final bool video;
  final String handle;
  final String? avatar;
  final String appName;
  final Map<String, dynamic>? extra;

  // ── Android incoming-call UI branding (hex colors like '#5F0204'). When null
  // the plugin's defaults are used. iOS uses the system CallKit look. ──────────
  /// Full-screen incoming-call background.
  final String? backgroundColor;

  /// Accept/decline action accent.
  final String? accentColor;

  /// Foreground text color.
  final String? textColor;

  /// Android notification channel label shown in system settings.
  final String? notificationChannelName;

  /// Custom ringtone (Android raw resource name / asset); null = system default.
  final String? ringtonePath;

  /// Image shown at the TOP of the Android incoming screen (e.g. an app
  /// wordmark). A Flutter asset path (bundled in flutter_assets) or http(s) URL.
  /// null = no top logo.
  final String? logo;
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
        // Brand the native Android incoming-call UI. Null fields fall back to the
        // plugin defaults; the full-screen + heads-up surfaces use these colors.
        android: AndroidParams(
          isShowFullLockedScreen: true,
          isImportant: true,
          isShowLogo: c.logo != null,
          logoUrl: c.logo,
          backgroundColor: c.backgroundColor,
          actionColor: c.accentColor,
          textColor: c.textColor,
          ringtonePath: c.ringtonePath,
          incomingCallNotificationChannelName: c.notificationChannelName,
        ),
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

  /// Recover a killed-app accept whose native action fired before [actions] was
  /// subscribed. When the app is launched by tapping Accept on a ringing call
  /// from a KILLED state, the `ACTION_CALL_ACCEPT` event is emitted during
  /// startup — before any Dart listener exists — and is dropped ([actions] is a
  /// broadcast stream with no replay), so the call never joins. This queries the
  /// OS for an already-accepted call and returns it as an [accepted]
  /// [VoxaCallAction] so the app can run its normal accept→join path. Returns
  /// null when no accepted call is pending (the common case on a normal launch).
  static Future<VoxaCallAction?> pendingAcceptedCall() async {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls is! List) return null;
    for (final c in calls) {
      // Only an explicitly-accepted call — never a still-ringing one.
      if (c is! Map || c['isAccepted'] != true) continue;
      final body = Map<String, dynamic>.from(c);
      final rawId = (body['id'] ?? '').toString();
      final extra = body['extra'];
      final callId = (extra is Map ? extra['voxaCallId']?.toString() : null) ??
          _uuidToCallId[rawId] ??
          rawId;
      if (callId.isEmpty) continue;
      // Learn CallKit's UUID for this call (created natively by the push, so our
      // Dart map never saw it) so a later end()/setConnected resolves the SAME
      // UUID instead of minting a new one and failing to dismiss the call.
      if (rawId.isNotEmpty && callId != rawId) {
        _callIdToUuid[callId] = rawId;
        _uuidToCallId[rawId] = callId;
      }
      return VoxaCallAction(VoxaCallActionType.accepted, callId, body);
    }
    return null;
  }

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
    // Learn CallKit's UUID for this call from the event itself. On a killed-app
    // VoIP push the CallKit call is created NATIVELY (iOS AppDelegate) with a UUID
    // our Dart map never saw — the real callId rides in extra['voxaCallId']. Record
    // the pairing so a later end()/setConnected() resolves to the SAME UUID; without
    // it they'd mint a different UUID and fail to dismiss the call, leaving the
    // system call live after hang-up.
    if (rawId.isNotEmpty && callId.isNotEmpty && callId != rawId) {
      _callIdToUuid[callId] = rawId;
      _uuidToCallId[rawId] = callId;
    }
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
