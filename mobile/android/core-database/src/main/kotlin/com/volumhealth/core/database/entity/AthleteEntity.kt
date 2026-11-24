package com.volumhealth.core.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate

/**
 * Room entity for athlete profiles.
 * Matches Supabase `athletes` table schema.
 */
@Entity(tableName = "athletes")
data class AthleteEntity(
    @PrimaryKey
    val id: String,

    @ColumnInfo(name = "user_id")
    val userId: String?,

    @ColumnInfo(name = "full_name")
    val fullName: String,

    @ColumnInfo(name = "date_of_birth")
    val dateOfBirth: LocalDate,

    @ColumnInfo(name = "dominant_leg")
    val dominantLeg: String,

    @ColumnInfo(name = "biological_sex")
    val biologicalSex: String?,

    @ColumnInfo(name = "medical_history")
    val medicalHistory: String?,

    val medications: String?,

    @ColumnInfo(name = "diet_type")
    val dietType: String?,

    @ColumnInfo(name = "daily_calories")
    val dailyCalories: Int?,

    @ColumnInfo(name = "allergies_json")
    val allergiesJson: String?,

    @ColumnInfo(name = "usual_activities_json")
    val usualActivitiesJson: String?,

    @ColumnInfo(name = "height_cm")
    val heightCm: Double? = null,

    @ColumnInfo(name = "weight_kg")
    val weightKg: Double? = null,

    @ColumnInfo(name = "right_thigh_length")
    val rightThighLength: Double? = null,

    @ColumnInfo(name = "right_thigh_circumference")
    val rightThighCircumference: Double? = null,

    @ColumnInfo(name = "left_thigh_length")
    val leftThighLength: Double? = null,

    @ColumnInfo(name = "left_thigh_circumference")
    val leftThighCircumference: Double? = null,

    @ColumnInfo(name = "has_current_injury")
    val hasCurrentInjury: Boolean? = null,

    @ColumnInfo(name = "current_injury_details")
    val currentInjuryDetails: String? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: Instant,

    @ColumnInfo(name = "updated_at")
    val updatedAt: Instant,

    // Sync fields
    @ColumnInfo(name = "sync_status")
    val syncStatus: String,

    @ColumnInfo(name = "last_sync_attempt")
    val lastSyncAttempt: Instant?,

    @ColumnInfo(name = "sync_error")
    val syncError: String?
)
