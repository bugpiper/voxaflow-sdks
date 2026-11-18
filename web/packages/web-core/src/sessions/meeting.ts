import type { Room } from 'livekit-client';
import { VoxaError } from '../errors.js';
import type { VoxaRest } from '../transport/rest.js';
import type { VoxaRealtime } from '../transport/realtime.js';
import { RtcSession, type LiveKitCreds } from './call.js';

interface MeetingTokenResponse {
  token?: string;
  wsUrl?: string;
}

interface MeetingJoinParams {
  displayName?: string;
  role?: string;
  language?: string;
}

/** A multi-party meeting (MP1–MP8). Backed by `POST /meetings/:id/token` → a LiveKit room.
 *  Per-speaker transcript / participant / AI-output events arrive on the client's
 *  meetingTranscript / meetingParticipant / meetingOutput events once joined.
 *  Auto-rejoins after an unexpected drop like CallSession (see RtcSession). */
export class MeetingSession extends RtcSession {
  private constructor(
    room: Room,
    meetingId: string,
    realtime: VoxaRealtime,
    private readonly rest: VoxaRest,
    private readonly params: MeetingJoinParams,
    opts: { video?: boolean; autoRejoin?: boolean },
  ) {
    super(room, meetingId, realtime, opts);
  }

  static async join(opts: {
    rest: VoxaRest;
    realtime: VoxaRealtime;
    meetingId: string;
    video?: boolean;
    displayName?: string;
    role?: string;
    language?: string;
    /** Re-join automatically after an unexpected drop (default true). */
    autoRejoin?: boolean;
  }): Promise<MeetingSession> {
    const { rest, realtime, meetingId, video = false, displayName, role, language } = opts;
    const params = { displayName, role, language };
    const creds = await MeetingSession.token(rest, meetingId, params);

    const { Room } = await import('livekit-client');
    const room = new Room();
    try {
      await room.connect(creds.wsUrl, creds.token);
      await room.localParticipant.setMicrophoneEnabled(true);
      if (video) await room.localParticipant.setCameraEnabled(true);
    } catch (cause) {
      await room.disconnect();
      throw new VoxaError('MEDIA', 'Failed to join the meeting room', { cause });
    }
    realtime.joinMeeting(meetingId);
    return new MeetingSession(room, meetingId, realtime, rest, params, { video, autoRejoin: opts.autoRejoin });
  }

  private static async token(rest: VoxaRest, meetingId: string, p: MeetingJoinParams): Promise<LiveKitCreds> {
    const res = await rest.post<MeetingTokenResponse>(`/meetings/${meetingId}/token`, {
      ...(p.displayName ? { name: p.displayName } : {}),
      ...(p.role ? { role: p.role } : {}),
      ...(p.language ? { language: p.language } : {}),
    });
    if (!res.wsUrl || !res.token) {
      throw new VoxaError('CONNECTION', 'Backend did not return a meeting LiveKit token/wsUrl');
    }
    return { token: res.token, wsUrl: res.wsUrl };
  }

  protected fetchCreds(): Promise<LiveKitCreds> {
    return MeetingSession.token(this.rest, this.id, this.params);
  }
  protected rejoinRealtime(): void {
    this.realtime.joinMeeting(this.id);
  }
  protected async leave(): Promise<void> {
    this.realtime.leaveMeeting(this.id);
  }
}
