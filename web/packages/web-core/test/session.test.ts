import { describe, it, expect, vi, afterEach } from 'vitest';
import { EventEmitter } from 'eventemitter3';
import { Waker, browserReadiness } from '../src/sessions/rejoin.js';
import { RtcSession, type LiveKitCreds } from '../src/sessions/call.js';

afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

/** Minimal browser globals so readiness can be exercised under node. */
function fakeBrowser(init: { visible: boolean; online: boolean }) {
  const doc = new EventTarget() as EventTarget & { visibilityState: string };
  doc.visibilityState = init.visible ? 'visible' : 'hidden';
  const win = new EventTarget();
  const nav = { onLine: init.online };
  vi.stubGlobal('document', doc);
  vi.stubGlobal('window', win);
  vi.stubGlobal('navigator', nav);
  return {
    goOnline() { nav.onLine = true; win.dispatchEvent(new Event('online')); },
    show() { doc.visibilityState = 'visible'; doc.dispatchEvent(new Event('visibilitychange')); },
  };
}

describe('browserReadiness', () => {
  it('waits while offline and wakes a pending back-off sleep when the network returns', async () => {
    const b = fakeBrowser({ visible: true, online: false });
    const w = new Waker();
    const r = browserReadiness(w);
    let slept = false, ready = false;
    void w.sleep(30_000).then(() => { slept = true; });
    void r.waitReady().then(() => { ready = true; });
    await Promise.resolve();
    expect(ready).toBe(false);
    b.goOnline();
    await new Promise((res) => setTimeout(res, 0));
    expect(slept).toBe(true);
    expect(ready).toBe(true);
    r.dispose();
  });

  it('waits while the page is hidden (locked phone) and resumes when it becomes visible', async () => {
    const b = fakeBrowser({ visible: false, online: true });
    const r = browserReadiness(new Waker());
    let ready = false;
    void r.waitReady().then(() => { ready = true; });
    await Promise.resolve();
    expect(ready).toBe(false);
    b.show();
    await new Promise((res) => setTimeout(res, 0));
    expect(ready).toBe(true);
    r.dispose();
  });

  it('is always ready outside a browser (React Native / SSR)', async () => {
    vi.stubGlobal('document', undefined);
    vi.stubGlobal('window', undefined);
    vi.stubGlobal('navigator', undefined);
    const r = browserReadiness(new Waker());
    expect(r.isReady()).toBe(true);
    await r.waitReady();
  });
});

/** Fake LiveKit Room: connect() succeeds/fails per script; disconnect() emits 'disconnected'. */
class FakeRoom extends EventEmitter {
  state = 'connected';
  connects = 0;
  failNext = 0;
  mic: boolean[] = [];
  cam: boolean[] = [];
  localParticipant = {
    setMicrophoneEnabled: async (on: boolean) => { this.mic.push(on); },
    setCameraEnabled: async (on: boolean) => { this.cam.push(on); },
    setScreenShareEnabled: async () => {},
  };
  async connect() {
    this.connects++;
    if (this.failNext > 0) { this.failNext--; this.state = 'disconnected'; throw new Error('offline'); }
    this.state = 'connected';
  }
  async disconnect() { this.state = 'disconnected'; }
  drop(reason?: number) { this.state = 'disconnected'; this.emit('disconnected', reason); }
}

class TestSession extends RtcSession {
  tokens = 0;
  realtimeRejoins = 0;
  constructor(room: FakeRoom, opts: { video?: boolean; autoRejoin?: boolean } = {}) {
    super(room as never, 'call-1', { joinCall() {}, leaveCall() {} } as never, opts);
  }
  protected async fetchCreds(): Promise<LiveKitCreds> { this.tokens++; return { token: 't', wsUrl: 'w' }; }
  protected rejoinRealtime() { this.realtimeRejoins++; }
  protected async leave() {}
}

describe('RtcSession auto-rejoin', () => {
  it('unexpected drop → reconnecting → fresh token + connect → connected, restoring the CURRENT mic/cam', async () => {
    vi.useFakeTimers();
    const room = new FakeRoom();
    const s = new TestSession(room, { video: true });
    const states: string[] = [];
    s.on('connectionState', (x) => states.push(x));
    await s.setMicEnabled(false); // user muted before the drop
    room.mic.length = 0;
    room.drop(14); // CONNECTION_TIMEOUT
    await vi.advanceTimersByTimeAsync(500);
    expect(states).toEqual(['reconnecting', 'connected']);
    expect(s.tokens).toBe(1);
    expect(room.connects).toBe(1);
    expect(room.mic).toEqual([]); // stays muted
    expect(room.cam).toEqual([true]);
    expect(s.realtimeRejoins).toBe(1);
  });

  it('intentional end (CLIENT_INITIATED / ROOM_DELETED) → disconnected, no rejoin', async () => {
    vi.useFakeTimers();
    for (const reason of [1, 5]) {
      const room = new FakeRoom();
      const s = new TestSession(room);
      room.drop(reason);
      await vi.advanceTimersByTimeAsync(60_000);
      expect(s.state).toBe('disconnected');
      expect(room.connects).toBe(0);
    }
  });

  it('autoRejoin:false → disconnected on any drop', async () => {
    vi.useFakeTimers();
    const room = new FakeRoom();
    const s = new TestSession(room, { autoRejoin: false });
    room.drop(14);
    await vi.advanceTimersByTimeAsync(60_000);
    expect(s.state).toBe('disconnected');
    expect(room.connects).toBe(0);
  });

  it('rejoinNow() cuts the back-off wait short', async () => {
    vi.useFakeTimers();
    const room = new FakeRoom();
    room.failNext = 5; // attempts 1-5 fail; next wait is 30s
    const s = new TestSession(room);
    room.drop(9);
    await vi.advanceTimersByTimeAsync(500 + 2000 + 5000 + 10000 + 20000);
    expect(room.connects).toBe(5);
    s.rejoinNow();
    await vi.advanceTimersByTimeAsync(0);
    expect(room.connects).toBe(6);
    expect(s.state).toBe('connected');
  });

  it('gives up after 10 min → disconnected; rejoinNow() then starts a new loop', async () => {
    vi.useFakeTimers();
    const room = new FakeRoom();
    room.failNext = 1_000;
    const s = new TestSession(room);
    room.drop(9);
    await vi.advanceTimersByTimeAsync(11 * 60_000);
    expect(s.state).toBe('disconnected');
    const n = room.connects;
    await vi.advanceTimersByTimeAsync(5 * 60_000);
    expect(room.connects).toBe(n); // really stopped
    room.failNext = 0;
    s.rejoinNow();
    await vi.advanceTimersByTimeAsync(500);
    expect(s.state).toBe('connected');
  });

  it('end() during the loop cancels it — no further connects', async () => {
    vi.useFakeTimers();
    const room = new FakeRoom();
    room.failNext = 1_000;
    const s = new TestSession(room);
    room.drop(9);
    await vi.advanceTimersByTimeAsync(2500);
    const n = room.connects;
    await s.end();
    await vi.advanceTimersByTimeAsync(5 * 60_000);
    expect(room.connects).toBe(n);
    expect(s.state).toBe('disconnected');
  });

  it("rejoinNow() is ignored while LiveKit's own resume runs (room reconnecting)", async () => {
    vi.useFakeTimers();
    const room = new FakeRoom();
    const s = new TestSession(room);
    room.state = 'reconnecting';
    room.emit('reconnecting');
    expect(s.state).toBe('reconnecting');
    s.rejoinNow();
    await vi.advanceTimersByTimeAsync(60_000);
    expect(room.connects).toBe(0);
  });

  it('rejoinNow() after end() does nothing', async () => {
    vi.useFakeTimers();
    const room = new FakeRoom();
    const s = new TestSession(room);
    await s.end();
    s.rejoinNow();
    await vi.advanceTimersByTimeAsync(60_000);
    expect(room.connects).toBe(0);
  });

  it('exposes the current attempt number for the banner', async () => {
    vi.useFakeTimers();
    const room = new FakeRoom();
    room.failNext = 2;
    const s = new TestSession(room);
    const seen: number[] = [];
    s.on('rejoinAttempt', (e) => seen.push(e.attempt));
    room.drop(9);
    await vi.advanceTimersByTimeAsync(500 + 2000);
    expect(s.rejoinAttemptNumber).toBe(2);
    await vi.advanceTimersByTimeAsync(5000);
    expect(seen).toEqual([1, 2, 3]);
    expect(s.state).toBe('connected');
  });
});
