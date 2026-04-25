package com.codexflow.codexflow.data.repository

import com.codexflow.codexflow.data.api.AgentApi
import com.codexflow.codexflow.data.api.SseClient
import com.codexflow.codexflow.data.api.userMessage
import com.codexflow.codexflow.data.model.ApprovalResultBuilder
import com.codexflow.codexflow.data.model.DashboardResponse
import com.codexflow.codexflow.data.model.PendingRequestView
import com.codexflow.codexflow.data.model.SessionDetail
import com.codexflow.codexflow.data.model.SessionSummary
import com.codexflow.codexflow.data.model.SseConnectionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class DashboardUiState(
    val dashboard: DashboardResponse = DashboardResponse(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val errorMessage: String? = null
)

class CodexFlowRepository(
    private val api: AgentApi,
    private val sseClient: SseClient,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) {
    private val refreshMutex = Mutex()

    private val _dashboardUiState = MutableStateFlow(DashboardUiState())
    val dashboardUiState: StateFlow<DashboardUiState> = _dashboardUiState.asStateFlow()

    private val _sessionDetails = MutableStateFlow<Map<String, SessionDetail>>(emptyMap())
    val sessionDetails: StateFlow<Map<String, SessionDetail>> = _sessionDetails.asStateFlow()

    private val _sessionErrors = MutableStateFlow<Map<String, String>>(emptyMap())
    val sessionErrors: StateFlow<Map<String, String>> = _sessionErrors.asStateFlow()

    private val _activeSessionId = MutableStateFlow<String?>(null)
    val sseConnectionState: StateFlow<SseConnectionState> = sseClient.connectionState

    init {
        scope.launch {
            sseClient.events.collect {
                refresh()
                _activeSessionId.value?.let { loadSession(it) }
            }
        }
    }

    fun startRealtime() {
        sseClient.start(scope)
    }

    fun stopRealtime() {
        sseClient.stop()
    }

    fun restartRealtime() {
        stopRealtime()
        startRealtime()
    }

    fun setActiveSession(sessionId: String?) {
        _activeSessionId.value = sessionId
    }

    suspend fun refresh(): Result<Unit> = refreshMutex.withLock {
        _dashboardUiState.update {
            it.copy(isLoading = it.isLoading && it.dashboard.sessions.isEmpty(), isRefreshing = true, errorMessage = null)
        }
        runCatching {
            val latest = api.dashboard()
            _dashboardUiState.value = DashboardUiState(
                dashboard = latest,
                isLoading = false,
                isRefreshing = false,
                errorMessage = null
            )
        }.onFailure { error ->
            _dashboardUiState.update {
                it.copy(isLoading = false, isRefreshing = false, errorMessage = error.userMessage())
            }
        }
    }

    suspend fun loadSession(sessionId: String): Result<Unit> = runCatching {
        val detail = api.sessionDetail(sessionId)
        _sessionDetails.update { it + (sessionId to detail) }
        _sessionErrors.update { it - sessionId }
    }.onFailure { error ->
        _sessionErrors.update { it + (sessionId to error.userMessage()) }
    }

    suspend fun refreshSessions(): Result<Unit> = action {
        api.refreshSessions()
        refresh().getOrThrow()
    }

    suspend fun startSession(cwd: String, prompt: String): Result<Unit> = action {
        api.startSession(cwd.trim(), prompt.trim())
        refresh().getOrThrow()
    }

    suspend fun resume(sessionId: String): Result<Unit> = action {
        api.resumeSession(sessionId)
        refresh().getOrThrow()
        loadSession(sessionId).getOrThrow()
    }

    suspend fun archive(sessionId: String): Result<Unit> = action {
        api.archiveSession(sessionId)
        _sessionDetails.update { it - sessionId }
        refresh().getOrThrow()
    }

    suspend fun end(sessionId: String): Result<Unit> = action {
        api.endSession(sessionId)
        refresh().getOrThrow()
        loadSession(sessionId).getOrThrow()
    }

    suspend fun submitPrompt(sessionId: String, prompt: String): Result<Unit> = action {
        val trimmedPrompt = prompt.trim()
        if (trimmedPrompt.isEmpty()) return@action
        val summary = currentSummary(sessionId) ?: error("找不到会话 $sessionId")
        if (summary.lastTurnStatus == "inProgress" && summary.lastTurnId.isNotBlank()) {
            api.steerTurn(sessionId, summary.lastTurnId, trimmedPrompt)
        } else {
            api.startTurn(sessionId, trimmedPrompt)
        }
        refresh().getOrThrow()
        loadSession(sessionId).getOrThrow()
    }

    suspend fun interrupt(sessionId: String): Result<Unit> = action {
        val summary = currentSummary(sessionId) ?: error("找不到会话 $sessionId")
        if (summary.lastTurnId.isBlank()) return@action
        api.interruptTurn(sessionId, summary.lastTurnId)
        refresh().getOrThrow()
        loadSession(sessionId).getOrThrow()
    }

    suspend fun resolveApproval(
        approval: PendingRequestView,
        selectedChoice: String,
        userInputText: String = ""
    ): Result<Unit> = action {
        val result = ApprovalResultBuilder.build(approval, selectedChoice, userInputText)
        api.resolveApproval(approval.id, result)
        refresh().getOrThrow()
        if (approval.threadId.isNotBlank()) {
            loadSession(approval.threadId).getOrThrow()
        }
    }

    private fun currentSummary(sessionId: String): SessionSummary? {
        return _sessionDetails.value[sessionId]?.summary
            ?: _dashboardUiState.value.dashboard.sessions.firstOrNull { it.id == sessionId }
    }

    private suspend fun action(block: suspend () -> Unit): Result<Unit> {
        return runCatching { block() }.onFailure { error ->
            _dashboardUiState.update { it.copy(errorMessage = error.userMessage()) }
        }
    }
}
