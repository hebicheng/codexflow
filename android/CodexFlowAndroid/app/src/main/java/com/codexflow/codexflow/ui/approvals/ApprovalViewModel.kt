package com.codexflow.codexflow.ui.approvals

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.codexflow.codexflow.data.api.userMessage
import com.codexflow.codexflow.data.model.PendingRequestView
import com.codexflow.codexflow.data.repository.CodexFlowRepository
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class ApprovalViewModel(
    private val repository: CodexFlowRepository
) : ViewModel() {
    val dashboardState = repository.dashboardUiState
    val messages = MutableSharedFlow<String>()
    private val _resolvingIds = MutableStateFlow<Set<String>>(emptySet())
    val resolvingIds: StateFlow<Set<String>> = _resolvingIds.asStateFlow()

    fun refresh() {
        viewModelScope.launch {
            repository.refresh().onFailure { messages.emit(it.userMessage()) }
        }
    }

    fun resolve(approval: PendingRequestView, selectedChoice: String, userInputText: String = "") {
        if (approval.id in _resolvingIds.value) return
        viewModelScope.launch {
            _resolvingIds.update { it + approval.id }
            repository.resolveApproval(approval, selectedChoice, userInputText)
                .onSuccess { messages.emit("审批已处理") }
                .onFailure { messages.emit(it.userMessage()) }
            _resolvingIds.update { it - approval.id }
        }
    }

    companion object {
        fun factory(repository: CodexFlowRepository) =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return ApprovalViewModel(repository) as T
                }
            }
    }
}
