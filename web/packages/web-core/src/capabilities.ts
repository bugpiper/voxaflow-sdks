import { VoxaError } from './errors.js';

/**
 * Granular capabilities the SDK gates on. The backend is the real enforcement point;
 * this client-side gating gives fast, friendly errors and lets apps hide unusable UI.
 *
 * NOTE: the current Voxa backend authorizes by `role` (AGENT/SUPERVISOR/ADMIN/
 * SUPER_ADMIN). We DERIVE the capability set from the role; when the backend adds an
 * explicit `capabilities` claim, read that instead (no public API change).
 */
export type Capability =
  | 'joinCall'
  | 'joinVideo'
  | 'chat'
  | 'consent'
  | 'callControl'
  | 'video'
  | 'copilot'
  | 'transcript'
  | 'entities'
  | 'suggestions'
  | 'forms'
  | 'presence'
  | 'queue'
  | 'transfer'
  | 'escalate'
  | 'botHandoff'
  | 'monitor'
  | 'whisper'
  | 'barge'
  | 'analytics';

const CLIENT: Capability[] = ['joinCall', 'joinVideo', 'chat', 'consent'];
const AGENT: Capability[] = [
  ...CLIENT,
  'callControl', 'video', 'copilot', 'transcript', 'entities', 'suggestions',
  'forms', 'presence', 'queue', 'transfer', 'escalate', 'botHandoff',
];
const SUPERVISOR: Capability[] = [...AGENT, 'monitor', 'whisper', 'barge', 'analytics'];

export class TokenProfile {
  readonly role: string;
  readonly capabilities: ReadonlySet<Capability>;
  readonly tenantId?: string;
  readonly userId?: string;

  private constructor(role: string, caps: Capability[], tenantId?: string, userId?: string) {
    this.role = role;
    this.capabilities = new Set(caps);
    this.tenantId = tenantId;
    this.userId = userId;
  }

  can(c: Capability): boolean {
    return this.capabilities.has(c);
  }

  requireCapability(c: Capability): void {
    if (!this.can(c)) {
      throw new VoxaError('CAPABILITY', `This token (${this.role}) is not permitted to use "${c}".`);
    }
  }

  /** Decode a Voxa access token (JWT) for client-side gating. Does NOT verify the
   *  signature — the server does. A non-JWT / guest token yields the CLIENT profile. */
  static fromToken(token: string): TokenProfile {
    const claims = decodeJwt(token);
    const role = typeof claims?.role === 'string' ? claims.role.toUpperCase() : undefined;
    const tenantId = typeof claims?.tenantId === 'string' ? claims.tenantId : undefined;
    const userId = typeof claims?.userId === 'string' ? claims.userId : undefined;
    const caps =
      role === 'SUPERVISOR' || role === 'ADMIN' || role === 'SUPER_ADMIN'
        ? SUPERVISOR
        : role === 'AGENT'
          ? AGENT
          : CLIENT;
    return new TokenProfile(role ?? 'CLIENT', caps, tenantId, userId);
  }
}

function decodeJwt(token: string): Record<string, unknown> | null {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const payload = parts[1]!.replace(/-/g, '+').replace(/_/g, '/');
    // atob is available in browsers and modern Node (16+) as a global; claims we read
    // (role/tenantId/userId) are ASCII, so this is sufficient for client-side gating.
    const parsed: unknown = JSON.parse(atob(payload));
    return typeof parsed === 'object' && parsed !== null ? (parsed as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}
