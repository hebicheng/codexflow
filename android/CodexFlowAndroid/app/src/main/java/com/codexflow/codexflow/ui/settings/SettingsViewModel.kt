package com.codexflow.codexflow.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.codexflow.codexflow.data.api.AgentApiClient
import com.codexflow.codexflow.data.api.userMessage
import com.codexflow.codexflow.data.repository.CodexFlowRepository
import com.codexflow.codexflow.data.settings.SettingsStore
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class SettingsUiState(
    val currentBaseUrl: String = SettingsStore.DEFAULT_BASE_URL,
    val draftBaseUrl: String = SettingsStore.DEFAULT_BASE_URL,
    val isTesting: Boolean = false,
    val testMessage: String? = null
)

class SettingsViewModel(
    private val settingsStore: SettingsStore,
    private val repository: CodexFlowRepository
) : ViewModel() {
    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()
    val messages = MutableSharedFlow<String>()
    private var userEdited = false

    init {
        viewModelScope.launch {
            settingsStore.baseUrl.collect { baseUrl ->
                _uiState.update {
                    it.copy(
                        currentBaseUrl = baseUrl,
                        draftBaseUrl = if (userEdited) it.draftBaseUrl else baseUrl
                    )
                }
            }
        }
    }

    fun updateDraft(value: String) {
        userEdited = true
        _uiState.update { it.copy(draftBaseUrl = value, testMessage = null) }
    }

    fun save() {
        viewModelScope.launch {
            val baseUrl = _uiState.value.draftBaseUrl
            settingsStore.saveBaseUrl(baseUrl)
            userEdited = false
            repository.restartRealtime()
            repository.refresh()
            messages.emit("Agent 地址已保存")
        }
    }

    fun restoreDefault() {
        viewModelScope.launch {
            userEdited = false
            settingsStore.restoreDefaultBaseUrl()
            repository.restartRealtime()
            repository.refresh()
            messages.emit("已恢复默认地址")
        }
    }

    fun testConnection() {
        viewModelScope.launch {
            _uiState.update { it.copy(isTesting = true, testMessage = null) }
            val draft = _uiState.value.draftBaseUrl
            runCatching {
                AgentApiClient(baseUrlProvider = { draft }).health()
            }.onSuccess { health ->
                _uiState.update {
                    it.copy(
                        isTesting = false,
                        testMessage = if (health.ok) "连接成功：/healthz 正常" else "连接失败：Agent 未返回 ok"
                    )
                }
            }.onFailure { error ->
                _uiState.update {
                    it.copy(isTesting = false, testMessage = "连接失败：${error.userMessage()}")
                }
            }
        }
    }

    companion object {
        fun factory(settingsStore: SettingsStore, repository: CodexFlowRepository) =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return SettingsViewModel(settingsStore, repository) as T
                }
            }
    }
}
