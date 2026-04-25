package com.codexflow.codexflow.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.codexflow.codexflow.data.api.userMessage
import com.codexflow.codexflow.data.repository.CodexFlowRepository
import com.codexflow.codexflow.data.settings.SettingsStore
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class DashboardViewModel(
    private val repository: CodexFlowRepository,
    settingsStore: SettingsStore
) : ViewModel() {
    val uiState = repository.dashboardUiState
    val sseState = repository.sseConnectionState
    val baseUrl: StateFlow<String> = settingsStore.baseUrl.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        SettingsStore.DEFAULT_BASE_URL
    )
    val messages = MutableSharedFlow<String>()

    fun refresh() {
        viewModelScope.launch {
            repository.refresh().onFailure { messages.emit(it.userMessage()) }
        }
    }

    fun refreshSessions() {
        viewModelScope.launch {
            repository.refreshSessions().onFailure { messages.emit(it.userMessage()) }
        }
    }

    fun startSession(cwd: String, prompt: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            repository.startSession(cwd, prompt)
                .onSuccess {
                    messages.emit("会话已创建")
                    onSuccess()
                }
                .onFailure { messages.emit(it.userMessage()) }
        }
    }

    fun resume(sessionId: String) {
        viewModelScope.launch {
            repository.resume(sessionId)
                .onSuccess { messages.emit("已接管会话") }
                .onFailure { messages.emit(it.userMessage()) }
        }
    }

    fun end(sessionId: String) {
        viewModelScope.launch {
            repository.end(sessionId)
                .onSuccess { messages.emit("会话已结束") }
                .onFailure { messages.emit(it.userMessage()) }
        }
    }

    fun archive(sessionId: String) {
        viewModelScope.launch {
            repository.archive(sessionId)
                .onSuccess { messages.emit("会话已归档") }
                .onFailure { messages.emit(it.userMessage()) }
        }
    }

    companion object {
        fun factory(repository: CodexFlowRepository, settingsStore: SettingsStore) =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return DashboardViewModel(repository, settingsStore) as T
                }
            }
    }
}
