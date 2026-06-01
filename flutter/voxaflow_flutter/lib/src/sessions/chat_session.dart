import '../errors.dart';
import '../models/models.dart';
import '../transport/realtime.dart';
import '../transport/rest_client.dart';

/// A chat conversation (text channel + AI bot). Messages and typing for THIS
/// conversation are filtered from the realtime stream. Bot messages have
/// [ChatMessage.isBot] true and carry `botMeta` (quick replies / cards / confidence).
class ChatSession {
  ChatSession._(this.conversationId, this._rest, this._realtime);

  final String conversationId;
  final VoxaRest _rest;
  final VoxaRealtime _realtime;

  /// Live messages (and bot drafts) for this conversation.
  Stream<ChatMessage> get messages =>
      _realtime.messages.where((m) => m.conversationId == conversationId);

  /// Typing indicators from the other party in this conversation.
  Stream<TypingEvent> get typing =>
      _realtime.typing.where((t) => t.conversationId == conversationId);

  /// Open a chat: attach to an existing [conversationId], or start a new one on a
  /// public [channel] handle (contact/widget entry point).
  static Future<ChatSession> open({
    required VoxaRest rest,
    required VoxaRealtime realtime,
    String? conversationId,
    String? channel,
    String? contactIdentifier,
    String? language,
  }) async {
    String convId;
    if (conversationId != null) {
      convId = conversationId;
    } else if (channel != null) {
      final res = await rest.post('/chat/widget/$channel/start', {
        if (contactIdentifier != null) 'contactIdentifier': contactIdentifier,
        if (language != null) 'language': language,
      });
      convId = res['conversationId'] as String;
    } else {
      throw const VoxaError(
        VoxaErrorCode.server,
        'openChat requires either a conversationId or a channel handle',
      );
    }
    realtime.joinChat(convId);
    return ChatSession._(convId, rest, realtime);
  }

  /// Send a text message. Returns the new message id. In BOT/BOT_ASSISTED modes the
  /// backend may run a bot turn (surfaced via the [messages] stream).
  Future<String> sendMessage(String content) async {
    final res = await _rest.post('/chat/conversations/$conversationId/messages', {'content': content});
    return (res['id'] as String?) ?? '';
  }

  /// Emit a typing indicator (best-effort; the backend models a transient ping).
  Future<void> setTyping(bool typing) async {
    if (typing) await _rest.post('/chat/conversations/$conversationId/typing');
  }

  /// Mark the other party's messages as read.
  Future<void> markRead() => _rest.post('/chat/conversations/$conversationId/read');

  /// Stop receiving live updates for this conversation.
  void leave() => _realtime.leaveChat(conversationId);
}
