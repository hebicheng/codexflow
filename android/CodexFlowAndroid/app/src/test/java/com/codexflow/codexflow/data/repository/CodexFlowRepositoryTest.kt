package com.codexflow.codexflow.data.repository

import com.codexflow.codexflow.data.api.AgentApi
import com.codexflow.codexflow.data.api.SseClient
import com.codexflow.codexflow.data.model.AgentSnapshot
import com.codexflow.codexflow.data.model.DashboardResponse
import com.codexflow.codexflow.data.model.DashboardStats
import com.codexflow.codexflow.data.model.HealthResponse
import com.codexflow.codexflow.data.model.JsonValue
import com.codexflow.codexflow.data.model.PendingRequestView
import com.codexflow.codexflow.data.model.SessionDetail
import com.codexflow.codexflow.data.model.SessionSummary
import com.codexflow.codexflow.data.model.TurnDetail
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class CodexFlowRepositoryTest {
    @Test
    fun submitPrompt_steersWhenLastTurnInProgress() = runTest {
        val api = FakeAgentApi(
            session = SessionSummary(id = "s1", loaded = true, lastTurnStatus = "inProgress", lastTurnId = "t1")
        )
        val repository = CodexFlowRepository(api, SseClient(baseUrlProvider = { "http://127.0.0.1:4318" }), backgroundScope)

        repository.refresh()
        repository.submitPrompt("s1", "调整方向")

        assertEquals(1, api.steerCalls)
        assertEquals(0, api.startTurnCalls)
    }

    @Test
    fun submitPrompt_startsTurnWhenNoInProgressTurn() = runTest {
        val api = FakeAgentApi(
            session = SessionSummary(id = "s1", loaded = true, lastTurnStatus = "completed", lastTurnId = "t1")
        )
        val repository = CodexFlowRepository(api, SseClient(baseUrlProvider = { "http://127.0.0.1:4318" }), backgroundScope)

        repository.refresh()
        repository.submitPrompt("s1", "继续下一步")

        assertEquals(0, api.steerCalls)
        assertEquals(1, api.startTurnCalls)
    }
}

private class FakeAgentApi(private val session: SessionSummary) : AgentApi {
    var steerCalls = 0
    var startTurnCalls = 0

    override suspend fun health() = HealthResponse(ok = true)
    override suspend fun dashboard() = DashboardResponse(
        agent = AgentSnapshot(connected = true),
        stats = DashboardStats(totalSessions = 1, loadedSessions = 1),
        sessions = listOf(session)
    )

    override suspend fun sessions() = listOf(session)
    override suspend fun refreshSessions() = Unit
    override suspend fun startSession(cwd: String, prompt: String) = session
    override suspend fun sessionDetail(id: String) = SessionDetail(summary = session)
    override suspend fun resumeSession(id: String) = session
    override suspend fun endSession(id: String) = Unit
    override suspend fun archiveSession(id: String) = Unit
    override suspend fun startTurn(sessionId: String, prompt: String): TurnDetail {
        startTurnCalls += 1
        return TurnDetail(id = "new")
    }
    override suspend fun steerTurn(sessionId: String, turnId: String, prompt: String) {
        steerCalls += 1
    }
    override suspend fun interruptTurn(sessionId: String, turnId: String) = Unit
    override suspend fun approvals(): List<PendingRequestView> = emptyList()
    override suspend fun resolveApproval(id: String, result: JsonValue) = Unit
}
