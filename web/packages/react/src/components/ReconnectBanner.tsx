import type { CSSProperties } from 'react';
import type { VoxaConnectionState } from '@voxaflow/web-core';

export interface ReconnectBannerProps {
  /** The call session's media state (`useVoxaCall().callState`). */
  state: VoxaConnectionState;
  /** Retry now (`useVoxaCall().rejoinNow`). */
  onRejoin: () => void;
  style?: CSSProperties;
}

/** Meet-style "connection lost" banner: shown while the SDK auto-rejoins, and with a Rejoin
 *  button once it gives up. Renders nothing while connected. */
export function ReconnectBanner({ state, onRejoin, style }: ReconnectBannerProps): JSX.Element | null {
  if (state !== 'reconnecting' && state !== 'disconnected') return null;
  const reconnecting = state === 'reconnecting';
  return (
    <div role="status" aria-live="polite" style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 10px', background: reconnecting ? '#fef3c7' : '#fee2e2', color: '#111827', fontSize: 13, ...style }}>
      <span>{reconnecting ? 'Connection lost — reconnecting…' : 'Disconnected'}</span>
      <button onClick={onRejoin} style={{ marginLeft: 'auto', padding: '4px 10px', borderRadius: 6, border: '1px solid #d1d5db', background: '#fff', cursor: 'pointer', fontSize: 13 }}>
        {reconnecting ? 'Rejoin now' : 'Rejoin'}
      </button>
    </div>
  );
}
