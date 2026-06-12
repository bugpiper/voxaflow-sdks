package com.voxaflow.sdk

import android.content.Context
import com.voxaflow.sdk.sessions.CallSession
import com.voxaflow.sdk.sessions.ChatSession
import com.voxaflow.sdk.sessions.MeetingSession
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
    val meetingTranscript: Flow<MeetingTranscriptSegment> get() = realtime.meetingTranscript
    val meetingParticipant: Flow<MeetingParticipantEvent> get() = realtime.meetingParticipant
    val meetingOutput: Flow<MeetingOutputEvent> get() = realtime.meetingOutput

    /** Directed incoming rings ("user X is calling you"). Show your incoming-call UI, then
     *  [acceptCall] or [rejectCall]. */
    val incomingCalls: Flow<VoxaCallRing> get() = realtime.incomingCalls

    /** Resolution of a ring you're a party to (accepted/rejected/canceled/timeout). As the
     *  caller, [startCall] with the callId on [VoxaCallSignalKind.ACCEPTED]; tear down the ring
     *  UI on the others. */
    val callSignals: Flow<VoxaCallSignal> get() = realtime.callSignals

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

    /** Create a multi-party meeting (AGENT+); returns its id + room name. */
    suspend fun createMeeting(type: String? = null, title: String? = null): JSONObject {
        profile.requireCapability(Capability.callControl)
        ensureConnected()
        val body = JSONObject()
        if (type != null) body.put("type", type)
        if (title != null) body.put("title", title)
        return rest.post("/meetings", body)
    }

    /** Join a multi-party meeting by [meetingId]. */
    suspend fun joinMeeting(
        meetingId: String,
        video: Boolean = false,
        displayName: String? = null,
        role: String? = null,
        language: String? = null,
    ): MeetingSession {
        profile.requireCapability(if (video) Capability.joinVideo else Capability.joinCall)
        ensureConnected()
        return MeetingSession.join(appContext, rest, realtime, meetingId, video, displayName, role, language)
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

    // ── Client engagement (SDK9) ───────────────────────────────────────────────

    suspend fun requestCall(handle: String, name: String? = null, audioOnly: Boolean? = null): String {
        profile.requireCapability(Capability.joinCall)
        val body = JSONObject()
        if (name != null) body.put("name", name)
        if (audioOnly != null) body.put("audioOnly", audioOnly)
        return rest.post("/calls/dial/$handle", body).optString("callId")
    }

    // ── Directed ringing ("dial user X → ring → accept/reject/connect") ─────────

    /** Result of [inviteUser]: the new callId and when the ring expires (ISO-8601, or null). */
    data class CallInvite(val callId: String, val expiresAt: String?)

    /**
     * Ring a specific user ([toUserId]) in your tenant. Returns the new callId (and when the
     * ring expires). The callee receives a [VoxaCallRing] on [incomingCalls]; you receive a
     * [VoxaCallSignal] on [callSignals] when they accept (→ then [startCall] with this callId),
     * reject, or it times out.
     */
    suspend fun inviteUser(toUserId: String, video: Boolean = false, name: String? = null): CallInvite {
        profile.requireCapability(Capability.joinCall)
        ensureConnected()
        val body = JSONObject().put("toUserId", toUserId).put("video", video)
        if (name != null) body.put("name", name)
        val res = rest.post("/calls/invite", body)
        return CallInvite(res.optString("callId"), res.optString("expiresAt").takeIf { it.isNotEmpty() })
    }

    /**
     * Accept an incoming ring, then join its room. Returns the live [CallSession].
     * Equivalent to [answerCall] + [startCall] for the ringing callId.
     */
    suspend fun acceptCall(callId: String, video: Boolean = false, name: String? = null): CallSession {
        ensureConnected()
        rest.post("/calls/$callId/answer")
        return CallSession.start(appContext, rest, realtime, callId, video, name)
    }

    /** Decline an incoming ring as the callee. */
    suspend fun rejectCall(callId: String, reason: String? = null) {
        val body = JSONObject()
        if (reason != null) body.put("reason", reason)
        rest.post("/calls/$callId/reject", body)
    }

    /** Cancel a ring you placed, before it's answered. */
    suspend fun cancelCall(callId: String) {
        rest.post("/calls/$callId/cancel")
    }

    /**
     * Register this device's push token so rings reach the app when it's backgrounded/killed.
     * [platform] is 'ios' | 'android' | 'web'; [voip] is for an iOS PushKit token. Delivery is
     * gated on the backend having FCM/APNs creds configured.
     */
    suspend fun registerDevice(platform: String, token: String, voip: Boolean = false) {
        val body = JSONObject().put("platform", platform).put("token", token)
        if (voip) body.put("voip", true)
        rest.post("/push/devices", body)
    }

    /** Unregister a device push token (logout / token rotation). */
    suspend fun unregisterDevice(token: String) {
        rest.delete("/push/devices", JSONObject().put("token", token))
    }

    // ── Agent operations + copilot (SDK8) ──────────────────────────────────────

    suspend fun getActiveCalls(): List<JSONObject> {
        profile.requireCapability(Capability.callControl)
        val arr = rest.get("/calls").optJSONArray("calls") ?: return emptyList()
        return (0 until arr.length()).map { arr.getJSONObject(it) }
    }
    suspend fun answerCall(callId: String) { profile.requireCapability(Capability.callControl); rest.post("/calls/$callId/answer") }
    suspend fun holdCall(callId: String) { profile.requireCapability(Capability.callControl); rest.post("/calls/$callId/hold") }
    suspend fun transferCall(callId: String, toAgentId: String) { profile.requireCapability(Capability.transfer); rest.post("/calls/$callId/transfer", JSONObject().put("toAgentId", toAgentId)) }

    suspend fun getEntities(callId: String): List<ExtractedEntity> {
        profile.requireCapability(Capability.entities)
        val arr = rest.get("/calls/$callId/entities").optJSONArray("entities") ?: return emptyList()
        return (0 until arr.length()).map { ExtractedEntity.fromJson(arr.getJSONObject(it)) }
    }
    suspend fun confirmEntity(entityId: String) { profile.requireCapability(Capability.entities); rest.put("/entities/$entityId/confirm") }
    suspend fun rejectEntity(entityId: String) { profile.requireCapability(Capability.entities); rest.put("/entities/$entityId/reject") }

    suspend fun getSuggestions(callId: String): List<Suggestion> {
        profile.requireCapability(Capability.suggestions)
        val arr = rest.get("/calls/$callId/suggestions").optJSONArray("suggestions") ?: return emptyList()
        return (0 until arr.length()).map { Suggestion.fromJson(arr.getJSONObject(it)) }
    }
    suspend fun dismissSuggestion(callId: String, suggestionId: String) { profile.requireCapability(Capability.suggestions); rest.post("/calls/$callId/suggestions/$suggestionId/dismiss") }

    suspend fun getForm(callId: String): JSONObject { profile.requireCapability(Capability.forms); return rest.get("/calls/$callId/form") }
    suspend fun editField(callId: String, fieldId: String, value: Any?) { profile.requireCapability(Capability.forms); rest.put("/calls/$callId/form", JSONObject().put("fieldId", fieldId).put("value", value)) }
    suspend fun confirmField(callId: String, fieldId: String) { profile.requireCapability(Capability.forms); rest.post("/calls/$callId/form/confirm-field", JSONObject().put("fieldId", fieldId)) }
    suspend fun rejectField(callId: String, fieldId: String) { profile.requireCapability(Capability.forms); rest.post("/calls/$callId/form/reject-field", JSONObject().put("fieldId", fieldId)) }
    suspend fun submitForm(callId: String) { profile.requireCapability(Capability.forms); rest.post("/calls/$callId/form/submit") }

    /** Post-call summary (SOAP/BANT/etc., template-driven). */
    suspend fun getSummary(callId: String): JSONObject { profile.requireCapability(Capability.copilot); return rest.get("/calls/$callId/summary") }

    private fun ensureConnected() {
        if (!connected) throw VoxaException(VoxaErrorCode.CONNECTION, "Call connect() before opening a session.")
    }

    private fun ephemeralId(prefix: String): String =
        "sdk-$prefix-" + UUID.randomUUID().toString().replace("-", "").take(6)
}
