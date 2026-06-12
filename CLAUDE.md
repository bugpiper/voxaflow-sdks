# VoxaFlow SDKs — context for Claude

These are the **client SDKs** for VoxaFlow — a separate repo from the backend monorepo
(`github.com:bugpiper/voxaflow`). The SDKs wrap the **live** Voxa backend; they do not contain it.

## What this repo is

One unified, capability-gated client (`VoxaClient`) shipped on **5 platforms**, each wrapping the
platform's LiveKit client (media) + the Voxa realtime (Socket.IO) + REST. The **public API is
conceptually identical on every platform** — only language idioms differ.

| Platform | Path | Idioms |
|---|---|---|
| Flutter (Dart) | `flutter/voxaflow_flutter` | Futures + Streams |
| Web (TypeScript) | `web/packages/web-core`, `web/packages/react`, `web/packages/widget` | Promises + typed EventEmitter |
| React Native | `web/packages/react-native` | reuses web-core + react |
| iOS (Swift) | `ios/Sources/VoxaSDK` | async/await + Combine |
| Android (Kotlin) | `android/voxa-sdk` | coroutines + Flow |

## ⭐ The cardinal rule: CONTRACT.md is the source of truth

**[`CONTRACT.md`](CONTRACT.md)** defines the unified API, capability model, REST endpoints, and the
Socket.IO event schema. **Any change to the client surface must (a) be mirrored on all 5 platforms and
(b) update CONTRACT.md.** When porting, read the Flutter + web-core implementations first — they are
the reference; iOS/Android/RN mirror them.

## Shared principles (enforce on every platform)

- **Wrap, don't rebuild.** Media via the LiveKit client; transcript/entities/chat/ring via Voxa
  realtime + REST. Never bundle the LiveKit client unless a call actually starts (lazy-load on web).
- **Token-only auth.** Initialized with a short-lived access token minted by the tenant's backend
  (never an API secret); auto-refresh via `onTokenRefresh`.
- **Capabilities come from the JWT role** (`AGENT`/`SUPERVISOR`/`ADMIN`/`SUPER_ADMIN`/`END_USER`;
  guest/unknown → `CLIENT`). Client-side gating is for UX only — the backend is the real enforcer.
- **No PHI in logs** (transcript/message content), ever, on any platform.

## What the backend provides (it lives in the OTHER repo)

`bugpiper/voxaflow`, branch `deploy/minimal-single-vm` (live single-VM astro deploy). Endpoints the
SDKs use: `POST /rtc/token`, `/calls/*` (incl. **directed ring**: `/calls/invite`, `/calls/:id/answer`
`/reject` `/cancel`), `/chat/*`, `/meetings/*`, `/agents/presence`, **`/push/devices`**,
**`/tenant/push-config`**; Socket.IO event catalog (transcript/entities/chat/presence/callStatus +
the `call:ring`/`accepted`/`rejected`/`canceled`/`timeout` ring events). **If an SDK change needs new
backend behavior, it must land in that repo too** (shared code is portable to the K8s env).

## Feature areas (current)

- **Calls / meetings / chat** — `startCall`, `joinMeeting`/`createMeeting`, `openChat`; live AI event
  streams (transcript/entities/suggestions/forms); agent copilot + ops.
- **Directed ring** ("dial user X → ring → accept/reject/connect") — events `incomingCalls`
  (`VoxaCallRing`) + `callSignals`; methods `inviteUser`/`acceptCall`/`rejectCall`/`cancelCall`.
- **Background/killed-app push** — `registerDevice`/`unregisterDevice`; server delivers a data push
  (FCM / APNs-VoIP) **per tenant** (creds set on the backend via `/tenant/push-config`). Native display
  on Flutter is `VoxaCallKit` (see `flutter/voxaflow_flutter/NATIVE_CALL_SETUP.md`).
- **Prebuilt UI** — Flutter: `VoxaCallScreen` / `VoxaIncomingCallScreen` / `VoxaCallOverlay` (+
  `VoxaParticipantTile`/`VoxaCallControlBar`/`VoxaCallTheme`). React: `CallView`/`ChatWidget`/
  `CopilotPanel`/`<IncomingCallModal>` + hooks (`useVoxaCall`/`useIncomingCall`/…).

## Build / validate per platform (do this after any change)

```sh
# Flutter
cd flutter/voxaflow_flutter && flutter pub get && dart analyze
# Web (web-core + react + widget)
cd web && pnpm install && pnpm -r build
# iOS (full LiveKit compile needs Xcode; CLT does a lot)
cd ios && swift build
# Android (pinned Gradle 8.9 wrapper; SDK at ~/Library/Android/sdk)
cd android && ./gradlew :voxa-sdk:assembleDebug
```

Toolchains present locally: flutter/dart (`/opt/homebrew/bin`), pnpm 9 + node 20, swift (CLT),
Android SDK + gradle wrapper. LiveKit **media** can't be verified headless — needs a real device/browser.

## Conventions

- Mirror the same public API names/shapes on every platform; keep CONTRACT.md in lockstep.
- Prebuilt UI is themeable (`VoxaCallTheme` / inline styles) and optional — the raw `lkRoom`/`room`
  escape hatch is always available for custom UI.
- Not published to package registries yet — consume via path/workspace.
- See [`HANDOFF.md`](HANDOFF.md) for the working state + Flutter/web-core quickstart, and
  [`README.md`](README.md) for the feature how-tos.
