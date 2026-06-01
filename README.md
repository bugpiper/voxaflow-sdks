# Voxa Flow SDKs

Client SDKs for [Voxa Flow](https://voxaflow.com) — embed Voxa voice, video, chat, transcripts and AI events into your app. Each SDK wraps the corresponding LiveKit client and adds the Voxa layer (token auth, role/capability gating, realtime AI event stream, chat + bot, consent, device controls, optional UI).

The **public API is conceptually identical across platforms** — only language idioms differ (Futures/Streams · Promises · async-await+Combine · Coroutines+Flow).

## Platforms

| Platform | Path | Status |
|----------|------|--------|
| Flutter (Dart) | [`flutter/voxaflow_flutter`](flutter/voxaflow_flutter) | **v0 core** — client, call, chat, event streams |
| Web (TypeScript) | `web/` | planned |
| React Native | `react-native/` | planned |
| iOS (Swift) | `ios/` | planned |
| Android (Kotlin) | `android/` | planned |

## Shared principles (all platforms)

- **Token-only auth**: initialized with a short-lived access token minted by the tenant's backend (never an API secret); auto-refresh via `onTokenRefresh`.
- **Wrap, don't rebuild**: media via the LiveKit client; transcript/entities/suggestions/chat via the Voxa realtime (Socket.IO) + REST.
- **Unified API**: `VoxaClient` (connect/disconnect), `startCall`/`joinMeeting`/`openChat`, device controls, consent, and a common event set.
- **Capability gating** comes from the token. **Never log PHI** (transcript/message content).

## Backend contract

These SDKs wrap the live Voxa backend (the monorepo's `apps/api`). The current backend authorizes by **role** (`AGENT`/`SUPERVISOR`/`ADMIN`/`SUPER_ADMIN`); SDKs derive a capability set from it. See each platform's README for the concept→endpoint mapping. The single source-of-truth contract doc lives at [`CONTRACT.md`](CONTRACT.md) *(to be added)*.

## License

Proprietary © Voxa Flow.
