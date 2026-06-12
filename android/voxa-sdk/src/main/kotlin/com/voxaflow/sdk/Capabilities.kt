package com.voxaflow.sdk

import android.util.Base64
import org.json.JSONObject

/** Granular capabilities the SDK gates on (derived from the JWT role today; the server is
 *  the real enforcement point). */
enum class Capability {
    joinCall, joinVideo, chat, consent,
    callControl, video, copilot, transcript, entities, suggestions, forms,
    presence, queue, transfer, escalate, botHandoff,
    monitor, whisper, barge, analytics,
}

/** Role + capability set derived from a token. */
class TokenProfile internal constructor(
    val role: String,
    val capabilities: Set<Capability>,
    val tenantId: String?,
    val userId: String?,
) {
    fun can(c: Capability): Boolean = capabilities.contains(c)

    internal fun requireCapability(c: Capability) {
        if (!can(c)) {
            throw VoxaException(VoxaErrorCode.CAPABILITY, "This token ($role) is not permitted to use \"${c.name}\".")
        }
    }

    companion object {
        private val CLIENT = setOf(Capability.joinCall, Capability.joinVideo, Capability.chat, Capability.consent)
        private val AGENT = CLIENT + setOf(
            Capability.callControl, Capability.video, Capability.copilot, Capability.transcript,
            Capability.entities, Capability.suggestions, Capability.forms, Capability.presence,
            Capability.queue, Capability.transfer, Capability.escalate, Capability.botHandoff,
        )
        private val SUPERVISOR = AGENT + setOf(Capability.monitor, Capability.whisper, Capability.barge, Capability.analytics)

        /** Decode a Voxa access token (JWT) for client-side gating. Does NOT verify the
         *  signature (the server does). A non-JWT / guest token yields the CLIENT profile. */
        fun fromToken(token: String): TokenProfile {
            val claims = decodeJwt(token)
            val role = claims?.optString("role")?.takeIf { it.isNotEmpty() }?.uppercase()
            val caps = when (role) {
                "SUPERVISOR", "ADMIN", "SUPER_ADMIN" -> SUPERVISOR
                "AGENT" -> AGENT
                // CLIENT / END_USER (guest/contact) + any unknown role → client capability set.
                "CLIENT", "END_USER" -> CLIENT
                else -> CLIENT
            }
            return TokenProfile(
                role = role ?: "CLIENT",
                capabilities = caps,
                tenantId = claims?.optString("tenantId")?.takeIf { it.isNotEmpty() },
                userId = claims?.optString("userId")?.takeIf { it.isNotEmpty() },
            )
        }

        private fun decodeJwt(token: String): JSONObject? = try {
            val parts = token.split(".")
            if (parts.size != 3) null
            else {
                val bytes = Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
                JSONObject(String(bytes, Charsets.UTF_8))
            }
        } catch (_: Exception) {
            null
        }
    }
}
