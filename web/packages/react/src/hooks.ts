import { useCallback, useEffect, useState } from 'react';
import type {
  CallSession,
  ChatSession,
  ChatMessage,
  TranscriptSegment,
  VoxaConnectionState,
  ExtractedEntity,
  Suggestion,
  VoxaCallRing,
  VoxaCallSignal,
} from '@voxaflow/web-core';
import { useVoxaClient } from './context.js';

/** Live connection state of the realtime channel. */
export function useConnectionState(): VoxaConnectionState {
  const client = useVoxaClient();
  const [state, setState] = useState<VoxaConnectionState>('connecting');
  useEffect(() => {
    if (!client) return;
    const h = (s: VoxaConnectionState) => setState(s);
    client.on('connectionState', h);
    return () => {
      client.off('connectionState', h);
    };
  }, [client]);
  return state;
}

export interface UseTranscript {
  finals: TranscriptSegment[];
  /** In-progress text per speaker (interim); replaced by the final. */
  interim: Record<string, string>;
}

/** Accumulates transcript events: final segments append, interim is per-speaker. */
export function useTranscript(): UseTranscript {
  const client = useVoxaClient();
  const [finals, setFinals] = useState<TranscriptSegment[]>([]);
  const [interim, setInterim] = useState<Record<string, string>>({});
  useEffect(() => {
    if (!client) return;
    const h = (seg: TranscriptSegment) => {
      if (seg.isFinal) {
        setFinals((prev) => (seg.id && prev.some((f) => f.id === seg.id) ? prev : [...prev, seg]));
        setInterim((prev) => {
          const next = { ...prev };
          delete next[seg.speaker];
          return next;
        });
      } else {
        setInterim((prev) => ({ ...prev, [seg.speaker]: seg.text }));
      }
    };
    client.on('transcript', h);
    return () => {
      client.off('transcript', h);
    };
  }, [client]);
  return { finals, interim };
}

export interface UseVoxaCall {
  call: CallSession | null;
  micOn: boolean;
  cameraOn: boolean;
  starting: boolean;
  /** Media state of the current call (auto-rejoin: `reconnecting` → `connected`, or `disconnected` on give-up). */
  callState: VoxaConnectionState;
  /** Retry the call connection now (cuts the back-off wait, or restarts after give-up). */
  rejoinNow: () => void;
  start: (opts?: { callId?: string; video?: boolean; name?: string; autoRejoin?: boolean }) => Promise<void>;
  end: () => Promise<void>;
  toggleMic: () => Promise<void>;
  toggleCamera: () => Promise<void>;
}

/** Manage a single call session with mic/camera state. */
export function useVoxaCall(): UseVoxaCall {
  const client = useVoxaClient();
  const [call, setCall] = useState<CallSession | null>(null);
  const [micOn, setMicOn] = useState(true);
  const [cameraOn, setCameraOn] = useState(false);
  const [starting, setStarting] = useState(false);
  const [callState, setCallState] = useState<VoxaConnectionState>('disconnected');

  useEffect(() => {
    if (!call) {
      setCallState('disconnected');
      return;
    }
    setCallState(call.state);
    const h = (s: VoxaConnectionState) => setCallState(s);
    call.on('connectionState', h);
    return () => {
      call.off('connectionState', h);
    };
  }, [call]);

  const rejoinNow = useCallback(() => call?.rejoinNow(), [call]);

  const start = useCallback(
    async (opts?: { callId?: string; video?: boolean; name?: string; autoRejoin?: boolean }) => {
      if (!client) return;
      setStarting(true);
      try {
        const c = await client.startCall(opts);
        setCall(c);
        setMicOn(true);
        setCameraOn(opts?.video ?? false);
      } finally {
        setStarting(false);
      }
    },
    [client],
  );

  const end = useCallback(async () => {
    await call?.end();
    setCall(null);
  }, [call]);

  const toggleMic = useCallback(async () => {
    if (!call) return;
    const next = !micOn;
    await call.setMicEnabled(next);
    setMicOn(next);
  }, [call, micOn]);

  const toggleCamera = useCallback(async () => {
    if (!call) return;
    const next = !cameraOn;
    await call.setCameraEnabled(next);
    setCameraOn(next);
  }, [call, cameraOn]);

  useEffect(() => () => void call?.end(), [call]);

  return { call, micOn, cameraOn, starting, callState, rejoinNow, start, end, toggleMic, toggleCamera };
}

export interface UseIncomingCall {
  /** The current incoming ring, or null when none is pending. */
  ring: VoxaCallRing | null;
  /** Accept the ring and join its room; returns the live call (or null). */
  accept: (opts?: { video?: boolean }) => Promise<CallSession | null>;
  /** Decline the ring. */
  reject: (reason?: string) => Promise<void>;
}

/** Surfaces the latest directed ring and resolves it. Clears automatically when the
 *  ring is canceled/timed out by the other side (`callSignal`). */
export function useIncomingCall(): UseIncomingCall {
  const client = useVoxaClient();
  const [ring, setRing] = useState<VoxaCallRing | null>(null);
  useEffect(() => {
    if (!client) return;
    const onRing = (r: VoxaCallRing) => setRing(r);
    const onSignal = (s: VoxaCallSignal) =>
      setRing((cur) => (cur && cur.callId === s.callId && s.kind !== 'accepted' ? null : cur));
    client.on('incomingCall', onRing);
    client.on('callSignal', onSignal);
    return () => {
      client.off('incomingCall', onRing);
      client.off('callSignal', onSignal);
    };
  }, [client]);

  const accept = useCallback(
    async (opts?: { video?: boolean }) => {
      if (!client || !ring) return null;
      const c = await client.acceptCall(ring.callId, { video: opts?.video ?? ring.video });
      setRing(null);
      return c;
    },
    [client, ring],
  );

  const reject = useCallback(
    async (reason?: string) => {
      if (!client || !ring) return;
      await client.rejectCall(ring.callId, { reason });
      setRing(null);
    },
    [client, ring],
  );

  return { ring, accept, reject };
}

export interface UseVoxaChat {
  session: ChatSession | null;
  messages: ChatMessage[];
  send: (content: string) => Promise<void>;
}

/** Open (or attach to) a chat conversation and collect its messages. */
export function useVoxaChat(opts: { conversationId?: string; channel?: string }): UseVoxaChat {
  const client = useVoxaClient();
  const [session, setSession] = useState<ChatSession | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const { conversationId, channel } = opts;

  useEffect(() => {
    if (!client) return;
    let active = true;
    let opened: ChatSession | null = null;

    void client.openChat({ conversationId, channel }).then((cs) => {
      if (!active) {
        cs.leave();
        return;
      }
      opened = cs;
      setSession(cs);
    });

    const h = (m: ChatMessage) => {
      if (opened && m.conversationId === opened.conversationId) {
        setMessages((prev) => (prev.some((x) => x.id === m.id) ? prev : [...prev, m]));
      }
    };
    client.on('message', h);

    return () => {
      active = false;
      client.off('message', h);
      opened?.leave();
    };
  }, [client, conversationId, channel]);

  const send = useCallback(
    async (content: string) => {
      await session?.sendMessage(content);
    },
    [session],
  );

  return { session, messages, send };
}

export interface UseEntities {
  entities: ExtractedEntity[];
  confirm: (entityId: string) => Promise<void>;
  reject: (entityId: string) => Promise<void>;
  refresh: () => Promise<void>;
}

/** Extracted entities for a call; refetches when an `entityExtracted` event arrives. */
export function useEntities(callId: string): UseEntities {
  const client = useVoxaClient();
  const [entities, setEntities] = useState<ExtractedEntity[]>([]);
  const refresh = useCallback(async () => {
    if (client && callId) setEntities(await client.getEntities(callId));
  }, [client, callId]);
  useEffect(() => {
    void refresh();
    if (!client) return;
    const h = () => void refresh();
    client.on('entityExtracted', h);
    return () => {
      client.off('entityExtracted', h);
    };
  }, [client, refresh]);
  const confirm = useCallback(async (id: string) => { await client?.confirmEntity(id); await refresh(); }, [client, refresh]);
  const reject = useCallback(async (id: string) => { await client?.rejectEntity(id); await refresh(); }, [client, refresh]);
  return { entities, confirm, reject, refresh };
}

export interface UseSuggestions {
  suggestions: Suggestion[];
  dismiss: (suggestionId: string) => Promise<void>;
  refresh: () => Promise<void>;
}

/** Live form-fill suggestions for a call; refetches on `formUpdate`. */
export function useSuggestions(callId: string): UseSuggestions {
  const client = useVoxaClient();
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const refresh = useCallback(async () => {
    if (client && callId) setSuggestions(await client.getSuggestions(callId));
  }, [client, callId]);
  useEffect(() => {
    void refresh();
    if (!client) return;
    const h = () => void refresh();
    client.on('formUpdate', h);
    return () => {
      client.off('formUpdate', h);
    };
  }, [client, refresh]);
  const dismiss = useCallback(async (id: string) => { await client?.dismissSuggestion(callId, id); await refresh(); }, [client, callId, refresh]);
  return { suggestions, dismiss, refresh };
}
