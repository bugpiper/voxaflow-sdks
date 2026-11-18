import { EventEmitter } from 'eventemitter3';
import { TokenProfile, type Capability } from './capabilities.js';
import { VoxaError } from './errors.js';
import type { VoxaConfig } from './config.js';
import type { VoxaEventMap } from './events.js';
import { VoxaRest } from './transport/rest.js';
import { VoxaRealtime } from './transport/realtime.js';
import { CallSession } from './sessions/call.js';
import { ChatSession } from './sessions/chat.js';
import { MeetingSession } from './sessions/meeting.js';
import { parseEntity, type ExtractedEntity, type Suggestion, type CallInfo, type FormState } from './models.js';

/**
 * Entry point of the Voxa Flow Web SDK core. Same concepts as the Flutter/RN/iOS/Android
 * SDKs — only the idioms (typed EventEmitter + Promises) differ.
 *
 * ```ts
 * const client = new VoxaClient({ endpoint, token, onTokenRefresh });
 * await client.connect();
 * client.on('transcript', (s) => console.log(s.speaker, s.text));
 * const call = await client.startCall({ video: true });
 * ```
 */
export class VoxaClient extends EventEmitter<VoxaEventMap> {
  readonly profile: TokenProfile;
  private readonly rest: VoxaRest;
  private readonly realtime: VoxaRealtime;
  private connected = false;

  constructor(config: VoxaConfig) {
    super();
    this.profile = TokenProfile.fromToken(config.token);
    this.rest = new VoxaRest(config.endpoint, config.token, config.onTokenRefresh);
    this.realtime = new VoxaRealtime(config.endpoint, config.token, this);
    // When REST refreshes the token, re-auth the realtime channel too.
    this.rest.onTokenChanged = (t) => this.realtime.updateToken(t);
  }

  can(c: Capability): boolean {
    return this.profile.can(c);
  }

  /** Self-serve marketplace signup (bootstrap — no token needed). Registers an
   *  `END_USER` under `handle` (the tenant slug) and returns the auth result; build a
   *  `VoxaClient` with the returned `accessToken`. The tenant must have enabled public
   *  end-user signup. */
  static async registerEndUser(opts: {
    endpoint: string;
    handle: string;
    email: string;
    password: string;
    name?: string;
  }): Promise<{ accessToken: string; refreshToken: string; user: Record<string, unknown>; tenant: Record<string, unknown> }> {
    const res = await fetch(`${opts.endpoint}/auth/register-end-user`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ handle: opts.handle, email: opts.email, password: opts.password, ...(opts.name ? { name: opts.name } : {}) }),
    }).catch((cause) => {
      throw new VoxaError('CONNECTION', 'Network error during signup', { cause });
    });
    const body = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    if (!res.ok) {
      const code = res.status === 401 || res.status === 403 || res.status === 409 ? 'AUTH' : 'SERVER';
      throw new VoxaError(code, (body.message as string) ?? 'Signup failed', { status: res.status });
    }
    return body as { accessToken: string; refreshToken: string; user: Record<string, unknown>; tenant: Record<string, unknown> };
  }

  /** Open the realtime channel and validate the token. */
  async connect(): Promise<void> {
    if (this.connected) return;
    try {
      await this.realtime.connect();
      this.connected = true;
    } catch (cause) {
      if (cause instanceof VoxaError) throw cause;
      throw new VoxaError('CONNECTION', 'Failed to open the Voxa realtime channel', { cause });
    }
  }

  /** Tear down realtime + REST. End sessions first. */
  async disconnect(): Promise<void> {
    this.connected = false;
    this.realtime.dispose();
  }

  /** Start (or join) a voice/video call. Omit `callId` for an ephemeral room. */
  async startCall(opts: { callId?: string; video?: boolean; name?: string; autoRejoin?: boolean } = {}): Promise<CallSession> {
    this.profile.requireCapability(opts.video ? 'joinVideo' : 'joinCall');
    this.ensureConnected();
    return CallSession.start({
      rest: this.rest,
      realtime: this.realtime,
      callId: opts.callId ?? ephemeralId('call'),
      video: opts.video,
      name: opts.name,
      autoRejoin: opts.autoRejoin,
    });
  }

  /** Create a multi-party meeting (AGENT+); returns its id + room name. */
  async createMeeting(opts: { type?: string; title?: string } = {}): Promise<{ meetingId: string; roomName: string }> {
    this.profile.requireCapability('callControl');
    this.ensureConnected();
    return this.rest.post<{ meetingId: string; roomName: string }>('/meetings', opts);
  }

  /** Join a multi-party meeting by id. Per-speaker transcript / participant / output events
   *  arrive on the meeting* events. */
  async joinMeeting(meetingId: string, opts: { video?: boolean; displayName?: string; role?: string; language?: string; autoRejoin?: boolean } = {}): Promise<MeetingSession> {
    this.profile.requireCapability(opts.video ? 'joinVideo' : 'joinCall');
    this.ensureConnected();
    return MeetingSession.join({ rest: this.rest, realtime: this.realtime, meetingId, ...opts });
  }

  /** Open a chat conversation (attach to `conversationId`, or start one on a `channel` handle). */
  async openChat(opts: {
    conversationId?: string;
    channel?: string;
    contactIdentifier?: string;
    language?: string;
  } = {}): Promise<ChatSession> {
    this.profile.requireCapability('chat');
    this.ensureConnected();
    return ChatSession.open({ rest: this.rest, realtime: this.realtime, ...opts });
  }

  /** Set the agent's presence (AGENT+). */
  async setPresence(status: string): Promise<void> {
    this.profile.requireCapability('presence');
    await this.rest.put('/agents/presence', { status });
  }

  // ── Client engagement (SDK9) ───────────────────────────────────────────────

  /** Click-to-call: place an inbound call on a tenant handle; returns the new callId. */
  async requestCall(handle: string, opts: { name?: string; audioOnly?: boolean } = {}): Promise<{ callId: string; vertical?: string; routedTo?: string }> {
    this.profile.requireCapability('joinCall');
    const res = await this.rest.post<{ callId: string; vertical?: string; routedTo?: string }>(`/calls/dial/${handle}`, opts);
    return res;
  }

  // ── Directed ringing (SDK10): "dial user X → ring → accept/reject/connect" ──

  /** Ring a specific user in your tenant. The callee gets an `incomingCall` event;
   *  you get a `callSignal` (accepted → then `startCall(callId)`, or rejected/timeout). */
  async inviteUser(toUserId: string, opts: { video?: boolean; name?: string } = {}): Promise<{ callId: string; expiresAt?: string }> {
    this.profile.requireCapability('joinCall');
    this.ensureConnected();
    return this.rest.post<{ callId: string; expiresAt?: string }>('/calls/invite', { toUserId, video: opts.video ?? false, ...(opts.name ? { name: opts.name } : {}) });
  }

  /** Accept an incoming ring as the callee, then join its room. */
  async acceptCall(callId: string, opts: { video?: boolean; name?: string; autoRejoin?: boolean } = {}): Promise<CallSession> {
    this.ensureConnected();
    await this.rest.post(`/calls/${callId}/answer`);
    return CallSession.start({ rest: this.rest, realtime: this.realtime, callId, video: opts.video, name: opts.name, autoRejoin: opts.autoRejoin });
  }

  /** Decline an incoming ring as the callee. */
  async rejectCall(callId: string, opts: { reason?: string } = {}): Promise<void> {
    await this.rest.post(`/calls/${callId}/reject`, opts.reason ? { reason: opts.reason } : undefined);
  }

  /** Cancel a ring you placed, before it's answered. */
  async cancelCall(callId: string): Promise<void> {
    await this.rest.post(`/calls/${callId}/cancel`);
  }

  /** Register this browser/device push token for background incoming-call delivery
   *  (gated on backend push creds). `platform` is 'web' | 'ios' | 'android'. */
  async registerDevice(platform: 'web' | 'ios' | 'android', token: string, opts: { voip?: boolean } = {}): Promise<void> {
    await this.rest.post('/push/devices', { platform, token, ...(opts.voip ? { voip: true } : {}) });
  }
  async unregisterDevice(token: string): Promise<void> {
    await this.rest.delete('/push/devices', { token });
  }

  // ── Agent operations (SDK8) ────────────────────────────────────────────────

  /** Active calls visible to this agent (own + shared queue). */
  async getActiveCalls(): Promise<CallInfo[]> {
    this.profile.requireCapability('callControl');
    const res = await this.rest.get<{ calls?: CallInfo[] }>('/calls');
    return res.calls ?? [];
  }
  async answerCall(callId: string): Promise<void> {
    this.profile.requireCapability('callControl');
    await this.rest.post(`/calls/${callId}/answer`);
  }
  async holdCall(callId: string): Promise<void> {
    this.profile.requireCapability('callControl');
    await this.rest.post(`/calls/${callId}/hold`);
  }
  async transferCall(callId: string, toAgentId: string): Promise<void> {
    this.profile.requireCapability('transfer');
    await this.rest.post(`/calls/${callId}/transfer`, { toAgentId });
  }

  // ── Agent copilot: entities (SDK8) ─────────────────────────────────────────
  async getEntities(callId: string): Promise<ExtractedEntity[]> {
    this.profile.requireCapability('entities');
    const res = await this.rest.get<{ entities?: Record<string, unknown>[] }>(`/calls/${callId}/entities`);
    return (res.entities ?? []).map(parseEntity);
  }
  async confirmEntity(entityId: string): Promise<void> {
    this.profile.requireCapability('entities');
    await this.rest.put(`/entities/${entityId}/confirm`);
  }
  async rejectEntity(entityId: string): Promise<void> {
    this.profile.requireCapability('entities');
    await this.rest.put(`/entities/${entityId}/reject`);
  }

  // ── Agent copilot: suggestions (SDK8) ──────────────────────────────────────
  async getSuggestions(callId: string): Promise<Suggestion[]> {
    this.profile.requireCapability('suggestions');
    const res = await this.rest.get<{ suggestions?: Suggestion[] }>(`/calls/${callId}/suggestions`);
    return res.suggestions ?? [];
  }
  async dismissSuggestion(callId: string, suggestionId: string): Promise<void> {
    this.profile.requireCapability('suggestions');
    await this.rest.post(`/calls/${callId}/suggestions/${suggestionId}/dismiss`);
  }

  // ── Agent copilot: smart form (SDK8) ───────────────────────────────────────
  async getForm(callId: string): Promise<FormState> {
    this.profile.requireCapability('forms');
    return this.rest.get<FormState>(`/calls/${callId}/form`);
  }
  async editField(callId: string, fieldId: string, value: unknown): Promise<void> {
    this.profile.requireCapability('forms');
    await this.rest.put(`/calls/${callId}/form`, { fieldId, value });
  }
  async confirmField(callId: string, fieldId: string): Promise<void> {
    this.profile.requireCapability('forms');
    await this.rest.post(`/calls/${callId}/form/confirm-field`, { fieldId });
  }
  async rejectField(callId: string, fieldId: string): Promise<void> {
    this.profile.requireCapability('forms');
    await this.rest.post(`/calls/${callId}/form/reject-field`, { fieldId });
  }
  async submitForm(callId: string): Promise<void> {
    this.profile.requireCapability('forms');
    await this.rest.post(`/calls/${callId}/form/submit`);
  }

  /** Post-call summary (SOAP/BANT/etc., template-driven). */
  async getSummary(callId: string): Promise<Record<string, unknown>> {
    this.profile.requireCapability('copilot');
    return this.rest.get<Record<string, unknown>>(`/calls/${callId}/summary`);
  }

  private ensureConnected(): void {
    if (!this.connected) {
      throw new VoxaError('CONNECTION', 'Call connect() before opening a session.');
    }
  }
}

function ephemeralId(prefix: string): string {
  return `sdk-${prefix}-${Math.random().toString(36).slice(2, 8)}`;
}
