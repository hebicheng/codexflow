package com.codexflow.codexflow.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.SettingsEthernet
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.codexflow.codexflow.data.settings.SettingsStore

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(viewModel: SettingsViewModel) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(viewModel) {
        viewModel.messages.collect { snackbarHostState.showSnackbar(it) }
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("设置") }) },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(Icons.Outlined.SettingsEthernet, contentDescription = null)
                            Text("Agent 地址", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        }
                        Text("当前保存：${uiState.currentBaseUrl}", style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
                        TextField(
                            value = uiState.draftBaseUrl,
                            onValueChange = viewModel::updateDraft,
                            label = { Text("Base URL") },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = viewModel::save, modifier = Modifier.weight(1f)) { Text("保存") }
                            OutlinedButton(onClick = viewModel::testConnection, enabled = !uiState.isTesting, modifier = Modifier.weight(1f)) {
                                Text(if (uiState.isTesting) "测试中…" else "测试连接")
                            }
                        }
                        OutlinedButton(onClick = viewModel::restoreDefault, modifier = Modifier.fillMaxWidth()) {
                            Text("恢复默认值 ${SettingsStore.DEFAULT_BASE_URL}")
                        }
                        uiState.testMessage?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }

            item {
                InfoCard(
                    title = "Android Emulator",
                    lines = listOf(
                        "模拟器访问 Mac 本机 Agent 使用：",
                        "http://10.0.2.2:4318"
                    )
                )
            }

            item {
                InfoCard(
                    title = "真机调试",
                    lines = listOf(
                        "Mac Agent 需要监听 0.0.0.0:4318。",
                        "App 中填写 Mac 局域网 IP，例如 http://192.168.1.10:4318。"
                    )
                )
            }

            item {
                InfoCard(
                    title = "启动 Agent",
                    lines = listOf(
                        "go run ./cmd/codexflow-agent",
                        "CODEXFLOW_LISTEN_ADDR=0.0.0.0:4318 go run ./cmd/codexflow-agent"
                    ),
                    monospace = true
                )
            }
        }
    }
}

@Composable
private fun InfoCard(title: String, lines: List<String>, monospace: Boolean = false) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            lines.forEach { line ->
                Text(
                    line,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = if (monospace || line.startsWith("http")) FontFamily.Monospace else FontFamily.Default,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
