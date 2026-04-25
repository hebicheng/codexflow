package com.codexflow.codexflow.ui.dashboard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.codexflow.codexflow.data.model.SessionSummary
import com.codexflow.codexflow.ui.components.EmptyState
import com.codexflow.codexflow.ui.components.ErrorBanner
import com.codexflow.codexflow.ui.components.LoadingState
import com.codexflow.codexflow.ui.components.StatusBadge
import com.codexflow.codexflow.ui.components.sseColor
import com.codexflow.codexflow.ui.components.sseLabel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    viewModel: DashboardViewModel,
    onOpenSession: (String) -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val sseState by viewModel.sseState.collectAsState()
    val baseUrl by viewModel.baseUrl.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var showNewSession by remember { mutableStateOf(false) }
    var pendingEnd by remember { mutableStateOf<SessionSummary?>(null) }
    var pendingArchive by remember { mutableStateOf<SessionSummary?>(null) }

    LaunchedEffect(viewModel) {
        viewModel.messages.collect { snackbarHostState.showSnackbar(it) }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("会话") },
                actions = {
                    IconButton(onClick = viewModel::refreshSessions) {
                        Icon(Icons.Outlined.Refresh, contentDescription = "刷新")
                    }
                    IconButton(onClick = { showNewSession = true }) {
                        Icon(Icons.Outlined.Add, contentDescription = "新建会话")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = uiState.isRefreshing,
            onRefresh = viewModel::refresh,
            modifier = Modifier.padding(padding).fillMaxSize()
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp)
            ) {
                item {
                    HeaderCard(
                        connected = uiState.dashboard.agent.connected,
                        baseUrl = baseUrl,
                        sseText = sseLabel(sseState),
                        sseTone = sseColor(sseState)
                    )
                }
                item { StatsRow(uiState.dashboard.stats) }
                uiState.errorMessage?.let { item { ErrorBanner(it) } }

                if (uiState.isLoading) {
                    item { LoadingState("正在加载 dashboard…") }
                } else if (uiState.dashboard.sessions.isEmpty()) {
                    item { EmptyState("暂时没有会话。请确认 Mac Agent 已启动，或新建受控会话。") }
                } else {
                    val groups = groupedSessions(uiState.dashboard.sessions)
                    groups.forEach { group ->
                        item {
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(group.title, style = MaterialTheme.typography.titleMedium)
                                Text(group.helper, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        items(group.sessions, key = { it.id }) { session ->
                            SessionCard(
                                session = session,
                                onOpen = { onOpenSession(session.id) },
                                onResume = { viewModel.resume(session.id) },
                                onEnd = { pendingEnd = session },
                                onArchive = { pendingArchive = session }
                            )
                        }
                    }
                }
            }
        }
    }

    if (showNewSession) {
        NewSessionDialog(
            onDismiss = { showNewSession = false },
            onCreate = { cwd, prompt -> viewModel.startSession(cwd, prompt) { showNewSession = false } }
        )
    }

    pendingEnd?.let { session ->
        ConfirmDialog(
            title = if (session.isRunningTurn) "中断并结束会话？" else "结束会话？",
            text = "会话历史仍会保留，但会退出 CodexFlow 托管状态。",
            confirmText = "结束",
            onDismiss = { pendingEnd = null },
            onConfirm = {
                pendingEnd = null
                viewModel.end(session.id)
            }
        )
    }

    pendingArchive?.let { session ->
        ConfirmDialog(
            title = "归档会话？",
            text = "此操作会从本地列表移除 CodexFlow 状态，不会修改 Codex CLI 协议或会话内容。",
            confirmText = "归档",
            onDismiss = { pendingArchive = null },
            onConfirm = {
                pendingArchive = null
                viewModel.archive(session.id)
            }
        )
    }
}

@Composable
private fun HeaderCard(connected: Boolean, baseUrl: String, sseText: String, sseTone: androidx.compose.ui.graphics.Color) {
    androidx.compose.material3.Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatusBadge(if (connected) "Agent 在线" else "Agent 离线", if (connected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error)
                StatusBadge(sseText, sseTone)
            }
            Text("Base URL", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(baseUrl, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
        }
    }
}

@Composable
private fun NewSessionDialog(onDismiss: () -> Unit, onCreate: (String, String) -> Unit) {
    var cwd by remember { mutableStateOf("") }
    var prompt by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("新建受控会话") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                TextField(
                    value = cwd,
                    onValueChange = {
                        cwd = it
                        error = null
                    },
                    label = { Text("工作目录，必须是绝对路径") },
                    placeholder = { Text("/Users/wu/work/repo") },
                    singleLine = true
                )
                TextField(
                    value = prompt,
                    onValueChange = {
                        prompt = it
                        error = null
                    },
                    label = { Text("首轮 prompt") },
                    minLines = 4
                )
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            Button(onClick = {
                val trimmedCwd = cwd.trim()
                val trimmedPrompt = prompt.trim()
                when {
                    !trimmedCwd.startsWith("/") -> error = "工作目录必须是绝对路径。"
                    trimmedPrompt.isBlank() -> error = "首轮 prompt 不能为空。"
                    else -> onCreate(trimmedCwd, trimmedPrompt)
                }
            }) {
                Text("创建")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } }
    )
}

@Composable
private fun ConfirmDialog(
    title: String,
    text: String,
    confirmText: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(text) },
        confirmButton = { Button(onClick = onConfirm) { Text(confirmText) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } }
    )
}

private data class SessionGroup(val title: String, val helper: String, val sessions: List<SessionSummary>)

private fun groupedSessions(sessions: List<SessionSummary>): List<SessionGroup> {
    val pending = sessions.filter { !it.ended && it.pendingApprovals > 0 }
    val running = sessions.filter { !it.ended && it.pendingApprovals == 0 && (it.isRunningTurn || it.status == "active") }
    val ended = sessions.filter { it.ended }
    val historical = sessions.filter { !it.ended && it.pendingApprovals == 0 && !it.loaded && it !in running }
    val managed = sessions.filter { !it.ended && it.pendingApprovals == 0 && it.loaded && it !in running }
    return listOf(
        SessionGroup("待审批", "这些会话有 command、fileChange、permissions 或 userInput 等请求等待处理。", pending),
        SessionGroup("运行中", "当前正在执行或可 steer 的会话。", running),
        SessionGroup("已接管", "已经由 CodexFlow 托管，可以继续下一步。", managed),
        SessionGroup("历史", "已发现但未接管的 Codex 历史会话。", historical),
        SessionGroup("已结束", "已退出托管但仍可查看历史。", ended)
    ).filter { it.sessions.isNotEmpty() }
}
