package com.voxaflow.sdk.transport

import com.voxaflow.sdk.*
import io.socket.client.IO
import io.socket.client.Socket
import io.socket.emitter.Emitter
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONObject
import java.net.URI
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Wraps the Voxa realtime channel (Socket.IO at `/socket.io`). Authenticates with the token
 *  in the handshake payload and republishes the server event catalog as Kotlin Flows. */
internal class VoxaRealtime(endpoint: String, @Volatile private var token: String) {
    val connectionState = MutableStateFlow(VoxaConnectionState.CONNECTING)
    val transcript = MutableSharedFlow<TranscriptSegment>(extraBufferCapacity = 64)
    val entities = MutableSharedFlow<ExtractedEntity>(extraBufferCapacity = 64)
    val formUpdates = MutableSharedFlow<FormUpdate>(extraBufferCapacity = 64)
    val messages = MutableSharedFlow<ChatMessage>(extraBufferCapacity = 64)
    val typing = MutableSharedFlow<TypingEvent>(extraBufferCapacity = 64)
    val presence = MutableSharedFlow<PresenceUpdate>(extraBufferCapacity = 64)
    val callStatus = MutableSharedFlow<CallStatusEvent>(extraBufferCapacity = 64)
    val meetingTranscript = MutableSharedFlow<MeetingTranscriptSegment>(extraBufferCapacity = 64)
    val meetingParticipant = MutableSharedFlow<MeetingParticipantEvent>(extraBufferCapacity = 64)
    val meetingOutput = MutableSharedFlow<MeetingOutputEvent>(extraBufferCapacity = 64)

    private val origin: String
    private var socket: Socket? = null

    init {
        val u = URI(endpoint)
        origin = "${u.scheme}://${u.host}" + if (u.port != -1) ":${u.port}" else ""
    }

    private fun buildSocket(): Socket {
        val opts = IO.Options().apply {
            path = "/socket.io/"
            transports = arrayOf("websocket")
            auth = mapOf("token" to token)
            reconnection = true
        }
        val sock = IO.socket(origin, opts)

        fun dict(args: Array<out Any>): JSONObject? = args.firstOrNull() as? JSONObject

        sock.on(Socket.EVENT_CONNECT) { connectionState.value = VoxaConnectionState.CONNECTED }
        sock.on(Socket.EVENT_DISCONNECT) { connectionState.value = VoxaConnectionState.DISCONNECTED }
        sock.io().on("reconnect_attempt") { connectionState.value = VoxaConnectionState.RECONNECTING }

        sock.on("transcript:update") { a -> dict(a)?.let { transcript.tryEmit(TranscriptSegment.fromJson(it)) } }
        sock.on("entity:extracted") { a -> dict(a)?.let { entities.tryEmit(ExtractedEntity.fromJson(it)) } }
        sock.on("form:autofill") { a -> dict(a)?.let { formUpdates.tryEmit(FormUpdate.fromJson(it)) } }
        sock.on("chat:message") { a -> dict(a)?.let { messages.tryEmit(ChatMessage.fromJson(it)) } }
        sock.on("chat:draft") { a -> dict(a)?.let { messages.tryEmit(ChatMessage.fromJson(it, true)) } }
        sock.on("chat:typing") { a -> dict(a)?.let { typing.tryEmit(TypingEvent.fromJson(it)) } }
        sock.on("presence:update") { a -> dict(a)?.let { presence.tryEmit(PresenceUpdate.fromJson(it)) } }
        sock.on("call:status") { a -> dict(a)?.let { callStatus.tryEmit(CallStatusEvent.fromJson(it)) } }
        sock.on("meeting:transcript") { a -> dict(a)?.let { meetingTranscript.tryEmit(MeetingTranscriptSegment.fromJson(it)) } }
        sock.on("meeting:participant") { a -> dict(a)?.let { meetingParticipant.tryEmit(MeetingParticipantEvent.fromJson(it)) } }
        sock.on("meeting:output") { a -> dict(a)?.let { meetingOutput.tryEmit(MeetingOutputEvent.fromJson(it)) } }
        return sock
    }

    suspend fun connect() {
        connectionState.value = VoxaConnectionState.CONNECTING
        val sock = buildSocket()
        socket = sock
        suspendCancellableCoroutine { cont ->
            val done = AtomicBoolean(false)
            sock.once(Socket.EVENT_CONNECT, Emitter.Listener { if (done.compareAndSet(false, true)) cont.resume(Unit) })
            sock.once(Socket.EVENT_CONNECT_ERROR, Emitter.Listener {
                if (done.compareAndSet(false, true)) {
                    cont.resumeWithException(VoxaException(VoxaErrorCode.CONNECTION, "Realtime connect failed"))
                }
            })
            sock.connect()
        }
    }

    /** Re-authenticate after a token refresh: rebuild the socket with the new token. */
    fun updateToken(t: String) {
        token = t
        socket?.disconnect()
        socket = buildSocket().also { it.connect() }
    }

    fun joinCall(id: String) { socket?.emit("call:join", id) }
    fun leaveCall(id: String) { socket?.emit("call:leave", id) }
    fun joinMeeting(id: String) { socket?.emit("meeting:join", id) }
    fun leaveMeeting(id: String) { socket?.emit("meeting:leave", id) }
    fun joinChat(id: String) { socket?.emit("chat:join", id) }
    fun leaveChat(id: String) { socket?.emit("chat:leave", id) }

    fun dispose() {
        socket?.disconnect()
        socket?.off()
        socket = null
    }
}
