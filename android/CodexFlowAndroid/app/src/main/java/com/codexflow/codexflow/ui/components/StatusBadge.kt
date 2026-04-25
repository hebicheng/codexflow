package com.codexflow.codexflow.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.codexflow.codexflow.data.model.SseConnectionState
import com.codexflow.codexflow.ui.theme.Danger
import com.codexflow.codexflow.ui.theme.Forest
import com.codexflow.codexflow.ui.theme.MutedInk
import com.codexflow.codexflow.ui.theme.SoftBlue
import com.codexflow.codexflow.ui.theme.Warning

@Composable
fun StatusBadge(
    text: String,
    color: Color,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .background(color.copy(alpha = 0.14f), RoundedCornerShape(999.dp))
            .padding(horizontal = 10.dp, vertical = 6.dp)
    ) {
        Text(
            text = text,
            color = color,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold
        )
    }
}

fun sessionStatusLabel(status: String, waiting: Boolean, ended: Boolean): String = when {
    ended -> "已结束"
    waiting -> "待审批"
    status == "active" || status == "inProgress" -> "运行中"
    status == "completed" -> "已完成"
    status == "notLoaded" -> "未接管"
    status == "failed" || status == "systemError" -> "失败"
    status == "idle" -> "空闲"
    status.isBlank() -> "未知"
    else -> status
}

fun sessionStatusColor(status: String, waiting: Boolean, ended: Boolean): Color = when {
    ended -> MutedInk
    waiting -> Warning
    status == "active" || status == "inProgress" -> Forest
    status == "completed" || status == "idle" -> Forest
    status == "notLoaded" -> SoftBlue
    status == "failed" || status == "systemError" -> Danger
    else -> MutedInk
}

fun sseLabel(state: SseConnectionState): String = when (state) {
    SseConnectionState.Connected -> "实时连接中"
    SseConnectionState.Connecting -> "正在连接"
    SseConnectionState.Reconnecting -> "正在重连"
    SseConnectionState.Disconnected -> "已断开"
}

fun sseColor(state: SseConnectionState): Color = when (state) {
    SseConnectionState.Connected -> Forest
    SseConnectionState.Connecting -> SoftBlue
    SseConnectionState.Reconnecting -> Warning
    SseConnectionState.Disconnected -> Danger
}
