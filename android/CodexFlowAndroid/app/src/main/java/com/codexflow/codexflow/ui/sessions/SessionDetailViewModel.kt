package com.codexflow.codexflow.ui.sessions

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.codexflow.codexflow.data.api.userMessage
import com.codexflow.codexflow.data.repository.CodexFlowRepository
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class SessionDetailViewModel(
    val sessionId: String,
    private val repository: CodexFlowRepository
) : ViewModel() {
    val dashboardState = repository.dashboardUiState
    val detail = repository.sessionDetails.map { it[sessionId] }.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        repository.sessionDetails.value[sessionId]
    )
    val error: StateFlow<String?> = repository.sessionErrors.map { it[sessionId] }.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        repository.sessionErrors.value[sessionId]
    )
    val messages = MutableSharedFlow<String>()
    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    init {
        repository.setActiveSession(sessionId)
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            repository.refresh()
            repository.loadSession(sessionId).onFailure { messages.emit(it.userMessage()) }
        }
    }

    fun resume() = runAction("已接管会话") { repository.resume(sessionId) }

    fun archive(onArchived: () -> Unit) {
        if (_busy.value) return
        viewModelScope.launch {
            _busy.update { true }
            repository.archive(sessionId)
                .onSuccess {
                    messages.emit("会话已归档")
                    onArchived()
                }
                .onFailure { messages.emit(it.userMessage()) }
            _busy.update { false }
        }
    }

    fun end() = runAction("会话已结束") { repository.end(sessionId) }

    fun submitPrompt(prompt: String) = runAction("已发送") {
        repository.submitPrompt(sessionId, prompt)
    }

    fun interrupt() = runAction("已发送中断") {
        repository.interrupt(sessionId)
    }

    private fun runAction(successMessage: String, block: suspend () -> Result<Unit>) {
        if (_busy.value) return
        viewModelScope.launch {
            _busy.update { true }
            block()
                .onSuccess { messages.emit(successMessage) }
                .onFailure { messages.emit(it.userMessage()) }
            _busy.update { false }
        }
    }

    override fun onCleared() {
        repository.setActiveSession(null)
        super.onCleared()
    }

    companion object {
        fun factory(sessionId: String, repository: CodexFlowRepository) =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return SessionDetailViewModel(sessionId, repository) as T
                }
            }
    }
}
