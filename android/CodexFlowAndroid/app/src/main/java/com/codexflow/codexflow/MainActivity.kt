package com.codexflow.codexflow

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.codexflow.codexflow.data.api.AgentApiClient
import com.codexflow.codexflow.data.api.SseClient
import com.codexflow.codexflow.data.repository.CodexFlowRepository
import com.codexflow.codexflow.data.settings.SettingsStore

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = CodexFlowContainer.get(applicationContext)
        setContent {
            CodexFlowApp(container = container)
        }
    }
}

class CodexFlowContainer private constructor(context: android.content.Context) {
    val settingsStore: SettingsStore = SettingsStore.create(context.applicationContext)
    val apiClient: AgentApiClient = AgentApiClient(baseUrlProvider = { settingsStore.currentBaseUrl() })
    private val sseClient: SseClient = SseClient(baseUrlProvider = { settingsStore.currentBaseUrl() })
    val repository: CodexFlowRepository = CodexFlowRepository(apiClient, sseClient)

    companion object {
        @Volatile private var instance: CodexFlowContainer? = null

        fun get(context: android.content.Context): CodexFlowContainer {
            return instance ?: synchronized(this) {
                instance ?: CodexFlowContainer(context).also { instance = it }
            }
        }
    }
}
