package com.voxaflow.sdk.transport

import com.voxaflow.sdk.VoxaErrorCode
import com.voxaflow.sdk.VoxaException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

/** REST client: attaches the token, parses JSON, and on a 401 transparently refreshes the
 *  token (via onTokenRefresh) and retries once. */
internal class RestClient(
    private val endpoint: String,
    @Volatile private var token: String,
    private val onTokenRefresh: (suspend () -> String)?,
) {
    var onTokenChanged: ((String) -> Unit)? = null
    private val http = OkHttpClient()
    private val jsonMedia = "application/json".toMediaType()

    suspend fun post(path: String, body: JSONObject? = null): JSONObject = send("POST", path, body)
    suspend fun get(path: String): JSONObject = send("GET", path, null)
    suspend fun put(path: String, body: JSONObject? = null): JSONObject = send("PUT", path, body)
    suspend fun delete(path: String, body: JSONObject? = null): JSONObject = send("DELETE", path, body)

    private suspend fun send(method: String, path: String, body: JSONObject?, retry: Boolean = true): JSONObject =
        withContext(Dispatchers.IO) {
            val rb = body?.toString()?.toRequestBody(jsonMedia)
            val builder = Request.Builder().url(endpoint + path).header("Authorization", "Bearer $token")
            when (method) {
                "GET" -> builder.get()
                "PUT" -> builder.put(rb ?: "".toRequestBody(jsonMedia))
                "DELETE" -> if (rb != null) builder.delete(rb) else builder.delete()
                else -> builder.post(rb ?: "".toRequestBody(jsonMedia))
            }

            val resp = try {
                http.newCall(builder.build()).execute()
            } catch (e: Exception) {
                throw VoxaException(VoxaErrorCode.CONNECTION, "Network error calling $path", cause = e)
            }

            val status = resp.code
            val text = resp.body?.string().orEmpty()
            resp.close()

            if (status == 401 && retry && onTokenRefresh != null) {
                token = try {
                    onTokenRefresh.invoke()
                } catch (e: Exception) {
                    throw VoxaException(VoxaErrorCode.AUTH, "Token refresh failed", 401, e)
                }
                onTokenChanged?.invoke(token)
                return@withContext send(method, path, body, false)
            }
            if (status in 200..299) {
                return@withContext if (text.isEmpty()) JSONObject() else JSONObject(text)
            }
            val code = if (status == 401 || status == 403) VoxaErrorCode.AUTH else VoxaErrorCode.SERVER
            throw VoxaException(code, errorMessage(text, status), status)
        }

    private fun errorMessage(text: String, status: Int): String {
        return try {
            val j = JSONObject(text)
            j.optString("message").takeIf { it.isNotEmpty() }
                ?: j.optString("error").takeIf { it.isNotEmpty() }
                ?: "Request failed (HTTP $status)"
        } catch (_: Exception) {
            "Request failed (HTTP $status)"
        }
    }
}
