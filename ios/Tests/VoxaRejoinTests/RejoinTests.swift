import XCTest
@testable import VoxaRejoin

/// Meet-style auto-rejoin — mirrors web-core / Flutter / Android tests (CONTRACT.md "Auto-rejoin").
/// LiveKit-free: reasons are LiveKitErrorType raw values (nil = clean, user-initiated disconnect).
@MainActor
final class RejoinTests: XCTestCase {

    // LiveKitErrorType raw values (client-sdk-swift Errors.swift)
    let unknown = 0, cancelled = 100, timedOut = 101, network = 202, duplicateIdentity = 500, serverShutdown = 501,
        participantRemoved = 502, roomDeleted = 503, stateMismatch = 504, joinFailure = 505, serverPingTimedOut = 601

    func testRejoinsAfterConnectionLoss() {
        for r in [unknown, timedOut, network, serverShutdown, stateMismatch, joinFailure, serverPingTimedOut] {
            XCTAssertTrue(shouldAutoRejoin(errorCode: r), "\(r)")
        }
    }

    func testNeverRejoinsIntentionalEnd() {
        XCTAssertFalse(shouldAutoRejoin(errorCode: nil), "clean disconnect (user left)")
        for r in [cancelled, duplicateIdentity, participantRemoved, roomDeleted] {
            XCTAssertFalse(shouldAutoRejoin(errorCode: r), "\(r)")
        }
    }

    func testDelayScheduleRepeats30s() {
        XCTAssertEqual(rejoinDelaysMs, [500, 2000, 5000, 10000, 20000, 30000])
        XCTAssertEqual([0, 1, 2, 3, 4, 5, 6, 50].map(rejoinDelayMs), [500, 2000, 5000, 10000, 20000, 30000, 30000, 30000])
        XCTAssertEqual(rejoinGiveUpMs, 600_000)
    }

    /// Fake clock: sleep advances time instantly.
    final class Clock {
        var t = 0
        var slept: [Int] = []
        func sleep(_ ms: Int) async { slept.append(ms); t += ms }
    }

    struct Down: Error {}

    func testFirstAttemptSucceeds() async {
        let c = Clock(); var joins = 0
        let r = await runRejoinLoop(join: { joins += 1 }, sleep: c.sleep, waitReady: {}, cancelled: { false }, now: { c.t })
        XCTAssertEqual(r, .joined); XCTAssertEqual(joins, 1)
    }

    func testRetriesOnScheduleReportingAttempts() async {
        let c = Clock(); var joins = 0; var attempts: [[Int]] = []
        let r = await runRejoinLoop(join: { joins += 1; if joins < 3 { throw Down() } }, sleep: c.sleep, waitReady: {},
                                    cancelled: { false }, now: { c.t }, onAttempt: { a, d in attempts.append([a, d]) })
        XCTAssertEqual(r, .joined)
        XCTAssertEqual(c.slept, [500, 2000, 5000])
        // fired right before each try, with the wait before the NEXT try
        XCTAssertEqual(attempts, [[1, 2000], [2, 5000], [3, 10000]])
    }

    func testGivesUpOnlyAfterTenMinutes() async {
        let c = Clock(); var joins = 0
        let r = await runRejoinLoop(join: { joins += 1; throw Down() }, sleep: c.sleep, waitReady: {}, cancelled: { false }, now: { c.t })
        XCTAssertEqual(r, .gaveUp)
        XCTAssertGreaterThanOrEqual(c.t, rejoinGiveUpMs)
        XCTAssertLessThan(c.t, rejoinGiveUpMs + 30_000)
        XCTAssertGreaterThan(joins, rejoinDelaysMs.count)
    }

    func testReadinessThenAttemptThenJoin() async {
        let c = Clock(); var order: [String] = []
        _ = await runRejoinLoop(join: { order.append("join") }, sleep: c.sleep, waitReady: { order.append("ready") },
                                cancelled: { false }, now: { c.t }, onAttempt: { a, _ in order.append("attempt\(a)") })
        XCTAssertEqual(order, ["ready", "attempt1", "join"])
    }

    func testStopsOnceCancelled() async {
        let c = Clock(); var left = false; var joins = 0
        let r = await runRejoinLoop(join: { joins += 1; left = true; throw Down() }, sleep: c.sleep, waitReady: {},
                                    cancelled: { left }, now: { c.t })
        XCTAssertEqual(r, .cancelled); XCTAssertEqual(joins, 1)
    }

    func testWakerSleepTimesOut() async {
        let w = Waker()
        let start = Date()
        await w.sleep(ms: 30)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.025)
    }

    func testWakeCutsSleepShort() async {
        let w = Waker()
        let start = Date()
        Task { @MainActor in try? await Task.sleep(nanoseconds: 10_000_000); w.wake() }
        await w.sleep(ms: 30_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    // ── RejoinController ──

    final class FakeReadiness: RejoinReadiness {
        var ready = true
        private var waiters: [CheckedContinuation<Void, Never>] = []
        var isReady: Bool { ready }
        func waitReady() async {
            while !ready { await withCheckedContinuation { waiters.append($0) } }
        }
        func becomeReady() { ready = true; let w = waiters; waiters = []; w.forEach { $0.resume() } }
        func dispose() {}
    }

    var joins = 0, failNext = 0, rejoined = 0
    var readiness = FakeReadiness()

    func make(autoRejoin: Bool = true, delay: ((Int) -> Int)? = nil) -> RejoinController {
        joins = 0; failNext = 0; rejoined = 0; readiness = FakeReadiness()
        return RejoinController(
            join: { [unowned self] in joins += 1; if failNext > 0 { failNext -= 1; throw Down() } },
            onRejoined: { [unowned self] in rejoined += 1 },
            readiness: readiness,
            autoRejoin: autoRejoin,
            // compressed schedule: 1ms per scheduled second
            delayMs: delay ?? { max(1, rejoinDelayMs($0) / 1000) },
            giveUpMs: 200)
    }

    func settle(_ ms: UInt64 = 30) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }

    func testUnexpectedDropRejoinsFresh() async {
        let c = make(); var states: [VoxaRejoinState] = []
        c.onStateChange = { states.append($0) }
        c.onDisconnected(errorCode: network)
        await settle()
        XCTAssertEqual(states, [.reconnecting, .connected])
        XCTAssertEqual(joins, 1); XCTAssertEqual(rejoined, 1)
    }

    func testIntentionalEndDisconnects() async {
        for r in [nil, roomDeleted] as [Int?] {
            let c = make()
            c.onDisconnected(errorCode: r)
            await settle()
            XCTAssertEqual(c.state, .disconnected); XCTAssertEqual(joins, 0)
        }
    }

    func testAutoRejoinFalseDisconnects() async {
        let c = make(autoRejoin: false)
        c.onDisconnected(errorCode: network)
        await settle()
        XCTAssertEqual(c.state, .disconnected); XCTAssertEqual(joins, 0)
    }

    func testLiveKitShortResumeMapsToStates() {
        let c = make()
        c.onReconnecting(); XCTAssertEqual(c.state, .reconnecting)
        c.onReconnected(); XCTAssertEqual(c.state, .connected)
    }

    func testRejoinNowIgnoredDuringLiveKitResume() async {
        let c = make()
        c.onReconnecting()
        c.rejoinNow()
        await settle()
        XCTAssertEqual(joins, 0)
    }

    func testWaitsWhileBackgroundedThenAttempts() async {
        let c = make()
        readiness.ready = false
        c.onDisconnected(errorCode: network)
        await settle()
        XCTAssertEqual(joins, 0)
        readiness.becomeReady()
        await settle()
        XCTAssertEqual(joins, 1); XCTAssertEqual(c.state, .connected)
    }

    func testRejoinNowCutsTheWait() async {
        let c = make(delay: { _ in 30_000 })
        c.onDisconnected(errorCode: network)
        await settle()
        XCTAssertEqual(joins, 0)
        c.rejoinNow()
        await settle()
        XCTAssertEqual(joins, 1); XCTAssertEqual(c.state, .connected)
    }

    func testGivesUpThenRejoinNowRestarts() async {
        let c = make()
        failNext = Int.max
        c.onDisconnected(errorCode: network)
        await settle(400)
        XCTAssertEqual(c.state, .disconnected)
        let n = joins
        await settle(60)
        XCTAssertEqual(joins, n)
        failNext = 0
        c.rejoinNow()
        await settle()
        XCTAssertEqual(c.state, .connected)
    }

    func testCancelStopsTheLoop() async {
        let c = make()
        failNext = Int.max
        c.onDisconnected(errorCode: network)
        await settle(10)
        c.cancel()
        let n = joins
        await settle(60)
        XCTAssertEqual(joins, n)
        XCTAssertEqual(c.state, .disconnected)
        c.rejoinNow()
        await settle()
        XCTAssertEqual(joins, n, "rejoinNow after leave does nothing")
    }

    func testAttemptNumberForBanner() async {
        let c = make(delay: { _ in 30_000 })
        c.onDisconnected(errorCode: network)
        await settle()
        XCTAssertEqual(c.attempt, 0)
        c.rejoinNow()
        await settle()
        XCTAssertEqual(c.attempt, 0, "reset after success")
    }
}
