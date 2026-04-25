package com.codexflow.codexflow.ui.sessions

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.codexflow.codexflow.data.model.TurnItem
import com.codexflow.codexflow.data.model.headTailTruncated
import com.codexflow.codexflow.ui.components.StatusBadge
import com.codexflow.codexflow.ui.theme.Ember
import com.codexflow.codexflow.ui.theme.Forest
import com.codexflow.codexflow.ui.theme.MutedInk
import com.codexflow.codexflow.ui.theme.SoftBlue
import com.codexflow.codexflow.ui.theme.Warning

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TimelineSection(items: List<TurnItem>, modifier: Modifier = Modifier) {
    if (items.isEmpty()) return
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Timeline", style = MaterialTheme.typography.titleSmall)
        items.forEach { item -> TimelineItemCard(item) }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TimelineItemCard(item: TurnItem) {
    Surface(shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceVariant) {
        Column(modifier = Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatusBadge(timelineTypeLabel(item), timelineTypeColor(item.type))
                if (item.status.isNotBlank()) StatusBadge(item.status, MutedInk)
            }
            if (item.body.isNotBlank()) {
                if (item.type == "commandExecution") {
                    CodeBlock(item.body)
                } else {
                    SelectionContainer {
                        Text(
                            item.body.headTailTruncated(maxLength = 900, head = 600, tail = 260),
                            style = MaterialTheme.typography.bodySmall,
                            maxLines = if (item.type == "agentMessage") 40 else 16,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
            if (item.auxiliary.isNotBlank()) {
                CodeBlock(item.auxiliary, dark = true)
            }
            if (item.metadata.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    item.metadata.forEach { (key, value) ->
                        Text("$key=$value", style = MaterialTheme.typography.labelSmall, fontFamily = FontFamily.Monospace)
                    }
                }
            }
        }
    }
}

@Composable
fun CodeBlock(text: String, dark: Boolean = false) {
    val background = if (dark) androidx.compose.ui.graphics.Color(0xFF121719) else MaterialTheme.colorScheme.surface
    val content = if (dark) androidx.compose.ui.graphics.Color(0xFFE0E7E7) else MaterialTheme.colorScheme.onSurface
    SelectionContainer {
        Text(
            text = text,
            color = content,
            fontFamily = FontFamily.Monospace,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .background(background, MaterialTheme.shapes.small)
                .padding(10.dp)
        )
    }
}

private fun timelineTypeLabel(item: TurnItem): String = when (item.type) {
    "userMessage" -> "用户"
    "agentMessage" -> "Agent"
    "fileChange" -> "文件变更"
    "commandExecution" -> "命令"
    else -> item.title.ifBlank { item.type.ifBlank { "事件" } }
}

private fun timelineTypeColor(type: String) = when (type) {
    "userMessage" -> SoftBlue
    "agentMessage" -> Forest
    "fileChange" -> Ember
    "commandExecution" -> Warning
    else -> MutedInk
}
