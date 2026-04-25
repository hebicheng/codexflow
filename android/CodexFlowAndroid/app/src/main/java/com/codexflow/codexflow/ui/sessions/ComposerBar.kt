package com.codexflow.codexflow.ui.sessions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun ComposerBar(
    isSteering: Boolean,
    busy: Boolean,
    onSubmit: (String) -> Unit,
    onInterrupt: () -> Unit,
    modifier: Modifier = Modifier
) {
    var prompt by remember { mutableStateOf("") }
    Surface(modifier = modifier.fillMaxWidth(), tonalElevation = 4.dp) {
        Column(
            modifier = Modifier.navigationBarsPadding().padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            TextField(
                value = prompt,
                onValueChange = { prompt = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text(if (isSteering) "补充方向或约束…" else "输入下一步 prompt…") },
                minLines = 2,
                maxLines = 5,
                enabled = !busy
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = {
                        val text = prompt.trim()
                        if (text.isNotEmpty()) {
                            onSubmit(text)
                            prompt = ""
                        }
                    },
                    enabled = !busy && prompt.isNotBlank(),
                    modifier = Modifier.weight(1f)
                ) {
                    Text(if (busy) "发送中…" else if (isSteering) "Steer 当前 turn" else "继续下一步")
                }
                if (isSteering) {
                    OutlinedButton(onClick = onInterrupt, enabled = !busy) {
                        Text("Interrupt")
                    }
                }
            }
        }
    }
}
