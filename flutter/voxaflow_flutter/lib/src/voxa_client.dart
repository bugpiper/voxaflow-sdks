import 'dart:math';

import 'capabilities.dart';
import 'errors.dart';
import 'models/models.dart';
import 'sessions/call_session.dart';
import 'sessions/chat_session.dart';
import 'transport/realtime.dart';
import 'transport/rest_client.dart';

/// Configuration for a [VoxaClient].
class VoxaConfig {
  const VoxaConfig({required this.endpoint, required this.token, this.onTokenRefresh});

  /// Voxa API base, e.g. `https://api.voxaflow.com/api`. The realtime channel is
  /// derived from its origin (`/socket.io`).
  final String endpoint;

  /// Short-lived Voxa access token minted by the TENANT's backend (never an API secret).
  final String token;

  /// Called when the token is rejected/expired; returns a fresh token. The SDK
  /// re-auths REST + realtime transparently.
  final Future<String> Function()? onTokenRefresh;
}

/// Entry point of the Voxa Flow Flutter SDK. Same concepts as the web/RN/iOS/Android
/// SDKs — only the Dart idioms (Futures + Streams) differ.
///
/// ```dart
/// final client = VoxaClient(VoxaConfig(endpoint: '...', token: '...', onTokenRefresh: ...));
/// await client.connect();
/// final call = await client.startCall(video: true);
/// client.transcript.listen((seg) => print('${seg.speaker}: ${seg.text}'));
/// ```
class VoxaClient {
  VoxaClient(this.config)
      : _profile = TokenProfile.fromToken(config.token),
        _rest = VoxaRest(
          endpoint: config.endpoint,
          token: config.token,
          onTokenRefresh: config.onTokenRefresh,
        ),
        _realtime = VoxaRealtime(endpoint: config.endpoint, token: config.token) {
    // When REST refreshes the token, re-auth the realtime channel too.
    _rest.onTokenChanged = _realtime.updateToken;
  }

  final VoxaConfig config;
  final VoxaRest _rest;
  final VoxaRealtime _realtime;
  final TokenProfile _profile;
  bool _connected = false;

  /// The capability profile derived from the token (role-based today).
  TokenProfile get profile => _profile;
  bool can(Capability c) => _profile.can(c);

  // ── Event streams (mirror the unified event model) ─────────────────────────
  Stream<VoxaConnectionState> get connectionState => _realtime.connectionState;
  Stream<TranscriptSegment> get transcript => _realtime.transcript;
  Stream<ExtractedEntity> get entities => _realtime.entities;
  Stream<FormUpdate> get formUpdates => _realtime.formUpdates;
  Stream<ChatMessage> get messages => _realtime.messages;
  Stream<TypingEvent> get typing => _realtime.typing;
  Stream<PresenceUpdate> get presence => _realtime.presence;
  Stream<CallStatusEvent> get callStatus => _realtime.callStatus;

  /// Open the realtime channel and validate the token.
  Future<void> connect() async {
    if (_connected) return;
    try {
      await _realtime.connect();
      _connected = true;
    } catch (e) {
      if (e is VoxaError) rethrow;
      throw VoxaError(VoxaErrorCode.connection, 'Failed to open the Voxa realtime channel', cause: e);
    }
  }

  /// Tear down realtime + REST. Sessions should be ended first.
  Future<void> disconnect() async {
    _connected = false;
    await _realtime.dispose();
    _rest.close();
  }

  /// Start (or join) a voice/video call. If [callId] is omitted, an ephemeral room
  /// id is generated (good for direct/click-to-call). Transcript/entity/form events
  /// for the call then arrive on this client's streams.
  Future<CallSession> startCall({String? callId, bool video = false, String? name}) async {
    _profile.requireCapability(video ? Capability.joinVideo : Capability.joinCall);
    _ensureConnected();
    return CallSession.start(
      rest: _rest,
      realtime: _realtime,
      callId: callId ?? _ephemeralId('call'),
      video: video,
      name: name,
    );
  }

  /// Open a chat conversation (attach to [conversationId], or start one on a public
  /// [channel] handle).
  Future<ChatSession> openChat({String? conversationId, String? channel, String? contactIdentifier, String? language}) async {
    _profile.requireCapability(Capability.chat);
    _ensureConnected();
    return ChatSession.open(
      rest: _rest,
      realtime: _realtime,
      conversationId: conversationId,
      channel: channel,
      contactIdentifier: contactIdentifier,
      language: language,
    );
  }

  /// Set the agent's presence (AGENT+). Reflects the backend AgentPresence.
  Future<void> setPresence(String status) async {
    _profile.requireCapability(Capability.presence);
    await _rest.put('/agents/presence', {'status': status});
  }

  void _ensureConnected() {
    if (!_connected) {
      throw const VoxaError(VoxaErrorCode.connection, 'Call connect() before opening a session.');
    }
  }

  String _ephemeralId(String prefix) {
    final r = Random();
    final s = List.generate(6, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[r.nextInt(36)]).join();
    return 'sdk-$prefix-$s';
  }
}
