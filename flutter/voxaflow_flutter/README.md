# voxaflow_flutter

Voxa Flow client SDK for Flutter. Wraps [`livekit_client`](https://pub.dev/packages/livekit_client) for media and the Voxa realtime/REST API for transcripts, entities, suggestions, and chat — behind one unified, capability-gated `VoxaClient`.

This is **v0 (core)** — the foundation the rest of the SDK (and the web/RN/iOS/Android SDKs) build on. See [Status](#status) for what's implemented vs. planned.

## Install

```yaml
dependencies:
  voxaflow_flutter:
    path: ../sdks/flutter/voxaflow_flutter   # or the published pub.dev version once released
```

## Quick start

```dart
import 'package:voxaflow_flutter/voxaflow_flutter.dart';

final client = VoxaClient(VoxaConfig(
  endpoint: 'https://voxaflow.fastwheel.ai/api',   // Voxa API base
  token: serverMintedAccessToken,                  // from YOUR backend — never an API secret
  onTokenRefresh: () => myBackend.freshVoxaToken(), // called transparently on expiry
));

await client.connect();

// Live transcript / AI events (typed Streams)
client.transcript.listen((s) => print('${s.speaker}: ${s.text} (final=${s.isFinal})'));
client.entities.listen((e) => print('entity: ${e.entityType}=${e.value}'));
client.connectionState.listen((s) => print('conn: $s'));

// Voice/video call (LiveKit under the hood)
final call = await client.startCall(video: true);
await call.setMicEnabled(true);
await call.setCameraEnabled(false);
// ... later
await call.end();

// Chat + bot
final chat = await client.openChat(channel: 'my-web-widget');
chat.messages.listen((m) => print('${m.sender}: ${m.content}${m.isBot ? " [bot]" : ""}'));
await chat.sendMessage('Hello');

await client.disconnect();
```

## Auth & capability model

- The client is initialized with a **short-lived access token minted by the tenant's backend** (never an API secret). `onTokenRefresh` is invoked on 401/expiry to fetch a new one; REST **and** the realtime channel re-auth transparently.
- **Capability gating** is derived from the token. The current Voxa backend authorizes by **role** (`AGENT` / `SUPERVISOR` / `ADMIN` / `SUPER_ADMIN`); guest/contact tokens map to a **CLIENT** profile. The SDK derives a capability set from the role and throws `VoxaError(VoxaErrorCode.capability)` if you call a method the token doesn't permit. (When the backend adds an explicit `capabilities` claim, the SDK will read that instead — no API change.)

## How this maps to the backend (important)

The all-platforms spec references a `/sdk/join` endpoint and a per-capability token. **Those don't exist yet** — this SDK wraps the **real** backend:

| SDK concept            | Real backend                                              |
|------------------------|-----------------------------------------------------------|
| token / refresh        | `POST /auth/login`, `POST /auth/refresh`                  |
| `startCall`            | `POST /rtc/token` → connect a LiveKit room                |
| realtime events        | Socket.IO `/socket.io` (transcript:update, entity:extracted, form:autofill, chat:message/draft/typing, presence:update, call:status) |
| `openChat`             | `POST /chat/widget/:handle/start`, `POST /chat/conversations/:id/messages`, `/typing`, `/read` |
| `setPresence`          | `PUT /agents/presence`                                    |

## Platform setup (app integrators)

These come from `livekit_client`/WebRTC — add them in the **host app**:

- **iOS** (`ios/Runner/Info.plist`): `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`; background modes `audio` (+ `voip` for incoming calls). `platform :ios, '13.0'` (or higher) in the Podfile.
- **Android** (`AndroidManifest.xml`): `RECORD_AUDIO`, `CAMERA`, `INTERNET`, `MODIFY_AUDIO_SETTINGS`, `BLUETOOTH_CONNECT`, `FOREGROUND_SERVICE`; `minSdkVersion 24`.
- Request runtime mic/camera permissions before `startCall` (e.g. via `permission_handler`).

## Status

**Implemented (v0):**
- `VoxaClient` connect/disconnect, token auth + transparent refresh (REST + realtime), role→capability gating.
- `CallSession` — LiveKit room join via `/rtc/token`; mic/camera/screen-share/hold/resume/mute/end; `lkRoom` escape hatch.
- `ChatSession` — start/attach, send, typing, mark-read; bot messages (`isBot`/`botMeta`) and drafts.
- Typed event Streams: `connectionState`, `transcript`, `entities`, `formUpdates`, `messages`, `typing`, `presence`, `callStatus`.
- No PHI in errors/logs.

**Planned (next increments):**
- `MeetingSession` (multi-party, per-speaker `meeting:transcript`) + meeting AI outputs.
- Agent-workflow APIs (SDK8): queue/incoming-work accept-decline, forms confirm/reject/submit, transcript/entities/suggestions getters, transfer/escalate, bot handoff, contact history, canned responses, summaries.
- Client engagement APIs (SDK9): requestCall/requestVideo/startChat with queue status, callback, green room + waiting-room admit, CSAT.
- Shared (SDK10): attachments, snapshot, push-token register + incoming-push, connection pre-check, theming/white-label, locale, low-data mode.
- UI widgets (Midnight Intelligence): `CallView`, `VideoRoom`, `ChatWidget`, `CopilotPanel`, building blocks.
- Mobile-critical native: CallKit/AVAudioSession (iOS), AudioManager/foreground service (Android), interruptions, route changes (Bluetooth/output indicator), proximity, background continuity, low-data.
- Audio/video QoS streams (MOS/loss/jitter/rtt, fps/freeze) from LiveKit stats.
- Background effects (track processors), device enumeration/output routing, `runAudioTest`.
- Sample apps (patient + agent) + token-minting backend example; CI + `dart analyze`/tests.

## Develop

```sh
cd sdks/flutter/voxaflow_flutter
dart pub get        # or: flutter pub get
dart analyze
```
