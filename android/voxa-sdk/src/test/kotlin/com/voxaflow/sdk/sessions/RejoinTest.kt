package com.voxaflow.sdk.sessions

import com.voxaflow.sdk.VoxaConnectionState
import io.livekit.android.events.DisconnectReason
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Meet-style auto-rejoin — mirrors web-core/Flutter tests (CONTRACT.md "Auto-rejoin"). */
@OptIn(ExperimentalCoroutinesApi::class)
class RejoinTest {

    @Test fun rejoinsAfterConnectionLoss() {
        for (r in listOf(null, DisconnectReason.UNKNOWN_REASON, DisconnectReason.SIGNAL_CLOSE, DisconnectReason.STATE_MISMATCH,
            DisconnectReason.JOIN_FAILURE, DisconnectReason.SERVER_SHUTDOWN, DisconnectReason.MIGRATION)) {
            assertTrue("$r", shouldAutoRejoin(r))
        }
    }

    @Test fun neverRejoinsIntentionalEnd() {
        for (r in listOf(DisconnectReason.CLIENT_INITIATED, DisconnectReason.DUPLICATE_IDENTITY, DisconnectReason.PARTICIPANT_REMOVED,
            DisconnectReason.ROOM_DELETED, DisconnectReason.ROOM_CLOSED)) {
            assertFalse("$r", shouldAutoRejoin(r))
        }
    }

    @Test fun delayScheduleRepeats30s() {
        assertEquals(listOf(500L, 2000L, 5000L, 10000L, 20000L, 30000L), REJOIN_DELAYS_MS)
        assertEquals(listOf(500L, 2000L, 5000L, 10000L, 20000L, 30000L, 30000L, 30000L), listOf(0, 1, 2, 3, 4, 5, 6, 50).map { rejoinDelay(it) })
        assertEquals(10 * 60_000L, REJOIN_GIVE_UP_MS)
    }

    @Test fun attemptIsReportedAfterReadinessRightBeforeJoin() = runTest {
        val order = mutableListOf<String>()
        loop({ order += "join" }, waitReady = { order += "ready" }, onAttempt = { a, _ -> order += "attempt$a" })()
        assertEquals(listOf("ready", "attempt1", "join"), order)
    }

    private fun TestScope.loop(join: suspend () -> Unit, cancelled: () -> Boolean = { false },
                               waitReady: suspend () -> Unit = {}, onAttempt: (Int, Long) -> Unit = { _, _ -> }) =
        suspend { runRejoinLoop(join, { kotlinx.coroutines.delay(it) }, waitReady, cancelled, { testScheduler.currentTime }, onAttempt) }

    @Test fun firstAttemptSucceeds() = runTest {
        var joins = 0
        assertEquals(RejoinOutcome.JOINED, loop({ joins++ })())
        assertEquals(1, joins)
    }

    @Test fun retriesOnScheduleReportingAttempts() = runTest {
        var joins = 0
        val attempts = mutableListOf<Pair<Int, Long>>()
        val r = loop({ if (++joins < 3) error("net") }, onAttempt = { a, d -> attempts += a to d })()
        assertEquals(RejoinOutcome.JOINED, r)
        // fired right before each try, with the wait before the NEXT try
        assertEquals(listOf(1 to 2000L, 2 to 5000L, 3 to 10000L), attempts)
        assertEquals(7500L, testScheduler.currentTime)
    }

    @Test fun givesUpOnlyAfterTenMinutes() = runTest {
        var joins = 0
        assertEquals(RejoinOutcome.GAVE_UP, loop({ joins++; error("down") })())
        assertTrue(testScheduler.currentTime >= REJOIN_GIVE_UP_MS)
        assertTrue(testScheduler.currentTime < REJOIN_GIVE_UP_MS + 30_000)
        assertTrue(joins > REJOIN_DELAYS_MS.size)
    }

    @Test fun waitsForReadinessBeforeEveryAttempt() = runTest {
        val order = mutableListOf<String>()
        loop({ order += "join" }, waitReady = { order += "ready" })()
        assertEquals(listOf("ready", "join"), order)
    }

    @Test fun stopsOnceCancelled() = runTest {
        var left = false
        var joins = 0
        assertEquals(RejoinOutcome.CANCELLED, loop({ joins++; left = true; error("x") }, cancelled = { left })())
        assertEquals(1, joins)
    }

    @Test fun wakerSleepTimesOutOrWakesEarly() = runTest {
        val w = Waker()
        var done = false
        launch { w.sleep(1000); done = true }
        advanceTimeBy(999); runCurrent()
        assertFalse(done)
        advanceTimeBy(1); runCurrent()
        assertTrue(done)
        done = false
        launch { w.sleep(30_000); done = true }
        runCurrent()
        w.wake(); runCurrent()
        assertTrue(done)
    }

    // ── RejoinController ──────────────────────────────────────────────────────────────

    private class FakeReadiness(ready: Boolean = true) : RejoinReadiness {
        val ready = MutableStateFlow(ready)
        override val isReady get() = ready.value
        override suspend fun waitReady() { ready.first { it } }
        override fun dispose() {}
    }

    private class Harness(scope: TestScope, autoRejoin: Boolean = true) {
        var joins = 0
        var failNext = 0
        var rejoined = 0
        val readiness = FakeReadiness()
        val c = RejoinController(
            scope = scope.backgroundScope,
            join = { joins++; if (failNext > 0) { failNext--; error("offline") } },
            onRejoined = { rejoined++ },
            readiness = readiness,
            autoRejoin = autoRejoin,
            now = { scope.testScheduler.currentTime },
        )
    }

    @Test fun unexpectedDropRejoinsFresh() = runTest {
        val h = Harness(this)
        val states = mutableListOf<VoxaConnectionState>()
        backgroundScope.launch { h.c.state.collect { states += it } }
        runCurrent()
        h.c.onDisconnected(DisconnectReason.SIGNAL_CLOSE)
        advanceTimeBy(500); runCurrent()
        assertEquals(listOf(VoxaConnectionState.CONNECTED, VoxaConnectionState.RECONNECTING, VoxaConnectionState.CONNECTED), states)
        assertEquals(1, h.joins)
        assertEquals(1, h.rejoined)
    }

    @Test fun intentionalEndDisconnects() = runTest {
        for (r in listOf(DisconnectReason.CLIENT_INITIATED, DisconnectReason.ROOM_DELETED)) {
            val h = Harness(this)
            h.c.onDisconnected(r)
            advanceTimeBy(60_000); runCurrent()
            assertEquals(VoxaConnectionState.DISCONNECTED, h.c.state.value)
            assertEquals(0, h.joins)
        }
    }

    @Test fun autoRejoinFalseDisconnects() = runTest {
        val h = Harness(this, autoRejoin = false)
        h.c.onDisconnected(DisconnectReason.SIGNAL_CLOSE)
        advanceTimeBy(60_000); runCurrent()
        assertEquals(VoxaConnectionState.DISCONNECTED, h.c.state.value)
        assertEquals(0, h.joins)
    }

    @Test fun livekitShortResumeMapsToStates() = runTest {
        val h = Harness(this)
        h.c.onReconnecting(); assertEquals(VoxaConnectionState.RECONNECTING, h.c.state.value)
        h.c.onReconnected(); assertEquals(VoxaConnectionState.CONNECTED, h.c.state.value)
    }

    @Test fun waitsWhileNotReadyThenAttempts() = runTest {
        val h = Harness(this)
        h.readiness.ready.value = false
        h.c.onDisconnected(DisconnectReason.UNKNOWN_REASON)
        advanceTimeBy(60_000); runCurrent()
        assertEquals(0, h.joins)
        h.readiness.ready.value = true
        runCurrent()
        assertEquals(1, h.joins)
        assertEquals(VoxaConnectionState.CONNECTED, h.c.state.value)
    }

    @Test fun rejoinNowCutsTheWait() = runTest {
        val h = Harness(this)
        h.failNext = 5
        h.c.onDisconnected(DisconnectReason.SIGNAL_CLOSE)
        advanceTimeBy(500L + 2000 + 5000 + 10000 + 20000); runCurrent()
        assertEquals(5, h.joins)
        h.c.rejoinNow(); runCurrent()
        assertEquals(6, h.joins)
        assertEquals(VoxaConnectionState.CONNECTED, h.c.state.value)
    }

    @Test fun givesUpThenRejoinNowRestarts() = runTest {
        val h = Harness(this)
        h.failNext = Int.MAX_VALUE
        h.c.onDisconnected(DisconnectReason.SIGNAL_CLOSE)
        advanceTimeBy(11 * 60_000L); runCurrent()
        assertEquals(VoxaConnectionState.DISCONNECTED, h.c.state.value)
        val n = h.joins
        advanceTimeBy(5 * 60_000L); runCurrent()
        assertEquals(n, h.joins)
        h.failNext = 0
        h.c.rejoinNow()
        advanceTimeBy(500); runCurrent()
        assertEquals(VoxaConnectionState.CONNECTED, h.c.state.value)
    }

    @Test fun cancelStopsTheLoop() = runTest {
        val h = Harness(this)
        h.failNext = Int.MAX_VALUE
        h.c.onDisconnected(DisconnectReason.SIGNAL_CLOSE)
        advanceTimeBy(2500); runCurrent()
        val n = h.joins
        h.c.cancel()
        advanceTimeBy(5 * 60_000L); runCurrent()
        assertEquals(n, h.joins)
        assertEquals(VoxaConnectionState.DISCONNECTED, h.c.state.value)
    }
}
