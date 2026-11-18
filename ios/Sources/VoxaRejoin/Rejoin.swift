import Foundation
#if canImport(Network)
import Network
#endif
#if canImport(UIKit)
import UIKit
#endif

// Meet-style auto-rejoin (shared semantics on all 5 platforms — see CONTRACT.md "Auto-rejoin").
// On an unexpected drop the session does a FRESH join (new token, same Room, current mic/cam) with
// backoff, waiting until the app is foreground + online, waking early when the network returns, the
// app comes to the foreground, or rejoinNow() is called. Gives up after 10 min → disconnected.
//
// LiveKit-free on purpose (unit-tested without WebRTC): disconnect reasons arrive as
// LiveKitErrorType raw values; `nil` means a clean disconnect (the user left).

/// LiveKitErrorType raw values that mean "this call is over for you".
private let terminalErrorCodes: Set<Int> = [
    100, // cancelled
    500, // duplicateIdentity — joined again from another device
    502, // participantRemoved — removed by the agent/host
    503, // roomDeleted — call ended / room closed
]

/// `errorCode` = `LiveKitError.type.rawValue` from `room(_:didDisconnectWithError:)`; nil = clean (user left).
public func shouldAutoRejoin(errorCode: Int?) -> Bool {
    guard let code = errorCode else { return false }
    return !terminalErrorCodes.contains(code)
}

/// Wait before attempt i (0-based); the last value repeats forever.
public let rejoinDelaysMs: [Int] = [500, 2_000, 5_000, 10_000, 20_000, 30_000]
/// Stop auto-retrying after this long of continuous failure.
public let rejoinGiveUpMs: Int = 10 * 60_000

public func rejoinDelayMs(_ attemptIndex: Int) -> Int {
    rejoinDelaysMs[min(attemptIndex, rejoinDelaysMs.count - 1)]
}

public enum RejoinOutcome: Equatable { case joined, gaveUp, cancelled }

/// The pure loop. `sleep` may return early (see `Waker`).
@MainActor
public func runRejoinLoop(
    join: () async throws -> Void,
    sleep: (Int) async -> Void,
    waitReady: () async -> Void,
    cancelled: () -> Bool,
    now: () -> Int = { Int(Date().timeIntervalSince1970 * 1000) },
    onAttempt: (Int, Int) -> Void = { _, _ in },
    delayMs: (Int) -> Int = rejoinDelayMs,
    giveUpMs: Int = rejoinGiveUpMs
) async -> RejoinOutcome {
    let start = now()
    var i = 0
    while true {
        if cancelled() { return .cancelled }
        await sleep(delayMs(i))
        if cancelled() { return .cancelled }
        await waitReady()
        if cancelled() { return .cancelled }
        // Reported right before the try; the delay is the wait before the next try if this one fails.
        onAttempt(i + 1, delayMs(i + 1))
        do {
            try await join()
            return cancelled() ? .cancelled : .joined
        } catch {
            if cancelled() { return .cancelled }
            if now() - start >= giveUpMs { return .gaveUp }
        }
        i += 1
    }
}

/// A sleep that `wake()` cuts short — wired to network-back, foreground and rejoinNow().
@MainActor
public final class Waker {
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    public init() {}

    public func sleep(ms: Int) async {
        let id = UUID()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters[id] = c
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, ms)) * 1_000_000)
                self?.resume(id)
            }
        }
    }

    /// Resolves on the next `wake()`.
    public func next() async {
        let id = UUID()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in waiters[id] = c }
    }

    public func wake() {
        let all = waiters
        waiters = [:]
        all.values.forEach { $0.resume() }
    }

    private func resume(_ id: UUID) { waiters.removeValue(forKey: id)?.resume() }
}

/// "Can we attempt now?" — foreground + online.
@MainActor
public protocol RejoinReadiness: AnyObject {
    var isReady: Bool { get }
    func waitReady() async
    func dispose()
}

/// Online from NWPathMonitor; foreground from UIApplication notifications (always foreground on
/// macOS). Coming back online / to the foreground wakes the `Waker`.
@MainActor
public final class SystemReadiness: RejoinReadiness {
    private let waker: Waker
    private var online = true
    private var foreground = true
    private var observers: [NSObjectProtocol] = []
    #if canImport(Network)
    private let monitor = NWPathMonitor()
    #endif

    public init(waker: Waker) {
        self.waker = waker
        #if canImport(Network)
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.online = path.status == .satisfied
                if self.isReady { self.waker.wake() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "voxa.rejoin.path"))
        #endif
        #if canImport(UIKit) && !os(watchOS)
        foreground = UIApplication.shared.applicationState != .background
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.foreground = true
                if self.isReady { self.waker.wake() }
            }
        })
        observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.foreground = false }
        })
        #endif
    }

    public var isReady: Bool { online && foreground }

    public func waitReady() async {
        while !isReady { await waker.next() }
    }

    public func dispose() {
        #if canImport(Network)
        monitor.cancel()
        #endif
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }
}

/// Media state of a call/meeting session (mirrors VoxaConnectionState's cases).
public enum VoxaRejoinState: String, Sendable { case connected, reconnecting, disconnected }

/// An auto-rejoin try is starting (`attempt`, 1-based); if it fails the next comes `nextDelayMs` later.
public struct VoxaRejoinAttempt: Equatable, Sendable {
    public let attempt: Int
    public let nextDelayMs: Int
}

/// LiveKit-free session state machine (unit-tested). Sessions feed it Room delegate events.
@MainActor
public final class RejoinController {
    private let join: () async throws -> Void
    private let onRejoined: () -> Void
    private var readiness: RejoinReadiness?
    private let waker: Waker
    private let autoRejoin: Bool
    private let delayMs: (Int) -> Int
    private let giveUpMs: Int

    public private(set) var state: VoxaRejoinState = .connected
    /// 1-based number of the current try (0 when not rejoining) — for "(attempt n)" UI.
    public private(set) var attempt = 0
    public var onStateChange: ((VoxaRejoinState) -> Void)?
    public var onAttempt: ((VoxaRejoinAttempt) -> Void)?

    private var ended = false
    private var rejoining = false

    public init(
        join: @escaping () async throws -> Void,
        onRejoined: @escaping () -> Void,
        readiness: RejoinReadiness? = nil,
        waker: Waker? = nil,
        autoRejoin: Bool = true,
        delayMs: @escaping (Int) -> Int = rejoinDelayMs,
        giveUpMs: Int = rejoinGiveUpMs
    ) {
        self.join = join
        self.onRejoined = onRejoined
        self.readiness = readiness
        self.waker = waker ?? Waker()
        self.autoRejoin = autoRejoin
        self.delayMs = delayMs
        self.giveUpMs = giveUpMs
    }

    private func set(_ s: VoxaRejoinState) {
        guard state != s else { return }
        state = s
        onStateChange?(s)
    }

    public func onReconnecting() { set(.reconnecting) }
    public func onReconnected() { set(.connected) }

    public func onDisconnected(errorCode: Int?) {
        if ended || rejoining { return }
        guard autoRejoin, shouldAutoRejoin(errorCode: errorCode) else {
            set(.disconnected)
            return
        }
        start()
    }

    /// Retry now: cut the wait short, or restart once really disconnected (gave up). Ignored while
    /// LiveKit's own resume runs, while connected, and after `cancel()`.
    public func rejoinNow() {
        if ended { return }
        if rejoining { waker.wake() } else if state == .disconnected { start() }
    }

    /// The user left — stop for good.
    public func cancel() {
        ended = true
        waker.wake()
        readiness?.dispose()
        set(.disconnected)
    }

    private func start() {
        if ended || rejoining { return }
        rejoining = true
        attempt = 0
        set(.reconnecting)
        if readiness == nil { readiness = SystemReadiness(waker: waker) }
        let readiness = self.readiness!
        Task { @MainActor in
            let outcome = await runRejoinLoop(
                join: join,
                sleep: { [waker] in await waker.sleep(ms: $0) },
                waitReady: { await readiness.waitReady() },
                cancelled: { [unowned self] in ended },
                onAttempt: { [unowned self] a, d in
                    attempt = a
                    onAttempt?(VoxaRejoinAttempt(attempt: a, nextDelayMs: d))
                },
                delayMs: delayMs,
                giveUpMs: giveUpMs)
            rejoining = false
            attempt = 0
            switch outcome {
            case .joined: onRejoined(); set(.connected)
            case .gaveUp: set(.disconnected)
            case .cancelled: break
            }
        }
    }
}
