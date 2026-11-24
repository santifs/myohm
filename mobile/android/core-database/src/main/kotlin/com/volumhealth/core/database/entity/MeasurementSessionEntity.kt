package com.volumhealth.core.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import kotlinx.datetime.Instant

/**
 * Room entity for measurement sessions with pre-measurement questionnaire.
 * Matches Supabase `measurement_sessions` table schema.
 */
@Entity(
    tableName = "measurement_sessions",
    foreignKeys = [
        ForeignKey(
            entity = AthleteEntity::class,
            parentColumns = ["id"],
            childColumns = ["athlete_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("athlete_id")]
)
data class MeasurementSessionEntity(
    @PrimaryKey
    val id: String,

    @ColumnInfo(name = "athlete_id")
    val athleteId: String,

    @ColumnInfo(name = "started_at")
    val startedAt: Instant,

    // Pre-measurement questionnaire
    @ColumnInfo(name = "hours_since_activity")
    val hoursSinceActivity: Double?,

    @ColumnInfo(name = "last_activity_type")
    val lastActivityType: String?,

    @ColumnInfo(name = "sleep_hours")
    val sleepHours: Double?,

    @ColumnInfo(name = "general_fatigue")
    val generalFatigue: Int?,

    @ColumnInfo(name = "recent_physio")
    val recentPhysio: Boolean?,

    @ColumnInfo(name = "recent_physio_hours_ago")
    val recentPhysioHoursAgo: Int?,

    @ColumnInfo(name = "new_issues")
    val newIssues: String?,

    @ColumnInfo(name = "menstrual_cycle_phase")
    val menstrualCyclePhase: String?,

    @ColumnInfo(name = "involved_legs")
    val involvedLegs: Boolean? = null,

    @ColumnInfo(name = "leg_muscle_group")
    val legMuscleGroup: String? = null,

    @ColumnInfo(name = "session_type")
    val sessionType: String? = null,

    @ColumnInfo(name = "study_id")
    val studyId: String? = null,

    // Sync fields
    @ColumnInfo(name = "sync_status")
    val syncStatus: String,

    @ColumnInfo(name = "last_sync_attempt")
    val lastSyncAttempt: Instant?,

    @ColumnInfo(name = "sync_error")
    val syncError: String?
)
