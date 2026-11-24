package com.volumhealth.core.database.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import kotlinx.datetime.Instant

/**
 * Room entity for individual muscle measurements.
 * Matches Supabase `measurements` table schema.
 * Replaces the legacy RawMeasurementEntity.
 */
@Entity(
    tableName = "measurements",
    foreignKeys = [
        ForeignKey(
            entity = MeasurementSessionEntity::class,
            parentColumns = ["id"],
            childColumns = ["session_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("session_id")]
)
data class MeasurementEntity(
    @PrimaryKey
    val id: String,

    @ColumnInfo(name = "session_id")
    val sessionId: String?,

    // Muscle context
    @ColumnInfo(name = "muscle_group")
    val muscleGroup: String,

    val side: String,

    @ColumnInfo(name = "perceived_fatigue")
    val perceivedFatigue: Int,

    // Raw data
    @ColumnInfo(name = "raw_data_json")
    val rawDataJson: String,

    @ColumnInfo(name = "measured_at")
    val measuredAt: Instant,

    // Sync fields
    @ColumnInfo(name = "sync_status")
    val syncStatus: String,

    @ColumnInfo(name = "last_sync_attempt")
    val lastSyncAttempt: Instant?,

    @ColumnInfo(name = "sync_error")
    val syncError: String?
)
