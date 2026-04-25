package com.codexflow.codexflow

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.codexflow.codexflow.ui.navigation.AppNavGraph
import com.codexflow.codexflow.ui.theme.CodexFlowTheme

@Composable
fun CodexFlowApp(container: CodexFlowContainer) {
    val lifecycleOwner = LocalLifecycleOwner.current

    DisposableEffect(lifecycleOwner, container) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> container.repository.startRealtime()
                Lifecycle.Event.ON_STOP -> container.repository.stopRealtime()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            container.repository.stopRealtime()
        }
    }

    LaunchedEffect(container) {
        container.repository.refresh()
    }

    CodexFlowTheme {
        AppNavGraph(container = container)
    }
}
