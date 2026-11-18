import { describe, it, expect, vi } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';
import { ReconnectBanner } from '../src/components/ReconnectBanner.js';

describe('ReconnectBanner', () => {
  it('renders nothing while connected', () => {
    expect(renderToStaticMarkup(<ReconnectBanner state="connected" onRejoin={vi.fn()} />)).toBe('');
  });
  it('shows "reconnecting… (attempt n)" with a Rejoin-now button during the auto-rejoin loop', () => {
    const html = renderToStaticMarkup(<ReconnectBanner state="reconnecting" attempt={3} onRejoin={vi.fn()} />);
    expect(html).toContain('Connection lost — reconnecting… (attempt 3)');
    expect(html).toContain('Rejoin now');
    expect(html).toContain('role="status"');
  });
  it('omits the attempt suffix before the first attempt (LiveKit resume)', () => {
    const html = renderToStaticMarkup(<ReconnectBanner state="reconnecting" onRejoin={vi.fn()} />);
    expect(html).toContain('Connection lost — reconnecting…<');
  });
  it('after give-up: "Check your network, then rejoin." + Rejoin', () => {
    const html = renderToStaticMarkup(<ReconnectBanner state="disconnected" onRejoin={vi.fn()} />);
    expect(html).toContain('Connection lost. Check your network, then rejoin.');
    expect(html).toContain('>Rejoin<');
  });
});
