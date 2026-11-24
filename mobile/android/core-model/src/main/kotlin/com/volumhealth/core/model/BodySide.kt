package com.volumhealth.core.model

/**
 * Side of the body for bilateral measurements.
 * Used to identify which side (left or right) is being measured.
 */
enum class BodySide(val value: String) {
    LEFT("left"),
    RIGHT("right");

    /**
     * Display name in Spanish
     */
    val displayName: String
        get() = when (this) {
            LEFT -> "Izquierdo"
            RIGHT -> "Derecho"
        }

    /**
     * Short name for compact display (Spanish abbreviation)
     */
    val shortName: String
        get() = when (this) {
            LEFT -> "I"
            RIGHT -> "D"
        }

    /**
     * Get the opposite side
     */
    val opposite: BodySide
        get() = when (this) {
            LEFT -> RIGHT
            RIGHT -> LEFT
        }

    companion object {
        /**
         * Parse a string value to BodySide
         * @param value The string value to parse (case-insensitive)
         * @return The matching BodySide or null if not found
         */
        fun fromString(value: String): BodySide? = when (value.lowercase()) {
            "left" -> LEFT
            "right" -> RIGHT
            else -> null
        }
    }
}
