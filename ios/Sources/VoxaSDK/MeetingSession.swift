import Combine
import Foundation
import LiveKit

/// A multi-party meeting (MP1–MP8). Backed by `POST /meetings/:id/token` → a LiveKit Room.
/// Per-speaker transcript / participant / AI-output events arrive on the VoxaClient
/// meetingTranscript / meetingParticipant / meetingOutput publishers once joined.
public final class MeetingSession {
    public let room: Room
    public let id: String
    private let realtime: VoxaRealtime
    private let rejoin: RtcRejoin

    init(room: Room, id: String, realtime: VoxaRealtime, rest: VoxaRest, body: [String: Any], video: Bool, autoRejoin: Bool) {
        self.room = room
        self.id = id
        self.realtime = realtime
        self.rejoin = RtcRejoin(room: room, video: video, autoRejoin: autoRejoin,
                                fetchCreds: { try await MeetingSession.token(rest: rest, meetingId: id, body: body) },
                                onRejoined: { realtime.joinMeeting(id) })
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

    static func token(rest: VoxaRest, meetingId: String, body: [String: Any]) async throws -> LiveKitCreds {
        let res = try await rest.post("/meetings/\(meetingId)/token", body)
        guard let wsUrl = res["wsUrl"] as? String, let token = res["token"] as? String else {
            throw VoxaError(.connection, "Backend did not return a meeting LiveKit token/wsUrl")
        }
        return LiveKitCreds(wsUrl: wsUrl, token: token)
    }

    static func join(rest: VoxaRest, realtime: VoxaRealtime, meetingId: String, video: Bool, displayName: String?, role: String?, language: String?, autoRejoin: Bool = true) async throws -> MeetingSession {
        var body: [String: Any] = [:]
        if let displayName { body["name"] = displayName }
        if let role { body["role"] = role }
        if let language { body["language"] = language }
        let creds = try await token(rest: rest, meetingId: meetingId, body: body)
        let room = Room()
        do {
            try await room.connect(url: creds.wsUrl, token: creds.token)
            try await room.localParticipant.setMicrophone(enabled: true)
            if video { try await room.localParticipant.setCamera(enabled: true) }
        } catch {
            await room.disconnect()
            throw VoxaError(.media, "Failed to join the meeting room")
        }
        realtime.joinMeeting(meetingId)
        return MeetingSession(room: room, id: meetingId, realtime: realtime, rest: rest, body: body, video: video, autoRejoin: autoRejoin)
    }

    public func setMicEnabled(_ on: Bool) async throws { rejoin.wantMic = on; try await room.localParticipant.setMicrophone(enabled: on) }
    public func setCameraEnabled(_ on: Bool) async throws { rejoin.wantCam = on; try await room.localParticipant.setCamera(enabled: on) }

    public func end() async {
        await MainActor.run { rejoin.stop() }
        realtime.leaveMeeting(id)
        await room.disconnect()
    }
}
