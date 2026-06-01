import Foundation
import LiveKit

/// A multi-party meeting (MP1–MP8). Backed by `POST /meetings/:id/token` → a LiveKit Room.
/// Per-speaker transcript / participant / AI-output events arrive on the VoxaClient
/// meetingTranscript / meetingParticipant / meetingOutput publishers once joined.
public final class MeetingSession {
    public let room: Room
    public let id: String
    private let realtime: VoxaRealtime

    init(room: Room, id: String, realtime: VoxaRealtime) {
        self.room = room
        self.id = id
        self.realtime = realtime
    }

    public var lkRoom: Room { room }

    static func join(rest: VoxaRest, realtime: VoxaRealtime, meetingId: String, video: Bool, displayName: String?, role: String?, language: String?) async throws -> MeetingSession {
        var body: [String: Any] = [:]
        if let displayName { body["name"] = displayName }
        if let role { body["role"] = role }
        if let language { body["language"] = language }
        let res = try await rest.post("/meetings/\(meetingId)/token", body)
        guard let wsUrl = res["wsUrl"] as? String, let token = res["token"] as? String else {
            throw VoxaError(.connection, "Backend did not return a meeting LiveKit token/wsUrl")
        }
        let room = Room()
        do {
            try await room.connect(url: wsUrl, token: token)
            try await room.localParticipant.setMicrophone(enabled: true)
            if video { try await room.localParticipant.setCamera(enabled: true) }
        } catch {
            await room.disconnect()
            throw VoxaError(.media, "Failed to join the meeting room")
        }
        realtime.joinMeeting(meetingId)
        return MeetingSession(room: room, id: meetingId, realtime: realtime)
    }

    public func setMicEnabled(_ on: Bool) async throws { try await room.localParticipant.setMicrophone(enabled: on) }
    public func setCameraEnabled(_ on: Bool) async throws { try await room.localParticipant.setCamera(enabled: on) }

    public func end() async {
        realtime.leaveMeeting(id)
        await room.disconnect()
    }
}
