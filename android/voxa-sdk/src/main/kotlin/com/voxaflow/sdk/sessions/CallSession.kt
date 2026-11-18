package com.voxaflow.sdk.sessions

import android.content.Context
import com.voxaflow.sdk.VoxaConnectionState
import com.voxaflow.sdk.VoxaErrorCode
import com.voxaflow.sdk.VoxaException
import com.voxaflow.sdk.transport.RestClient
import com.voxaflow.sdk.transport.VoxaRealtime
import io.livekit.android.LiveKit
import io.livekit.android.room.Room
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONObject

/** A 1:1 / queue call. Backed by `POST /rtc/token` → a LiveKit [Room]. Use [lkRoom] for
 *  advanced LiveKit access (e.g. rendering video tracks).
 *
 *  Auto-rejoin (default on): after an unexpected drop the session re-joins the same room with a
 *  fresh token and the user's current mic/cam, Google-Meet style (see [connectionState]). */
class CallSession internal constructor(
    context: Context,
    val room: Room,
    val id: String,
    private val realtime: VoxaRealtime,
    rest: RestClient,
    name: String?,
    video: Boolean,
    autoRejoin: Boolean,
) {
    val lkRoom: Room get() = room
    private val rejoin = RtcRejoin(context, room, video, autoRejoin,
        fetchCreds = { token(rest, id, name) }, onRejoined = { realtime.joinCall(id) })

    /** Media connection state of THIS session (distinct from VoxaClient.connectionState, the
     *  realtime socket): CONNECTED → (RECONNECTING → CONNECTED)* → DISCONNECTED. */
    val connectionState: StateFlow<VoxaConnectionState> get() = rejoin.state
    /** Each scheduled auto-rejoin attempt. */
    val rejoinAttempts: SharedFlow<VoxaRejoinAttempt> get() = rejoin.attempts
    /** Retry now: cuts the back-off wait short, or restarts after auto-rejoin gave up. */
    fun rejoinNow() = rejoin.rejoinNow()

    suspend fun setMicEnabled(on: Boolean) { rejoin.wantMic = on; room.localParticipant.setMicrophoneEnabled(on) }
    suspend fun setMuted(muted: Boolean) = setMicEnabled(!muted)
    suspend fun setCameraEnabled(on: Boolean) { rejoin.wantCam = on; room.localParticipant.setCameraEnabled(on) }
    suspend fun hold() = setMicEnabled(false)
    suspend fun resume() = setMicEnabled(true)
    // NOTE: screen share on Android needs a MediaProjection permission result — a follow-up.

    fun end() {
        rejoin.stop()
        realtime.leaveCall(id)
        room.disconnect()
    }

    companion object {
        internal suspend fun start(
            context: Context,
            rest: RestClient,
            realtime: VoxaRealtime,
            callId: String,
            video: Boolean,
            name: String?,
            autoRejoin: Boolean = true,
        ): CallSession {
            val creds = token(rest, callId, name)

            val room = LiveKit.create(context.applicationContext)
            try {
                room.connect(creds.wsUrl, creds.token)
                room.localParticipant.setMicrophoneEnabled(true)
                if (video) room.localParticipant.setCameraEnabled(true)
            } catch (e: Exception) {
                room.disconnect()
                throw VoxaException(VoxaErrorCode.MEDIA, "Failed to join the call room", cause = e)
            }
            realtime.joinCall(callId)
            return CallSession(context, room, callId, realtime, rest, name, video, autoRejoin)
        }

        private suspend fun token(rest: RestClient, callId: String, name: String?): LiveKitCreds {
            val body = JSONObject().put("callId", callId)
            if (name != null) body.put("name", name)
            val res = rest.post("/rtc/token", body)
            val wsUrl = res.optString("wsUrl").takeIf { it.isNotEmpty() }
            val token = res.optString("token").takeIf { it.isNotEmpty() }
            if (wsUrl == null || token == null) {
                throw VoxaException(VoxaErrorCode.CONNECTION, "Backend did not return a LiveKit token/wsUrl")
            }
            return LiveKitCreds(wsUrl, token)
        }
    }
}
