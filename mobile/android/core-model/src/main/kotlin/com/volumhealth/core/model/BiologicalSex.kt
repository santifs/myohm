package com.volumhealth.core.model

/**
 * Biological sex for physiological considerations (e.g., menstrual cycle tracking)
 */
enum class BiologicalSex {
    FEMALE,
    MALE;

    val displayName: String
        get() = when (this) {
            FEMALE -> "Female"
            MALE -> "Male"
        }

    val spanishDisplayName: String
        get() = when (this) {
            FEMALE -> "Mujer"
            MALE -> "Hombre"
        }

    companion object {
        fun fromString(value: String): BiologicalSex? = when (value.lowercase()) {
            "female" -> FEMALE
            "male" -> MALE
            else -> null
        }
    }
}
