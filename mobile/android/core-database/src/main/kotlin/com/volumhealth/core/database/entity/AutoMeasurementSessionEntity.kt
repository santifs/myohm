package com.volumhealth.core.database.entity

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.volumhealth.core.model.SessionStatus
import com.volumhealth.core.model.SessionType
import kotlinx.datetime.Instant

/**
 * Room entity for automatic measurement sessions.
 */
@Entity(tableName = "auto_measurement_sessions")
data class AutoMeasurementSessionEntity(
    @PrimaryKey
    val id: String,
    val name: String,
    val intervalMinutes: Int,
    val sessionType: SessionType,
    val startTime: Instant,
    val endTime: Instant?,
    val status: SessionStatus,
    val totalMeasurements: Int,
    val successfulMeasurements: Int,
    val failedMeasurements: Int,
    val lastMeasurementTime: Instant?,
    val nextMeasurementTime: Instant?,
    val patientName: String?,
    val notes: String?
)
