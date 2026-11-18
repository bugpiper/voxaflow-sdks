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
  startCall({ callId?, video?, name?, autoRejoin? = true }) -> CallSession        // requires joinCall/joinVideo
  joinMeeting(meetingId, { video?, displayName?, role?, language?, autoRejoin? = true }) -> MeetingSession  // joinCall/joinVideo
  createMeeting({ type?, title? }) -> { meetingId, roomName }  // callControl (AGENT+)
  openChat({ conversationId? | channel?, contactIdentifier?, language? }) -> ChatSession  // requires chat
  setPresence(status)                                          // requires presence (AGENT+)

  // Client engagement (SDK9):
  requestCall(handle, { name?, audioOnly? }) -> { callId, … }  // requires joinCall

  // Directed ringing (SDK10) — "dial user X → ring → accept/reject/connect":
  inviteUser(toUserId, { video?, name? }) -> { callId, expiresAt }  // requires joinCall
  acceptCall(callId, { video?, name?, autoRejoin? = true }) -> CallSession  // callee answers + joins
  rejectCall(callId, { reason? })                                  // callee declines
  cancelCall(callId)                                               // caller cancels before answer

  // Agent ops + copilot (SDK8) — callId-scoped, capability-gated:
  getActiveCalls() · answerCall(id) · holdCall(id)             // callControl
  transferCall(id, toAgentId)                                  // transfer
  getEntities(id) · confirmEntity(eid) · rejectEntity(eid)     // entities
  getSuggestions(id) · dismissSuggestion(id, sid)              // suggestions
  getForm(id) · editField(id,f,v) · confirmField(id,f) · rejectField(id,f) · submitForm(id)  // forms
  getSummary(id)                                               // copilot

  events: connectionState, transcript, entityExtracted, formUpdate, message, typing,
          presence, callStatus, meetingTranscript, meetingParticipant, meetingOutput, error,
          incomingCalls (VoxaCallRing), callSignals (accepted/rejected/canceled/timeout)

CallSession   (wraps the platform LiveKit Room — `lkRoom`/`room` escape hatch)
  setMicEnabled(bool) · setMuted(bool) · setCameraEnabled(bool)
  startScreenShare() · stopScreenShare() · hold() · resume() · end()
  // Auto-rejoin (see §3.1) — same on MeetingSession:
  state · rejoinNow() · rejoinAttemptNumber
  events: connectionState (connected|reconnecting|disconnected — THIS session's media link),
          rejoinAttempt { attempt, nextDelayMs }

ChatSession
  conversationId · sendMessage(text) -> id · setTyping(bool) · markRead() · leave()
  (bot messages: isBot=true, isDraft for BOT_ASSISTED drafts, botMeta payload)
```

| Concept | Web (`web-core`/`react`) | React Native | Flutter | iOS (Swift) | Android (Kotlin) |
|---|---|---|---|---|---|
| async | `Promise` | `Promise` | `Future` | `async/await` | `suspend` |
| events | typed `EventEmitter` | (same) | `Stream` | Combine publishers | `Flow` |

### 3.1 Auto-rejoin (Meet-style) — identical semantics on all 5 platforms

When the LiveKit connection drops (phone locked / app backgrounded, network lost, media node
restarted) the session re-joins **the same room** instead of ending the call:

1. **Never rejoin** intentional ends: user left / `end()`, duplicate identity (joined elsewhere),
   participant removed, room deleted/closed. (iOS: a clean disconnect — `error == nil` — or
   `.cancelled` also count as "left".) Everything else → rejoin. `autoRejoin: false` → just `disconnected`.
2. **Fresh join**: new token (`POST /rtc/token` or `/meetings/:id/token`, same id) → connect the
   *same* Room object (app listeners/views survive) → restore the user's **current** mic/cam choice
   → re-subscribe the realtime socket (`call:join` / meeting join).
3. **Backoff** before each try: 500 ms, 2 s, 5 s, 10 s, 20 s, then **30 s repeating**.
4. **Wait until ready** before each try: foreground/visible **and** online (web: `visibilityState`
   + `navigator.onLine`; Android: activity lifecycle + `ConnectivityManager`; iOS: UIApplication
   notifications + `NWPathMonitor`; Flutter: app lifecycle only — no connectivity plugin is forced,
   offline tries fail fast; RN: `bindAppStateRejoin` wakes on foreground).
5. **Wake early** (skip the rest of the wait) when the network comes back, the app returns to the
   foreground, or the app calls `rejoinNow()`.
6. **Give up** after **10 minutes** of continuous failure → `disconnected`. `rejoinNow()` then
   starts a new loop. `rejoinNow()` is **ignored** while LiveKit's own short resume is running (room
   not yet disconnected — avoids a double connect), while connected, and after `end()`.
7. **Events**: session `connectionState`: `connected → reconnecting → connected` (or
   `→ disconnected` on give-up / intentional end; LiveKit's own short resume also shows as
   `reconnecting`). `rejoinAttempt { attempt, nextDelayMs }` fires **right before each try**
   (`attempt` = tries made; `nextDelayMs` = wait before the next try if this one fails).

Prebuilt UI copy (React `CallView`/`<ReconnectBanner>`, RN `CallView`, Flutter `VoxaCallScreen`/
`VoxaReconnectBanner`): "Connection lost — reconnecting… (attempt n)" + **Rejoin now**; after
give-up "Connection lost. Check your network, then rejoin." + **Rejoin**.

| Platform | session state | attempts | pure logic + tests |
|---|---|---|---|
| Web / RN | `session.on('connectionState')`, `session.state` | `on('rejoinAttempt')` | `web-core/src/sessions/rejoin.ts` (vitest) |
| Flutter | `session.connectionState` (Stream), `state` | `rejoinAttempts` | `lib/src/sessions/rejoin.dart` (flutter test) |
| iOS | `connectionState` (Combine), `state` | `rejoinAttempts` | `Sources/VoxaRejoin` (XCTest, LiveKit-free target) |
| Android | `connectionState` (StateFlow) | `rejoinAttempts` (SharedFlow) | `sessions/Rejoin.kt` (JUnit + coroutines-test) |

Note: the **client** `connectionState` is still the realtime socket; the per-session one above is the media link.

---

## 4. REST endpoints used by SDKs

Base = `config.endpoint` (e.g. `https://voxaflow.fastwheel.ai/api`). All authed with `Authorization: Bearer <token>` unless noted public.

| Method | Path | Body | Response | Used by |
|---|---|---|---|---|
| POST | `/auth/register-end-user` (public) | `{ handle, email, password, name? }` | `{ accessToken, refreshToken, user, tenant }` | `VoxaClient.registerEndUser` (marketplace signup; tenant must opt in via `settings.endUserSignup`) |
| POST | `/rtc/token` (public) | `{ callId, name? }` | `{ token, wsUrl, room, identity, videoConfig }` | `startCall` |
| GET | `/rtc/config/:callId` (public) | — | `{ exists, videoConfig }` | pre-join checks |
| POST | `/chat/widget/:handle/start` (public) | `{ contactIdentifier?, language? }` | `{ conversationId, callId, mode, disclosure, requireConsent }` | `openChat({channel})` |
| GET | `/chat/conversations/:id` | — | `{ conversation, messages[] }` | chat history |
| POST | `/chat/conversations/:id/messages` | `{ content, from? }` | `{ id, botReplied?, escalated? }` | `sendMessage` |
| POST | `/chat/conversations/:id/typing` | — | `204` | `setTyping(true)` |
| POST | `/chat/conversations/:id/read` | — | `200` | `markRead` |
| PUT | `/agents/presence` | `{ status }` | `{ ok, status }` | `setPresence` |
| POST | `/calls/invite` | `{ toUserId, video?, name? }` | `{ callId, expiresAt }` | `inviteUser` (directed ring) |
| POST | `/calls/:id/answer` | — | `{ ok, status }` | `acceptCall` (callee) |
| POST | `/calls/:id/reject` | `{ reason? }` | `{ ok, status }` | `rejectCall` (callee) |
| POST | `/calls/:id/cancel` | — | `{ ok, status }` | `cancelCall` (caller) |
| POST | `/push/devices` | `{ platform, token, voip? }` | `{ ok, count }` | `registerDevice` (background ring delivery) |
| DELETE | `/push/devices` | `{ token }` | `{ ok, count }` | `unregisterDevice` |
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
| `call:ring` | `{ callId, from:{id,name}, video, vertical?, expiresAt }` | `incomingCalls` (VoxaCallRing) |
| `call:accepted` | `{ callId, by }` | `callSignals` (accepted) |
| `call:rejected` | `{ callId, reason? }` | `callSignals` (rejected) |
| `call:canceled` | `{ callId }` | `callSignals` (canceled) |
| `call:timeout` | `{ callId }` | `callSignals` (timeout) |
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
