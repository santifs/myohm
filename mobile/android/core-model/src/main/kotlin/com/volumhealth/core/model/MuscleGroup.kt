package com.volumhealth.core.model

/**
 * Muscle groups for bioimpedance measurements.
 * Values must match the Supabase `muscle_group` enum:
 *   quadriceps, hamstring, biceps_brachii, vastus_lateralis, biceps_femoris.
 * Adding a new value here requires a backend migration adding it to the enum.
 */
enum class MuscleGroup(val value: String) {
    QUADRICEPS("quadriceps"),
    HAMSTRING("hamstring"),
    BICEPS_BRACHII("biceps_brachii"),
    VASTUS_LATERALIS("vastus_lateralis"),
    BICEPS_FEMORIS("biceps_femoris");

    val displayName: String
        get() = when (this) {
            QUADRICEPS -> "Cuádriceps"
            HAMSTRING -> "Isquiotibiales"
            BICEPS_BRACHII -> "Bíceps braquial"
            VASTUS_LATERALIS -> "Vasto lateral"
            BICEPS_FEMORIS -> "Bíceps femoral"
        }

    val iconName: String
        get() = when (this) {
            QUADRICEPS, VASTUS_LATERALIS -> "fitness_center"
            HAMSTRING, BICEPS_FEMORIS -> "accessibility_new"
            BICEPS_BRACHII -> "sports_martial_arts"
        }

    val location: String
        get() = when (this) {
            QUADRICEPS -> "Front of thigh"
            HAMSTRING -> "Back of thigh"
            BICEPS_BRACHII -> "Front of upper arm"
            VASTUS_LATERALIS -> "Outer front of thigh"
            BICEPS_FEMORIS -> "Outer back of thigh"
        }

    val spanishDescription: String
        get() = when (this) {
            QUADRICEPS -> "Músculo frontal del muslo"
            HAMSTRING -> "Músculo posterior del muslo"
            BICEPS_BRACHII -> "Músculo frontal del brazo"
            VASTUS_LATERALIS -> "Cabeza lateral del cuádriceps"
            BICEPS_FEMORIS -> "Cabeza lateral del isquiotibial"
        }

    companion object {
        fun fromString(value: String): MuscleGroup? = when (value.lowercase()) {
            "quadriceps" -> QUADRICEPS
            "hamstring" -> HAMSTRING
            "biceps_brachii" -> BICEPS_BRACHII
            "vastus_lateralis" -> VASTUS_LATERALIS
            "biceps_femoris" -> BICEPS_FEMORIS
            else -> null
        }
    }
}
