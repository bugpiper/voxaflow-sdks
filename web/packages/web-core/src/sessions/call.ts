import type { Room } from 'livekit-client';
import { EventEmitter } from 'eventemitter3';
import { VoxaError } from '../errors.js';
import type { VoxaRest } from '../transport/rest.js';
import type { VoxaRealtime } from '../transport/realtime.js';
import type { VoxaConnectionState } from '../models.js';
import { Waker, browserReadiness, rejoinNowAction, runRejoinLoop, shouldAutoRejoin } from './rejoin.js';

/** Per-session events (the media connection of THIS call/meeting — distinct from the client's
 *  `connectionState`, which is the realtime socket). */
export interface RtcSessionEventMap {
  /** `connected` → (`reconnecting` → `connected`)* → `disconnected`. */
  connectionState: (state: VoxaConnectionState) => void;
  /** An auto-rejoin try is starting (1-based `attempt`); if it fails the next comes `nextDelayMs` later. */
  rejoinAttempt: (e: { attempt: number; nextDelayMs: number }) => void;
}

export interface LiveKitCreds {
  token: string;
  wsUrl: string;
}

/** Base for media sessions (call/meeting). Wraps a LiveKit Room and exposes the unified
 *  device-control surface. Use `lkRoom` for advanced LiveKit access.
 *
 *  Auto-rejoin (default on): after an unexpected drop (locked phone, backgrounded app, lost
 *  network) the session re-joins the same room with a fresh token and the user's current mic/cam,
 *  Google-Meet style. See ./rejoin.ts and CONTRACT.md. */
export abstract class RtcSession extends EventEmitter<RtcSessionEventMap> {
  private _state: VoxaConnectionState = 'connected';
  private ended = false;
  private rejoining = false;
  private _attempt = 0;
  private wantMic = true;
  private wantCam = false;
  private readonly waker = new Waker();
  private readiness?: ReturnType<typeof browserReadiness>;

  protected constructor(
    readonly room: Room,
    readonly id: string,
    protected readonly realtime: VoxaRealtime,
    opts: { video?: boolean; autoRejoin?: boolean } = {},
  ) {
    super();
    this.wantCam = !!opts.video;
    // String event names (= RoomEvent.Reconnecting/Reconnected/Disconnected) so livekit-client
    // stays a lazy, type-only import here.
    const lk = room as unknown as { on(event: string, fn: (...args: never[]) => void): unknown };
    lk.on('reconnecting', () => this.setState('reconnecting'));
    lk.on('reconnected', () => this.setState('connected'));
    lk.on('disconnected', (reason?: number) => {
      void this.onDisconnected(reason, opts.autoRejoin !== false);
    });
  }

  get lkRoom(): Room {
    return this.room;
  }

  /** Media connection state of this session. */
  get state(): VoxaConnectionState {
    return this._state;
  }

  /** 1-based number of the current auto-rejoin attempt (0 when not rejoining) — for "(attempt n)" UI. */
  get rejoinAttemptNumber(): number {
    return this._attempt;
  }

  /** Fetch fresh LiveKit credentials for this session's room (POST /rtc/token or the meeting token). */
  protected abstract fetchCreds(): Promise<LiveKitCreds>;
  /** Re-subscribe the realtime socket to this session's events after a rejoin. */
  protected abstract rejoinRealtime(): void;

  async setMicEnabled(on: boolean): Promise<void> {
    this.wantMic = on;
    await this.room.localParticipant.setMicrophoneEnabled(on);
  }
  setMuted(muted: boolean): Promise<void> {
    return this.setMicEnabled(!muted);
  }
  async setCameraEnabled(on: boolean): Promise<void> {
    this.wantCam = on;
    await this.room.localParticipant.setCameraEnabled(on);
  }
  async startScreenShare(): Promise<void> {
    await this.room.localParticipant.setScreenShareEnabled(true);
  }
  async stopScreenShare(): Promise<void> {
    await this.room.localParticipant.setScreenShareEnabled(false);
  }
  hold(): Promise<void> {
    return this.setMicEnabled(false);
  }
  resume(): Promise<void> {
    return this.setMicEnabled(true);
  }

  /** Retry the connection immediately: cuts the current back-off wait short, or — once the room
   *  is really disconnected (auto-rejoin gave up) — starts a new rejoin loop. Ignored while
   *  LiveKit's own short resume is running, while connected, and after end(). */
  rejoinNow(): void {
    const roomState = String((this.room as unknown as { state?: string }).state ?? 'disconnected');
    const action = rejoinNowAction({ left: this.ended, rejoining: this.rejoining, roomState });
    if (action === 'wake') this.waker.wake();
    else if (action === 'restart') void this.startRejoin();
  }

  /** Leave the call. Cancels any in-flight auto-rejoin. */
  async end(): Promise<void> {
    this.ended = true;
    this.waker.wake();
    this.readiness?.dispose();
    await this.leave();
    await this.room.disconnect();
    this.setState('disconnected');
  }
  protected abstract leave(): Promise<void>;

  private setState(s: VoxaConnectionState): void {
    if (this._state === s) return;
    this._state = s;
    this.emit('connectionState', s);
  }

  private async onDisconnected(reason: number | undefined, autoRejoin: boolean): Promise<void> {
    if (this.ended || this.rejoining) return;
    if (!autoRejoin || !shouldAutoRejoin(reason)) {
      this.setState('disconnected');
      return;
    }
    await this.startRejoin();
  }

  private async startRejoin(): Promise<void> {
    if (this.ended || this.rejoining) return;
    this.rejoining = true;
    this._attempt = 0;
    this.setState('reconnecting');
    this.readiness ??= browserReadiness(this.waker);
    const outcome = await runRejoinLoop({
      join: () => this.freshJoin(),
      sleep: (ms) => this.waker.sleep(ms),
      waitReady: () => this.readiness!.waitReady(),
      cancelled: () => this.ended,
      onAttempt: (attempt, nextDelayMs) => {
        this._attempt = attempt;
        this.emit('rejoinAttempt', { attempt, nextDelayMs });
      },
    });
    this.rejoining = false;
    this._attempt = 0;
    if (outcome === 'joined') {
      this.rejoinRealtime();
      this.setState('connected');
    } else if (outcome === 'gaveUp') {
      this.setState('disconnected');
    }
  }

  /** New token → connect the same Room (so `lkRoom` listeners survive) → restore mic/cam. */
  private async freshJoin(): Promise<void> {
    try {
      const { token, wsUrl } = await this.fetchCreds();
      await this.room.connect(wsUrl, token);
    } catch (e) {
      try { await this.room.disconnect(); } catch { /* already down */ }
      throw e;
    }
    // A device failing (e.g. camera busy) must not fail the rejoin itself.
    try { if (this.wantMic) await this.room.localParticipant.setMicrophoneEnabled(true); } catch { /* */ }
    try { if (this.wantCam) await this.room.localParticipant.setCameraEnabled(true); } catch { /* */ }
  }
}

interface JoinTokenResponse {
  token?: string;
  wsUrl?: string;
}

/** A 1:1 / queue call. Backed by `POST /rtc/token` → a LiveKit room. */
export class CallSession extends RtcSession {
  private constructor(
    room: Room,
    callId: string,
    realtime: VoxaRealtime,
    private readonly rest: VoxaRest,
    private readonly name: string | undefined,
    opts: { video?: boolean; autoRejoin?: boolean },
  ) {
    super(room, callId, realtime, opts);
  }

  static async start(opts: {
    rest: VoxaRest;
    realtime: VoxaRealtime;
    callId: string;
    video?: boolean;
    name?: string;
    /** Re-join automatically after an unexpected drop (default true). */
    autoRejoin?: boolean;
  }): Promise<CallSession> {
    const { rest, realtime, callId, video = false, name } = opts;
    const creds = await CallSession.token(rest, callId, name);

    // Load the WebRTC client only when a call actually starts, so chat-only consumers
    // (e.g. the embeddable widget) don't bundle/download livekit-client.
    const { Room } = await import('livekit-client');
    const room = new Room();
    try {
      await room.connect(creds.wsUrl, creds.token);
      await room.localParticipant.setMicrophoneEnabled(true);
      if (video) await room.localParticipant.setCameraEnabled(true);
    } catch (cause) {
      await room.disconnect();
      throw new VoxaError('MEDIA', 'Failed to join the call room', { cause });
    }

    realtime.joinCall(callId);
    return new CallSession(room, callId, realtime, rest, name, { video, autoRejoin: opts.autoRejoin });
  }

  private static async token(rest: VoxaRest, callId: string, name?: string): Promise<LiveKitCreds> {
    const res = await rest.post<JoinTokenResponse>('/rtc/token', { callId, ...(name ? { name } : {}) });
    if (!res.wsUrl || !res.token) {
      throw new VoxaError('CONNECTION', 'Backend did not return a LiveKit token/wsUrl');
    }
    return { token: res.token, wsUrl: res.wsUrl };
  }

  protected fetchCreds(): Promise<LiveKitCreds> {
    return CallSession.token(this.rest, this.id, this.name);
  }
  protected rejoinRealtime(): void {
    this.realtime.joinCall(this.id);
  }
  protected async leave(): Promise<void> {
    this.realtime.leaveCall(this.id);
  }
}
