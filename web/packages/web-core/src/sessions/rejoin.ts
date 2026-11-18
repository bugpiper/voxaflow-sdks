/**
 * Meet-style auto-rejoin (shared semantics on all 5 platforms — see CONTRACT.md "Auto-rejoin").
 *
 * When a call drops for a reason that isn't an intentional end (phone locked / app backgrounded,
 * network lost, media node restarted), the session does a FRESH join — new token, connect, restore
 * the user's current mic/cam — with backoff, waiting until the page/app is visible and online, and
 * waking early when the network comes back, the app returns to the foreground, or `rejoinNow()` is
 * called. It gives up after 10 minutes of continuous failure.
 *
 * Pure + injected I/O so it's unit-tested without LiveKit (test/rejoin.test.ts). It deliberately
 * does NOT import livekit-client at runtime (that stays lazy-loaded).
 */

/** LiveKit `DisconnectReason` values that mean "this call is over for you" — never rejoin.
 *  Numeric to avoid a runtime livekit-client import; the test pins them to the real enum. */
const TERMINAL_REASONS = new Set<number>([
  1, // CLIENT_INITIATED — the user left / end() was called
  2, // DUPLICATE_IDENTITY — joined again from another tab/device
  4, // PARTICIPANT_REMOVED — removed by the agent/host
  5, // ROOM_DELETED — call ended
  10, // ROOM_CLOSED
]);

export function shouldAutoRejoin(reason: number | undefined | null): boolean {
  return reason == null || !TERMINAL_REASONS.has(reason);
}

/** Wait before attempt i (0-based). The last value repeats forever. */
export const REJOIN_DELAYS_MS: readonly number[] = [500, 2_000, 5_000, 10_000, 20_000, 30_000];
/** Stop auto-retrying after this long of continuous failure → state `disconnected`. */
export const REJOIN_GIVE_UP_MS = 10 * 60_000;

export function rejoinDelay(attemptIndex: number): number {
  return REJOIN_DELAYS_MS[Math.min(attemptIndex, REJOIN_DELAYS_MS.length - 1)]!;
}

export type RejoinOutcome = 'joined' | 'gaveUp' | 'cancelled';

export async function runRejoinLoop(deps: {
  join: () => Promise<void>;
  /** Sleep that may resolve early (see Waker). */
  sleep: (ms: number) => Promise<void>;
  /** Resolves once the page/app is foreground AND online. */
  waitReady: () => Promise<void>;
  cancelled: () => boolean;
  now?: () => number;
  /** Right before each try: 1-based attempt + the wait before the next try if it fails. */
  onAttempt?: (attempt: number, nextDelayMs: number) => void;
}): Promise<RejoinOutcome> {
  const now = deps.now ?? Date.now;
  const start = now();
  for (let i = 0; ; i++) {
    if (deps.cancelled()) return 'cancelled';
    await deps.sleep(rejoinDelay(i));
    if (deps.cancelled()) return 'cancelled';
    await deps.waitReady();
    if (deps.cancelled()) return 'cancelled';
    // Reported right before the try; nextDelayMs = the wait before the next try if this one fails.
    deps.onAttempt?.(i + 1, rejoinDelay(i + 1));
    try {
      await deps.join();
      return deps.cancelled() ? 'cancelled' : 'joined';
    } catch {
      if (deps.cancelled()) return 'cancelled';
      if (now() - start >= REJOIN_GIVE_UP_MS) return 'gaveUp';
    }
  }
}

/** A sleep that `wake()` can cut short — wired to 'online', visibility→visible and rejoinNow(). */
export class Waker {
  private pending = new Set<() => void>();

  sleep(ms: number): Promise<void> {
    return new Promise((resolve) => {
      const done = () => {
        clearTimeout(timer);
        this.pending.delete(done);
        resolve();
      };
      const timer = setTimeout(done, ms);
      this.pending.add(done);
    });
  }

  /** Resolve every pending sleep/wait now. */
  wake(): void {
    for (const done = [...this.pending]; done.length; ) done.pop()!();
  }

  /** Resolves on the next wake(). */
  next(): Promise<void> {
    return new Promise((resolve) => {
      const done = () => {
        this.pending.delete(done);
        resolve();
      };
      this.pending.add(done);
    });
  }
}

/** Browser readiness: visible + online. Outside a browser (React Native, SSR) there's no
 *  `document`/`navigator.onLine`, so it's always ready (RN apps can call `rejoinNow()` from an
 *  AppState 'active' listener — the RN CallView does). Returns `dispose` to remove listeners. */
export function browserReadiness(waker: Waker): { isReady: () => boolean; waitReady: () => Promise<void>; dispose: () => void } {
  const hasDoc = typeof document !== 'undefined' && typeof document.addEventListener === 'function';
  const hasWin = typeof window !== 'undefined' && typeof window.addEventListener === 'function';
  const isReady = () => {
    const visible = !hasDoc || document.visibilityState !== 'hidden';
    const online = typeof navigator === 'undefined' || navigator.onLine !== false;
    return visible && online;
  };
  const onChange = () => {
    if (isReady()) waker.wake();
  };
  if (hasDoc) document.addEventListener('visibilitychange', onChange);
  if (hasWin) window.addEventListener('online', onChange);
  return {
    isReady,
    async waitReady() {
      while (!isReady()) await waker.next();
    },
    dispose() {
      if (hasDoc) document.removeEventListener('visibilitychange', onChange);
      if (hasWin) window.removeEventListener('online', onChange);
    },
  };
}

/** What `rejoinNow()` / the "Rejoin now" button does. While LiveKit's own short-blip resume runs,
 *  the room is not 'disconnected' yet — starting a fresh join on top of it would double-connect. */
export function rejoinNowAction(s: { left: boolean; rejoining: boolean; roomState: string }): 'wake' | 'restart' | 'ignore' {
  if (s.left) return 'ignore';
  if (s.rejoining) return 'wake';
  return s.roomState === 'disconnected' ? 'restart' : 'ignore';
}
