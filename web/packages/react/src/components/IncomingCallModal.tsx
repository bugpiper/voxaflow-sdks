import type { CSSProperties } from 'react';
import type { CallSession } from '@voxaflow/web-core';
import { useIncomingCall } from '../hooks.js';

export interface IncomingCallModalProps {
  /** Called after the ring is accepted and the call room is joined. */
  onAccepted?: (call: CallSession) => void;
  /** Force audio/video on accept; defaults to whatever the caller requested. */
  acceptVideo?: boolean;
  style?: CSSProperties;
}

/**
 * Drop-in incoming-call (ringing) modal. Subscribes to directed rings via
 * [useIncomingCall] and renders an Accept/Decline prompt. Styling is intentionally
 * light — swap in your own theme (mirrors the Flutter `VoxaIncomingCallScreen`).
 */
export function IncomingCallModal({ onAccepted, acceptVideo, style }: IncomingCallModalProps): JSX.Element | null {
  const { ring, accept, reject } = useIncomingCall();
  if (!ring) return null;

  return (
    <div style={overlay}>
      <div style={{ ...card, ...style }} role="dialog" aria-label="Incoming call">
        <div style={avatar}>{ring.video ? '🎥' : '📞'}</div>
        <div style={{ fontSize: 20, fontWeight: 700, color: '#0f172a' }}>{ring.fromName || 'Unknown'}</div>
        <div style={{ fontSize: 14, color: '#64748b', marginBottom: 20 }}>
          Incoming {ring.video ? 'video' : 'voice'} call
        </div>
        <div style={{ display: 'flex', gap: 16, justifyContent: 'center' }}>
          <button onClick={() => void reject()} style={{ ...big, background: '#dc2626' }} aria-label="Decline">
            ✕
          </button>
          <button
            onClick={() => void accept({ video: acceptVideo ?? ring.video }).then((c) => c && onAccepted?.(c))}
            style={{ ...big, background: '#16a34a' }}
            aria-label="Accept"
          >
            ✓
          </button>
        </div>
      </div>
    </div>
  );
}

const overlay: CSSProperties = {
  position: 'fixed',
  inset: 0,
  background: 'rgba(2, 6, 23, 0.55)',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  zIndex: 9999,
  fontFamily: 'system-ui, sans-serif',
};
const card: CSSProperties = {
  background: '#fff',
  borderRadius: 20,
  padding: '32px 28px',
  width: 300,
  textAlign: 'center',
  boxShadow: '0 20px 60px rgba(0,0,0,0.3)',
};
const avatar: CSSProperties = {
  width: 80,
  height: 80,
  borderRadius: '50%',
  margin: '0 auto 16px',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  fontSize: 34,
  background: 'linear-gradient(135deg, #6366f1, #818cf8)',
};
const big: CSSProperties = {
  width: 60,
  height: 60,
  borderRadius: '50%',
  border: 'none',
  color: '#fff',
  fontSize: 24,
  cursor: 'pointer',
};
