package com.codexflow.codexflow.data.api

import com.codexflow.codexflow.data.model.AgentEvent
import com.codexflow.codexflow.data.model.JsonValue
import com.codexflow.codexflow.data.model.SseConnectionState
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.sse.EventSource
import okhttp3.sse.EventSourceListener
import okhttp3.sse.EventSources
import kotlin.coroutines.resume

class SseClient(
    private val baseUrlProvider: suspend () -> String,
    private val okHttpClient: OkHttpClient = AgentApiClient.defaultClient(),
    private val json: Json = AgentApiClient.defaultJson
) {
    private val _connectionState = MutableStateFlow(SseConnectionState.Disconnected)
    val connectionState: StateFlow<SseConnectionState> = _connectionState

    private val _events = MutableSharedFlow<AgentEvent>(
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val events: SharedFlow<AgentEvent> = _events

    private var job: Job? = null
    private var activeSource: EventSource? = null
    private val stopped = AtomicBoolean(true)

    fun start(scope: CoroutineScope) {
        if (job?.isActive == true) return
        stopped.set(false)
        job = scope.launch {
            var backoffMs = INITIAL_BACKOFF_MS
            while (isActive && !stopped.get()) {
                _connectionState.value =
                    if (backoffMs == INITIAL_BACKOFF_MS) SseConnectionState.Connecting else SseConnectionState.Reconnecting

                val connected = runCatching {
                    connectOnce(scope)
                }.getOrDefault(false)

                if (!isActive || stopped.get()) break
                _connectionState.value = SseConnectionState.Reconnecting
                delay(backoffMs)
                backoffMs = if (connected) {
                    INITIAL_BACKOFF_MS
                } else {
                    (backoffMs * 2).coerceAtMost(MAX_BACKOFF_MS)
                }
            }
            _connectionState.value = SseConnectionState.Disconnected
        }
    }

    fun stop() {
        stopped.set(true)
        activeSource?.cancel()
        activeSource = null
        job?.cancel()
        job = null
        _connectionState.value = SseConnectionState.Disconnected
    }

    private suspend fun connectOnce(scope: CoroutineScope): Boolean {
        val url = AgentApiClient.buildUrl(baseUrlProvider(), "/api/v1/events")
        val request = Request.Builder()
            .url(url)
            .header("Accept", "text/event-stream")
            .get()
            .build()

        return suspendCancellableCoroutine { continuation ->
            var opened = false
            val listener = object : EventSourceListener() {
                override fun onOpen(eventSource: EventSource, response: Response) {
                    activeSource = eventSource
                    opened = true
                    _connectionState.value = SseConnectionState.Connected
                }

                override fun onEvent(eventSource: EventSource, id: String?, type: String?, data: String) {
                    val eventType = type.orEmpty()
                    if (eventType == "ping" || data.isBlank()) return
                    val event = runCatching {
                        json.decodeFromString<AgentEvent>(data)
                    }.getOrElse {
                        AgentEvent(type = eventType.ifBlank { "message" }, payload = JsonValue.string(data))
                    }
                    scope.launch { _events.emit(event.copy(type = event.type.ifBlank { eventType })) }
                }

                override fun onClosed(eventSource: EventSource) {
                    if (continuation.isActive) continuation.resume(opened)
                }

                override fun onFailure(eventSource: EventSource, t: Throwable?, response: Response?) {
                    if (stopped.get() || t is CancellationException) {
                        if (continuation.isActive) continuation.resume(opened)
                        return
                    }
                    if (continuation.isActive) continuation.resume(false)
                }
            }

            val source = EventSources.createFactory(okHttpClient).newEventSource(request, listener)
            activeSource = source
            continuation.invokeOnCancellation {
                source.cancel()
                activeSource = null
            }
        }
    }

    companion object {
        private const val INITIAL_BACKOFF_MS = 1_000L
        private const val MAX_BACKOFF_MS = 30_000L
    }
}
