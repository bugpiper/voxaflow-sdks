import type { CSSProperties } from 'react';
import { useEntities, useSuggestions, useTranscript } from '../hooks.js';

export interface CopilotPanelProps {
  /** The call whose transcript / entities / suggestions to surface. */
  callId: string;
  style?: CSSProperties;
}

/**
 * Agent copilot: live transcript + extracted entities (confirm/reject) + form suggestions
 * (dismiss). Headless data via useTranscript/useEntities/useSuggestions. Light styling for
 * v0 — swap in the Midnight Intelligence design tokens.
 */
export function CopilotPanel({ callId, style }: CopilotPanelProps): JSX.Element {
  const { finals, interim } = useTranscript();
  const { entities, confirm, reject } = useEntities(callId);
  const { suggestions, dismiss } = useSuggestions(callId);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12, height: '100%', fontFamily: 'system-ui, sans-serif', ...style }}>
      <section style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
        <h4 style={h}>Transcript</h4>
        <div style={{ flex: 1, overflowY: 'auto', fontSize: 14 }} aria-live="polite">
          {finals.map((s, i) => (
            <p key={s.id ?? i} style={{ margin: '3px 0' }}>
              <strong style={{ marginRight: 6 }}>{s.speaker}:</strong>{s.text}
            </p>
          ))}
          {Object.entries(interim).map(([sp, t]) => (
            <p key={`i-${sp}`} style={{ margin: '3px 0', opacity: 0.55, fontStyle: 'italic' }}>
              <strong style={{ marginRight: 6 }}>{sp}:</strong>{t}
            </p>
          ))}
        </div>
      </section>

      <section>
        <h4 style={h}>Entities</h4>
        {entities.length === 0 && <p style={muted}>None yet.</p>}
        {entities.map((e) => (
          <div key={e.id ?? e.value} style={row}>
            <span style={{ fontSize: 13 }}>
              <span style={{ color: '#6b7280' }}>{e.entityType}: </span>{e.value}
              {e.confidence != null && <span style={{ color: '#9ca3af' }}> · {(e.confidence * 100).toFixed(0)}%</span>}
            </span>
            <span>
              {e.id && <button style={chip} onClick={() => void confirm(e.id!)}>✓</button>}
              {e.id && <button style={chip} onClick={() => void reject(e.id!)}>✕</button>}
            </span>
          </div>
        ))}
      </section>

      <section>
        <h4 style={h}>Suggestions</h4>
        {suggestions.length === 0 && <p style={muted}>None.</p>}
        {suggestions.map((s) => (
          <div key={s.id} style={row}>
            <span style={{ fontSize: 13 }}>
              <span style={{ color: '#6b7280' }}>{s.fieldId}: </span>{String(s.value)}
            </span>
            <button style={chip} onClick={() => void dismiss(s.id)}>Dismiss</button>
          </div>
        ))}
      </section>
    </div>
  );
}

const h: CSSProperties = { margin: '0 0 6px', fontSize: 12, textTransform: 'uppercase', letterSpacing: 0.5, color: '#6b7280' };
const muted: CSSProperties = { color: '#9ca3af', fontSize: 13, margin: '2px 0' };
const row: CSSProperties = { display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '4px 0', borderBottom: '1px solid #f3f4f6' };
const chip: CSSProperties = { marginLeft: 6, padding: '2px 8px', borderRadius: 6, border: '1px solid #d1d5db', background: '#fff', cursor: 'pointer', fontSize: 12 };
