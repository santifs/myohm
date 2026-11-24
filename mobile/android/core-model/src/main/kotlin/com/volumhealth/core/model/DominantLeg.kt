package com.volumhealth.core.model

/**
 * Dominant leg for bilateral comparisons.
 */
enum class DominantLeg {
    RIGHT,
    LEFT,
    AMBIDEXTROUS;

    val displayName: String
        get() = when (this) {
            RIGHT -> "Right"
            LEFT -> "Left"
            AMBIDEXTROUS -> "Both"
        }

    val spanishDisplayName: String
        get() = when (this) {
            RIGHT -> "Derecha"
            LEFT -> "Izquierda"
            AMBIDEXTROUS -> "Ambas"
        }

    val shortName: String
        get() = when (this) {
            RIGHT -> "R"
            LEFT -> "L"
            AMBIDEXTROUS -> "A"
        }

    companion object {
        fun fromString(value: String): DominantLeg = when (value.lowercase()) {
            "right" -> RIGHT
            "left" -> LEFT
            "ambidextrous" -> AMBIDEXTROUS
            else -> RIGHT
        }
    }
}
