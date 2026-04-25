package com.codexflow.codexflow.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Forest = Color(0xFF269458)
val SoftBlue = Color(0xFF3973B5)
val Ember = Color(0xFFE07038)
val Canvas = Color(0xFFF7F7F4)
val Shell = Color(0xFFF0F0EA)
val Ink = Color(0xFF1C2226)
val MutedInk = Color(0xFF666B70)
val Danger = Color(0xFFBA3838)
val Warning = Color(0xFFDB7A2B)

private val LightColors = lightColorScheme(
    primary = Forest,
    onPrimary = Color.White,
    secondary = SoftBlue,
    onSecondary = Color.White,
    tertiary = Ember,
    background = Canvas,
    onBackground = Ink,
    surface = Color.White,
    onSurface = Ink,
    surfaceVariant = Shell,
    onSurfaceVariant = MutedInk,
    error = Danger,
    onError = Color.White
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF5BD08B),
    onPrimary = Color(0xFF08381E),
    secondary = Color(0xFF8AB8EF),
    onSecondary = Color(0xFF072C56),
    tertiary = Color(0xFFFFB088),
    background = Color(0xFF101313),
    onBackground = Color(0xFFE6E8E4),
    surface = Color(0xFF181C1B),
    onSurface = Color(0xFFE6E8E4),
    surfaceVariant = Color(0xFF252A28),
    onSurfaceVariant = Color(0xFFB8BDB8),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005)
)

@Composable
fun CodexFlowTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content
    )
}
