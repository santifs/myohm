package com.volumhealth.app.ui.theme

import androidx.compose.ui.graphics.Color

object VolumColors {
    // Primary colors (matching iOS)
    val SystemIndigo = Color(0xFF5856D6)
    val SystemTeal = Color(0xFF30B0C7)
    val SystemMint = Color(0xFF00C7BE)
    val SystemBlue = Color(0xFF007AFF)
    val SystemPurple = Color(0xFFAF52DE)
    val SystemOrange = Color(0xFFFF9500)
    val SystemGreen = Color(0xFF34C759)
    val SystemRed = Color(0xFFFF3B30)

    // Parameter colors (matching iOS)
    val ParameterPrimary = SystemIndigo
    val ParameterSecondary = SystemTeal
    val ParameterTertiary = SystemMint

    // Brand colors
    val BrandPrimary = SystemBlue

    // Accent colors
    val AccentBlue = SystemBlue

    // Surface colors
    val SurfaceDark = Color(0xFF0E1726)
    val SurfaceMedium = Color(0xFF19253A)
    val SurfaceLight = Color(0xFF22324F)

    // Quality indicators (matching iOS)
    val QualityExcellent = Color(0xFF34C759) // Green
    val QualityGood = Color(0xFF00C7BE)      // Mint
    val QualityFair = Color(0xFFFF9500)      // Orange
    val QualityPoor = Color(0xFFFF3B30)      // Red

    // Status colors
    val StatusActive = Color(0xFF34C759)
    val StatusPaused = Color(0xFFFF9500)
    val StatusError = Color(0xFFFF3B30)
    val StatusPending = Color(0xFF007AFF)
}
