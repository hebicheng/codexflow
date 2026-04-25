package com.codexflow.codexflow.ui.dashboard

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.codexflow.codexflow.data.model.SessionSummary
import com.codexflow.codexflow.ui.components.StatusBadge
import com.codexflow.codexflow.ui.components.sessionStatusColor
import com.codexflow.codexflow.ui.components.sessionStatusLabel

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SessionCard(
    session: SessionSummary,
    onOpen: () -> Unit,
    onResume: () -> Unit,
    onEnd: () -> Unit,
    onArchive: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth().clickable(onClick = onOpen),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(session.displayName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(
                        text = session.cwd.ifBlank { "未识别工作目录" },
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = "更新 ${session.updatedAtDisplay}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                StatusBadge(
                    text = sessionStatusLabel(session.status, session.hasWaitingState, session.ended),
                    color = sessionStatusColor(session.status, session.hasWaitingState, session.ended)
                )
            }

            if (session.previewSummary.isNotBlank()) {
                Text(
                    text = session.previewExcerpt.ifBlank { session.previewSummary },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }

            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MetaChip("来源 ${session.source.ifBlank { "未知" }}")
                MetaChip("分支 ${session.branch.ifBlank { "未识别" }}")
                if (session.lastTurnStatus.isNotBlank()) MetaChip("最近 ${turnStatusLabel(session.lastTurnStatus)}")
                if (session.pendingApprovals > 0) MetaChip("审批 ${session.pendingApprovals}")
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onOpen, modifier = Modifier.weight(1f)) {
                    Text(if (session.loaded && !session.ended) "查看并继续" else "查看详情")
                }
                when {
                    session.ended || !session.loaded -> {
                        OutlinedButton(onClick = onResume, modifier = Modifier.weight(1f)) {
                            Text(if (session.ended) "重新接管" else "接管")
                        }
                    }
                    else -> {
                        OutlinedButton(onClick = onEnd, modifier = Modifier.weight(1f)) {
                            Text(if (session.isRunningTurn) "中断并结束" else "结束")
                        }
                    }
                }
            }

            if (!session.loaded || session.ended) {
                OutlinedButton(onClick = onArchive, modifier = Modifier.fillMaxWidth()) {
                    Text(if (session.ended) "归档已结束会话" else "从列表移除")
                }
            }
        }
    }
}

@Composable
fun MetaChip(text: String) {
    Text(
        text = text,
        modifier = Modifier
            .padding(end = 2.dp)
            .then(Modifier),
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

fun turnStatusLabel(status: String): String = when (status) {
    "inProgress" -> "运行中"
    "completed" -> "已完成"
    "failed" -> "失败"
    else -> status
}
