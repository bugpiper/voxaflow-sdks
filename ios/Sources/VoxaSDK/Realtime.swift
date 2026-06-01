import Foundation
import Combine
import SocketIO

/// Wraps the Voxa realtime channel (Socket.IO at `/socket.io`). Authenticates with the
/// token in the handshake payload and republishes the server event catalog as Combine subjects.
final class VoxaRealtime {
    let connectionState = CurrentValueSubject<VoxaConnectionState, Never>(.connecting)
    let transcript = PassthroughSubject<TranscriptSegment, Never>()
    let entities = PassthroughSubject<ExtractedEntity, Never>()
    let formUpdates = PassthroughSubject<FormUpdate, Never>()
    let messages = PassthroughSubject<ChatMessage, Never>()
    let typing = PassthroughSubject<TypingEvent, Never>()
    let presence = PassthroughSubject<PresenceUpdate, Never>()
    let callStatus = PassthroughSubject<CallStatusEvent, Never>()

    private let origin: URL
    private var token: String
    private var manager: SocketManager?
    private var socket: SocketIOClient?

    init(endpoint: String, token: String) {
        let url = URL(string: endpoint)
        var comp = URLComponents()
        comp.scheme = url?.scheme ?? "https"
        comp.host = url?.host
        comp.port = url?.port
        self.origin = URL(string: comp.string ?? endpoint)!
        self.token = token
    }

    func connect() async throws {
        connectionState.send(.connecting)
        let mgr = SocketManager(socketURL: origin, config: [
            .path("/socket.io/"),
            .forceWebsockets(true),
            .version(.three),
            .reconnects(true),
        ])
        manager = mgr
        let sock = mgr.defaultSocket
        socket = sock

        sock.on(clientEvent: .connect) { [weak self] _, _ in self?.connectionState.send(.connected) }
        sock.on(clientEvent: .reconnectAttempt) { [weak self] _, _ in self?.connectionState.send(.reconnecting) }
        sock.on(clientEvent: .disconnect) { [weak self] _, _ in self?.connectionState.send(.disconnected) }

        func dict(_ data: [Any]) -> [String: Any]? { data.first as? [String: Any] }
        sock.on("transcript:update") { [weak self] d, _ in if let j = dict(d) { self?.transcript.send(.init(json: j)) } }
        sock.on("entity:extracted") { [weak self] d, _ in if let j = dict(d) { self?.entities.send(.init(json: j)) } }
        sock.on("form:autofill") { [weak self] d, _ in if let j = dict(d) { self?.formUpdates.send(.init(json: j)) } }
        sock.on("chat:message") { [weak self] d, _ in if let j = dict(d) { self?.messages.send(.init(json: j)) } }
        sock.on("chat:draft") { [weak self] d, _ in if let j = dict(d) { self?.messages.send(.init(json: j, isDraft: true)) } }
        sock.on("chat:typing") { [weak self] d, _ in if let j = dict(d) { self?.typing.send(.init(json: j)) } }
        sock.on("presence:update") { [weak self] d, _ in if let j = dict(d) { self?.presence.send(.init(json: j)) } }
        sock.on("call:status") { [weak self] d, _ in if let j = dict(d) { self?.callStatus.send(.init(json: j)) } }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = ResumeOnce()
            sock.once(clientEvent: .connect) { _, _ in if resumed.take() { cont.resume() } }
            sock.once(clientEvent: .error) { _, _ in if resumed.take() { cont.resume(throwing: VoxaError(.connection, "Realtime connect failed")) } }
            sock.connect(withPayload: ["token": token])
        }
    }

    func updateToken(_ t: String) {
        token = t
        socket?.disconnect()
        socket?.connect(withPayload: ["token": t])
    }

    func joinCall(_ id: String) { socket?.emit("call:join", id) }
    func leaveCall(_ id: String) { socket?.emit("call:leave", id) }
    func joinMeeting(_ id: String) { socket?.emit("meeting:join", id) }
    func leaveMeeting(_ id: String) { socket?.emit("meeting:leave", id) }
    func joinChat(_ id: String) { socket?.emit("chat:join", id) }
    func leaveChat(_ id: String) { socket?.emit("chat:leave", id) }

    func dispose() {
        socket?.disconnect()
        manager?.disconnect()
    }
}

/// Single-resume guard for the connect continuation.
private final class ResumeOnce {
    private var done = false
    private let lock = NSLock()
    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
