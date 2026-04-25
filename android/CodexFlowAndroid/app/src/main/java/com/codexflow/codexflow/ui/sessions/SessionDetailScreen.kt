package com.codexflow.codexflow.ui.sessions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Archive
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.StopCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.codexflow.codexflow.data.model.SessionSummary
import com.codexflow.codexflow.data.model.TurnDetail
import com.codexflow.codexflow.ui.components.EmptyState
import com.codexflow.codexflow.ui.components.ErrorBanner
import com.codexflow.codexflow.ui.components.LoadingState
import com.codexflow.codexflow.ui.components.StatusBadge
import com.codexflow.codexflow.ui.components.sessionStatusColor
import com.codexflow.codexflow.ui.components.sessionStatusLabel
import com.codexflow.codexflow.ui.dashboard.MetaChip
import com.codexflow.codexflow.ui.dashboard.turnStatusLabel
import com.codexflow.codexflow.ui.theme.Warning

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionDetailScreen(
    viewModel: SessionDetailViewModel,
    onBack: () -> Unit
) {
    val dashboardState by viewModel.dashboardState.collectAsState()
    val detail by viewModel.detail.collectAsState()
    val error by viewModel.error.collectAsState()
    val busy by viewModel.busy.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var confirmEnd by remember { mutableStateOf(false) }
    var confirmArchive by remember { mutableStateOf(false) }
    val summary = detail?.summary ?: dashboardState.dashboard.sessions.firstOrNull { it.id == viewModel.sessionId }
    val effectiveSummary = summary ?: detail?.summary

    LaunchedEffect(viewModel) {
        viewModel.messages.collect { snackbarHostState.showSnackbar(it) }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(effectiveSummary?.displayName ?: "会话详情") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "返回") }
                },
                actions = {
                    IconButton(onClick = viewModel::refresh) { Icon(Icons.Outlined.Refresh, contentDescription = "刷新") }
                    effectiveSummary?.let {
                        IconButton(onClick = { confirmArchive = true }, enabled = !busy) {
                            Icon(Icons.Outlined.Archive, contentDescription = "归档")
                        }
                        if (it.loaded && !it.ended) {
                            IconButton(onClick = { confirmEnd = true }, enabled = !busy) {
                                Icon(Icons.Outlined.StopCircle, contentDescription = "结束")
                            }
                        }
                    }
                }
            )
        },
        bottomBar = {
            if (effectiveSummary?.loaded == true && effectiveSummary.ended.not()) {
                ComposerBar(
                    isSteering = effectiveSummary.isRunningTurn,
                    busy = busy,
                    onSubmit = viewModel::submitPrompt,
                    onInterrupt = viewModel::interrupt
                )
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = dashboardState.isRefreshing,
            onRefresh = viewModel::refresh,
            modifier = Modifier.padding(padding).fillMaxSize()
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                error?.let { item { ErrorBanner(it) } }
                effectiveSummary?.let { item { SummaryCard(it, pendingApprovals = dashboardState.dashboard.approvals.count { approval -> approval.threadId == it.id }) } }

                effectiveSummary?.let { summaryValue ->
                    if (!summaryValue.loaded || summaryValue.ended) {
                        item {
                            Card(modifier = Modifier.fillMaxWidth()) {
                                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Text(if (summaryValue.ended) "会话已结束" else "先接管，再继续", style = MaterialTheme.typography.titleMedium)
                                    Text(
                                        if (summaryValue.ended) {
                                            "历史记录仍可查看。需要继续 prompt、steer 或处理后续审批时，先重新接管。"
                                        } else {
                                            "这是已发现的历史会话。接管后才可以继续下一轮、steer 或 interrupt。"
                                        },
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    Button(onClick = viewModel::resume, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                                        Text(if (busy) "处理中…" else "接管到 CodexFlow")
                                    }
                                }
                            }
                        }
                    }
                }

                if (detail == null) {
                    item { LoadingState("正在加载会话详情…") }
                } else if (detail?.turns.orEmpty().isEmpty()) {
                    item { EmptyState("当前没有可展示的 turn。") }
                } else {
                    val turns = detail?.turns.orEmpty().asReversed()
                    items(turns, key = { it.id }) { turn ->
                        TurnCard(turn)
                    }
                }
            }
        }
    }

    if (confirmEnd) {
        ConfirmActionDialog(
            title = "结束会话？",
            text = "如果当前 turn 正在运行，Agent 会先中断再结束托管状态。",
            confirmText = "结束",
            onDismiss = { confirmEnd = false },
            onConfirm = {
                confirmEnd = false
                viewModel.end()
            }
        )
    }

    if (confirmArchive) {
        ConfirmActionDialog(
            title = "归档会话？",
            text = "归档只移除本地 CodexFlow 状态，不会修改 Codex CLI 会话内容。",
            confirmText = "归档",
            onDismiss = { confirmArchive = false },
            onConfirm = {
                confirmArchive = false
                viewModel.archive(onBack)
            }
        )
    }
}

@Composable
private fun SummaryCard(summary: SessionSummary, pendingApprovals: Int) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(summary.displayName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                    Text(summary.cwd, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
                }
                StatusBadge(
                    text = sessionStatusLabel(summary.status, summary.hasWaitingState, summary.ended),
                    color = sessionStatusColor(summary.status, summary.hasWaitingState, summary.ended)
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MetaChip("分支 ${summary.branch.ifBlank { "未识别" }}")
                MetaChip("模型 ${summary.modelProvider.ifBlank { "未知" }}")
                MetaChip("更新 ${summary.updatedAtDisplay}")
            }
            if (summary.previewSummary.isNotBlank()) {
                Text(summary.previewExcerpt, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (pendingApprovals > 0) {
                StatusBadge("当前有 $pendingApprovals 个审批", Warning)
            }
        }
    }
}

@Composable
private fun TurnCard(turn: TurnDetail) {
    var expanded by remember(turn.id) { mutableStateOf(turn.status == "inProgress") }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(turnStatusLabel(turn.status), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(turn.id, style = MaterialTheme.typography.labelSmall, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (turn.durationMs > 0) Text("${turn.durationMs / 1000}s", style = MaterialTheme.typography.labelMedium)
            }
            if (turn.error.isNotBlank()) ErrorBanner(turn.error)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (turn.plan.isNotEmpty()) MetaChip("计划 ${turn.plan.size} 步")
                if (turn.diff.isNotBlank()) MetaChip("Diff")
                if (turn.items.isNotEmpty()) MetaChip("Timeline ${turn.items.size}")
            }
            OutlinedButton(onClick = { expanded = !expanded }, modifier = Modifier.fillMaxWidth()) {
                Text(if (expanded) "收起详情" else "查看详情")
            }
            if (expanded) {
                PlanSection(turn.planExplanation, turn.plan)
                DiffSection(turn.diff)
                TimelineSection(turn.items)
            }
        }
    }
}

@Composable
private fun ConfirmActionDialog(
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
