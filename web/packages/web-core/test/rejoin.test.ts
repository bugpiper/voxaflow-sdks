import { describe, it, expect, vi } from 'vitest';
import { DisconnectReason } from 'livekit-client';
import {
  shouldAutoRejoin,
  rejoinDelay,
  runRejoinLoop,
  Waker,
  REJOIN_DELAYS_MS,
  REJOIN_GIVE_UP_MS,
} from '../src/sessions/rejoin.js';

describe('shouldAutoRejoin', () => {
  it('rejoins after any connection/network loss', () => {
    for (const r of [
      undefined,
      DisconnectReason.UNKNOWN_REASON,
      DisconnectReason.SIGNAL_CLOSE,
      DisconnectReason.STATE_MISMATCH,
      DisconnectReason.JOIN_FAILURE,
      DisconnectReason.CONNECTION_TIMEOUT,
      DisconnectReason.MEDIA_FAILURE,
      DisconnectReason.SERVER_SHUTDOWN,
      DisconnectReason.MIGRATION,
    ]) expect(shouldAutoRejoin(r), `reason ${r}`).toBe(true);
  });
  it('never rejoins an intentional end', () => {
    for (const r of [
      DisconnectReason.CLIENT_INITIATED,
      DisconnectReason.DUPLICATE_IDENTITY,
      DisconnectReason.PARTICIPANT_REMOVED,
      DisconnectReason.ROOM_DELETED,
      DisconnectReason.ROOM_CLOSED,
    ]) expect(shouldAutoRejoin(r), `reason ${r}`).toBe(false);
  });
});

describe('rejoinDelay', () => {
  it('follows the schedule then repeats 30s forever', () => {
    expect(REJOIN_DELAYS_MS).toEqual([500, 2000, 5000, 10000, 20000, 30000]);
    expect([0, 1, 2, 3, 4, 5, 6, 50].map(rejoinDelay)).toEqual([500, 2000, 5000, 10000, 20000, 30000, 30000, 30000]);
  });
});

/** Fake clock: sleep advances time instantly. */
function fakeClock() {
  let t = 0;
  return { now: () => t, sleep: vi.fn(async (ms: number) => { t += ms; }) };
}
const ready = () => Promise.resolve();

describe('runRejoinLoop', () => {
  it('first attempt succeeds → joined', async () => {
    const c = fakeClock();
    const join = vi.fn().mockResolvedValue(undefined);
    expect(await runRejoinLoop({ join, ...c, waitReady: ready, cancelled: () => false })).toBe('joined');
    expect(join).toHaveBeenCalledTimes(1);
  });

  it('retries on the backoff schedule until a join succeeds, reporting each attempt', async () => {
    const c = fakeClock();
    const onAttempt = vi.fn();
    const join = vi.fn().mockRejectedValueOnce(new Error('net')).mockRejectedValueOnce(new Error('net')).mockResolvedValue(undefined);
    expect(await runRejoinLoop({ join, ...c, waitReady: ready, cancelled: () => false, onAttempt })).toBe('joined');
    expect(join).toHaveBeenCalledTimes(3);
    expect(c.sleep.mock.calls.map((x) => x[0])).toEqual([500, 2000, 5000]);
    expect(onAttempt.mock.calls).toEqual([[1, 500], [2, 2000], [3, 5000]]);
  });

  it('keeps trying past the schedule (30s apart) and gives up only after 10 minutes', async () => {
    const c = fakeClock();
    const join = vi.fn().mockRejectedValue(new Error('down'));
    expect(await runRejoinLoop({ join, ...c, waitReady: ready, cancelled: () => false })).toBe('gaveUp');
    expect(c.now()).toBeGreaterThanOrEqual(REJOIN_GIVE_UP_MS);
    expect(c.now()).toBeLessThan(REJOIN_GIVE_UP_MS + 30_000);
    expect(join.mock.calls.length).toBeGreaterThan(REJOIN_DELAYS_MS.length);
  });

  it('waits for readiness (visible + online) before every attempt', async () => {
    const c = fakeClock();
    const order: string[] = [];
    const join = vi.fn(async () => { order.push('join'); });
    const waitReady = vi.fn(async () => { order.push('ready'); });
    await runRejoinLoop({ join, ...c, waitReady, cancelled: () => false });
    expect(order).toEqual(['ready', 'join']);
  });

  it('stops without joining once cancelled (user left)', async () => {
    const c = fakeClock();
    let left = false;
    const join = vi.fn().mockImplementation(async () => { left = true; throw new Error('x'); });
    expect(await runRejoinLoop({ join, ...c, waitReady: ready, cancelled: () => left })).toBe('cancelled');
    expect(join).toHaveBeenCalledTimes(1);
  });
});

describe('Waker', () => {
  it('sleep resolves on the timer', async () => {
    vi.useFakeTimers();
    const w = new Waker();
    let done = false;
    void w.sleep(1000).then(() => { done = true; });
    await vi.advanceTimersByTimeAsync(999);
    expect(done).toBe(false);
    await vi.advanceTimersByTimeAsync(1);
    expect(done).toBe(true);
    vi.useRealTimers();
  });
  it('wake() cuts a pending sleep short (network back / foreground / rejoinNow)', async () => {
    vi.useFakeTimers();
    const w = new Waker();
    let done = false;
    void w.sleep(30_000).then(() => { done = true; });
    w.wake();
    await vi.advanceTimersByTimeAsync(0);
    expect(done).toBe(true);
    vi.useRealTimers();
  });
});
