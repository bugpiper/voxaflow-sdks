import Combine
import Foundation
import LiveKit

/// A 1:1 / queue call. Backed by `POST /rtc/token` → a LiveKit Room. Use `lkRoom` for
/// advanced LiveKit access (e.g. rendering video tiles).
///
/// Auto-rejoin (default on): after an unexpected drop the session re-joins the same room with a
/// fresh token and the user's current mic/cam, Google-Meet style (see `connectionState`).
public final class CallSession {
    public let room: Room
    public let id: String
    private let realtime: VoxaRealtime
    private let rejoin: RtcRejoin

    init(room: Room, id: String, realtime: VoxaRealtime, rest: VoxaRest, name: String?, video: Bool, autoRejoin: Bool) {
        self.room = room
        self.id = id
        self.realtime = realtime
        self.rejoin = RtcRejoin(room: room, video: video, autoRejoin: autoRejoin,
                                fetchCreds: { try await CallSession.token(rest: rest, callId: id, name: name) },
                                onRejoined: { realtime.joinCall(id) })
    }

    public var lkRoom: Room { room }

    /// Media connection state of THIS session (distinct from VoxaClient.connectionState, the
    /// realtime socket): connected → (reconnecting → connected)* → disconnected.
    public var connectionState: AnyPublisher<VoxaConnectionState, Never> { rejoin.state.eraseToAnyPublisher() }
    public var state: VoxaConnectionState { rejoin.state.value }
    /// Each auto-rejoin try, as it starts.
    public var rejoinAttempts: AnyPublisher<VoxaRejoinAttempt, Never> { rejoin.attempts.eraseToAnyPublisher() }
    /// 1-based number of the current auto-rejoin try (0 when not rejoining) — for "(attempt n)" UI.
    @MainActor public var rejoinAttemptNumber: Int { rejoin.attemptNumber }
    /// Retry now: cuts the back-off wait short, or restarts after auto-rejoin gave up. Ignored while
    /// LiveKit's own resume runs and after end().
    @MainActor public func rejoinNow() { rejoin.rejoinNow() }

    static func token(rest: VoxaRest, callId: String, name: String?) async throws -> LiveKitCreds {
        var body: [String: Any] = ["callId": callId]
        if let name { body["name"] = name }
        let res = try await rest.post("/rtc/token", body)
        guard let wsUrl = res["wsUrl"] as? String, let token = res["token"] as? String else {
            throw VoxaError(.connection, "Backend did not return a LiveKit token/wsUrl")
        }
        return LiveKitCreds(wsUrl: wsUrl, token: token)
    }

    static func start(rest: VoxaRest, realtime: VoxaRealtime, callId: String, video: Bool, name: String?, autoRejoin: Bool = true) async throws -> CallSession {
        let creds = try await token(rest: rest, callId: callId, name: name)

        let room = Room()
        do {
            try await room.connect(url: creds.wsUrl, token: creds.token)
            try await room.localParticipant.setMicrophone(enabled: true)
            if video { try await room.localParticipant.setCamera(enabled: true) }
        } catch {
            await room.disconnect()
            throw VoxaError(.media, "Failed to join the call room")
        }
        realtime.joinCall(callId)
        return CallSession(room: room, id: callId, realtime: realtime, rest: rest, name: name, video: video, autoRejoin: autoRejoin)
    }

    public func setMicEnabled(_ on: Bool) async throws { rejoin.wantMic = on; try await room.localParticipant.setMicrophone(enabled: on) }
    public func setMuted(_ muted: Bool) async throws { try await setMicEnabled(!muted) }
    public func setCameraEnabled(_ on: Bool) async throws { rejoin.wantCam = on; try await room.localParticipant.setCamera(enabled: on) }
    public func startScreenShare() async throws { _ = try await room.localParticipant.set(source: .screenShareVideo, enabled: true) }
    public func stopScreenShare() async throws { _ = try await room.localParticipant.set(source: .screenShareVideo, enabled: false) }
    public func hold() async throws { try await setMicEnabled(false) }
    public func resume() async throws { try await setMicEnabled(true) }

    public func end() async {
        await MainActor.run { rejoin.stop() }
        realtime.leaveCall(id)
        await room.disconnect()
    }
}
