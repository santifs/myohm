package com.volumhealth.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary = VolumColors.SystemIndigo,
    secondary = VolumColors.SystemTeal,
    tertiary = VolumColors.SystemMint,
    background = VolumColors.SurfaceDark,
    surface = VolumColors.SurfaceMedium,
    surfaceVariant = VolumColors.SurfaceLight,
    onSurface = Color.White
)

private val LightColorScheme = lightColorScheme(
    primary = VolumColors.SystemIndigo,
    secondary = VolumColors.SystemTeal,
    tertiary = VolumColors.SystemMint
)

@Composable
fun VolumHealthTheme(
    useDarkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (useDarkTheme) DarkColorScheme else LightColorScheme

    MaterialTheme(
        colorScheme = colorScheme,
        typography = VolumTypography,
        content = content
    )
}
