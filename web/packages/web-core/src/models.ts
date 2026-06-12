// Data models surfaced by the SDK events. Shapes mirror the Voxa backend Socket.IO
// event catalog (ServerToClientEvents) and REST responses.

export type VoxaConnectionState = 'connecting' | 'connected' | 'reconnecting' | 'disconnected';

export interface TranscriptSegment {
  id?: string;
  speaker: string; // 'AGENT' | 'CALLER'
  text: string;
  isFinal: boolean;
  confidence?: number;
  language?: string;
  startTime?: number;
  endTime?: number;
}

export interface ExtractedEntity {
  id?: string;
  entityType: string;
  entityCategory: string;
  value: string;
  code?: string;
  codeSystem?: string;
  confidence?: number;
  negated?: boolean;
}

export interface FormUpdate {
  fieldId: string;
  value: unknown;
  confidence?: number;
}

export interface ChatMessage {
  id: string;
  conversationId: string;
  sender: string; // 'CONTACT' | 'AGENT' | 'BOT' | 'SYSTEM'
  content: string;
  createdAt: string;
  isDraft: boolean;
  isBot: boolean;
  botMeta?: Record<string, unknown>;
}

export interface TypingEvent {
  conversationId: string;
  sender: string;
}

export interface PresenceUpdate {
  userId: string;
  status: string;
}

export interface CallStatusEvent {
  callId: string;
  status: string;
  durationSeconds?: number;
}

/** An incoming directed ring ("user X is calling you"). Sourced from `call:ring`. */
export interface VoxaCallRing {
  callId: string;
  fromId: string;
  fromName: string;
  video: boolean;
  vertical?: string;
  expiresAt?: string;
}

export type VoxaCallSignalKind = 'accepted' | 'rejected' | 'canceled' | 'timeout';

/** How a pending ring resolved for the other party. Sourced from
 *  `call:accepted` / `call:rejected` / `call:canceled` / `call:timeout`. */
export interface VoxaCallSignal {
  callId: string;
  kind: VoxaCallSignalKind;
  by?: string;
  reason?: string;
}

export interface AudioQuality {
  mos?: number;
  loss?: number;
  jitter?: number;
  rtt?: number;
}

/** A live form-fill suggestion (agent copilot). */
export interface Suggestion {
  id: string;
  fieldId: string;
  value: unknown;
  confidence?: number;
}

/** Summary of a call in the agent's queue/active list. */
export interface CallInfo {
  id: string;
  callerIdentifier?: string;
  status: string;
  agentId?: string | null;
  startedAt?: string;
}

/** Smart-form state + schema. */
export interface FormState {
  form: Record<string, unknown>;
  status: string;
  schema: unknown[];
}

type J = Record<string, unknown>;
const str = (v: unknown, d = ''): string => (typeof v === 'string' ? v : d);
const num = (v: unknown): number | undefined => (typeof v === 'number' ? v : undefined);
const bool = (v: unknown, d = false): boolean => (typeof v === 'boolean' ? v : d);

export function parseTranscript(j: J): TranscriptSegment {
  return {
    id: typeof j.id === 'string' ? j.id : undefined,
    speaker: str(j.speaker, 'CALLER'),
    text: str(j.text),
    isFinal: bool(j.isFinal),
    confidence: num(j.confidence),
    language: typeof j.language === 'string' ? j.language : undefined,
    startTime: num(j.startTime),
    endTime: num(j.endTime),
  };
}

export function parseEntity(j: J): ExtractedEntity {
  return {
    id: typeof j.id === 'string' ? j.id : undefined,
    entityType: str(j.entityType),
    entityCategory: str(j.entityCategory),
    value: str(j.value),
    code: typeof j.code === 'string' ? j.code : undefined,
    codeSystem: typeof j.codeSystem === 'string' ? j.codeSystem : undefined,
    confidence: num(j.confidence),
    negated: bool(j.negated),
  };
}

export function parseFormUpdate(j: J): FormUpdate {
  return { fieldId: str(j.fieldId), value: j.value, confidence: num(j.confidence) };
}

export function parseMessage(j: J, isDraft = false): ChatMessage {
  const sender = str(j.sender, 'SYSTEM');
  return {
    id: str(j.id),
    conversationId: str(j.conversationId),
    sender,
    content: str(j.content),
    createdAt: str(j.createdAt),
    isDraft,
    isBot: sender === 'BOT',
    botMeta: typeof j.botMeta === 'object' && j.botMeta !== null ? (j.botMeta as Record<string, unknown>) : undefined,
  };
}

export function parseTyping(j: J): TypingEvent {
  return { conversationId: str(j.conversationId), sender: str(j.sender) };
}

export function parsePresence(j: J): PresenceUpdate {
  return { userId: str(j.userId), status: str(j.status) };
}

export function parseCallStatus(j: J): CallStatusEvent {
  return { callId: str(j.callId), status: str(j.status), durationSeconds: num(j.durationSeconds) };
}

/** Per-speaker meeting transcript segment. Sourced from `meeting:transcript`. */
export interface MeetingTranscriptSegment {
  meetingId: string;
  speakerId: string;
  identity: string;
  text: string;
  isFinal: boolean;
  language?: string;
  startTime?: number;
}
/** Meeting participant join/left. Sourced from `meeting:participant`. */
export interface MeetingParticipantEvent {
  meetingId: string;
  identity: string;
  state: string; // 'joined' | 'left'
}
/** Meeting AI output generated (summary, action items, …). Sourced from `meeting:output`. */
export interface MeetingOutputEvent {
  meetingId: string;
  type: string;
}

export function parseMeetingTranscript(j: J): MeetingTranscriptSegment {
  return {
    meetingId: str(j.meetingId),
    speakerId: str(j.speakerId),
    identity: str(j.identity),
    text: str(j.text),
    isFinal: bool(j.isFinal),
    language: typeof j.language === 'string' ? j.language : undefined,
    startTime: num(j.startTime),
  };
}
export function parseMeetingParticipant(j: J): MeetingParticipantEvent {
  return { meetingId: str(j.meetingId), identity: str(j.identity), state: str(j.state) };
}
export function parseMeetingOutput(j: J): MeetingOutputEvent {
  return { meetingId: str(j.meetingId), type: str(j.type) };
}

export function parseCallRing(j: J): VoxaCallRing {
  const from = (j.from ?? {}) as J;
  return {
    callId: str(j.callId),
    fromId: str(from.id),
    fromName: str(from.name, 'Caller'),
    video: bool(j.video),
    vertical: typeof j.vertical === 'string' ? j.vertical : undefined,
    expiresAt: typeof j.expiresAt === 'string' ? j.expiresAt : undefined,
  };
}
export function parseCallSignal(kind: VoxaCallSignalKind, j: J): VoxaCallSignal {
  return {
    callId: str(j.callId),
    kind,
    by: typeof j.by === 'string' ? j.by : undefined,
    reason: typeof j.reason === 'string' ? j.reason : undefined,
  };
}
