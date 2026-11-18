import { describe, it, expect, vi } from 'vitest';
import { bindAppStateRejoin } from '../src/appStateRejoin.js';

function fakeAppState() {
  let fn: ((s: string) => void) | null = null;
  return {
    addEventListener: (_: 'change', f: (s: string) => void) => { fn = f; return { remove: () => { fn = null; } }; },
    emit: (s: string) => fn?.(s),
    bound: () => fn !== null,
  };
}

describe('bindAppStateRejoin', () => {
  it('app returning to the foreground wakes a reconnecting/disconnected call (rejoinNow)', () => {
    const as = fakeAppState();
    const call = { state: 'reconnecting', rejoinNow: vi.fn() };
    bindAppStateRejoin(as, () => call);
    as.emit('active');
    expect(call.rejoinNow).toHaveBeenCalledTimes(1);
    call.state = 'disconnected';
    as.emit('active');
    expect(call.rejoinNow).toHaveBeenCalledTimes(2);
  });
  it('ignores background transitions and connected calls', () => {
    const as = fakeAppState();
    const call = { state: 'reconnecting', rejoinNow: vi.fn() };
    bindAppStateRejoin(as, () => call);
    as.emit('background');
    call.state = 'connected';
    as.emit('active');
    expect(call.rejoinNow).not.toHaveBeenCalled();
  });
  it('no call → no-op; unsubscribe removes the listener', () => {
    const as = fakeAppState();
    const off = bindAppStateRejoin(as, () => null);
    as.emit('active');
    off();
    expect(as.bound()).toBe(false);
  });
});
