package com.volumhealth.core.database.entity

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.volumhealth.core.model.ProcessingState
import kotlinx.datetime.Instant

@Entity(tableName = "raw_measurements")
data class RawMeasurementEntity(
    @PrimaryKey val id: String,
    val rawDataJson: String,
    val patientSnapshotJson: String?,
    val captureTimestamp: Instant,
    val processingState: ProcessingState,
    val resultsJson: String?,
    val processingAttempts: Int,
    val lastProcessingAttempt: Instant?,
    val processingError: String?,
    val signalQuality: Float?
)
