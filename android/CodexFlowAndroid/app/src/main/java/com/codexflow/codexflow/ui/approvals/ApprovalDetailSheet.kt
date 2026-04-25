package com.codexflow.codexflow.ui.approvals

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.codexflow.codexflow.data.model.JsonValue
import com.codexflow.codexflow.data.model.PendingRequestView

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ApprovalDetailSheet(
    approval: PendingRequestView,
    isResolving: Boolean,
    onDismiss: () -> Unit,
    onResolve: (String, String) -> Unit
) {
    var reply by remember(approval.id) { mutableStateOf("") }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(kindTitle(approval.kind), style = MaterialTheme.typography.titleLarge)
            Text(approval.summary.ifBlank { approval.method }, style = MaterialTheme.typography.bodyMedium)
            if (approval.reason.isNotBlank()) {
                Text("原因：${approval.reason}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text("Session: ${approval.threadId}", style = MaterialTheme.typography.labelSmall, fontFamily = FontFamily.Monospace)
            if (approval.turnId.isNotBlank()) {
                Text("Turn: ${approval.turnId}", style = MaterialTheme.typography.labelSmall, fontFamily = FontFamily.Monospace)
            }
            Text("创建时间：${approval.createdAt}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

            if (approval.kind == "userInput") {
                val question = firstQuestionPrompt(approval)
                if (question.isNotBlank()) Text(question, style = MaterialTheme.typography.bodyMedium)
                TextField(
                    value = reply,
                    onValueChange = { reply = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("回复内容") },
                    minLines = 3,
                    enabled = !isResolving
                )
                Button(
                    onClick = { onResolve("answer", reply) },
                    enabled = !isResolving && reply.isNotBlank(),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(if (isResolving) "提交中…" else "提交回复")
                }
            } else {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    effectiveChoices(approval).forEach { choice ->
                        val label = choiceLabel(approval.kind, choice)
                        val destructive = choice == "reject" || choice == "decline" || choice == "cancel"
                        if (destructive) {
                            OutlinedButton(onClick = { onResolve(choice, "") }, enabled = !isResolving) { Text(label) }
                        } else {
                            Button(onClick = { onResolve(choice, "") }, enabled = !isResolving) { Text(label) }
                        }
                    }
                }
            }

            TextButton(onClick = onDismiss, enabled = !isResolving, modifier = Modifier.fillMaxWidth()) {
                Text("关闭")
            }
        }
    }
}

fun kindTitle(kind: String): String = when (kind) {
    "command" -> "命令审批"
    "fileChange" -> "文件变更审批"
    "permissions" -> "权限审批"
    "userInput" -> "需要你的回复"
    else -> "审批"
}

fun effectiveChoices(approval: PendingRequestView): List<String> {
    if (approval.choices.isNotEmpty()) return approval.choices
    return when (approval.kind) {
        "command", "fileChange" -> listOf("accept", "reject")
        "permissions" -> listOf("session", "turn", "decline")
        "userInput" -> listOf("answer")
        else -> listOf("accept", "decline")
    }
}

fun choiceLabel(kind: String, choice: String): String = when (choice) {
    "accept" -> "允许一次"
    "reject", "decline" -> "拒绝"
    "acceptForSession" -> "本会话内允许"
    "cancel" -> "取消"
    "session" -> "授权到会话"
    "turn" -> "仅本轮授权"
    "answer" -> if (kind == "userInput") "回复" else "确认"
    else -> choice
}

private fun firstQuestionPrompt(approval: PendingRequestView): String {
    return approval.params["questions"]
        ?.arrayValue
        ?.firstOrNull()
        ?.objectValue
        ?.let { question ->
            question["question"]?.stringValue
                ?: question["prompt"]?.stringValue
                ?: question["title"]?.stringValue
        }
        .orEmpty()
}
