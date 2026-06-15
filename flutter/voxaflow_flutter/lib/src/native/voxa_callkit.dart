// NOTE (prototype): the native CallKit integration (flutter_callkit_incoming) is
// stubbed out here because that package ships Android classes in the SAME
// `com.hiennv.flutter_callkit_incoming` namespace as Zego's fork
// (flutter_callkit_incoming_yoer), so the two cannot coexist in one APK. While an
// app still has ZegoCloud installed, this SDK must NOT pull flutter_callkit_incoming.
// Foreground ringing uses the prebuilt `VoxaIncomingCallScreen` instead. Restore
// the real implementation (and the pubspec dep) once Zego is removed — see ZegoToVoxa.md.

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

/// A native call action the user/OS took (accept/decline/end/…), plus the callId.
class VoxaCallAction {
  const VoxaCallAction(this.type, this.callId, this.body);
  final VoxaCallActionType type;
  final String callId;
  final Map<String, dynamic> body;
}

/// Native call experience (CallKit / full-screen incoming) — **stubbed in this
/// build** (see file header). Methods are no-ops; [actions] is an empty stream.
/// Use [VoxaIncomingCall] with the prebuilt `VoxaIncomingCallScreen` for
/// foreground ringing. Re-enable the flutter_callkit_incoming-backed version once
/// Zego (and its flutter_callkit_incoming_yoer fork) is gone.
class VoxaCallKit {
  static const String _disabled =
      'VoxaCallKit native CallKit is disabled in this build (conflicts with Zego). '
      'Use VoxaIncomingCallScreen for foreground ringing.';

  static Future<void> showIncoming(VoxaIncomingCall call) async {}
  static Future<void> startOutgoing(VoxaIncomingCall call) async {}
  static Future<void> setConnected(String callId) async {}
  static Future<void> end(String callId) async {}
  static Future<void> endAll() async {}
  static Future<dynamic> activeCalls() async => const <dynamic>[];
  static Future<dynamic> voipPushToken() async => null;

  static Stream<VoxaCallAction> get actions =>
      const Stream<VoxaCallAction>.empty();

  static Future<void> handleIncomingPush(
    Map<String, dynamic> payload, {
    VoxaIncomingCall Function(Map<String, dynamic>)? fromPayload,
  }) async {
    // No-op: native push-driven ringing is unavailable in this build.
    assert(() {
      // ignore: avoid_print
      print(_disabled);
      return true;
    }());
  }
}
