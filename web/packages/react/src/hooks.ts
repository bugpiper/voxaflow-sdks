import { useCallback, useEffect, useState } from 'react';
import type {
  CallSession,
  ChatSession,
  ChatMessage,
  TranscriptSegment,
  VoxaConnectionState,
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
  start: (opts?: { callId?: string; video?: boolean; name?: string }) => Promise<void>;
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

  const start = useCallback(
    async (opts?: { callId?: string; video?: boolean; name?: string }) => {
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

  return { call, micOn, cameraOn, starting, start, end, toggleMic, toggleCamera };
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
