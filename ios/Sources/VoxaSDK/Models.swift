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

/// An incoming directed ring ("user X is calling you"). Sourced from `call:ring`.
public struct VoxaCallRing: Sendable {
    public let callId: String
    public let fromId: String
    public let fromName: String
    public let video: Bool
    public let vertical: String?
    public let expiresAt: Date?

    init(json j: [String: Any]) {
        let from = j["from"] as? [String: Any] ?? [:]
        callId = j["callId"] as? String ?? ""
        fromId = from["id"] as? String ?? ""
        fromName = from["name"] as? String ?? "Caller"
        video = j["video"] as? Bool ?? false
        vertical = j["vertical"] as? String
        expiresAt = (j["expiresAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}

/// How a pending ring resolved (for the OTHER party). Sourced from
/// `call:accepted` / `call:rejected` / `call:canceled` / `call:timeout`.
public enum VoxaCallSignalKind: String, Sendable {
    case accepted, rejected, canceled, timeout
}

/// Resolution of a directed ring you're a party to.
public struct VoxaCallSignal: Sendable {
    public let callId: String
    public let kind: VoxaCallSignalKind
    /// Who accepted (for `.accepted`).
    public let by: String?
    /// Why it was rejected (for `.rejected`).
    public let reason: String?

    init(kind: VoxaCallSignalKind, json j: [String: Any]) {
        callId = j["callId"] as? String ?? ""
        self.kind = kind
        by = j["by"] as? String
        reason = j["reason"] as? String
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

public struct MeetingTranscriptSegment: Sendable {
    public let meetingId: String
    public let speakerId: String
    public let identity: String
    public let text: String
    public let isFinal: Bool
    public let language: String?
    public let startTime: Double?
    init(json j: [String: Any]) {
        meetingId = j["meetingId"] as? String ?? ""
        speakerId = j["speakerId"] as? String ?? ""
        identity = j["identity"] as? String ?? ""
        text = j["text"] as? String ?? ""
        isFinal = j["isFinal"] as? Bool ?? false
        language = j["language"] as? String
        startTime = j["startTime"] as? Double
    }
}

public struct MeetingParticipantEvent: Sendable {
    public let meetingId: String
    public let identity: String
    public let state: String
    init(json j: [String: Any]) {
        meetingId = j["meetingId"] as? String ?? ""
        identity = j["identity"] as? String ?? ""
        state = j["state"] as? String ?? ""
    }
}

public struct MeetingOutputEvent: Sendable {
    public let meetingId: String
    public let type: String
    init(json j: [String: Any]) {
        meetingId = j["meetingId"] as? String ?? ""
        type = j["type"] as? String ?? ""
    }
}
