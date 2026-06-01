import { registerGlobals } from '@livekit/react-native';

let registered = false;

/**
 * Wire up the native WebRTC globals that LiveKit needs on React Native. Call ONCE at app
 * startup (before any call), e.g. in your root component or index.js. After this,
 * `@voxaflow/web-core`'s CallSession (which uses livekit-client's Room) works on RN.
 *
 * Also ensure the native deps are installed and configured:
 *  - @livekit/react-native + @livekit/react-native-webrtc
 *  - iOS: mic/camera usage strings + `audio` background mode (Info.plist); `pod install`
 *  - Android: RECORD_AUDIO/CAMERA/MODIFY_AUDIO_SETTINGS/FOREGROUND_SERVICE + a foreground
 *    service for ongoing calls
 */
export function registerVoxaGlobals(): void {
  if (registered) return;
  registerGlobals();
  registered = true;
}
