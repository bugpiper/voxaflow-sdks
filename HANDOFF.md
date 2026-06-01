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

### Known gaps (not built / not in scope here)
- Mobile-critical native integration: CallKit/AVAudioSession (iOS), AudioManager focus + foreground service (Android), push/incoming-call, proximity, Bluetooth-route UI. **A real call works; these polish the OS-level call experience.**
- Rich UI is minimal/light-styled (Midnight Intelligence design tokens not yet applied). Flutter UI widgets beyond the example aren't built.
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
