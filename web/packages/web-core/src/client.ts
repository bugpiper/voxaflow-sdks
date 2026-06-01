import { EventEmitter } from 'eventemitter3';
import { TokenProfile, type Capability } from './capabilities.js';
import { VoxaError } from './errors.js';
import type { VoxaConfig } from './config.js';
import type { VoxaEventMap } from './events.js';
import { VoxaRest } from './transport/rest.js';
import { VoxaRealtime } from './transport/realtime.js';
import { CallSession } from './sessions/call.js';
import { ChatSession } from './sessions/chat.js';

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
  async startCall(opts: { callId?: string; video?: boolean; name?: string } = {}): Promise<CallSession> {
    this.profile.requireCapability(opts.video ? 'joinVideo' : 'joinCall');
    this.ensureConnected();
    return CallSession.start({
      rest: this.rest,
      realtime: this.realtime,
      callId: opts.callId ?? ephemeralId('call'),
      video: opts.video,
      name: opts.name,
    });
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

  private ensureConnected(): void {
    if (!this.connected) {
      throw new VoxaError('CONNECTION', 'Call connect() before opening a session.');
    }
  }
}

function ephemeralId(prefix: string): string {
  return `sdk-${prefix}-${Math.random().toString(36).slice(2, 8)}`;
}
