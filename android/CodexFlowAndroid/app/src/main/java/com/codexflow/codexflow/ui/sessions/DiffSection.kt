package com.codexflow.codexflow.ui.sessions

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.text.selection.SelectionContainer
import com.codexflow.codexflow.ui.theme.Danger
import com.codexflow.codexflow.ui.theme.Forest
import com.codexflow.codexflow.ui.theme.SoftBlue

@Composable
fun DiffSection(diff: String, modifier: Modifier = Modifier) {
    if (diff.isBlank()) return
    Column(modifier = modifier.fillMaxWidth()) {
        Text("Diff", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(bottom = 8.dp))
        SelectionContainer {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .background(MaterialTheme.colorScheme.surfaceVariant, MaterialTheme.shapes.medium)
                    .padding(vertical = 8.dp)
            ) {
                diff.lines().forEach { line ->
                    Text(
                        text = if (line.isEmpty()) " " else line,
                        fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.bodySmall,
                        color = diffLineColor(line),
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(diffLineBackground(line))
                            .padding(horizontal = 10.dp, vertical = 2.dp)
                    )
                }
            }
        }
    }
}

private fun diffLineColor(line: String): Color = when {
    line.startsWith("+") && !line.startsWith("+++") -> Forest
    line.startsWith("-") && !line.startsWith("---") -> Danger
    line.startsWith("@@") || line.startsWith("diff ") || line.startsWith("+++") || line.startsWith("---") -> SoftBlue
    else -> Color.Unspecified
}

private fun diffLineBackground(line: String): Color = when {
    line.startsWith("+") && !line.startsWith("+++") -> Forest.copy(alpha = 0.10f)
    line.startsWith("-") && !line.startsWith("---") -> Danger.copy(alpha = 0.10f)
    line.startsWith("@@") || line.startsWith("diff ") || line.startsWith("+++") || line.startsWith("---") -> SoftBlue.copy(alpha = 0.08f)
    else -> Color.Transparent
}
