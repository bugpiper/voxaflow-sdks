import { VoxaError } from '../errors.js';

/** REST client: attaches the token, parses JSON, and on a 401 transparently refreshes
 *  the token (via onTokenRefresh) and retries once. */
export class VoxaRest {
  onTokenChanged?: (token: string) => void;

  constructor(
    private readonly endpoint: string,
    private token: string,
    private readonly onTokenRefresh?: () => Promise<string>,
  ) {}

  post<T = Record<string, unknown>>(path: string, body?: unknown): Promise<T> {
    return this.send<T>('POST', path, body);
  }
  get<T = Record<string, unknown>>(path: string): Promise<T> {
    return this.send<T>('GET', path);
  }
  put<T = Record<string, unknown>>(path: string, body?: unknown): Promise<T> {
    return this.send<T>('PUT', path, body);
  }

  private async send<T>(method: string, path: string, body?: unknown, retry = true): Promise<T> {
    let res: Response;
    try {
      res = await fetch(`${this.endpoint}${path}`, {
        method,
        headers: { authorization: `Bearer ${this.token}`, 'content-type': 'application/json' },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch (cause) {
      throw new VoxaError('CONNECTION', `Network error calling ${path}`, { cause });
    }

    if (res.status === 401 && retry && this.onTokenRefresh) {
      try {
        this.token = await this.onTokenRefresh();
        this.onTokenChanged?.(this.token);
      } catch (cause) {
        throw new VoxaError('AUTH', 'Token refresh failed', { status: 401, cause });
      }
      return this.send<T>(method, path, body, false);
    }

    if (res.ok) {
      const text = await res.text();
      return (text ? JSON.parse(text) : {}) as T;
    }
    const code = res.status === 401 || res.status === 403 ? 'AUTH' : 'SERVER';
    throw new VoxaError(code, await errMessage(res), { status: res.status });
  }
}

async function errMessage(res: Response): Promise<string> {
  try {
    const j: unknown = JSON.parse(await res.text());
    if (j && typeof j === 'object') {
      const o = j as Record<string, unknown>;
      if (typeof o.message === 'string') return o.message;
      if (typeof o.error === 'string') return o.error;
    }
  } catch {
    /* ignore */
  }
  return `Request failed (HTTP ${res.status})`;
}
