package com.codexflow.codexflow.data.model

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.serialization.Serializable

@Serializable
data class SessionListEnvelope(
    val data: List<SessionSummary> = emptyList()
)

@Serializable
data class SessionSummary(
    val id: String = "",
    val name: String = "",
    val preview: String = "",
    val cwd: String = "",
    val source: String = "",
    val status: String = "",
    val activeFlags: List<String> = emptyList(),
    val loaded: Boolean = false,
    val updatedAt: Long = 0,
    val createdAt: Long = 0,
    val modelProvider: String = "",
    val branch: String = "",
    val pendingApprovals: Int = 0,
    val lastTurnId: String = "",
    val lastTurnStatus: String = "",
    val agentNickname: String = "",
    val agentRole: String = "",
    val ended: Boolean = false
) {
    val displayName: String
        get() = normalizedTitle(name)
            ?: normalizedTitle(agentNickname)
            ?: cwd.trim().substringAfterLast('/').takeIf { it.isNotBlank() }
            ?: previewSummary.takeIf { it.isNotBlank() }?.take(32)
            ?: "Session ${id.take(8)}"

    val previewSummary: String
        get() = preview
            .lineSequence()
            .map { it.trim().replace("\t", " ") }
            .firstOrNull { it.isNotBlank() }
            .orEmpty()

    val previewExcerpt: String
        get() = preview
            .splitToSequence(Regex("\\s+"))
            .filter { it.isNotBlank() }
            .joinToString(" ")
            .headTailTruncated()

    val updatedAtDisplay: String
        get() = formatEpochSeconds(updatedAt)

    val hasWaitingState: Boolean
        get() = activeFlags.contains("waitingOnApproval") || activeFlags.contains("waitingOnUserInput")

    val isActive: Boolean
        get() = status == "active"

    val isRunningTurn: Boolean
        get() = lastTurnStatus == "inProgress"

    private fun normalizedTitle(value: String): String? = value.trim().takeIf { it.isNotEmpty() }
}

@Serializable
data class SessionDetail(
    val summary: SessionSummary = SessionSummary(),
    val turns: List<TurnDetail> = emptyList()
)

@Serializable
data class TurnDetail(
    val id: String = "",
    val status: String = "",
    val startedAt: Long = 0,
    val completedAt: Long = 0,
    val durationMs: Long = 0,
    val error: String = "",
    val diff: String = "",
    val planExplanation: String = "",
    val plan: List<PlanStep> = emptyList(),
    val items: List<TurnItem> = emptyList()
)

@Serializable
data class PlanStep(
    val step: String = "",
    val status: String = ""
)

@Serializable
data class TurnItem(
    val id: String = "",
    val type: String = "",
    val title: String = "",
    val body: String = "",
    val status: String = "",
    val auxiliary: String = "",
    val metadata: Map<String, String> = emptyMap()
)

fun String.headTailTruncated(maxLength: Int = 220, head: Int = 140, tail: Int = 72): String {
    val trimmed = trim()
    if (trimmed.length <= maxLength) return trimmed
    if (head <= 0 || tail <= 0 || head + tail >= trimmed.length) return trimmed
    return trimmed.take(head) + " ... " + trimmed.takeLast(tail)
}

fun formatEpochSeconds(timestamp: Long): String {
    if (timestamp <= 0) return "未知"
    val dateTime = Instant.ofEpochSecond(timestamp).atZone(ZoneId.systemDefault())
    val now = Instant.now().atZone(ZoneId.systemDefault())
    val formatter = when {
        dateTime.toLocalDate() == now.toLocalDate() ->
            DateTimeFormatter.ofPattern("今天 HH:mm", Locale.CHINA)
        dateTime.toLocalDate() == now.toLocalDate().minusDays(1) ->
            DateTimeFormatter.ofPattern("昨天 HH:mm", Locale.CHINA)
        dateTime.year == now.year ->
            DateTimeFormatter.ofPattern("MM-dd HH:mm", Locale.CHINA)
        else ->
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm", Locale.CHINA)
    }
    return dateTime.format(formatter)
}
