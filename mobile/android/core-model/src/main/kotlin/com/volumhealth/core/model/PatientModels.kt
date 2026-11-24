package com.volumhealth.core.model

import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/** Mutable structure reflecting the editable patient form. */
data class PatientInfo(
    var name: String = "",
    var exerciseName: String = "",
    var age: String = "",
    var gender: Gender = Gender.MALE,
    var height: String = "",  // centimeters
    var weight: String = ""   // kilograms
) {
    val bmi: Float?
        get() {
            val h = height.toFloatOrNull() ?: return null
            val w = weight.toFloatOrNull() ?: return null
            if (h <= 0f) return null
            val meters = h / 100f
            return w / (meters * meters)
        }

    val isValid: Boolean
        get() = name.isNotBlank() &&
            exerciseName.isNotBlank() &&
            age.toIntOrNull() != null &&
            height.toFloatOrNull() != null &&
            weight.toFloatOrNull() != null

    fun snapshot(measurementNumber: Int = 1) = PatientSnapshot(
        name = name,
        exerciseName = exerciseName,
        measurementNumber = measurementNumber,
        age = age.toIntOrNull() ?: 0,
        gender = gender,
        height = height.toFloatOrNull() ?: 0f,
        weight = weight.toFloatOrNull() ?: 0f,
        bmi = bmi ?: 0f,
        timestamp = Clock.System.now()
    )
}

enum class Gender { MALE, FEMALE, OTHER }

data class PatientSnapshot(
    val name: String,
    val exerciseName: String,
    val measurementNumber: Int,
    val age: Int,
    val gender: Gender,
    val height: Float,
    val weight: Float,
    val bmi: Float,
    val timestamp: Instant
)
