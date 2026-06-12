# Voxa Flow SDK — Handoff (Flutter + web-core) for the Astrology app

This is the working state + everything a developer needs to **build, test, and run** the Voxa SDK for an astrology app. Scope of this handoff: **`flutter/voxaflow_flutter`** and **`web/packages/web-core`** (the other platforms exist in this repo but aren't the focus here).

Repo: `github.com/bugpiper/voxaflow-sdks` (private). Backend it wraps: the live Voxa API (e.g. `https://voxaflow.fastwheel.ai/api`).

---

## 1. What these SDKs do

One unified, capability-gated client that wraps LiveKit (media) + the Voxa realtime/REST API. Same API on both:

```
VoxaClient(endpoint, token, onTokenRefresh?)
  connect() · disconnect() · can(capability) · profile
  startCall({callId?, video?, name?}) -> CallSession         // voice/video
  joinMeeting(meetingId, {...}) -> MeetingSession            // multi-party
  createMeeting({type?, title?})                             // AGENT+
  openChat({channel? | conversationId?}) -> ChatSession      // text + AI bot
  requestCall(handle, {...})                                 // click-to-call
  setPresence(status)                                        // AGENT+
  // agent copilot: getEntities/confirmEntity/rejectEntity, getSuggestions/dismissSuggestion,
  //   getForm/editField/confirmField/rejectField/submitForm, getSummary,
  //   getActiveCalls/answerCall/holdCall/transferCall
events / streams: connectionState, transcript, entityExtracted/entities, formUpdate(s),
  message(s), typing, presence, callStatus, meetingTranscript, meetingParticipant, meetingOutput, error
```

CallSession/MeetingSession: `setMicEnabled`, `setCameraEnabled`, screen share (web), `hold`/`resume`/`setMuted`/`end`, and `lkRoom`/`room` (the raw LiveKit room) as an escape hatch for custom video UI.

The full contract (REST endpoints + Socket.IO event payloads + capability model) is in **[`CONTRACT.md`](CONTRACT.md)**.

---

## 2. Validation status (what I tested)

| | Flutter (`voxaflow_flutter`) | web-core (`@voxaflow/web-core`) |
|---|---|---|
| Static analysis / types | ✅ `dart analyze` — No issues | ✅ `tsc`/`tsup` ESM+CJS+`.d.ts` |
| Full build | ✅ `flutter build web` | ✅ `tsup` |
| **Runtime vs prod (data path)** | ✅ `flutter test` runtime smoke (connect + role + getActiveCalls) — see `test/runtime_prod_test.dart` | ✅ connect + setPresence round-trip + getActiveCalls (4 live calls) |
| LiveKit media (call audio/video) | ⚠️ **not run here** — needs a device/emulator | ⚠️ needs a browser |

**Bottom line:** auth (token + transparent 401 refresh), realtime (Socket.IO), capability gating, REST methods, and event parsing are **proven against production**. The only unverified piece is **LiveKit media**, which can't be exercised headless — the next dev should confirm it on a real device/browser (it's a thin wrapper over the LiveKit client, which is itself battle-tested).

---

## 3. Astrology-app quickstart (Flutter)

1. **Tenant + vertical.** The tenant should be created with vertical `astrology` (self-serve `POST /auth/register {vertical: "astrology"}`, or set by an admin). The vertical drives the AI/NER/summary templates server-side — the SDK is vertical-agnostic and just carries the token.
2. **Token minting (your backend).** Never ship an API secret. Your backend logs the user in / mints a short-lived Voxa JWT (`POST /auth/login` → `accessToken`) and exposes an endpoint your app calls. The SDK refreshes via `onTokenRefresh`.
3. **App code:**

```dart
import 'package:voxaflow_flutter/voxaflow_flutter.dart';

final client = VoxaClient(VoxaConfig(
  endpoint: 'https://voxaflow.fastwheel.ai/api',
  token: await myBackend.voxaToken(),
  onTokenRefresh: () => myBackend.voxaToken(),
));
await client.connect();

// Astrologer ↔ client consultation (audio or video):
final call = await client.startCall(video: true);
client.transcript.listen((s) => print('${s.speaker}: ${s.text}'));
// ... call.setMicEnabled(false); await call.end();

// Or chat-first (bot triage, then human astrologer):
final chat = await client.openChat(channel: 'astrology-web');
client.messages.listen((m) => /* render; m.isBot for bot replies */ {});
await chat.sendMessage('What does my birth chart say?');
```

4. **Run it:** there's a sample app at `flutter/voxaflow_flutter/example/` (connect → call → live transcript). `cd example && flutter run` after dropping in a token.

### web-core quickstart
```ts
import { VoxaClient } from '@voxaflow/web-core';
const client = new VoxaClient({ endpoint, token, onTokenRefresh });
await client.connect();
client.on('transcript', s => …);
const call = await client.startCall({ video: true });
```
(`@voxaflow/react` gives `<VoxaProvider>` + hooks + `<CallView>`/`<ChatWidget>`/`<CopilotPanel>` if they want React components.)

---

## 4. What the next developer needs to do

- **Run on a real device/emulator** to verify LiveKit audio/video (headless build only proves it compiles).
- **Native permissions/config** (already in the example, replicate in the real app):
  - iOS `Info.plist`: `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`, background mode `audio`. `pod install`.
  - Android manifest: `RECORD_AUDIO`, `CAMERA`, `INTERNET`, `MODIFY_AUDIO_SETTINGS`, `BLUETOOTH_CONNECT`, `FOREGROUND_SERVICE`; `minSdk 24`. Request runtime mic/camera before `startCall`.
- **Token endpoint** on the tenant backend (the one thing the SDK requires).
- **Custom video UI** if desired: use `call.lkRoom` (the `livekit_client` `Room`) with `VideoTrackRenderer`.

### Native call UX (CallKit / incoming UI / foreground service / push)
**Wired** in the Flutter SDK as `VoxaCallKit` (CallKit on iOS; full-screen incoming notification + ConnectionService on Android; VoIP/FCM push handling) — see **`flutter/voxaflow_flutter/NATIVE_CALL_SETUP.md`** for Dart usage + the required Info.plist / AndroidManifest / PushKit-FCM config. The Dart side compiles clean; OS behavior (incoming-while-backgrounded, accept→join, lock-screen UI, audio routing) **must be verified on real devices** — it can't run headless. In-call audio routing is handled by LiveKit/WebRTC.

### Prebuilt UI (now shipped — Flutter)
The SDK ships drop-in Material widgets so apps don't hand-build call surfaces
(exported from `package:voxaflow_flutter/voxaflow_flutter.dart`):
- **`VoxaCallScreen(session:, client?:, …)`** — full in-call screen for any
  `RtcSession` (1:1 `CallSession` or `MeetingSession`): adaptive video layout
  (remote focus + draggable PiP for 1:1, grid for meetings, screen-share
  priority), mic/camera/screen-share/hold/end control bar, call timer,
  connection state, optional live-transcript panel.
- **`VoxaIncomingCallScreen(call:, onAccept:, onDecline:)`** — branded in-app
  ringing screen (pulse animation, accept/video/decline). Complements the native
  `VoxaCallKit` ring used for background/killed-app.
- **`VoxaCallOverlay` / `VoxaCallOverlayController`** — draggable floating
  mini-call (PiP) you can float over the whole app via the root `Overlay`.
- **`VoxaParticipantTile`**, **`VoxaCallControlBar`**, **`VoxaCallTheme`**
  (Midnight Intelligence tokens; `.midnight()` / `.light()`) — reusable building
  blocks. The example app wires "Prebuilt UI" + "Incoming" buttons.
- `dart analyze` clean for both `lib/` and `example/`.

### Known gaps (not built / not in scope here)
- Directed ring/invite signaling (call user X → ring → accept/reject) is a
  **backend** gap, not an SDK one — see the SDK's incoming-call flow notes.
- Proximity sensor + a custom Bluetooth-route picker UI (LiveKit handles the routing itself; a custom picker isn't built).
- Not published to pub.dev/npm yet — consume via path/workspace for now.

---

## 5. Build & test commands

```sh
# Flutter
cd flutter/voxaflow_flutter
flutter pub get && dart analyze && flutter test
flutter test test/runtime_prod_test.dart --dart-define=VOXA_TOKEN=<jwt>   # live data-path smoke

# web-core
cd web && pnpm install && pnpm --filter @voxaflow/web-core build
```

Toolchains used while building this: Flutter 3.44, Dart 3.x, pnpm 9, Node 20.
