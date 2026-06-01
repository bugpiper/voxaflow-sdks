package com.voxaflow.sdk

import android.content.Context
import com.voxaflow.sdk.sessions.CallSession
import com.voxaflow.sdk.sessions.ChatSession
import com.voxaflow.sdk.transport.RestClient
import com.voxaflow.sdk.transport.VoxaRealtime
import kotlinx.coroutines.flow.Flow
import org.json.JSONObject
import java.util.UUID

/** Configuration for a [VoxaClient]. */
data class VoxaConfig(
    val endpoint: String,
    val token: String,
    val onTokenRefresh: (suspend () -> String)? = null,
)

/**
 * Entry point of the Voxa Flow Android SDK. Same concepts as the Web/Flutter/RN/iOS SDKs —
 * idiomatic Kotlin (suspend functions + Flow).
 *
 * ```kotlin
 * val client = VoxaClient(appContext, VoxaConfig(endpoint = "…", token = "…") { freshToken() })
 * client.connect()
 * lifecycleScope.launch { client.transcript.collect { println("${it.speaker}: ${it.text}") } }
 * val call = client.startCall(video = true)
 * ```
 */
class VoxaClient(private val appContext: Context, config: VoxaConfig) {
    val profile: TokenProfile = TokenProfile.fromToken(config.token)
    private val rest = RestClient(config.endpoint, config.token, config.onTokenRefresh)
    private val realtime = VoxaRealtime(config.endpoint, config.token)

    @Volatile
    private var connected = false

    init {
        rest.onTokenChanged = { realtime.updateToken(it) }
    }

    // Event streams (the unified event set)
    val connectionState: Flow<VoxaConnectionState> get() = realtime.connectionState
    val transcript: Flow<TranscriptSegment> get() = realtime.transcript
    val entities: Flow<ExtractedEntity> get() = realtime.entities
    val formUpdates: Flow<FormUpdate> get() = realtime.formUpdates
    val messages: Flow<ChatMessage> get() = realtime.messages
    val typing: Flow<TypingEvent> get() = realtime.typing
    val presence: Flow<PresenceUpdate> get() = realtime.presence
    val callStatus: Flow<CallStatusEvent> get() = realtime.callStatus

    fun can(c: Capability): Boolean = profile.can(c)

    /** Open the realtime channel and validate the token. */
    suspend fun connect() {
        if (connected) return
        realtime.connect()
        connected = true
    }

    /** Tear down realtime. End sessions first. */
    fun disconnect() {
        connected = false
        realtime.dispose()
    }

    /** Start (or join) a voice/video call. Omit [callId] for an ephemeral room. */
    suspend fun startCall(callId: String? = null, video: Boolean = false, name: String? = null): CallSession {
        profile.requireCapability(if (video) Capability.joinVideo else Capability.joinCall)
        ensureConnected()
        return CallSession.start(appContext, rest, realtime, callId ?: ephemeralId("call"), video, name)
    }

    /** Open a chat conversation (attach to [conversationId], or start one on a [channel] handle). */
    suspend fun openChat(
        conversationId: String? = null,
        channel: String? = null,
        contactIdentifier: String? = null,
        language: String? = null,
    ): ChatSession {
        profile.requireCapability(Capability.chat)
        ensureConnected()
        return ChatSession.open(rest, realtime, conversationId, channel, contactIdentifier, language)
    }

    /** Set the agent's presence (AGENT+). */
    suspend fun setPresence(status: String) {
        profile.requireCapability(Capability.presence)
        rest.put("/agents/presence", JSONObject().put("status", status))
    }

    private fun ensureConnected() {
        if (!connected) throw VoxaException(VoxaErrorCode.CONNECTION, "Call connect() before opening a session.")
    }

    private fun ephemeralId(prefix: String): String =
        "sdk-$prefix-" + UUID.randomUUID().toString().replace("-", "").take(6)
}
