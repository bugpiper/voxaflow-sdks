import Foundation
import LiveKit

/// A 1:1 / queue call. Backed by `POST /rtc/token` → a LiveKit Room. Use `lkRoom` for
/// advanced LiveKit access (e.g. rendering video tiles).
public final class CallSession {
    public let room: Room
    public let id: String
    private let realtime: VoxaRealtime

    init(room: Room, id: String, realtime: VoxaRealtime) {
        self.room = room
        self.id = id
        self.realtime = realtime
    }

    public var lkRoom: Room { room }

    static func start(rest: VoxaRest, realtime: VoxaRealtime, callId: String, video: Bool, name: String?) async throws -> CallSession {
        var body: [String: Any] = ["callId": callId]
        if let name { body["name"] = name }
        let res = try await rest.post("/rtc/token", body)
        guard let wsUrl = res["wsUrl"] as? String, let token = res["token"] as? String else {
            throw VoxaError(.connection, "Backend did not return a LiveKit token/wsUrl")
        }

        let room = Room()
        do {
            try await room.connect(url: wsUrl, token: token)
            try await room.localParticipant.setMicrophone(enabled: true)
            if video { try await room.localParticipant.setCamera(enabled: true) }
        } catch {
            await room.disconnect()
            throw VoxaError(.media, "Failed to join the call room")
        }
        realtime.joinCall(callId)
        return CallSession(room: room, id: callId, realtime: realtime)
    }

    public func setMicEnabled(_ on: Bool) async throws { try await room.localParticipant.setMicrophone(enabled: on) }
    public func setMuted(_ muted: Bool) async throws { try await setMicEnabled(!muted) }
    public func setCameraEnabled(_ on: Bool) async throws { try await room.localParticipant.setCamera(enabled: on) }
    public func startScreenShare() async throws { _ = try await room.localParticipant.set(source: .screenShareVideo, enabled: true) }
    public func stopScreenShare() async throws { _ = try await room.localParticipant.set(source: .screenShareVideo, enabled: false) }
    public func hold() async throws { try await setMicEnabled(false) }
    public func resume() async throws { try await setMicEnabled(true) }

    public func end() async {
        realtime.leaveCall(id)
        await room.disconnect()
    }
}
