import { describe, it, expect, vi } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';
import { ReconnectBanner } from '../src/components/ReconnectBanner.js';

describe('ReconnectBanner', () => {
  it('renders nothing while connected', () => {
    expect(renderToStaticMarkup(<ReconnectBanner state="connected" onRejoin={vi.fn()} />)).toBe('');
  });
  it('shows "reconnecting" with a Rejoin-now button during the auto-rejoin loop', () => {
    const html = renderToStaticMarkup(<ReconnectBanner state="reconnecting" onRejoin={vi.fn()} />);
    expect(html).toContain('Connection lost — reconnecting…');
    expect(html).toContain('Rejoin now');
    expect(html).toContain('role="status"');
  });
  it('after give-up shows "disconnected" with a Rejoin button', () => {
    const html = renderToStaticMarkup(<ReconnectBanner state="disconnected" onRejoin={vi.fn()} />);
    expect(html).toContain('Disconnected');
    expect(html).toContain('>Rejoin<');
  });
});
