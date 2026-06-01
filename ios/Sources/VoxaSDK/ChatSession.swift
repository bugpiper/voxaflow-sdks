import Foundation

/// A chat conversation (text channel + AI bot). Messages for this conversation arrive on
/// `VoxaClient.messages` (filter by `conversationId`); bot messages have `isBot` true.
public final class ChatSession {
    public let conversationId: String
    private let rest: VoxaRest
    private let realtime: VoxaRealtime

    init(conversationId: String, rest: VoxaRest, realtime: VoxaRealtime) {
        self.conversationId = conversationId
        self.rest = rest
        self.realtime = realtime
    }

    static func open(
        rest: VoxaRest,
        realtime: VoxaRealtime,
        conversationId: String?,
        channel: String?,
        contactIdentifier: String?,
        language: String?
    ) async throws -> ChatSession {
        let convId: String
        if let conversationId {
            convId = conversationId
        } else if let channel {
            var body: [String: Any] = [:]
            if let contactIdentifier { body["contactIdentifier"] = contactIdentifier }
            if let language { body["language"] = language }
            let res = try await rest.post("/chat/widget/\(channel)/start", body)
            guard let id = res["conversationId"] as? String else {
                throw VoxaError(.server, "chat start did not return a conversationId")
            }
            convId = id
        } else {
            throw VoxaError(.server, "openChat requires either a conversationId or a channel handle")
        }
        realtime.joinChat(convId)
        return ChatSession(conversationId: convId, rest: rest, realtime: realtime)
    }

    @discardableResult
    public func sendMessage(_ content: String) async throws -> String {
        let res = try await rest.post("/chat/conversations/\(conversationId)/messages", ["content": content])
        return res["id"] as? String ?? ""
    }

    public func setTyping(_ typing: Bool) async throws {
        if typing { try await rest.post("/chat/conversations/\(conversationId)/typing") }
    }

    public func markRead() async throws {
        try await rest.post("/chat/conversations/\(conversationId)/read")
    }

    public func leave() { realtime.leaveChat(conversationId) }
}
