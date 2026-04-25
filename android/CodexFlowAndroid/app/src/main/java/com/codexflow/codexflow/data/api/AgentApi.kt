package com.codexflow.codexflow.data.api

import com.codexflow.codexflow.data.model.DashboardResponse
import com.codexflow.codexflow.data.model.HealthResponse
import com.codexflow.codexflow.data.model.JsonValue
import com.codexflow.codexflow.data.model.PendingRequestView
import com.codexflow.codexflow.data.model.SessionDetail
import com.codexflow.codexflow.data.model.SessionSummary
import com.codexflow.codexflow.data.model.TurnDetail

interface AgentApi {
    suspend fun health(): HealthResponse
    suspend fun dashboard(): DashboardResponse
    suspend fun sessions(): List<SessionSummary>
    suspend fun refreshSessions()
    suspend fun startSession(cwd: String, prompt: String): SessionSummary
    suspend fun sessionDetail(id: String): SessionDetail
    suspend fun resumeSession(id: String): SessionSummary
    suspend fun endSession(id: String)
    suspend fun archiveSession(id: String)
    suspend fun startTurn(sessionId: String, prompt: String): TurnDetail
    suspend fun steerTurn(sessionId: String, turnId: String, prompt: String)
    suspend fun interruptTurn(sessionId: String, turnId: String)
    suspend fun approvals(): List<PendingRequestView>
    suspend fun resolveApproval(id: String, result: JsonValue)
}
