package com.volumhealth.core.model

/**
 * Menstrual cycle phase for female athletes (affects recovery).
 * Different phases affect fluid retention and can impact bioimpedance measurements.
 */
enum class MenstrualCyclePhase {
    MENSTRUATION,
    FOLLICULAR,
    OVULATION,
    LUTEAL,
    UNKNOWN;

    val displayName: String
        get() = when (this) {
            MENSTRUATION -> "Menstruation"
            FOLLICULAR -> "Follicular"
            OVULATION -> "Ovulation"
            LUTEAL -> "Luteal"
            UNKNOWN -> "Unknown"
        }

    val spanishDisplayName: String
        get() = when (this) {
            MENSTRUATION -> "Menstruación"
            FOLLICULAR -> "Folicular"
            OVULATION -> "Ovulación"
            LUTEAL -> "Lútea"
            UNKNOWN -> "No lo sé"
        }

    val description: String
        get() = when (this) {
            MENSTRUATION -> "Days 1-5: Period"
            FOLLICULAR -> "Days 6-14: Pre-ovulation"
            OVULATION -> "Days 14-16: Ovulation"
            LUTEAL -> "Days 17-28: Post-ovulation"
            UNKNOWN -> "Not sure"
        }

    val spanishDescription: String
        get() = when (this) {
            MENSTRUATION -> "Días 1-5: Menstruación"
            FOLLICULAR -> "Días 6-14: Pre-ovulación"
            OVULATION -> "Días 14-16: Ovulación"
            LUTEAL -> "Días 17-28: Post-ovulación"
            UNKNOWN -> "No estoy segura"
        }

    companion object {
        fun fromString(value: String): MenstrualCyclePhase = when (value.lowercase()) {
            "menstruation" -> MENSTRUATION
            "follicular" -> FOLLICULAR
            "ovulation" -> OVULATION
            "luteal" -> LUTEAL
            else -> UNKNOWN
        }
    }
}
