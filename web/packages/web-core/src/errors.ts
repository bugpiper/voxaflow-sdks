/** Error codes shared across all Voxa SDKs. Keep identical in concept everywhere. */
export type VoxaErrorCode =
  | 'AUTH'
  | 'CAPABILITY'
  | 'CONNECTION'
  | 'DEVICE'
  | 'MEDIA'
  | 'SERVER';

/** Typed error surfaced by the SDK. Never contains PHI (transcript/message content). */
export class VoxaError extends Error {
  readonly code: VoxaErrorCode;
  readonly status?: number;
  readonly cause?: unknown;

  constructor(code: VoxaErrorCode, message: string, opts?: { status?: number; cause?: unknown }) {
    super(message);
    this.name = 'VoxaError';
    this.code = code;
    this.status = opts?.status;
    this.cause = opts?.cause;
  }
}
