package com.voxaflow.sdk.sessions

import com.voxaflow.sdk.VoxaErrorCode
import com.voxaflow.sdk.VoxaException
import com.voxaflow.sdk.transport.RestClient
import com.voxaflow.sdk.transport.VoxaRealtime
import org.json.JSONObject

/** A chat conversation (text channel + AI bot). Messages for this conversation arrive on
 *  `VoxaClient.messages` (filter by [conversationId]); bot messages have `isBot` true. */
class ChatSession internal constructor(
    val conversationId: String,
    private val rest: RestClient,
    private val realtime: VoxaRealtime,
) {
    suspend fun sendMessage(content: String): String {
        val res = rest.post("/chat/conversations/$conversationId/messages", JSONObject().put("content", content))
        return res.optString("id")
    }

    suspend fun setTyping(typing: Boolean) {
        if (typing) rest.post("/chat/conversations/$conversationId/typing")
    }

    suspend fun markRead() {
        rest.post("/chat/conversations/$conversationId/read")
    }

    fun leave() = realtime.leaveChat(conversationId)

    companion object {
        internal suspend fun open(
            rest: RestClient,
            realtime: VoxaRealtime,
            conversationId: String?,
            channel: String?,
            contactIdentifier: String?,
            language: String?,
        ): ChatSession {
            val convId: String = when {
                conversationId != null -> conversationId
                channel != null -> {
                    val body = JSONObject()
                    if (contactIdentifier != null) body.put("contactIdentifier", contactIdentifier)
                    if (language != null) body.put("language", language)
                    val res = rest.post("/chat/widget/$channel/start", body)
                    res.optString("conversationId").takeIf { it.isNotEmpty() }
                        ?: throw VoxaException(VoxaErrorCode.SERVER, "chat start did not return a conversationId")
                }
                else -> throw VoxaException(VoxaErrorCode.SERVER, "openChat requires either a conversationId or a channel handle")
            }
            realtime.joinChat(convId)
            return ChatSession(convId, rest, realtime)
        }
    }
}
