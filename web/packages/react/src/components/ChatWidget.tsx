import { useState, type CSSProperties, type FormEvent } from 'react';
import { useVoxaChat } from '../hooks.js';

export interface ChatWidgetProps {
  /** Attach to an existing conversation… */
  conversationId?: string;
  /** …or start a new one on a public channel handle. */
  channel?: string;
  style?: CSSProperties;
}

/**
 * Minimal threaded chat + bot. Bot messages are labeled (AI-transparency). Styling is
 * light — replace with the Midnight Intelligence tokens / your own theme.
 */
export function ChatWidget({ conversationId, channel, style }: ChatWidgetProps): JSX.Element {
  const { messages, send } = useVoxaChat({ conversationId, channel });
  const [text, setText] = useState('');

  const onSubmit = (e: FormEvent) => {
    e.preventDefault();
    const t = text.trim();
    if (!t) return;
    setText('');
    void send(t);
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', fontFamily: 'system-ui, sans-serif', ...style }}>
      <div style={{ flex: 1, overflowY: 'auto', padding: 12 }} aria-live="polite">
        {messages.length === 0 && <p style={{ color: '#9ca3af' }}>Say hello to start the conversation.</p>}
        {messages.map((m) => {
          const mine = m.sender === 'CONTACT';
          return (
            <div key={m.id} style={{ display: 'flex', justifyContent: mine ? 'flex-end' : 'flex-start', margin: '4px 0' }}>
              <div
                style={{
                  maxWidth: '75%',
                  padding: '6px 10px',
                  borderRadius: 12,
                  background: mine ? '#4f46e5' : '#f3f4f6',
                  color: mine ? '#fff' : '#111827',
                  opacity: m.isDraft ? 0.6 : 1,
                }}
              >
                {m.isBot && <div style={{ fontSize: 10, opacity: 0.7 }}>🤖 Bot{m.isDraft ? ' · draft' : ''}</div>}
                {m.content}
              </div>
            </div>
          );
        })}
      </div>
      <form onSubmit={onSubmit} style={{ display: 'flex', gap: 8, padding: 8, borderTop: '1px solid #e5e7eb' }}>
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Type a message…"
          aria-label="Message"
          style={{ flex: 1, padding: '8px 10px', borderRadius: 8, border: '1px solid #d1d5db', fontSize: 14 }}
        />
        <button type="submit" style={{ padding: '8px 14px', borderRadius: 8, border: 'none', background: '#4f46e5', color: '#fff', cursor: 'pointer' }}>
          Send
        </button>
      </form>
    </div>
  );
}
