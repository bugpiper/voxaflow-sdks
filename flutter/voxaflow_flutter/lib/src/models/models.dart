/// Data models surfaced by the SDK as typed Streams. Field shapes mirror the
/// Voxa backend Socket.IO event catalog (ServerToClientEvents) and REST responses.

/// Unified connection lifecycle (mirrors LiveKit + the Voxa realtime channel).
enum VoxaConnectionState { connecting, connected, reconnecting, disconnected }

/// A speech-to-text segment. Interim segments (isFinal=false) are replaced by the
/// final. Sourced from `transcript:update`.
class TranscriptSegment {
  const TranscriptSegment({
    required this.speaker,
    required this.text,
    required this.isFinal,
    this.id,
    this.confidence,
    this.language,
    this.startTime,
    this.endTime,
  });

  final String? id;
  final String speaker; // 'AGENT' | 'CALLER'
  final String text;
  final bool isFinal;
  final double? confidence;
  final String? language;
  final double? startTime;
  final double? endTime;

  factory TranscriptSegment.fromJson(Map<String, dynamic> j) => TranscriptSegment(
        id: j['id'] as String?,
        speaker: (j['speaker'] ?? 'CALLER') as String,
        text: (j['text'] ?? '') as String,
        isFinal: (j['isFinal'] ?? false) as bool,
        confidence: (j['confidence'] as num?)?.toDouble(),
        language: j['language'] as String?,
        startTime: (j['startTime'] as num?)?.toDouble(),
        endTime: (j['endTime'] as num?)?.toDouble(),
      );
}

/// An entity extracted from speech (NER). Sourced from `entity:extracted`.
class ExtractedEntity {
  const ExtractedEntity({
    required this.entityType,
    required this.entityCategory,
    required this.value,
    this.id,
    this.code,
    this.codeSystem,
    this.confidence,
    this.negated = false,
  });

  final String? id;
  final String entityType;
  final String entityCategory;
  final String value;
  final String? code;
  final String? codeSystem;
  final double? confidence;
  final bool negated;

  factory ExtractedEntity.fromJson(Map<String, dynamic> j) => ExtractedEntity(
        id: j['id'] as String?,
        entityType: (j['entityType'] ?? '') as String,
        entityCategory: (j['entityCategory'] ?? '') as String,
        value: (j['value'] ?? '') as String,
        code: j['code'] as String?,
        codeSystem: j['codeSystem'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble(),
        negated: (j['negated'] ?? false) as bool,
      );
}

/// A smart-form auto-fill suggestion. Sourced from `form:autofill`.
class FormUpdate {
  const FormUpdate({required this.fieldId, required this.value, this.confidence});

  final String fieldId;
  final Object? value;
  final double? confidence;

  factory FormUpdate.fromJson(Map<String, dynamic> j) => FormUpdate(
        fieldId: (j['fieldId'] ?? '') as String,
        value: j['value'],
        confidence: (j['confidence'] as num?)?.toDouble(),
      );
}

/// A chat message (contact/agent/bot/system). Sourced from `chat:message` /
/// `chat:draft`. Bot messages carry [botMeta] (quick replies, cards, confidence).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.content,
    required this.createdAt,
    this.isDraft = false,
    this.botMeta,
  });

  final String id;
  final String conversationId;
  final String sender; // 'CONTACT' | 'AGENT' | 'BOT' | 'SYSTEM'
  final String content;
  final DateTime createdAt;
  final bool isDraft;
  final Map<String, dynamic>? botMeta;

  bool get isBot => sender == 'BOT';

  factory ChatMessage.fromJson(Map<String, dynamic> j, {bool isDraft = false}) => ChatMessage(
        id: (j['id'] ?? '') as String,
        conversationId: (j['conversationId'] ?? '') as String,
        sender: (j['sender'] ?? 'SYSTEM') as String,
        content: (j['content'] ?? '') as String,
        createdAt: DateTime.tryParse((j['createdAt'] ?? '') as String) ?? DateTime.now().toUtc(),
        isDraft: isDraft,
        botMeta: (j['botMeta'] as Map?)?.cast<String, dynamic>(),
      );
}

/// Typing indicator. Sourced from `chat:typing`.
class TypingEvent {
  const TypingEvent({required this.conversationId, required this.sender});
  final String conversationId;
  final String sender;
  factory TypingEvent.fromJson(Map<String, dynamic> j) =>
      TypingEvent(conversationId: (j['conversationId'] ?? '') as String, sender: (j['sender'] ?? '') as String);
}

/// Agent presence change. Sourced from `presence:update`.
class PresenceUpdate {
  const PresenceUpdate({required this.userId, required this.status});
  final String userId;
  final String status; // ONLINE | AWAY | DND | OFFLINE | BUSY
  factory PresenceUpdate.fromJson(Map<String, dynamic> j) =>
      PresenceUpdate(userId: (j['userId'] ?? '') as String, status: (j['status'] ?? '') as String);
}

/// Call status change. Sourced from `call:status`.
class CallStatusEvent {
  const CallStatusEvent({required this.callId, required this.status, this.durationSeconds});
  final String callId;
  final String status; // RINGING | ACTIVE | ON_HOLD | ENDED
  final int? durationSeconds;
  factory CallStatusEvent.fromJson(Map<String, dynamic> j) => CallStatusEvent(
        callId: (j['callId'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        durationSeconds: (j['durationSeconds'] as num?)?.toInt(),
      );
}

/// Audio quality (E9 QoS). Computed from LiveKit stats client-side.
class AudioQuality {
  const AudioQuality({this.mos, this.loss, this.jitter, this.rtt});
  final double? mos;
  final double? loss;
  final double? jitter;
  final double? rtt;
}
