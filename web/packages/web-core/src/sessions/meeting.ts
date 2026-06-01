import { VoxaError } from '../errors.js';
import type { VoxaRest } from '../transport/rest.js';
import type { VoxaRealtime } from '../transport/realtime.js';
import { RtcSession } from './call.js';

interface MeetingTokenResponse {
  token?: string;
  wsUrl?: string;
}

/** A multi-party meeting (MP1–MP8). Backed by `POST /meetings/:id/token` → a LiveKit room.
 *  Per-speaker transcript / participant / AI-output events arrive on the client's
 *  meetingTranscript / meetingParticipant / meetingOutput events once joined. */
export class MeetingSession extends RtcSession {
  static async join(opts: {
    rest: VoxaRest;
    realtime: VoxaRealtime;
    meetingId: string;
    video?: boolean;
    displayName?: string;
    role?: string;
    language?: string;
  }): Promise<MeetingSession> {
    const { rest, realtime, meetingId, video = false, displayName, role, language } = opts;
    const res = await rest.post<MeetingTokenResponse>(`/meetings/${meetingId}/token`, {
      ...(displayName ? { name: displayName } : {}),
      ...(role ? { role } : {}),
      ...(language ? { language } : {}),
    });
    if (!res.wsUrl || !res.token) {
      throw new VoxaError('CONNECTION', 'Backend did not return a meeting LiveKit token/wsUrl');
    }

    const { Room } = await import('livekit-client');
    const room = new Room();
    try {
      await room.connect(res.wsUrl, res.token);
      await room.localParticipant.setMicrophoneEnabled(true);
      if (video) await room.localParticipant.setCameraEnabled(true);
    } catch (cause) {
      await room.disconnect();
      throw new VoxaError('MEDIA', 'Failed to join the meeting room', { cause });
    }
    realtime.joinMeeting(meetingId);
    return new MeetingSession(room, meetingId, realtime);
  }

  async end(): Promise<void> {
    this.realtime.leaveMeeting(this.id);
    await this.room.disconnect();
  }
}
