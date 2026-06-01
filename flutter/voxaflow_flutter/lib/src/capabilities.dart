import 'dart:convert';

import 'errors.dart';

/// Granular capabilities the unified SDK gates on. The backend is the real
/// enforcement point; this client-side gating gives fast, friendly errors and
/// lets apps hide UI they can't use.
///
/// NOTE: the current Voxa backend authorizes by `role` (AGENT/SUPERVISOR/ADMIN/
/// SUPER_ADMIN), not by a per-capability claim. We DERIVE the capability set from
/// the role here so the SDK's à-la-carte capability model (per the SDK spec) works
/// today; when the backend adds an explicit `capabilities` claim we read that instead.
enum Capability {
  joinCall,
  joinVideo,
  chat,
  consent,
  callControl,
  video,
  copilot,
  transcript,
  entities,
  suggestions,
  forms,
  presence,
  queue,
  transfer,
  escalate,
  botHandoff,
  monitor,
  whisper,
  barge,
  analytics,
}

/// Capabilities available to a contact/patient or guest (no logged-in role).
const Set<Capability> _client = {
  Capability.joinCall,
  Capability.joinVideo,
  Capability.chat,
  Capability.consent,
};

/// Frontline agent.
const Set<Capability> _agent = {
  ..._client,
  Capability.callControl,
  Capability.video,
  Capability.copilot,
  Capability.transcript,
  Capability.entities,
  Capability.suggestions,
  Capability.forms,
  Capability.presence,
  Capability.queue,
  Capability.transfer,
  Capability.escalate,
  Capability.botHandoff,
};

/// Supervisor = agent + live monitoring.
const Set<Capability> _supervisor = {
  ..._agent,
  Capability.monitor,
  Capability.whisper,
  Capability.barge,
  Capability.analytics,
};

/// Derived from the token: the role and the capability set it grants.
class TokenProfile {
  const TokenProfile(this.role, this.capabilities, {this.tenantId, this.userId});

  /// 'CLIENT' for guest/contact tokens; otherwise the JWT role.
  final String role;
  final Set<Capability> capabilities;
  final String? tenantId;
  final String? userId;

  bool can(Capability c) => capabilities.contains(c);

  /// Decode a Voxa access token (JWT) to derive the profile. Does NOT verify the
  /// signature — the server does that; this is only for client-side gating/UI.
  /// A non-JWT or guest token yields the CLIENT profile.
  factory TokenProfile.fromToken(String token) {
    final claims = _decodeJwt(token);
    final role = (claims?['role'] as String?)?.toUpperCase();
    final tenantId = claims?['tenantId'] as String?;
    final userId = claims?['userId'] as String?;
    final caps = switch (role) {
      'SUPERVISOR' => _supervisor,
      'ADMIN' || 'SUPER_ADMIN' => _supervisor, // admins get the full surface
      'AGENT' => _agent,
      _ => _client,
    };
    return TokenProfile(role ?? 'CLIENT', caps, tenantId: tenantId, userId: userId);
  }

  void requireCapability(Capability c) {
    if (!can(c)) {
      throw VoxaError(
        VoxaErrorCode.capability,
        'This token ($role) is not permitted to use "${c.name}".',
      );
    }
  }
}

Map<String, dynamic>? _decodeJwt(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    payload = payload.padRight((payload.length + 3) & ~3, '=');
    final json = utf8.decode(base64.decode(payload));
    final map = jsonDecode(json);
    return map is Map<String, dynamic> ? map : null;
  } catch (_) {
    return null;
  }
}
