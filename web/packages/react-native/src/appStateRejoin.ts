/** Minimal slice of RN's AppState (injected so this stays unit-testable without RN). */
export interface AppStateLike {
  addEventListener(type: 'change', fn: (state: string) => void): { remove(): void };
}
interface RejoinableCall {
  readonly state: string;
  rejoinNow(): void;
}

/**
 * On React Native there's no `document.visibilityState`, so web-core's auto-rejoin treats the app
 * as always "ready". This wakes it the moment the app returns to the foreground (Meet-style):
 * a call that is `reconnecting` retries immediately; one that gave up (`disconnected`) restarts.
 * Returns an unsubscribe.
 */
export function bindAppStateRejoin(appState: AppStateLike, getCall: () => RejoinableCall | null | undefined): () => void {
  const sub = appState.addEventListener('change', (next) => {
    if (next !== 'active') return;
    const call = getCall();
    if (call && (call.state === 'reconnecting' || call.state === 'disconnected')) call.rejoinNow();
  });
  return () => sub.remove();
}
