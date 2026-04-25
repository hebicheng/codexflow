package com.codexflow.codexflow.ui.sessions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.codexflow.codexflow.data.model.PlanStep
import com.codexflow.codexflow.ui.components.StatusBadge
import com.codexflow.codexflow.ui.theme.Forest
import com.codexflow.codexflow.ui.theme.MutedInk
import com.codexflow.codexflow.ui.theme.Warning

@Composable
fun PlanSection(explanation: String, plan: List<PlanStep>, modifier: Modifier = Modifier) {
    if (explanation.isBlank() && plan.isEmpty()) return
    Surface(modifier = modifier, shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceVariant) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Plan", style = MaterialTheme.typography.titleSmall)
            if (explanation.isNotBlank()) {
                Text(explanation, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            plan.forEach { step ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StatusBadge(stepStatusLabel(step.status), stepStatusColor(step.status))
                    Text(step.step, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

private fun stepStatusLabel(status: String): String = when (status) {
    "completed" -> "已完成"
    "in_progress" -> "进行中"
    else -> "待处理"
}

private fun stepStatusColor(status: String) = when (status) {
    "completed" -> Forest
    "in_progress" -> Warning
    else -> MutedInk
}
