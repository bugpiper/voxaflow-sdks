# Native call setup (Flutter) — CallKit / AudioManager / foreground service / push

`VoxaCallKit` (in the SDK) is the Dart surface for the OS-level call experience, built on
[`flutter_callkit_incoming`](https://pub.dev/packages/flutter_callkit_incoming). The Dart side
is wired and compiles; the items below are the **native project config** the integrating app
must add for it to work on device. None of this can be validated headless — test on a real
device/simulator.

## How it fits together

```dart
import 'package:voxaflow_flutter/voxaflow_flutter.dart';

// 1) React to native call actions (set this up once at app start).
VoxaCallKit.actions.listen((a) async {
  switch (a.type) {
    case VoxaCallActionType.accepted:
      await client.connect();
      final call = await client.startCall(callId: a.callId); // or joinMeeting(a.callId)
      await VoxaCallKit.setConnected(a.callId);               // tell the OS the call is live
      break;
    case VoxaCallActionType.declined:
    case VoxaCallActionType.ended:
    case VoxaCallActionType.timedOut:
      await VoxaCallKit.end(a.callId);
      break;
    default:
      break;
  }
});

// 2) Outgoing call → also show the system call UI:
final call = await client.startCall(video: true);
await VoxaCallKit.startOutgoing(VoxaIncomingCall(callId: call.id, callerName: 'Astrologer', video: true));
await VoxaCallKit.setConnected(call.id);

// 3) Incoming call from a push payload (in your FCM/APNs handler):
await VoxaCallKit.handleIncomingPush(pushData); // shows the native ringing UI
```

In-call **audio routing** (earpiece/speaker/Bluetooth) is managed by LiveKit/`flutter_webrtc`
once the room connects; on iOS, CallKit owns audio activation (handled by the plugin).

## iOS

`ios/Runner/Info.plist`:
```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
  <string>voip</string>
</array>
<key>NSMicrophoneUsageDescription</key><string>Calls use the microphone.</string>
<key>NSCameraUsageDescription</key><string>Video calls use the camera.</string>
```

- **VoIP push (PushKit)** is required to wake the app for an incoming call when backgrounded/killed
  (a normal data push can't reliably present CallKit). In `AppDelegate.swift`, register PushKit and,
  on a VoIP push, report a new incoming call to CallKit. `flutter_callkit_incoming` ships a
  `SwiftCallkitIncomingAppDelegate` you can subclass, or implement `PKPushRegistryDelegate` yourself.
  Get the token from Dart via `VoxaCallKit.voipPushToken()` and register it with your push backend.
- `pod install` after `flutter pub get`. CallKit needs a real device for full testing (simulator is limited).
- The example's `example/ios/Podfile` is already configured for this: `platform :ios, '13.0'` (LiveKit/CallKit
  need a modern target) and a `post_install` block that sets `PERMISSION_MICROPHONE=1` + `PERMISSION_CAMERA=1`
  for `permission_handler`. Copy that block into your own app's Podfile and add macros for any other
  permissions you request (`example/macos/Podfile` has the macOS equivalent).

## Android

`android/app/src/main/AndroidManifest.xml` (the plugin merges its own services; add):
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE"/>
<uses-permission android:name="android.permission.MANAGE_OWN_CALLS"/>
```
- Request `POST_NOTIFICATIONS` (Android 13+) at runtime; `USE_FULL_SCREEN_INTENT` (Android 14+) so the
  ringing screen shows over the lock screen.
- **Incoming calls via FCM**: in a background data-message handler call `VoxaCallKit.handleIncomingPush(message.data)`.
  The plugin shows the full-screen incoming UI and (optionally) registers a Telecom `ConnectionService`.
- The plugin runs a foreground service for the ongoing call so the OS doesn't kill it.

## Push backend (tenant)

Your backend sends the VoIP/FCM push when routing assigns a call to a user, with a payload containing
at least `callId` and `callerName` (and `video`). The SDK's `VoxaCallKit.handleIncomingPush` reads those
(override `fromPayload` for a custom schema). Register device tokens with your backend:
`registerPushToken` on your side; iOS VoIP token via `VoxaCallKit.voipPushToken()`.

## What's validated vs. not
- ✅ Dart compiles (`dart analyze` clean) and the action/lifecycle/push-parse logic is in place.
- ⚠️ CallKit/PushKit/ConnectionService behavior is **device-only** — verify incoming (background + killed),
  accept→join, decline, audio routing, and lock-screen UI on real iOS + Android devices.
