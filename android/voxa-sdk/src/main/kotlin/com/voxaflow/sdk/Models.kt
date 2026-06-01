package com.voxaflow.sdk

import org.json.JSONObject

enum class VoxaConnectionState { CONNECTING, CONNECTED, RECONNECTING, DISCONNECTED }

private fun JSONObject.strOr(key: String, default: String = ""): String = optString(key, default)
private fun JSONObject.dblOrNull(key: String): Double? = if (has(key) && !isNull(key)) optDouble(key) else null
private fun JSONObject.intOrNull(key: String): Int? = if (has(key) && !isNull(key)) optInt(key) else null

data class TranscriptSegment(
    val id: String?,
    val speaker: String,
    val text: String,
    val isFinal: Boolean,
    val confidence: Double?,
    val language: String?,
    val startTime: Double?,
    val endTime: Double?,
) {
    companion object {
        fun fromJson(j: JSONObject) = TranscriptSegment(
            id = j.optString("id").takeIf { it.isNotEmpty() },
            speaker = j.strOr("speaker", "CALLER"),
            text = j.strOr("text"),
            isFinal = j.optBoolean("isFinal", false),
            confidence = j.dblOrNull("confidence"),
            language = j.optString("language").takeIf { it.isNotEmpty() },
            startTime = j.dblOrNull("startTime"),
            endTime = j.dblOrNull("endTime"),
        )
    }
}

data class ExtractedEntity(
    val id: String?,
    val entityType: String,
    val entityCategory: String,
    val value: String,
    val code: String?,
    val codeSystem: String?,
    val confidence: Double?,
    val negated: Boolean,
) {
    companion object {
        fun fromJson(j: JSONObject) = ExtractedEntity(
            id = j.optString("id").takeIf { it.isNotEmpty() },
            entityType = j.strOr("entityType"),
            entityCategory = j.strOr("entityCategory"),
            value = j.strOr("value"),
            code = j.optString("code").takeIf { it.isNotEmpty() },
            codeSystem = j.optString("codeSystem").takeIf { it.isNotEmpty() },
            confidence = j.dblOrNull("confidence"),
            negated = j.optBoolean("negated", false),
        )
    }
}

data class FormUpdate(val fieldId: String, val value: String?, val confidence: Double?) {
    companion object {
        fun fromJson(j: JSONObject) = FormUpdate(
            fieldId = j.strOr("fieldId"),
            value = if (j.has("value") && !j.isNull("value")) j.get("value").toString() else null,
            confidence = j.dblOrNull("confidence"),
        )
    }
}

data class ChatMessage(
    val id: String,
    val conversationId: String,
    val sender: String,
    val content: String,
    val createdAt: String,
    val isDraft: Boolean,
) {
    val isBot: Boolean get() = sender == "BOT"

    companion object {
        fun fromJson(j: JSONObject, isDraft: Boolean = false) = ChatMessage(
            id = j.strOr("id"),
            conversationId = j.strOr("conversationId"),
            sender = j.strOr("sender", "SYSTEM"),
            content = j.strOr("content"),
            createdAt = j.strOr("createdAt"),
            isDraft = isDraft,
        )
    }
}

data class TypingEvent(val conversationId: String, val sender: String) {
    companion object {
        fun fromJson(j: JSONObject) = TypingEvent(j.strOr("conversationId"), j.strOr("sender"))
    }
}

data class PresenceUpdate(val userId: String, val status: String) {
    companion object {
        fun fromJson(j: JSONObject) = PresenceUpdate(j.strOr("userId"), j.strOr("status"))
    }
}

data class CallStatusEvent(val callId: String, val status: String, val durationSeconds: Int?) {
    companion object {
        fun fromJson(j: JSONObject) = CallStatusEvent(j.strOr("callId"), j.strOr("status"), j.intOrNull("durationSeconds"))
    }
}

/** A live form-fill suggestion (agent copilot). From `GET /calls/:id/suggestions`. */
data class Suggestion(val id: String, val fieldId: String, val value: String?, val confidence: Double?) {
    companion object {
        fun fromJson(j: JSONObject) = Suggestion(
            id = j.strOr("id"),
            fieldId = j.strOr("fieldId"),
            value = if (j.has("value") && !j.isNull("value")) j.get("value").toString() else null,
            confidence = j.dblOrNull("confidence"),
        )
    }
}

/** Per-speaker meeting transcript segment. From `meeting:transcript`. */
data class MeetingTranscriptSegment(
    val meetingId: String,
    val speakerId: String,
    val identity: String,
    val text: String,
    val isFinal: Boolean,
    val language: String?,
    val startTime: Double?,
) {
    companion object {
        fun fromJson(j: JSONObject) = MeetingTranscriptSegment(
            meetingId = j.strOr("meetingId"),
            speakerId = j.strOr("speakerId"),
            identity = j.strOr("identity"),
            text = j.strOr("text"),
            isFinal = j.optBoolean("isFinal", false),
            language = j.optString("language").takeIf { it.isNotEmpty() },
            startTime = j.dblOrNull("startTime"),
        )
    }
}

/** Meeting participant join/left. From `meeting:participant`. */
data class MeetingParticipantEvent(val meetingId: String, val identity: String, val state: String) {
    companion object {
        fun fromJson(j: JSONObject) = MeetingParticipantEvent(j.strOr("meetingId"), j.strOr("identity"), j.strOr("state"))
    }
}

/** Meeting AI output generated. From `meeting:output`. */
data class MeetingOutputEvent(val meetingId: String, val type: String) {
    companion object {
        fun fromJson(j: JSONObject) = MeetingOutputEvent(j.strOr("meetingId"), j.strOr("type"))
    }
}
