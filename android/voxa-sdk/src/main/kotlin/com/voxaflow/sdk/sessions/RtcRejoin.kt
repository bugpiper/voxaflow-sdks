package com.voxaflow.sdk.sessions

import android.content.Context
import com.voxaflow.sdk.VoxaConnectionState
import io.livekit.android.events.RoomEvent
import io.livekit.android.room.Room
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Fresh LiveKit credentials for a session's room. */
internal data class LiveKitCreds(val wsUrl: String, val token: String)

/**
 * Wires a LiveKit [Room] to [RejoinController] for Call/MeetingSession: maps Room events, tracks
 * the user's mic/cam choice, and performs the fresh join (new token → connect the SAME Room so
 * app collectors survive → restore mic/cam).
 */
internal class RtcRejoin(
    context: Context,
    private val room: Room,
    video: Boolean,
    autoRejoin: Boolean,
    private val fetchCreds: suspend () -> LiveKitCreds,
    onRejoined: () -> Unit,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    var wantMic = true
    var wantCam = video
    private val waker = Waker()
    private val controller = RejoinController(
        scope = scope,
        join = ::freshJoin,
        onRejoined = onRejoined,
        readiness = AndroidReadiness(context, waker),
        autoRejoin = autoRejoin,
        waker = waker,
    )

    val state: StateFlow<VoxaConnectionState> get() = controller.state
    val attempts: SharedFlow<VoxaRejoinAttempt> get() = controller.attempts

    init {
        scope.launch {
            room.events.events.collect { e ->
                when (e) {
                    is RoomEvent.Reconnecting -> controller.onReconnecting()
                    is RoomEvent.Reconnected -> controller.onReconnected()
                    is RoomEvent.Disconnected -> controller.onDisconnected(e.reason)
                    else -> {}
                }
            }
        }
    }

    fun rejoinNow() = controller.rejoinNow()

    fun stop() {
        controller.cancel()
        scope.cancel()
    }

    private suspend fun freshJoin() {
        try {
            val c = fetchCreds()
            room.connect(c.wsUrl, c.token)
        } catch (e: Exception) {
            try { room.disconnect() } catch (_: Exception) {}
            throw e
        }
        try { if (wantMic) room.localParticipant.setMicrophoneEnabled(true) } catch (_: Exception) {}
        try { if (wantCam) room.localParticipant.setCameraEnabled(true) } catch (_: Exception) {}
    }
}
