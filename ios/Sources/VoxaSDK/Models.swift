import Foundation

public enum VoxaConnectionState: String, Sendable {
    case connecting, connected, reconnecting, disconnected
}

public struct TranscriptSegment: Sendable {
    public let id: String?
    public let speaker: String
    public let text: String
    public let isFinal: Bool
    public let confidence: Double?
    public let language: String?
    public let startTime: Double?
    public let endTime: Double?

    init(json j: [String: Any]) {
        id = j["id"] as? String
        speaker = j["speaker"] as? String ?? "CALLER"
        text = j["text"] as? String ?? ""
        isFinal = j["isFinal"] as? Bool ?? false
        confidence = j["confidence"] as? Double
        language = j["language"] as? String
        startTime = j["startTime"] as? Double
        endTime = j["endTime"] as? Double
    }
}

public struct ExtractedEntity: Sendable {
    public let id: String?
    public let entityType: String
    public let entityCategory: String
    public let value: String
    public let code: String?
    public let codeSystem: String?
    public let confidence: Double?
    public let negated: Bool

    init(json j: [String: Any]) {
        id = j["id"] as? String
        entityType = j["entityType"] as? String ?? ""
        entityCategory = j["entityCategory"] as? String ?? ""
        value = j["value"] as? String ?? ""
        code = j["code"] as? String
        codeSystem = j["codeSystem"] as? String
        confidence = j["confidence"] as? Double
        negated = j["negated"] as? Bool ?? false
    }
}

public struct FormUpdate: Sendable {
    public let fieldId: String
    public let value: String?
    public let confidence: Double?

    init(json j: [String: Any]) {
        fieldId = j["fieldId"] as? String ?? ""
        value = j["value"].map { "\($0)" }
        confidence = j["confidence"] as? Double
    }
}

public struct ChatMessage: Sendable {
    public let id: String
    public let conversationId: String
    public let sender: String
    public let content: String
    public let createdAt: String
    public let isDraft: Bool
    public var isBot: Bool { sender == "BOT" }

    init(json j: [String: Any], isDraft: Bool = false) {
        id = j["id"] as? String ?? ""
        conversationId = j["conversationId"] as? String ?? ""
        sender = j["sender"] as? String ?? "SYSTEM"
        content = j["content"] as? String ?? ""
        createdAt = j["createdAt"] as? String ?? ""
        self.isDraft = isDraft
    }
}

public struct TypingEvent: Sendable {
    public let conversationId: String
    public let sender: String
    init(json j: [String: Any]) {
        conversationId = j["conversationId"] as? String ?? ""
        sender = j["sender"] as? String ?? ""
    }
}

public struct PresenceUpdate: Sendable {
    public let userId: String
    public let status: String
    init(json j: [String: Any]) {
        userId = j["userId"] as? String ?? ""
        status = j["status"] as? String ?? ""
    }
}

public struct CallStatusEvent: Sendable {
    public let callId: String
    public let status: String
    public let durationSeconds: Int?
    init(json j: [String: Any]) {
        callId = j["callId"] as? String ?? ""
        status = j["status"] as? String ?? ""
        durationSeconds = j["durationSeconds"] as? Int
    }
}

public struct Suggestion: Sendable {
    public let id: String
    public let fieldId: String
    public let value: String?
    public let confidence: Double?
    init(json j: [String: Any]) {
        id = j["id"] as? String ?? ""
        fieldId = j["fieldId"] as? String ?? ""
        value = j["value"].map { "\($0)" }
        confidence = j["confidence"] as? Double
    }
}
