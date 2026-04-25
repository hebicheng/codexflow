package com.codexflow.codexflow.data.api

import com.codexflow.codexflow.data.model.ApprovalListEnvelope
import com.codexflow.codexflow.data.model.DashboardResponse
import com.codexflow.codexflow.data.model.HealthResponse
import com.codexflow.codexflow.data.model.JsonValue
import com.codexflow.codexflow.data.model.SessionDetail
import com.codexflow.codexflow.data.model.SessionListEnvelope
import com.codexflow.codexflow.data.model.SessionSummary
import com.codexflow.codexflow.data.model.TurnDetail
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

class AgentApiClient(
    private val baseUrlProvider: suspend () -> String,
    private val okHttpClient: OkHttpClient = defaultClient(),
    private val json: Json = defaultJson
) : AgentApi {
    override suspend fun health(): HealthResponse = get("/healthz", timeoutSeconds = 10)

    override suspend fun dashboard(): DashboardResponse = get("/api/v1/dashboard")

    override suspend fun sessions(): List<SessionSummary> =
        get<SessionListEnvelope>("/api/v1/sessions").data

    override suspend fun refreshSessions() {
        post<UnitResponse>("/api/v1/sessions", jsonObject("action" to "refresh"))
    }

    override suspend fun startSession(cwd: String, prompt: String): SessionSummary =
        post(
            "/api/v1/sessions",
            jsonObject("action" to "start", "cwd" to cwd, "prompt" to prompt),
            timeoutSeconds = 45
        )

    override suspend fun sessionDetail(id: String): SessionDetail =
        get("/api/v1/sessions/$id")

    override suspend fun resumeSession(id: String): SessionSummary =
        post("/api/v1/sessions/$id/resume", JsonObject(emptyMap()))

    override suspend fun endSession(id: String) {
        post<UnitResponse>("/api/v1/sessions/$id/end", JsonObject(emptyMap()))
    }

    override suspend fun archiveSession(id: String) {
        post<UnitResponse>("/api/v1/sessions/$id/archive", JsonObject(emptyMap()))
    }

    override suspend fun startTurn(sessionId: String, prompt: String): TurnDetail =
        post("/api/v1/sessions/$sessionId/turns/start", jsonObject("prompt" to prompt), timeoutSeconds = 30)

    override suspend fun steerTurn(sessionId: String, turnId: String, prompt: String) {
        post<UnitResponse>(
            "/api/v1/sessions/$sessionId/turns/steer",
            jsonObject("turnId" to turnId, "prompt" to prompt),
            timeoutSeconds = 30
        )
    }

    override suspend fun interruptTurn(sessionId: String, turnId: String) {
        post<UnitResponse>(
            "/api/v1/sessions/$sessionId/turns/interrupt",
            jsonObject("turnId" to turnId),
            timeoutSeconds = 15
        )
    }

    override suspend fun approvals() =
        get<ApprovalListEnvelope>("/api/v1/approvals").data

    override suspend fun resolveApproval(id: String, result: JsonValue) {
        val body = buildJsonObject {
            put("result", result.toJsonElement())
        }
        post<UnitResponse>("/api/v1/approvals/$id/resolve", body, timeoutSeconds = 15)
    }

    private suspend inline fun <reified T> get(path: String, timeoutSeconds: Long = 20): T {
        return decode(send(path = path, method = "GET", body = null, timeoutSeconds = timeoutSeconds))
    }

    private suspend inline fun <reified T> post(
        path: String,
        body: JsonElement,
        timeoutSeconds: Long = 20
    ): T {
        return decode(send(path = path, method = "POST", body = body, timeoutSeconds = timeoutSeconds))
    }

    private suspend inline fun <reified T> decode(raw: String): T {
        if (T::class == UnitResponse::class && raw.isBlank()) {
            @Suppress("UNCHECKED_CAST")
            return UnitResponse() as T
        }
        return json.decodeFromString(raw)
    }

    private suspend fun send(
        path: String,
        method: String,
        body: JsonElement?,
        timeoutSeconds: Long
    ): String = withContext(Dispatchers.IO) {
        val baseUrl = baseUrlProvider()
        val url = buildUrl(baseUrl, path)
        val requestBuilder = Request.Builder().url(url)

        if (method == "GET") {
            requestBuilder.get()
        } else {
            val requestBody = json.encodeToString(JsonElement.serializer(), body ?: JsonObject(emptyMap()))
                .toRequestBody(JSON_MEDIA_TYPE)
            requestBuilder.method(method, requestBody)
                .header("Content-Type", "application/json")
        }

        try {
            val callClient = okHttpClient.newBuilder()
                .callTimeout(timeoutSeconds, TimeUnit.SECONDS)
                .build()
            callClient.newCall(requestBuilder.build()).execute().use { response ->
                val raw = response.body?.string().orEmpty()
                if (!response.isSuccessful) {
                    val serverMessage = runCatching {
                        json.decodeFromString<ErrorEnvelope>(raw).error
                    }.getOrNull()
                    throw ApiError.Server(serverMessage ?: "请求失败：HTTP ${response.code}")
                }
                raw
            }
        } catch (error: ApiError) {
            throw error
        } catch (error: IOException) {
            throw ApiError.Network(error.localizedMessage ?: "网络请求失败", error)
        }
    }

    companion object {
        val defaultJson = Json {
            ignoreUnknownKeys = true
            explicitNulls = false
            isLenient = true
        }

        private val JSON_MEDIA_TYPE = "application/json".toMediaType()

        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()

        internal fun buildUrl(baseUrl: String, path: String): HttpUrl {
            val normalizedBase = baseUrl.trim().trimEnd('/')
            val normalizedPath = path.trimStart('/')
            return "$normalizedBase/$normalizedPath".toHttpUrlOrNull() ?: throw ApiError.InvalidBaseUrl
        }
    }
}

@Serializable
data class UnitResponse(val ok: Boolean = true)

@Serializable
private data class ErrorEnvelope(val error: String = "")

private fun jsonObject(vararg pairs: Pair<String, String>): JsonObject = buildJsonObject {
    pairs.forEach { (key, value) -> put(key, value) }
}
