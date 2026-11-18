import Foundation
import Combine

/// Configuration for a VoxaClient.
public struct VoxaConfig {
    public let endpoint: String
    public let token: String
    public let onTokenRefresh: (() async throws -> String)?

    public init(endpoint: String, token: String, onTokenRefresh: (() async throws -> String)? = nil) {
        self.endpoint = endpoint
        self.token = token
        self.onTokenRefresh = onTokenRefresh
    }
}

/// Entry point of the Voxa Flow iOS SDK. Same concepts as the Web/Flutter/RN/Android SDKs —
/// only the idioms (async/await + Combine) differ.
///
/// ```swift
/// let client = VoxaClient(VoxaConfig(endpoint: "…", token: "…", onTokenRefresh: { try await myToken() }))
/// try await client.connect()
/// let sub = client.transcript.sink { print($0.speaker, $0.text) }
/// let call = try await client.startCall(video: true)
/// ```
public final class VoxaClient {
    public let profile: TokenProfile
    private let rest: VoxaRest
    private let realtime: VoxaRealtime
    private var connected = false

    public init(_ config: VoxaConfig) {
        profile = .from(token: config.token)
        rest = VoxaRest(endpoint: config.endpoint, token: config.token, onTokenRefresh: config.onTokenRefresh)
        realtime = VoxaRealtime(endpoint: config.endpoint, token: config.token)
        rest.onTokenChanged = { [weak realtime] t in realtime?.updateToken(t) }
    }

    // MARK: Combine publishers (the unified event set)
    public var connectionState: AnyPublisher<VoxaConnectionState, Never> { realtime.connectionState.eraseToAnyPublisher() }
    public var transcript: AnyPublisher<TranscriptSegment, Never> { realtime.transcript.eraseToAnyPublisher() }
    public var entities: AnyPublisher<ExtractedEntity, Never> { realtime.entities.eraseToAnyPublisher() }
    public var formUpdates: AnyPublisher<FormUpdate, Never> { realtime.formUpdates.eraseToAnyPublisher() }
    public var messages: AnyPublisher<ChatMessage, Never> { realtime.messages.eraseToAnyPublisher() }
    public var typing: AnyPublisher<TypingEvent, Never> { realtime.typing.eraseToAnyPublisher() }
    public var presence: AnyPublisher<PresenceUpdate, Never> { realtime.presence.eraseToAnyPublisher() }
    public var callStatus: AnyPublisher<CallStatusEvent, Never> { realtime.callStatus.eraseToAnyPublisher() }
    public var meetingTranscript: AnyPublisher<MeetingTranscriptSegment, Never> { realtime.meetingTranscript.eraseToAnyPublisher() }
    public var meetingParticipant: AnyPublisher<MeetingParticipantEvent, Never> { realtime.meetingParticipant.eraseToAnyPublisher() }
    public var meetingOutput: AnyPublisher<MeetingOutputEvent, Never> { realtime.meetingOutput.eraseToAnyPublisher() }

    /// Directed incoming rings ("user X is calling you"). Present an incoming-call UI,
    /// then `acceptCall`/`rejectCall`.
    public var incomingCalls: AnyPublisher<VoxaCallRing, Never> { realtime.incomingCalls.eraseToAnyPublisher() }

    /// Resolution of a ring you're a party to (accepted/rejected/canceled/timeout).
    /// As the caller, `startCall` with this callId on `.accepted`; tear down the ring UI on the others.
    public var callSignals: AnyPublisher<VoxaCallSignal, Never> { realtime.callSignals.eraseToAnyPublisher() }

    public func can(_ c: Capability) -> Bool { profile.can(c) }

    /// Open the realtime channel and validate the token.
    public func connect() async throws {
        if connected { return }
        try await realtime.connect()
        connected = true
    }

    /// Tear down realtime + REST. End sessions first.
    public func disconnect() {
        connected = false
        realtime.dispose()
    }

    /// Start (or join) a voice/video call. Omit `callId` for an ephemeral room.
    public func startCall(callId: String? = nil, video: Bool = false, name: String? = nil, autoRejoin: Bool = true) async throws -> CallSession {
        try profile.requireCapability(video ? .joinVideo : .joinCall)
        try ensureConnected()
        return try await CallSession.start(rest: rest, realtime: realtime, callId: callId ?? Self.ephemeralId("call"), video: video, name: name, autoRejoin: autoRejoin)
    }

    /// Create a multi-party meeting (AGENT+); returns its id + room name.
    @discardableResult
    public func createMeeting(type: String? = nil, title: String? = nil) async throws -> [String: Any] {
        try profile.requireCapability(.callControl)
        try ensureConnected()
        var body: [String: Any] = [:]
        if let type { body["type"] = type }
        if let title { body["title"] = title }
        return try await rest.post("/meetings", body)
    }

    /// Join a multi-party meeting by id.
    public func joinMeeting(_ meetingId: String, video: Bool = false, displayName: String? = nil, role: String? = nil, language: String? = nil, autoRejoin: Bool = true) async throws -> MeetingSession {
        try profile.requireCapability(video ? .joinVideo : .joinCall)
        try ensureConnected()
        return try await MeetingSession.join(rest: rest, realtime: realtime, meetingId: meetingId, video: video, displayName: displayName, role: role, language: language, autoRejoin: autoRejoin)
    }

    /// Open a chat conversation (attach to `conversationId`, or start one on a `channel` handle).
    public func openChat(conversationId: String? = nil, channel: String? = nil, contactIdentifier: String? = nil, language: String? = nil) async throws -> ChatSession {
        try profile.requireCapability(.chat)
        try ensureConnected()
        return try await ChatSession.open(rest: rest, realtime: realtime, conversationId: conversationId, channel: channel, contactIdentifier: contactIdentifier, language: language)
    }

    /// Set the agent's presence (AGENT+).
    public func setPresence(_ status: String) async throws {
        try profile.requireCapability(.presence)
        try await rest.put("/agents/presence", ["status": status])
    }

    // MARK: Client engagement (SDK9)

    @discardableResult
    public func requestCall(handle: String, name: String? = nil, audioOnly: Bool? = nil) async throws -> String {
        try profile.requireCapability(.joinCall)
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let audioOnly { body["audioOnly"] = audioOnly }
        let res = try await rest.post("/calls/dial/\(handle)", body)
        return res["callId"] as? String ?? ""
    }

    // MARK: Directed ringing ("dial user X → ring → accept/reject/connect")

    /// Ring a specific user (`toUserId`) in your tenant. Returns the new callId and when the
    /// ring expires. The callee receives a `VoxaCallRing` on `incomingCalls`; you receive a
    /// `VoxaCallSignal` on `callSignals` when they accept (→ then `startCall` with this callId),
    /// reject, or it times out.
    @discardableResult
    public func inviteUser(_ toUserId: String, video: Bool = false, name: String? = nil) async throws -> (callId: String, expiresAt: Date?) {
        try profile.requireCapability(.joinCall)
        try ensureConnected()
        var body: [String: Any] = ["toUserId": toUserId, "video": video]
        if let name { body["name"] = name }
        let res = try await rest.post("/calls/invite", body)
        let expiresAt = (res["expiresAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return (res["callId"] as? String ?? "", expiresAt)
    }

    /// Accept an incoming ring, then join its room. Returns the live `CallSession`.
    public func acceptCall(_ callId: String, video: Bool = false, name: String? = nil, autoRejoin: Bool = true) async throws -> CallSession {
        try ensureConnected()
        _ = try await rest.post("/calls/\(callId)/answer")
        return try await CallSession.start(rest: rest, realtime: realtime, callId: callId, video: video, name: name, autoRejoin: autoRejoin)
    }

    /// Decline an incoming ring as the callee.
    public func rejectCall(_ callId: String, reason: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let reason { body["reason"] = reason }
        _ = try await rest.post("/calls/\(callId)/reject", body)
    }

    /// Cancel a ring you placed, before it's answered.
    public func cancelCall(_ callId: String) async throws { _ = try await rest.post("/calls/\(callId)/cancel") }

    /// Register this device's push token so rings reach the app when it's backgrounded/killed.
    /// `platform` is "ios" | "android" | "web"; set `voip` for an iOS PushKit token. Delivery is
    /// gated on the backend having APNs/FCM creds configured.
    public func registerDevice(platform: String, token: String, voip: Bool = false) async throws {
        var body: [String: Any] = ["platform": platform, "token": token]
        if voip { body["voip"] = true }
        _ = try await rest.post("/push/devices", body)
    }

    /// Unregister a device push token (logout / token rotation).
    public func unregisterDevice(_ token: String) async throws { _ = try await rest.delete("/push/devices", ["token": token]) }

    // MARK: Agent operations + copilot (SDK8)

    public func getActiveCalls() async throws -> [[String: Any]] {
        try profile.requireCapability(.callControl)
        let res = try await rest.get("/calls")
        return res["calls"] as? [[String: Any]] ?? []
    }
    public func answerCall(_ callId: String) async throws { try profile.requireCapability(.callControl); _ = try await rest.post("/calls/\(callId)/answer") }
    public func holdCall(_ callId: String) async throws { try profile.requireCapability(.callControl); _ = try await rest.post("/calls/\(callId)/hold") }
    public func transferCall(_ callId: String, toAgentId: String) async throws { try profile.requireCapability(.transfer); _ = try await rest.post("/calls/\(callId)/transfer", ["toAgentId": toAgentId]) }

    public func getEntities(_ callId: String) async throws -> [ExtractedEntity] {
        try profile.requireCapability(.entities)
        let res = try await rest.get("/calls/\(callId)/entities")
        return (res["entities"] as? [[String: Any]] ?? []).map { ExtractedEntity(json: $0) }
    }
    public func confirmEntity(_ entityId: String) async throws { try profile.requireCapability(.entities); _ = try await rest.put("/entities/\(entityId)/confirm") }
    public func rejectEntity(_ entityId: String) async throws { try profile.requireCapability(.entities); _ = try await rest.put("/entities/\(entityId)/reject") }

    public func getSuggestions(_ callId: String) async throws -> [Suggestion] {
        try profile.requireCapability(.suggestions)
        let res = try await rest.get("/calls/\(callId)/suggestions")
        return (res["suggestions"] as? [[String: Any]] ?? []).map { Suggestion(json: $0) }
    }
    public func dismissSuggestion(_ callId: String, suggestionId: String) async throws { try profile.requireCapability(.suggestions); _ = try await rest.post("/calls/\(callId)/suggestions/\(suggestionId)/dismiss") }

    public func getForm(_ callId: String) async throws -> [String: Any] { try profile.requireCapability(.forms); return try await rest.get("/calls/\(callId)/form") }
    public func editField(_ callId: String, fieldId: String, value: Any) async throws { try profile.requireCapability(.forms); _ = try await rest.put("/calls/\(callId)/form", ["fieldId": fieldId, "value": value]) }
    public func confirmField(_ callId: String, fieldId: String) async throws { try profile.requireCapability(.forms); _ = try await rest.post("/calls/\(callId)/form/confirm-field", ["fieldId": fieldId]) }
    public func rejectField(_ callId: String, fieldId: String) async throws { try profile.requireCapability(.forms); _ = try await rest.post("/calls/\(callId)/form/reject-field", ["fieldId": fieldId]) }
    public func submitForm(_ callId: String) async throws { try profile.requireCapability(.forms); _ = try await rest.post("/calls/\(callId)/form/submit") }

    public func getSummary(_ callId: String) async throws -> [String: Any] { try profile.requireCapability(.copilot); return try await rest.get("/calls/\(callId)/summary") }

    private func ensureConnected() throws {
        if !connected { throw VoxaError(.connection, "Call connect() before opening a session.") }
    }

    private static func ephemeralId(_ prefix: String) -> String {
        "sdk-\(prefix)-\(UUID().uuidString.prefix(6).lowercased())"
    }
}
