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
    public func startCall(callId: String? = nil, video: Bool = false, name: String? = nil) async throws -> CallSession {
        try profile.requireCapability(video ? .joinVideo : .joinCall)
        try ensureConnected()
        return try await CallSession.start(rest: rest, realtime: realtime, callId: callId ?? Self.ephemeralId("call"), video: video, name: name)
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

    private func ensureConnected() throws {
        if !connected { throw VoxaError(.connection, "Call connect() before opening a session.") }
    }

    private static func ephemeralId(_ prefix: String) -> String {
        "sdk-\(prefix)-\(UUID().uuidString.prefix(6).lowercased())"
    }
}
