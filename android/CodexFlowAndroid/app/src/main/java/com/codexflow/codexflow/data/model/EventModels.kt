package com.codexflow.codexflow.data.model

import kotlinx.serialization.Serializable

@Serializable
data class AgentEvent(
    val type: String = "",
    val timestamp: String = "",
    val payload: JsonValue = JsonValue.NullValue
)

enum class SseConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting
}
