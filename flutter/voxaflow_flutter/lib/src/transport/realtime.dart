import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/models.dart';

/// Wraps the Voxa realtime channel (Socket.IO at `/socket.io`). Authenticates with
/// the access token in the handshake, exposes typed broadcast Streams for the server
/// event catalog, and lets callers join/leave call/meeting/chat rooms.
class VoxaRealtime {
  VoxaRealtime({required String endpoint, required String token})
      : _origin = Uri.parse(endpoint).origin,
        _token = token;

  final String _origin;
  String _token;
  io.Socket? _socket;

  final _connection = StreamController<VoxaConnectionState>.broadcast();
  final _transcript = StreamController<TranscriptSegment>.broadcast();
  final _entity = StreamController<ExtractedEntity>.broadcast();
  final _formUpdate = StreamController<FormUpdate>.broadcast();
  final _message = StreamController<ChatMessage>.broadcast();
  final _typing = StreamController<TypingEvent>.broadcast();
  final _presence = StreamController<PresenceUpdate>.broadcast();
  final _callStatus = StreamController<CallStatusEvent>.broadcast();

  Stream<VoxaConnectionState> get connectionState => _connection.stream;
  Stream<TranscriptSegment> get transcript => _transcript.stream;
  Stream<ExtractedEntity> get entities => _entity.stream;
  Stream<FormUpdate> get formUpdates => _formUpdate.stream;
  Stream<ChatMessage> get messages => _message.stream;
  Stream<TypingEvent> get typing => _typing.stream;
  Stream<PresenceUpdate> get presence => _presence.stream;
  Stream<CallStatusEvent> get callStatus => _callStatus.stream;

  Future<void> connect() => _open(awaitReady: true);

  /// Re-authenticate after a token refresh: reconnect the socket with the new token.
  void updateToken(String token) {
    _token = token;
    if (_socket != null) {
      _socket!.dispose();
      _socket = null;
      unawaited(_open(awaitReady: false).catchError((_) {}));
    }
  }

  Future<void> _open({required bool awaitReady}) async {
    _connection.add(VoxaConnectionState.connecting);
    final socket = io.io(
      _origin,
      io.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket'])
          .setAuth({'token': _token})
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) => _connection.add(VoxaConnectionState.connected));
    socket.onReconnectAttempt((_) => _connection.add(VoxaConnectionState.reconnecting));
    socket.onDisconnect((_) => _connection.add(VoxaConnectionState.disconnected));

    Map<String, dynamic> asMap(dynamic d) => (d as Map).cast<String, dynamic>();

    socket.on('transcript:update', (d) => _transcript.add(TranscriptSegment.fromJson(asMap(d))));
    socket.on('entity:extracted', (d) => _entity.add(ExtractedEntity.fromJson(asMap(d))));
    socket.on('form:autofill', (d) => _formUpdate.add(FormUpdate.fromJson(asMap(d))));
    socket.on('chat:message', (d) => _message.add(ChatMessage.fromJson(asMap(d))));
    socket.on('chat:draft', (d) => _message.add(ChatMessage.fromJson(asMap(d), isDraft: true)));
    socket.on('chat:typing', (d) => _typing.add(TypingEvent.fromJson(asMap(d))));
    socket.on('presence:update', (d) => _presence.add(PresenceUpdate.fromJson(asMap(d))));
    socket.on('call:status', (d) => _callStatus.add(CallStatusEvent.fromJson(asMap(d))));

    if (!awaitReady) {
      socket.connect();
      return;
    }
    final ready = Completer<void>();
    socket.once('connect', (_) {
      if (!ready.isCompleted) ready.complete();
    });
    socket.onConnectError((e) {
      if (!ready.isCompleted) ready.completeError(e);
    });
    socket.connect();
    await ready.future.timeout(const Duration(seconds: 15));
  }

  void joinCall(String callId) => _socket?.emit('call:join', callId);
  void leaveCall(String callId) => _socket?.emit('call:leave', callId);
  void joinMeeting(String meetingId) => _socket?.emit('meeting:join', meetingId);
  void leaveMeeting(String meetingId) => _socket?.emit('meeting:leave', meetingId);
  void joinChat(String conversationId) => _socket?.emit('chat:join', conversationId);
  void leaveChat(String conversationId) => _socket?.emit('chat:leave', conversationId);

  Future<void> dispose() async {
    _socket?.dispose();
    _socket = null;
    await _connection.close();
    await _transcript.close();
    await _entity.close();
    await _formUpdate.close();
    await _message.close();
    await _typing.close();
    await _presence.close();
    await _callStatus.close();
  }
}
