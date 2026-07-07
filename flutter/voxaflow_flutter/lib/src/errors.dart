/// Error codes shared across all Voxa SDKs (web, RN, Flutter, iOS, Android).
/// Keep this enum identical in concept on every platform.
enum VoxaErrorCode {
  /// Token missing/expired/invalid, or refresh failed.
  auth,

  /// The current token's role does not permit this method (capability gating).
  capability,

  /// Transport failure (REST, Socket.IO, or LiveKit signaling).
  connection,

  /// Mic/camera/output device problem.
  device,

  /// Media (publish/subscribe/track) failure.
  media,

  /// Backend rejected the request (validation, not_found, conflict, …).
  server,
}

/// Typed error surfaced by the SDK. Never contains PHI (transcript/message content).
class VoxaError implements Exception {
  const VoxaError(this.code, this.message, {this.cause, this.status});

  final VoxaErrorCode code;
  final String message;

  /// Underlying error/exception, if any.
  final Object? cause;

  /// HTTP status, when the error originated from a REST call.
  final int? status;

  @override
  String toString() => 'VoxaError(${code.name}): $message'
      '${status != null ? ' [HTTP $status]' : ''}'
      '${cause != null ? ' — cause: $cause' : ''}';
}
