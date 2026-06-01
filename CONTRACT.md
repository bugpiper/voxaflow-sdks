# Voxa Flow SDK Contract (single source of truth)

The contract every Voxa SDK implements — **unified public API**, **capability model**, **REST endpoints**, and the **Socket.IO event schema**. All platforms (Web, React Native, Flutter, iOS, Android) expose the same concepts; only language idioms differ (Promises / Streams / async-await+Combine / Coroutines+Flow). Keep this doc and every SDK in lockstep; bump the SDK major version with the Voxa API version.

> **Reality note:** the SDKs wrap the **existing** Voxa backend (`apps/api` in the backend monorepo). The all-platforms spec's hypothetical `/sdk/join` endpoint and per-capability token do **not** exist — capabilities are **derived from the JWT `role`** (see §2). When the backend adds an explicit `capabilities` claim, SDKs read it directly with no public API change.

---

## 1. Auth & tokens

- The SDK is initialized with a **short-lived access token minted by the tenant's backend** — never an API/LiveKit secret.
- `onTokenRefresh` is invoked on a `401`/expiry; the SDK transparently re-auths **both** REST and the realtime channel, then retries.
- Token is a JWT. Payload (client-decoded for gating only; the server verifies the signature):

```jsonc
{ "userId": "…", "tenantId": "…", "email": "…", "role": "AGENT", "iat": …, "exp": … }
```

| Endpoint | Body | Returns |
|---|---|---|
| `POST /auth/login` | `{ email, password, tenantSlug? }` | `{ accessToken, refreshToken, tenant, user }` |
| `POST /auth/refresh` | `{ refreshToken }` | `{ accessToken, refreshToken }` (rotated, single-use) |

Access token TTL ≈ 15m; refresh ≈ 7d (server/Redis). **Tenants mint SDK tokens server-side**; the SDK only consumes them.

---

## 2. Capability model

`role` → derived capability set. SDKs gate methods on capabilities and throw `CAPABILITY` if not permitted (the server is the real enforcement point).

| Role | Capabilities |
|---|---|
| **CLIENT** (guest/contact; no role) | `joinCall, joinVideo, chat, consent` |
| **AGENT** | CLIENT + `callControl, video, copilot, transcript, entities, suggestions, forms, presence, queue, transfer, escalate, botHandoff` |
| **SUPERVISOR** / **ADMIN** / **SUPER_ADMIN** | AGENT + `monitor, whisper, barge, analytics` |

---

## 3. Unified SDK API

Same surface on every platform (idioms differ):

```
VoxaClient(config: { endpoint, token, onTokenRefresh? })
  connect() · disconnect() · can(capability) · profile{ role, capabilities, tenantId, userId }
  startCall({ callId?, video?, name? }) -> CallSession        // requires joinCall/joinVideo
  openChat({ conversationId? | channel?, contactIdentifier?, language? }) -> ChatSession  // requires chat
  setPresence(status)                                          // requires presence (AGENT+)
  events: connectionState, transcript, entityExtracted, formUpdate, message, typing,
          presence, callStatus, error

CallSession   (wraps the platform LiveKit Room — `lkRoom`/`room` escape hatch)
  setMicEnabled(bool) · setMuted(bool) · setCameraEnabled(bool)
  startScreenShare() · stopScreenShare() · hold() · resume() · end()

ChatSession
  conversationId · sendMessage(text) -> id · setTyping(bool) · markRead() · leave()
  (bot messages: isBot=true, isDraft for BOT_ASSISTED drafts, botMeta payload)
```

| Concept | Web (`web-core`/`react`) | React Native | Flutter | iOS (Swift) | Android (Kotlin) |
|---|---|---|---|---|---|
| async | `Promise` | `Promise` | `Future` | `async/await` | `suspend` |
| events | typed `EventEmitter` | (same) | `Stream` | Combine publishers | `Flow` |

---

## 4. REST endpoints used by SDKs

Base = `config.endpoint` (e.g. `https://voxaflow.fastwheel.ai/api`). All authed with `Authorization: Bearer <token>` unless noted public.

| Method | Path | Body | Response | Used by |
|---|---|---|---|---|
| POST | `/rtc/token` (public) | `{ callId, name? }` | `{ token, wsUrl, room, identity, videoConfig }` | `startCall` |
| GET | `/rtc/config/:callId` (public) | — | `{ exists, videoConfig }` | pre-join checks |
| POST | `/chat/widget/:handle/start` (public) | `{ contactIdentifier?, language? }` | `{ conversationId, callId, mode, disclosure, requireConsent }` | `openChat({channel})` |
| GET | `/chat/conversations/:id` | — | `{ conversation, messages[] }` | chat history |
| POST | `/chat/conversations/:id/messages` | `{ content, from? }` | `{ id, botReplied?, escalated? }` | `sendMessage` |
| POST | `/chat/conversations/:id/typing` | — | `204` | `setTyping(true)` |
| POST | `/chat/conversations/:id/read` | — | `200` | `markRead` |
| PUT | `/agents/presence` | `{ status }` | `{ ok, status }` | `setPresence` |
| POST | `/meetings` · POST `/meetings/:id/token` | … | LiveKit token | `joinMeeting` (planned) |
| GET/PUT | `/calls/:id/form`, `/calls/:id/entities`, `/calls/:id/suggestions`, `/calls/:id/summary` | … | … | agent copilot APIs (planned) |

`videoConfig` (from `/rtc/token`) drives green room / waiting room / codec / background / low-data — see backend `rtc.ts`.

---

## 5. Realtime (Socket.IO)

- URL = the **origin** of `endpoint`; path `/socket.io`; transport `websocket`.
- Auth: JWT in the connection handshake (`auth.token` on web/RN/Flutter; `connect(withPayload:["token":…])` on iOS).
- On connect, the socket auto-joins `tenant:{tenantId}` + `user:{userId}`. Join per-context rooms with the client→server events below. On `call:join`, the server replays the last ~100 transcript segments.

### Client → Server
`call:join(callId)` · `call:leave(callId)` · `meeting:join(id)` · `meeting:leave(id)` · `chat:join(conversationId)` · `chat:leave(conversationId)`

### Server → Client (event → SDK event)

| Socket event | Payload | SDK event |
|---|---|---|
| `transcript:update` | `{ id?, speaker, text, isFinal, confidence?, language?, startTime?, endTime? }` | `transcript` |
| `entity:extracted` | `{ id, entityType, entityCategory, value, code?, codeSystem?, confidence?, negated? }` | `entityExtracted` |
| `form:autofill` | `{ fieldId, value, confidence? }` | `formUpdate` |
| `chat:message` | `{ id, conversationId, sender, content, botMeta?, createdAt }` | `message` |
| `chat:draft` | same as `chat:message` (sender `BOT`) | `message` (isDraft) |
| `chat:typing` | `{ conversationId, sender }` | `typing` |
| `presence:update` | `{ userId, status }` | `presence` |
| `call:status` | `{ callId, status, durationSeconds? }` | `callStatus` |
| `call:incoming`, `call:transfer`, `call:supervisor`, `waiting:update`, `meeting:transcript`, `meeting:output`, `meeting:participant`, `chat:status` | see backend `shared-types` | (planned SDK surfacing) |

`speaker` ∈ `AGENT`/`CALLER`; `sender` ∈ `CONTACT`/`AGENT`/`BOT`/`SYSTEM`; `status` ∈ call/presence enums.

---

## 6. Errors

`VoxaError { code, message, status? }` with codes: `AUTH`, `CAPABILITY`, `CONNECTION`, `DEVICE`, `MEDIA`, `SERVER`. **No PHI** (transcript/message content) in errors, logs, or telemetry — enforced on every platform.

---

## 7. Versioning & consistency

- The public API + event names + capability model are **identical** across platforms (idioms aside) — this doc is the reference.
- Pin and test the wrapped LiveKit client version per platform on every release.
- Media (`livekit-client` / `@livekit/react-native` / `livekit_client` / LiveKit Swift/Android) is loaded **only when a call starts** where the platform allows (e.g. web-core lazy-imports it) so chat-only consumers stay lean.
- Shared scenario tests (connect → call → transcript → chat+bot → device switch → reconnect) should run against each platform's sample app.
