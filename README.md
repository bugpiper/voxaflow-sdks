# Voxa Flow SDKs

Client SDKs for [Voxa Flow](https://voxaflow.com) — embed Voxa voice, video, chat, transcripts and AI events into your app. Each SDK wraps the corresponding LiveKit client and adds the Voxa layer (token auth, role/capability gating, realtime AI event stream, chat + bot, consent, device controls, **directed ringing**, **push**, and **prebuilt UI**).

The **public API is conceptually identical across platforms** — only language idioms differ (Futures/Streams · Promises · async-await+Combine · Coroutines+Flow). The single source of truth is **[`CONTRACT.md`](CONTRACT.md)**.

## Platforms

| Platform | Path | Status |
|----------|------|--------|
| Flutter (Dart) | [`flutter/voxaflow_flutter`](flutter/voxaflow_flutter) | **v0** — client, call, meeting, chat, copilot, **directed ring**, **prebuilt UI**, `VoxaCallKit` |
| Web core (TypeScript) | [`web/packages/web-core`](web/packages/web-core) | **v0** — full client + sessions + ring + push |
| React (components/hooks) | [`web/packages/react`](web/packages/react) | **v0** — `CallView`/`ChatWidget`/`CopilotPanel`/`IncomingCallModal` + hooks |
| Web widget (CDN) | [`web/packages/widget`](web/packages/widget) | **v0** — embeddable chat widget |
| React Native | [`web/packages/react-native`](web/packages/react-native) | **v0** — wraps web-core + react |
| iOS (Swift) | [`ios`](ios) | **v0** — full client + sessions + ring + push |
| Android (Kotlin) | [`android`](android) | **v0** — full client + sessions + ring + push |

## Shared principles (all platforms)

- **Token-only auth**: initialized with a short-lived access token minted by the tenant's backend (never an API secret); auto-refresh via `onTokenRefresh`.
- **Wrap, don't rebuild**: media via the LiveKit client; transcript/entities/suggestions/chat/ring via the Voxa realtime (Socket.IO) + REST. The LiveKit client is only loaded when a call actually starts.
- **Unified API**: `VoxaClient` (connect/disconnect), `startCall`/`joinMeeting`/`openChat`, `inviteUser`, device controls, consent, and a common event set.
- **Capability gating** comes from the JWT role (`AGENT`/`SUPERVISOR`/`ADMIN`/`SUPER_ADMIN`/`END_USER`; guest → `CLIENT`). **Never log PHI** (transcript/message content).

---

## Quickstart

```dart
// Flutter
final client = VoxaClient(VoxaConfig(
  endpoint: 'https://voxaflow.fastwheel.ai/api',
  token: await myBackend.voxaToken(),       // your backend mints a short-lived Voxa JWT
  onTokenRefresh: () => myBackend.voxaToken(),
));
await client.connect();
final call = await client.startCall(video: true);
client.transcript.listen((s) => print('${s.speaker}: ${s.text}'));
```

```ts
// Web
import { VoxaClient } from '@voxaflow/web-core';
const client = new VoxaClient({ endpoint, token, onTokenRefresh });
await client.connect();
const call = await client.startCall({ video: true });
client.on('transcript', (s) => console.log(s.speaker, s.text));
```

Same shape on iOS (`async/await` + Combine), Android (`suspend` + `Flow`), and React Native.

---

## Directed ringing — "dial user X → ring → accept / reject / connect"

A 1:1 invite that rings **a specific user** (vs `requestCall`, which drops into a shared queue). Works the same on every platform.

**Caller** rings someone and waits for the result:

```dart
// Flutter
final inv = await client.inviteUser(astrologerUserId, video: true);   // -> { callId, expiresAt }
client.callSignals.listen((sig) async {
  switch (sig.kind) {
    case VoxaCallSignalKind.accepted:
      final call = await client.startCall(callId: inv.callId, video: true); // join the room
      break;
    case VoxaCallSignalKind.rejected:
    case VoxaCallSignalKind.timeout:
      // tear down the "calling…" UI
      break;
    case VoxaCallSignalKind.canceled:
      break;
  }
});
// client.cancelCall(inv.callId);   // give up before they answer
```

**Callee** listens for incoming rings and answers:

```dart
client.incomingCalls.listen((ring) async {
  // ring.fromName / ring.video / ring.callId / ring.expiresAt
  final accepted = await showYourRingUI(ring);            // or VoxaIncomingCallScreen (below)
  if (accepted) {
    final call = await client.acceptCall(ring.callId, video: ring.video); // answers + joins
  } else {
    await client.rejectCall(ring.callId, reason: 'busy');
  }
});
```

```ts
// Web / React
const { callId } = await client.inviteUser(astrologerUserId, { video: true });
client.on('incomingCall', (ring) => { /* show UI */ });
client.on('callSignal', (s) => { if (s.kind === 'accepted') client.startCall({ callId, video: true }); });
// React: <IncomingCallModal onAccepted={(call) => openCallUI(call)} /> + useIncomingCall()
```

Socket events behind it (server → client): `call:ring` · `call:accepted` · `call:rejected` · `call:canceled` · `call:timeout`. REST: `POST /calls/invite`, `/calls/:id/{answer,reject,cancel}`. See [`CONTRACT.md`](CONTRACT.md).

> **Marketplace identity:** the callee is any user in your tenant. A customer logs in with the **`END_USER`** role (client capabilities) and can `inviteUser(agentId)`.

---

## Prebuilt UI

You can build your own UI on the raw `call.lkRoom` escape hatch, or drop in the shipped widgets.

### Flutter

```dart
import 'package:voxaflow_flutter/voxaflow_flutter.dart';

// In-call screen (1:1 or meeting): adaptive video grid + PiP + screen-share,
// control bar, timer, optional live transcript.
Navigator.push(context, MaterialPageRoute(builder: (_) => VoxaCallScreen(
  session: call, client: client, title: 'Consultation', showTranscript: true,
  onEnded: () => Navigator.pop(context),
)));

// Incoming ring screen (foreground):
VoxaIncomingCallScreen(
  call: VoxaIncomingCall(callId: ring.callId, callerName: ring.fromName, video: ring.video),
  onAccept: ({required video}) async { /* client.acceptCall(...) */ },
  onDecline: () { /* client.rejectCall(...) */ },
);

// Floating mini-call over the whole app:
final overlay = VoxaCallOverlayController();
overlay.show(context, session: call, onTap: () { overlay.hide(); /* reopen full screen */ });
```

Building blocks: `VoxaParticipantTile`, `VoxaCallControlBar`, `VoxaCallTheme` (Midnight tokens; `.midnight()` / `.light()`).

### React

```tsx
import { CallView, ChatWidget, CopilotPanel, IncomingCallModal, useIncomingCall } from '@voxaflow/react';

<IncomingCallModal onAccepted={(call) => openCallUI(call)} />   // auto-subscribes to rings
<CallView video />            // start/controls + live transcript
<ChatWidget channel="astrology-web" />
<CopilotPanel callId={callId} />   // agent: transcript + entities + suggestions
```

---

## Push notifications (background / killed-app ringing)

A live socket delivers `call:ring` to a **foregrounded** app. To ring a **backgrounded or killed** app you also need a high-priority **data push** that wakes it: **FCM data** (Android/web) or **APNs VoIP/PushKit** (iOS, for CallKit). This is **per-tenant** — each tenant ships its own app, so each brings its own Firebase project + Apple bundle id.

### One-time backend setup (per tenant, admin)

The tenant's backend/admin uploads its own credentials (stored per-tenant, write-only — never returned):

```http
PUT /api/tenant/push-config            # ADMIN / SUPER_ADMIN
{
  "fcm":  { "serviceAccount": { ...firebase-service-account.json... } },
  "apns": {
    "key": "-----BEGIN PRIVATE KEY-----\n...AuthKey_XXXX.p8...\n-----END PRIVATE KEY-----",
    "keyId": "ABC123DEFG", "teamId": "TEAM123456",
    "topic": "<your.bundle.id>.voip",   // APNs VoIP topic = bundleId + ".voip"
    "production": true
  }
}
# remove later: { "clear": ["fcm"] }   ·   GET /api/tenant returns "***configured***"
```

> **APNs VoIP key** = a `.p8` token-auth key (+ Key ID + Team ID) that authorizes VoIP/PushKit pushes; the topic `<bundleId>.voip` binds it to your app. (A legacy `.p12` VoIP cert per bundle id also works.) These do **not** go in the server's environment — they're stored per-tenant in the backend.

### App side

1. **Register the device token** (so the server knows where to push):

```dart
// Flutter — after getting the FCM token / iOS VoIP (PushKit) token
await client.registerDevice(platform: 'android', token: fcmToken);
await client.registerDevice(platform: 'ios', token: await VoxaCallKit.voipPushToken(), voip: true);
// client.unregisterDevice(token) on logout
```

2. **Show the native incoming UI** when the push arrives — on Flutter this is `VoxaCallKit`:

```dart
// in your FCM data handler / iOS PushKit handler:
await VoxaCallKit.handleIncomingPush(pushData);     // shows CallKit / full-screen ringing
VoxaCallKit.actions.listen((a) async {
  if (a.type == VoxaCallActionType.accepted) {
    await client.connect();
    final call = await client.acceptCall(a.callId);
  }
});
```

3. **Native wiring** (entitlements / `Info.plist` / `AndroidManifest` / a `FirebaseMessagingService` whose data handler calls `handleIncomingPush`) — see **[`flutter/voxaflow_flutter/NATIVE_CALL_SETUP.md`](flutter/voxaflow_flutter/NATIVE_CALL_SETUP.md)**. Verify on a **real device** (push can't be exercised headless).

### End-to-end flow

`registerDevice` → caller `inviteUser(calleeId)` → backend emits `call:ring` to the live socket **and** `deliverCallPush` sends a data push through **that tenant's** FCM/APNs → killed app wakes → `VoxaCallKit.handleIncomingPush` rings → `acceptCall(callId)` joins the room.

---

## Build & validate

```sh
cd flutter/voxaflow_flutter && flutter pub get && dart analyze        # Flutter
cd web && pnpm install && pnpm -r build                              # web-core + react + widget
cd ios && swift build                                                # iOS (full media needs Xcode)
cd android && ./gradlew :voxa-sdk:assembleDebug                      # Android (Gradle 8.9 wrapper)
```

LiveKit **media** (call audio/video) is a thin wrapper over the battle-tested LiveKit client but can only be verified on a real device/browser, not headless.

## Docs

- **[`CONTRACT.md`](CONTRACT.md)** — the unified API, capability model, REST + Socket.IO schema (source of truth).
- **[`HANDOFF.md`](HANDOFF.md)** — working state + Flutter/web-core quickstart and validation status.
- **[`CLAUDE.md`](CLAUDE.md)** — repo context + conventions for contributors (and Claude).
- **[`flutter/voxaflow_flutter/NATIVE_CALL_SETUP.md`](flutter/voxaflow_flutter/NATIVE_CALL_SETUP.md)** — native CallKit / push wiring.

## License

Proprietary © Voxa Flow.
