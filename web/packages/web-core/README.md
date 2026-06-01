# @voxaflow/web-core

Framework-agnostic core of the Voxa Flow Web SDK. Wraps [`livekit-client`](https://www.npmjs.com/package/livekit-client) (media) + the Voxa realtime/REST API (transcripts, entities, suggestions, chat) behind a unified, capability-gated `VoxaClient`. The public API mirrors the Flutter SDK — only the idioms differ (typed `EventEmitter` + Promises).

This is **v0 (core)**. `@voxaflow/react` and `@voxaflow/widget` build on it.

## Install

```sh
npm i @voxaflow/web-core livekit-client socket.io-client
```

`livekit-client` and `socket.io-client` are peer deps.

## Quick start

```ts
import { VoxaClient } from '@voxaflow/web-core';

const client = new VoxaClient({
  endpoint: 'https://voxaflow.fastwheel.ai/api',  // Voxa API base
  token: serverMintedAccessToken,                 // from YOUR backend — never an API secret
  onTokenRefresh: () => myBackend.freshVoxaToken(),
});

await client.connect();

client.on('connectionState', (s) => console.log('conn', s));
client.on('transcript', (s) => console.log(`${s.speaker}: ${s.text} (final=${s.isFinal})`));
client.on('entityExtracted', (e) => console.log('entity', e.entityType, e.value));

const call = await client.startCall({ video: true });
await call.setMicEnabled(true);
await call.setCameraEnabled(false);
// ... later
await call.end();

const chat = await client.openChat({ channel: 'my-web-widget' });
client.on('message', (m) => console.log(m.sender, m.content, m.isBot ? '[bot]' : ''));
await chat.sendMessage('Hello');

await client.disconnect();
```

## API surface (v0)

- `VoxaClient(config)` · `connect()` · `disconnect()` · `can(capability)` · `profile`
- `startCall({ callId?, video?, name? })` → `CallSession` (mic/camera/screen-share/hold/resume/mute/end, `lkRoom`)
- `openChat({ conversationId? | channel? })` → `ChatSession` (send, typing, markRead)
- `setPresence(status)` (AGENT+)
- Events: `connectionState`, `transcript`, `entityExtracted`, `formUpdate`, `message`, `typing`, `presence`, `callStatus`, `error`

## Auth & capability model

Token-only auth (short-lived, server-minted); `onTokenRefresh` re-auths REST **and** the realtime channel on 401. Capability gating derives from the JWT **role** (`AGENT`/`SUPERVISOR`/`ADMIN`/`SUPER_ADMIN`; guests → CLIENT) — calling a method the token can't use throws `VoxaError` with code `CAPABILITY`. No PHI in errors/logs.

## Backend mapping

Wraps the real backend (not the spec's hypothetical `/sdk/join`): `POST /rtc/token` (LiveKit), Socket.IO `/socket.io` (transcript/entity/form/chat/presence/call events), `/chat/*`, `/agents/presence`. See the repo root README.

## Build

```sh
pnpm install
pnpm build      # tsup → ESM + CJS + d.ts
```

## Status

Implemented: client, call, chat, typed events, auth+refresh, capability gating.
Planned: meetings, agent/client workflow APIs, device enumeration/QoS, attachments/screen-share helpers, then `@voxaflow/react` (hooks + components) and `@voxaflow/widget` (embeddable script).
