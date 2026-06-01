package com.voxaflow.sdk.sessions

import android.content.Context
import com.voxaflow.sdk.VoxaErrorCode
import com.voxaflow.sdk.VoxaException
import com.voxaflow.sdk.transport.RestClient
import com.voxaflow.sdk.transport.VoxaRealtime
import io.livekit.android.LiveKit
import io.livekit.android.room.Room
import org.json.JSONObject

/** A 1:1 / queue call. Backed by `POST /rtc/token` → a LiveKit [Room]. Use [lkRoom] for
 *  advanced LiveKit access (e.g. rendering video tracks). */
class CallSession internal constructor(
    val room: Room,
    val id: String,
    private val realtime: VoxaRealtime,
) {
    val lkRoom: Room get() = room

    suspend fun setMicEnabled(on: Boolean) { room.localParticipant.setMicrophoneEnabled(on) }
    suspend fun setMuted(muted: Boolean) = setMicEnabled(!muted)
    suspend fun setCameraEnabled(on: Boolean) { room.localParticipant.setCameraEnabled(on) }
    suspend fun hold() = setMicEnabled(false)
    suspend fun resume() = setMicEnabled(true)
    // NOTE: screen share on Android needs a MediaProjection permission result — a follow-up.

    fun end() {
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
        ): CallSession {
            val body = JSONObject().put("callId", callId)
            if (name != null) body.put("name", name)
            val res = rest.post("/rtc/token", body)
            val wsUrl = res.optString("wsUrl").takeIf { it.isNotEmpty() }
            val token = res.optString("token").takeIf { it.isNotEmpty() }
            if (wsUrl == null || token == null) {
                throw VoxaException(VoxaErrorCode.CONNECTION, "Backend did not return a LiveKit token/wsUrl")
            }

            val room = LiveKit.create(context.applicationContext)
            try {
                room.connect(wsUrl, token)
                room.localParticipant.setMicrophoneEnabled(true)
                if (video) room.localParticipant.setCameraEnabled(true)
            } catch (e: Exception) {
                room.disconnect()
                throw VoxaException(VoxaErrorCode.MEDIA, "Failed to join the call room", cause = e)
            }
            realtime.joinCall(callId)
            return CallSession(room, callId, realtime)
        }
    }
}
