import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from 'react';
import { VoxaClient, type VoxaConfig } from '@voxaflow/web-core';

// undefined = no provider above; null = provider present but client not created yet.
const VoxaContext = createContext<VoxaClient | null | undefined>(undefined);

export interface VoxaProviderProps extends VoxaConfig {
  children: ReactNode;
}

/**
 * Creates and connects a [VoxaClient] once, and provides it via context. Child hooks/
 * components read it with [useVoxaClient]. The client is created on mount; token refresh
 * is handled internally by the SDK via `onTokenRefresh`.
 */
export function VoxaProvider({ endpoint, token, onTokenRefresh, children }: VoxaProviderProps): JSX.Element {
  const [client, setClient] = useState<VoxaClient | null>(null);
  // Keep the latest onTokenRefresh without recreating the client.
  const refreshRef = useRef(onTokenRefresh);
  refreshRef.current = onTokenRefresh;

  useEffect(() => {
    const c = new VoxaClient({ endpoint, token, onTokenRefresh: () => refreshRef.current!() });
    setClient(c);
    // Fire-and-forget connect; consumers observe progress via useConnectionState.
    c.connect().catch(() => {
      /* surfaced via the 'error'/connectionState events */
    });
    return () => {
      void c.disconnect();
    };
    // Create once for a given endpoint/token identity.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [endpoint, token]);

  return <VoxaContext.Provider value={client}>{children}</VoxaContext.Provider>;
}

/** The VoxaClient from context. Throws if used outside <VoxaProvider>. May be null for
 *  the first render before the client is created — hooks below handle that. */
export function useVoxaClient(): VoxaClient | null {
  const c = useContext(VoxaContext);
  if (c === undefined) {
    throw new Error('useVoxaClient must be used within a <VoxaProvider>');
  }
  return c;
}
