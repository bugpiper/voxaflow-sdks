package com.voxaflow.sdk.sessions

import android.app.Activity
import android.app.Application
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Bundle
import com.voxaflow.sdk.VoxaConnectionState
import io.livekit.android.events.DisconnectReason
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/*
 * Meet-style auto-rejoin (shared semantics on all 5 platforms — see CONTRACT.md "Auto-rejoin").
 * On an unexpected drop the session does a FRESH join (new token, same Room, current mic/cam) with
 * backoff, waiting until the app is foreground + online, waking early when the network returns, the
 * app comes to the foreground, or rejoinNow() is called. Gives up after 10 min → DISCONNECTED.
 */

private val TERMINAL_REASONS = setOf(
    DisconnectReason.CLIENT_INITIATED,   // the user left / end()
    DisconnectReason.DUPLICATE_IDENTITY, // joined again from another device
    DisconnectReason.PARTICIPANT_REMOVED,// removed by the agent/host
    DisconnectReason.ROOM_DELETED,       // call ended
    DisconnectReason.ROOM_CLOSED,
)

fun shouldAutoRejoin(reason: DisconnectReason?): Boolean = reason == null || reason !in TERMINAL_REASONS

/** Wait before attempt i (0-based); the last value repeats forever. */
val REJOIN_DELAYS_MS: List<Long> = listOf(500L, 2_000L, 5_000L, 10_000L, 20_000L, 30_000L)
/** Stop auto-retrying after this long of continuous failure. */
const val REJOIN_GIVE_UP_MS: Long = 10 * 60_000L

fun rejoinDelay(attemptIndex: Int): Long = REJOIN_DELAYS_MS[minOf(attemptIndex, REJOIN_DELAYS_MS.size - 1)]

enum class RejoinOutcome { JOINED, GAVE_UP, CANCELLED }

/** The pure loop. [sleep] may return early (see [Waker]). */
suspend fun runRejoinLoop(
    join: suspend () -> Unit,
    sleep: suspend (Long) -> Unit,
    waitReady: suspend () -> Unit,
    cancelled: () -> Boolean,
    now: () -> Long = System::currentTimeMillis,
    onAttempt: (attempt: Int, delayMs: Long) -> Unit = { _, _ -> },
): RejoinOutcome {
    val start = now()
    var i = 0
    while (true) {
        if (cancelled()) return RejoinOutcome.CANCELLED
        sleep(rejoinDelay(i))
        if (cancelled()) return RejoinOutcome.CANCELLED
        waitReady()
        if (cancelled()) return RejoinOutcome.CANCELLED
        // Reported right before the try; delay = the wait before the next try if this one fails.
        onAttempt(i + 1, rejoinDelay(i + 1))
        try {
            join()
            return if (cancelled()) RejoinOutcome.CANCELLED else RejoinOutcome.JOINED
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: Exception) {
            if (cancelled()) return RejoinOutcome.CANCELLED
            if (now() - start >= REJOIN_GIVE_UP_MS) return RejoinOutcome.GAVE_UP
        }
        i++
    }
}

/** A sleep that [wake] cuts short — wired to network-back, foreground and rejoinNow(). */
class Waker {
    private val gen = MutableStateFlow(0L)
    suspend fun sleep(ms: Long) {
        val g = gen.value
        withTimeoutOrNull(ms) { gen.first { it != g } }
    }
    suspend fun next() {
        val g = gen.value
        gen.first { it != g }
    }
    fun wake() = gen.update { it + 1 }
}

/** "Can we attempt now?" — foreground + online. */
interface RejoinReadiness {
    val isReady: Boolean
    suspend fun waitReady()
    fun dispose()
}

/**
 * Built-ins only (no androidx.lifecycle dependency): online from ConnectivityManager's default
 * network callback; foreground from counting started Activities. A session is created from a
 * visible UI, so we start as foreground.
 */
class AndroidReadiness(context: Context, private val waker: Waker) : RejoinReadiness {
    private val app = context.applicationContext as Application
    private val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val online = MutableStateFlow(cm.activeNetwork != null)
    @Volatile private var started = 1

    private val netCb = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { online.value = true; if (isReady) waker.wake() }
        override fun onLost(network: Network) { online.value = cm.activeNetwork != null }
    }
    private val lifeCb = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityStarted(a: Activity) { started++; if (isReady) waker.wake() }
        override fun onActivityStopped(a: Activity) { started = maxOf(0, started - 1) }
        override fun onActivityCreated(a: Activity, b: Bundle?) {}
        override fun onActivityResumed(a: Activity) {}
        override fun onActivityPaused(a: Activity) {}
        override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
        override fun onActivityDestroyed(a: Activity) {}
    }

    init {
        try { cm.registerDefaultNetworkCallback(netCb) } catch (_: Exception) { online.value = true }
        app.registerActivityLifecycleCallbacks(lifeCb)
    }

    override val isReady: Boolean get() = online.value && started > 0
    override suspend fun waitReady() { while (!isReady) waker.next() }
    override fun dispose() {
        try { cm.unregisterNetworkCallback(netCb) } catch (_: Exception) {}
        app.unregisterActivityLifecycleCallbacks(lifeCb)
    }
}

/** An auto-rejoin try is starting ([attempt], 1-based); if it fails the next comes [nextDelayMs] later. */
data class VoxaRejoinAttempt(val attempt: Int, val nextDelayMs: Long)

/** LiveKit-free session state machine (unit-tested). Sessions feed it Room events. */
class RejoinController(
    private val scope: CoroutineScope,
    private val join: suspend () -> Unit,
    private val onRejoined: () -> Unit,
    private val readiness: RejoinReadiness,
    private val autoRejoin: Boolean = true,
    private val waker: Waker = Waker(),
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val _state = MutableStateFlow(VoxaConnectionState.CONNECTED)
    val state: StateFlow<VoxaConnectionState> = _state.asStateFlow()
    private val _attempts = MutableSharedFlow<VoxaRejoinAttempt>(extraBufferCapacity = 16)
    val attempts: SharedFlow<VoxaRejoinAttempt> = _attempts.asSharedFlow()

    @Volatile private var ended = false
    private var loop: Job? = null

    fun onReconnecting() { _state.value = VoxaConnectionState.RECONNECTING }
    fun onReconnected() { _state.value = VoxaConnectionState.CONNECTED }

    fun onDisconnected(reason: DisconnectReason?) {
        if (ended || loop?.isActive == true) return
        if (!autoRejoin || !shouldAutoRejoin(reason)) {
            _state.value = VoxaConnectionState.DISCONNECTED
            return
        }
        start()
    }

    /** Retry now: cut the wait short, or restart after give-up. No-op while connected. */
    fun rejoinNow() {
        if (ended) return
        if (loop?.isActive == true) waker.wake()
        else if (_state.value == VoxaConnectionState.DISCONNECTED) start()
    }

    /** The user left — stop for good. */
    fun cancel() {
        ended = true
        loop?.cancel()
        waker.wake()
        readiness.dispose()
        _state.value = VoxaConnectionState.DISCONNECTED
    }

    private fun start() {
        _state.value = VoxaConnectionState.RECONNECTING
        loop = scope.launch {
            val outcome = runRejoinLoop(
                join = join,
                sleep = { waker.sleep(it) },
                waitReady = { readiness.waitReady() },
                cancelled = { ended },
                now = now,
                onAttempt = { a, d -> _attempts.tryEmit(VoxaRejoinAttempt(a, d)) },
            )
            when (outcome) {
                RejoinOutcome.JOINED -> { onRejoined(); _state.value = VoxaConnectionState.CONNECTED }
                RejoinOutcome.GAVE_UP -> _state.value = VoxaConnectionState.DISCONNECTED
                RejoinOutcome.CANCELLED -> {}
            }
        }
    }
}
