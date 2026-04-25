package com.codexflow.codexflow.data.model

import kotlinx.serialization.Serializable

@Serializable
data class DashboardResponse(
    val agent: AgentSnapshot = AgentSnapshot(),
    val stats: DashboardStats = DashboardStats(),
    val sessions: List<SessionSummary> = emptyList(),
    val approvals: List<PendingRequestView> = emptyList()
)

@Serializable
data class AgentSnapshot(
    val connected: Boolean = false,
    val startedAt: String = "",
    val listenAddr: String = "",
    val codexBinaryPath: String = ""
)

@Serializable
data class DashboardStats(
    val totalSessions: Int = 0,
    val loadedSessions: Int = 0,
    val activeSessions: Int = 0,
    val pendingApprovals: Int = 0
)

@Serializable
data class HealthResponse(
    val ok: Boolean = false,
    val timestamp: String = ""
)
