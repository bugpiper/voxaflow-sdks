import 'dart:math';

import 'capabilities.dart';
import 'errors.dart';
import 'models/models.dart';
import 'sessions/call_session.dart';
import 'sessions/chat_session.dart';
import 'sessions/meeting_session.dart';
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
  Stream<MeetingTranscriptSegment> get meetingTranscript => _realtime.meetingTranscript;
  Stream<MeetingParticipantEvent> get meetingParticipant => _realtime.meetingParticipant;
  Stream<MeetingOutputEvent> get meetingOutput => _realtime.meetingOutput;

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

  /// Create a multi-party meeting (AGENT+); returns its id + room name.
  Future<Map<String, dynamic>> createMeeting({String? type, String? title}) async {
    _profile.requireCapability(Capability.callControl);
    _ensureConnected();
    return _rest.post('/meetings', {
      if (type != null) 'type': type,
      if (title != null) 'title': title,
    });
  }

  /// Join a multi-party meeting by [meetingId]. Per-speaker transcript / participant /
  /// output events arrive on the meeting* streams.
  Future<MeetingSession> joinMeeting(String meetingId, {bool video = false, String? displayName, String? role, String? language}) async {
    _profile.requireCapability(video ? Capability.joinVideo : Capability.joinCall);
    _ensureConnected();
    return MeetingSession.join(
      rest: _rest,
      realtime: _realtime,
      meetingId: meetingId,
      video: video,
      displayName: displayName,
      role: role,
      language: language,
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

  // ── Client engagement (SDK9) ───────────────────────────────────────────────

  /// Click-to-call: place an inbound call on a tenant [handle]; returns the new callId.
  Future<String> requestCall(String handle, {String? name, bool? audioOnly}) async {
    _profile.requireCapability(Capability.joinCall);
    final res = await _rest.post('/calls/dial/$handle', {
      if (name != null) 'name': name,
      if (audioOnly != null) 'audioOnly': audioOnly,
    });
    return (res['callId'] as String?) ?? '';
  }

  // ── Agent operations + copilot (SDK8), callId-scoped + capability-gated ─────

  Future<List<Map<String, dynamic>>> getActiveCalls() async {
    _profile.requireCapability(Capability.callControl);
    final res = await _rest.get('/calls');
    return ((res['calls'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  Future<void> answerCall(String callId) async {
    _profile.requireCapability(Capability.callControl);
    await _rest.post('/calls/$callId/answer');
  }

  Future<void> holdCall(String callId) async {
    _profile.requireCapability(Capability.callControl);
    await _rest.post('/calls/$callId/hold');
  }

  Future<void> transferCall(String callId, String toAgentId) async {
    _profile.requireCapability(Capability.transfer);
    await _rest.post('/calls/$callId/transfer', {'toAgentId': toAgentId});
  }

  Future<List<ExtractedEntity>> getEntities(String callId) async {
    _profile.requireCapability(Capability.entities);
    final res = await _rest.get('/calls/$callId/entities');
    return ((res['entities'] as List?) ?? [])
        .map((e) => ExtractedEntity.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> confirmEntity(String entityId) async {
    _profile.requireCapability(Capability.entities);
    await _rest.put('/entities/$entityId/confirm');
  }

  Future<void> rejectEntity(String entityId) async {
    _profile.requireCapability(Capability.entities);
    await _rest.put('/entities/$entityId/reject');
  }

  Future<List<Suggestion>> getSuggestions(String callId) async {
    _profile.requireCapability(Capability.suggestions);
    final res = await _rest.get('/calls/$callId/suggestions');
    return ((res['suggestions'] as List?) ?? [])
        .map((s) => Suggestion.fromJson((s as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> dismissSuggestion(String callId, String suggestionId) async {
    _profile.requireCapability(Capability.suggestions);
    await _rest.post('/calls/$callId/suggestions/$suggestionId/dismiss');
  }

  Future<Map<String, dynamic>> getForm(String callId) async {
    _profile.requireCapability(Capability.forms);
    return _rest.get('/calls/$callId/form');
  }

  Future<void> editField(String callId, String fieldId, Object? value) async {
    _profile.requireCapability(Capability.forms);
    await _rest.put('/calls/$callId/form', {'fieldId': fieldId, 'value': value});
  }

  Future<void> confirmField(String callId, String fieldId) async {
    _profile.requireCapability(Capability.forms);
    await _rest.post('/calls/$callId/form/confirm-field', {'fieldId': fieldId});
  }

  Future<void> rejectField(String callId, String fieldId) async {
    _profile.requireCapability(Capability.forms);
    await _rest.post('/calls/$callId/form/reject-field', {'fieldId': fieldId});
  }

  Future<void> submitForm(String callId) async {
    _profile.requireCapability(Capability.forms);
    await _rest.post('/calls/$callId/form/submit');
  }

  /// Post-call summary (SOAP/BANT/etc., template-driven).
  Future<Map<String, dynamic>> getSummary(String callId) async {
    _profile.requireCapability(Capability.copilot);
    return _rest.get('/calls/$callId/summary');
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
