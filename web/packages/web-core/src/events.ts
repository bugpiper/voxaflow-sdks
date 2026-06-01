import type { VoxaError } from './errors.js';
import type {
  VoxaConnectionState,
  TranscriptSegment,
  ExtractedEntity,
  FormUpdate,
  ChatMessage,
  TypingEvent,
  PresenceUpdate,
  CallStatusEvent,
  MeetingTranscriptSegment,
  MeetingParticipantEvent,
  MeetingOutputEvent,
} from './models.js';

/** Typed event map for the unified client (same concepts as the Flutter Streams). */
export interface VoxaEventMap {
  connectionState: (state: VoxaConnectionState) => void;
  transcript: (segment: TranscriptSegment) => void;
  entityExtracted: (entity: ExtractedEntity) => void;
  formUpdate: (update: FormUpdate) => void;
  message: (message: ChatMessage) => void;
  typing: (event: TypingEvent) => void;
  presence: (update: PresenceUpdate) => void;
  callStatus: (event: CallStatusEvent) => void;
  meetingTranscript: (segment: MeetingTranscriptSegment) => void;
  meetingParticipant: (event: MeetingParticipantEvent) => void;
  meetingOutput: (event: MeetingOutputEvent) => void;
  error: (error: VoxaError) => void;
}
