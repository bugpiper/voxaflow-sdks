/** Configuration for a VoxaClient. */
export interface VoxaConfig {
  /** Voxa API base, e.g. `https://api.voxaflow.com/api`. The realtime channel is derived
   *  from its origin (`/socket.io`). */
  endpoint: string;
  /** Short-lived Voxa access token minted by the tenant's backend (never an API secret). */
  token: string;
  /** Called on 401/expiry; returns a fresh token. REST + realtime re-auth transparently. */
  onTokenRefresh?: () => Promise<string>;
}
