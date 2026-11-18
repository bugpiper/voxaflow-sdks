import Combine
import Foundation
import LiveKit
@_exported import VoxaRejoin

/// Fresh LiveKit credentials for a session's room.
struct LiveKitCreds { let wsUrl: String; let token: String }

/// Wires a LiveKit `Room` to `RejoinController` for Call/MeetingSession: maps Room delegate events,
/// tracks the user's mic/cam choice, and performs the fresh join (new token → connect the SAME Room
/// so app delegates/views survive → restore mic/cam).
final class RtcRejoin: NSObject, RoomDelegate, @unchecked Sendable {
    private let room: Room
    private let fetchCreds: () async throws -> LiveKitCreds
    private let onRejoined: () -> Void
    private let autoRejoin: Bool
    var wantMic = true
    var wantCam: Bool

    let state = CurrentValueSubject<VoxaConnectionState, Never>(.connected)
    let attempts = PassthroughSubject<VoxaRejoinAttempt, Never>()
    @MainActor private var controller: RejoinController?

    init(room: Room, video: Bool, autoRejoin: Bool, fetchCreds: @escaping () async throws -> LiveKitCreds, onRejoined: @escaping () -> Void) {
        self.room = room
        self.wantCam = video
        self.autoRejoin = autoRejoin
        self.fetchCreds = fetchCreds
        self.onRejoined = onRejoined
        super.init()
        room.add(delegate: self)
    }

    @MainActor private func ctl() -> RejoinController {
        if let c = controller { return c }
        let c = RejoinController(join: { [weak self] in try await self?.freshJoin() }, onRejoined: { [weak self] in self?.onRejoined() }, autoRejoin: autoRejoin)
        c.onStateChange = { [weak self] s in
            self?.state.send(VoxaConnectionState(rawValue: s.rawValue) ?? .disconnected)
        }
        c.onAttempt = { [weak self] a in self?.attempts.send(a) }
        controller = c
        return c
    }

    @MainActor var attemptNumber: Int { controller?.attempt ?? 0 }
    @MainActor func rejoinNow() { ctl().rejoinNow() }

    @MainActor func stop() {
        ctl().cancel()
        room.remove(delegate: self)
    }

    // MARK: RoomDelegate (called off the main actor)
    func roomIsReconnecting(_ room: Room) { Task { @MainActor in self.ctl().onReconnecting() } }
    func roomDidReconnect(_ room: Room) { Task { @MainActor in self.ctl().onReconnected() } }
    func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        let code = error?.type.rawValue
        Task { @MainActor in self.ctl().onDisconnected(errorCode: code) }
    }

    private func freshJoin() async throws {
        do {
            let c = try await fetchCreds()
            try await room.connect(url: c.wsUrl, token: c.token)
        } catch {
            await room.disconnect()
            throw error
        }
        if wantMic { _ = try? await room.localParticipant.setMicrophone(enabled: true) }
        if wantCam { _ = try? await room.localParticipant.setCamera(enabled: true) }
    }
}
