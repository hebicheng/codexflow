package com.codexflow.codexflow.ui.approvals

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.codexflow.codexflow.data.model.PendingRequestView
import com.codexflow.codexflow.ui.components.EmptyState
import com.codexflow.codexflow.ui.components.ErrorBanner
import com.codexflow.codexflow.ui.components.StatusBadge
import com.codexflow.codexflow.ui.theme.Warning

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ApprovalsScreen(viewModel: ApprovalViewModel) {
    val dashboardState by viewModel.dashboardState.collectAsState()
    val resolvingIds by viewModel.resolvingIds.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var selected by remember { mutableStateOf<PendingRequestView?>(null) }

    LaunchedEffect(viewModel) {
        viewModel.messages.collect { snackbarHostState.showSnackbar(it) }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("审批") },
                actions = {
                    IconButton(onClick = viewModel::refresh) {
                        Icon(Icons.Outlined.Refresh, contentDescription = "刷新")
                    }
                }
            )
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
                item {
                    Text(
                        "这里集中处理 Codex 发来的 command、fileChange、permissions 和 userInput 请求。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                dashboardState.errorMessage?.let { item { ErrorBanner(it) } }
                if (dashboardState.dashboard.approvals.isEmpty()) {
                    item { EmptyState("当前没有待处理审批。") }
                } else {
                    groupedBySession(dashboardState.dashboard.approvals).forEach { (sessionId, approvals) ->
                        item {
                            Text("会话 $sessionId", style = MaterialTheme.typography.titleSmall, fontFamily = FontFamily.Monospace)
                        }
                        items(approvals, key = { it.id }) { approval ->
                            ApprovalCard(approval = approval, onClick = { selected = approval })
                        }
                    }
                }
            }
        }
    }

    selected?.let { approval ->
        ApprovalDetailSheet(
            approval = approval,
            isResolving = approval.id in resolvingIds,
            onDismiss = { selected = null },
            onResolve = { choice, text ->
                viewModel.resolve(approval, choice, text)
                selected = null
            }
        )
    }
}

@Composable
private fun ApprovalCard(approval: PendingRequestView, onClick: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(kindTitle(approval.kind), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                StatusBadge("待处理", Warning)
            }
            Text(
                approval.summary.ifBlank { approval.method },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )
            if (approval.reason.isNotBlank()) {
                Text("原因：${approval.reason}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(
                "选项：${effectiveChoices(approval).joinToString(" / ") { choiceLabel(approval.kind, it) }}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

private fun groupedBySession(approvals: List<PendingRequestView>): Map<String, List<PendingRequestView>> {
    return approvals.groupBy { it.threadId.ifBlank { "unknown" } }
}
