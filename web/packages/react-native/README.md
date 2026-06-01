# @voxaflow/react-native

React Native SDK for Voxa Flow. Wraps [`@livekit/react-native`](https://www.npmjs.com/package/@livekit/react-native) for media and reuses [`@voxaflow/web-core`](../web-core) (client/transport/events) + the pure-React hooks/provider from [`@voxaflow/react`](../react). Same unified API as every Voxa SDK — RN-native components.

## Install

```sh
npm i @voxaflow/react-native @voxaflow/react @voxaflow/web-core \
      @livekit/react-native @livekit/react-native-webrtc \
      livekit-client socket.io-client
cd ios && pod install
```

## Setup (once, at app startup)

```ts
import { registerVoxaGlobals } from '@voxaflow/react-native';
registerVoxaGlobals(); // wires native WebRTC globals so livekit-client works on RN
```

### Native config (app integrator)

- **iOS** `Info.plist`: `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`; `UIBackgroundModes` → `audio` (+ `voip` for incoming calls). `platform :ios, '13.4'`+ in the Podfile.
- **Android** `AndroidManifest.xml`: `RECORD_AUDIO`, `CAMERA`, `INTERNET`, `MODIFY_AUDIO_SETTINGS`, `BLUETOOTH_CONNECT`, `FOREGROUND_SERVICE`; a foreground service for ongoing calls. `minSdkVersion 24`+.
- Request runtime mic/camera permissions before `startCall`.

## Quick start

```tsx
import { VoxaProvider, CallView, ChatWidget } from '@voxaflow/react-native';

export default function App() {
  return (
    <VoxaProvider endpoint="https://voxaflow.fastwheel.ai/api" token={token} onTokenRefresh={refresh}>
      <CallView video />
      <ChatWidget channel="my-mobile-widget" />
    </VoxaProvider>
  );
}
```

Or compose with hooks (`useConnectionState`, `useTranscript`, `useVoxaCall`, `useVoxaChat`, `useVoxaClient`) — identical to `@voxaflow/react`. For video tiles, render `@livekit/react-native`'s `VideoTrack` against `call.lkRoom`.

## How it works

`@livekit/react-native`'s `registerGlobals()` patches native WebRTC, after which `web-core`'s `CallSession` (which uses `livekit-client`'s `Room`) runs unchanged on RN. The provider + hooks are pure React, so they're shared with the web SDK verbatim — only the leaf components differ (RN `View`/`Text` vs DOM).

## Status (v0)

Provider + hooks + `CallView`/`ChatWidget` (RN primitives). Planned: video tiles component, mobile-critical native integration (CallKit/AVAudioSession on iOS; AudioManager + foreground service on Android; interruptions; route/Bluetooth changes; proximity; background continuity; push/incoming-call), and a sample RN app (patient + agent). No PHI in device logs.

> Note: builds/typechecks in CI; runtime requires an RN app with the native deps (Metro + a device/simulator) — not exercised in this repo's headless build.
