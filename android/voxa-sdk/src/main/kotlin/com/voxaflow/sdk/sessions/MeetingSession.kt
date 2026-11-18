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

/** A multi-party meeting (MP1–MP8). Backed by `POST /meetings/:id/token` → a LiveKit [Room].
 *  Per-speaker transcript / participant / output events arrive on the VoxaClient meeting* Flows. */
class MeetingSession internal constructor(
    context: Context,
    val room: Room,
    val id: String,
    private val realtime: VoxaRealtime,
    rest: RestClient,
    body: JSONObject,
    video: Boolean,
    autoRejoin: Boolean,
) {
    val lkRoom: Room get() = room
    private val rejoin = RtcRejoin(context, room, video, autoRejoin,
        fetchCreds = { token(rest, id, body) }, onRejoined = { realtime.joinMeeting(id) })

    /** Media connection state of THIS session (distinct from VoxaClient.connectionState, the
     *  realtime socket): CONNECTED → (RECONNECTING → CONNECTED)* → DISCONNECTED. */
    val connectionState: StateFlow<VoxaConnectionState> get() = rejoin.state
    /** Each scheduled auto-rejoin attempt. */
    val rejoinAttempts: SharedFlow<VoxaRejoinAttempt> get() = rejoin.attempts
    /** Retry now: cuts the back-off wait short, or restarts after auto-rejoin gave up. */
    fun rejoinNow() = rejoin.rejoinNow()

    suspend fun setMicEnabled(on: Boolean) { rejoin.wantMic = on; room.localParticipant.setMicrophoneEnabled(on) }
    suspend fun setCameraEnabled(on: Boolean) { rejoin.wantCam = on; room.localParticipant.setCameraEnabled(on) }

    fun end() {
        rejoin.stop()
        realtime.leaveMeeting(id)
        room.disconnect()
    }

    companion object {
        internal suspend fun join(
            context: Context,
            rest: RestClient,
            realtime: VoxaRealtime,
            meetingId: String,
            video: Boolean,
            displayName: String?,
            role: String?,
            language: String?,
            autoRejoin: Boolean = true,
        ): MeetingSession {
            val body = JSONObject()
            if (displayName != null) body.put("name", displayName)
            if (role != null) body.put("role", role)
            if (language != null) body.put("language", language)
            val creds = token(rest, meetingId, body)

            val room = LiveKit.create(context.applicationContext)
            try {
                room.connect(creds.wsUrl, creds.token)
                room.localParticipant.setMicrophoneEnabled(true)
                if (video) room.localParticipant.setCameraEnabled(true)
            } catch (e: Exception) {
                room.disconnect()
                throw VoxaException(VoxaErrorCode.MEDIA, "Failed to join the meeting room", cause = e)
            }
            realtime.joinMeeting(meetingId)
            return MeetingSession(context, room, meetingId, realtime, rest, body, video, autoRejoin)
        }

        private suspend fun token(rest: RestClient, meetingId: String, body: JSONObject): LiveKitCreds {
            val res = rest.post("/meetings/$meetingId/token", body)
            val wsUrl = res.optString("wsUrl").takeIf { it.isNotEmpty() }
            val token = res.optString("token").takeIf { it.isNotEmpty() }
            if (wsUrl == null || token == null) {
                throw VoxaException(VoxaErrorCode.CONNECTION, "Backend did not return a meeting LiveKit token/wsUrl")
            }
            return LiveKitCreds(wsUrl, token)
        }
    }
}
