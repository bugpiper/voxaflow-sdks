import { Room } from 'livekit-client';
import { VoxaError } from '../errors.js';
import type { VoxaRest } from '../transport/rest.js';
import type { VoxaRealtime } from '../transport/realtime.js';

/** Base for media sessions (call/meeting). Wraps a LiveKit Room and exposes the unified
 *  device-control surface. Use `lkRoom` for advanced LiveKit access. */
export abstract class RtcSession {
  protected constructor(
    readonly room: Room,
    readonly id: string,
    protected readonly realtime: VoxaRealtime,
  ) {}

  get lkRoom(): Room {
    return this.room;
  }

  async setMicEnabled(on: boolean): Promise<void> {
    await this.room.localParticipant.setMicrophoneEnabled(on);
  }
  setMuted(muted: boolean): Promise<void> {
    return this.setMicEnabled(!muted);
  }
  async setCameraEnabled(on: boolean): Promise<void> {
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

  abstract end(): Promise<void>;
}

interface JoinTokenResponse {
  token?: string;
  wsUrl?: string;
}

/** A 1:1 / queue call. Backed by `POST /rtc/token` → a LiveKit room. */
export class CallSession extends RtcSession {
  static async start(opts: {
    rest: VoxaRest;
    realtime: VoxaRealtime;
    callId: string;
    video?: boolean;
    name?: string;
  }): Promise<CallSession> {
    const { rest, realtime, callId, video = false, name } = opts;
    const res = await rest.post<JoinTokenResponse>('/rtc/token', { callId, ...(name ? { name } : {}) });
    if (!res.wsUrl || !res.token) {
      throw new VoxaError('CONNECTION', 'Backend did not return a LiveKit token/wsUrl');
    }

    const room = new Room();
    try {
      await room.connect(res.wsUrl, res.token);
      await room.localParticipant.setMicrophoneEnabled(true);
      if (video) await room.localParticipant.setCameraEnabled(true);
    } catch (cause) {
      await room.disconnect();
      throw new VoxaError('MEDIA', 'Failed to join the call room', { cause });
    }

    realtime.joinCall(callId);
    return new CallSession(room, callId, realtime);
  }

  async end(): Promise<void> {
    this.realtime.leaveCall(this.id);
    await this.room.disconnect();
  }
}
