import type { CSSProperties } from 'react';
import { useConnectionState, useTranscript, useVoxaCall } from '../hooks.js';
import { ReconnectBanner } from './ReconnectBanner.js';

export interface CallViewProps {
  /** Start with video enabled. */
  video?: boolean;
  style?: CSSProperties;
}

/**
 * Minimal call surface: start/end + mic toggle, connection state, and a live transcript
 * (final + interim). Styling is intentionally light — swap in the Midnight Intelligence
 * design tokens / your own theme. For video tiles use the LiveKit room via `call.lkRoom`.
 */
export function CallView({ video = false, style }: CallViewProps): JSX.Element {
  const conn = useConnectionState();
  const { call, micOn, starting, callState, rejoinAttempt, rejoinNow, start, end, toggleMic } = useVoxaCall();
  const { finals, interim } = useTranscript();
  const inCall = call !== null;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', fontFamily: 'system-ui, sans-serif', ...style }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: 8, borderBottom: '1px solid #e5e7eb' }}>
        {!inCall ? (
          <button onClick={() => void start({ video })} disabled={starting} style={btn}>
            {starting ? 'Starting…' : video ? 'Start video call' : 'Start call'}
          </button>
        ) : (
          <>
            <button onClick={() => void toggleMic()} style={btn}>{micOn ? 'Mute' : 'Unmute'}</button>
            <button onClick={() => void end()} style={{ ...btn, background: '#dc2626', color: '#fff' }}>End</button>
          </>
        )}
        <span style={{ marginLeft: 'auto', fontSize: 12, color: '#6b7280' }}>{conn}</span>
      </div>
      {inCall && <ReconnectBanner state={callState} attempt={rejoinAttempt} onRejoin={rejoinNow} />}
      <div style={{ flex: 1, overflowY: 'auto', padding: 12 }} aria-live="polite">
        {finals.length === 0 && Object.keys(interim).length === 0 && (
          <p style={{ color: '#9ca3af' }}>Speak after starting the call — your words appear here.</p>
        )}
        {finals.map((s, i) => (
          <p key={s.id ?? i} style={{ margin: '4px 0', lineHeight: 1.5 }}>
            <strong style={{ marginRight: 6 }}>{s.speaker}:</strong>
            {s.text}
          </p>
        ))}
        {Object.entries(interim).map(([speaker, text]) => (
          <p key={`i-${speaker}`} style={{ margin: '4px 0', opacity: 0.55, fontStyle: 'italic' }}>
            <strong style={{ marginRight: 6 }}>{speaker}:</strong>
            {text}
          </p>
        ))}
      </div>
    </div>
  );
}

const btn: CSSProperties = {
  padding: '6px 12px',
  borderRadius: 8,
  border: '1px solid #d1d5db',
  background: '#fff',
  cursor: 'pointer',
  fontSize: 14,
};
