package com.voxaflow.sdk.sessions

import android.content.Context
import com.voxaflow.sdk.VoxaErrorCode
import com.voxaflow.sdk.VoxaException
import com.voxaflow.sdk.transport.RestClient
import com.voxaflow.sdk.transport.VoxaRealtime
import io.livekit.android.LiveKit
import io.livekit.android.room.Room
import org.json.JSONObject

/** A multi-party meeting (MP1–MP8). Backed by `POST /meetings/:id/token` → a LiveKit [Room].
 *  Per-speaker transcript / participant / output events arrive on the VoxaClient meeting* Flows. */
class MeetingSession internal constructor(
    val room: Room,
    val id: String,
    private val realtime: VoxaRealtime,
) {
    val lkRoom: Room get() = room

    suspend fun setMicEnabled(on: Boolean) { room.localParticipant.setMicrophoneEnabled(on) }
    suspend fun setCameraEnabled(on: Boolean) { room.localParticipant.setCameraEnabled(on) }

    fun end() {
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
        ): MeetingSession {
            val body = JSONObject()
            if (displayName != null) body.put("name", displayName)
            if (role != null) body.put("role", role)
            if (language != null) body.put("language", language)
            val res = rest.post("/meetings/$meetingId/token", body)
            val wsUrl = res.optString("wsUrl").takeIf { it.isNotEmpty() }
            val token = res.optString("token").takeIf { it.isNotEmpty() }
            if (wsUrl == null || token == null) {
                throw VoxaException(VoxaErrorCode.CONNECTION, "Backend did not return a meeting LiveKit token/wsUrl")
            }

            val room = LiveKit.create(context.applicationContext)
            try {
                room.connect(wsUrl, token)
                room.localParticipant.setMicrophoneEnabled(true)
                if (video) room.localParticipant.setCameraEnabled(true)
            } catch (e: Exception) {
                room.disconnect()
                throw VoxaException(VoxaErrorCode.MEDIA, "Failed to join the meeting room", cause = e)
            }
            realtime.joinMeeting(meetingId)
            return MeetingSession(room, meetingId, realtime)
        }
    }
}
