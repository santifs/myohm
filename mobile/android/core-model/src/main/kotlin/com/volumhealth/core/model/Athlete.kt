package com.volumhealth.core.model

import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.periodUntil
import kotlinx.datetime.toLocalDateTime
import java.util.UUID

/**
 * Domain model for athlete profiles.
 */
data class Athlete(
    val id: String = UUID.randomUUID().toString(),
    val userId: String? = null,
    val fullName: String,
    val dateOfBirth: LocalDate,
    val dominantLeg: DominantLeg = DominantLeg.RIGHT,
    val biologicalSex: BiologicalSex? = null,
    val medicalHistory: String? = null,
    val medications: String? = null,
    val dietType: String? = null,
    val dailyCalories: Int? = null,
    val allergies: List<String>? = null,
    val usualActivities: List<String>? = null,
    val heightCm: Double? = null,
    val weightKg: Double? = null,
    val rightThighLength: Double? = null,
    val rightThighCircumference: Double? = null,
    val leftThighLength: Double? = null,
    val leftThighCircumference: Double? = null,
    val hasCurrentInjury: Boolean? = null,
    val currentInjuryDetails: String? = null,
    val createdAt: Instant? = null,
    val syncStatus: SyncStatus = SyncStatus.PENDING
) {
    /**
     * Age in years calculated from date of birth.
     */
    val age: Int
        get() {
            val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
            return dateOfBirth.periodUntil(today).years
        }

    /**
     * Age group classification.
     */
    val ageGroup: String
        get() = when {
            age < 18 -> "Pediatric ($age y)"
            age < 65 -> "Adult ($age y)"
            else -> "Senior ($age y)"
        }

    /**
     * Display name for UI.
     */
    val displayName: String
        get() = fullName.trim().ifEmpty { "Unnamed Athlete" }

    /**
     * Check if profile has minimum required data.
     */
    val isComplete: Boolean
        get() = fullName.trim().isNotEmpty()

    companion object {
        val UNKNOWN_DOB: LocalDate = LocalDate(1970, 1, 1)

        /**
         * Create an athlete with only a name, tied to the given Supabase user id.
         * Non-null required fields get sentinel defaults. [userId] must be the
         * current authenticated user's id or the row will be invisible through RLS
         * (INSERT succeeds, SELECT returns nothing).
         */
        fun minimal(name: String, userId: String): Athlete = Athlete(
            fullName = name.trim(),
            userId = userId,
            dateOfBirth = UNKNOWN_DOB,
            dominantLeg = DominantLeg.RIGHT
        )

        fun hasUnknownDob(athlete: Athlete): Boolean = athlete.dateOfBirth == UNKNOWN_DOB
    }
}
