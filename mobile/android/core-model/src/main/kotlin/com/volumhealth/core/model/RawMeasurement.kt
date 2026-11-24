package com.volumhealth.core.model

import java.util.UUID
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
/** 
 * Raw measurement persisted before post-processing begins.
 */
data class RawMeasurement(
    val id: String = UUID.randomUUID().toString(),
    val rawData: ImpedanceData,
    val patientSnapshot: PatientSnapshot?,
    val captureTimestamp: Instant,
    var processingState: ProcessingState = ProcessingState.PENDING,
    var results: ColeParameters? = null,
    var processingAttempts: Int = 0,
    var lastProcessingAttempt: Instant? = null,
    var processingError: String? = null,
    val repetitions: List<ImpedanceData>? = null,
    val signalQuality: Float? = null
) {
    val shouldRetry: Boolean
        get() = processingState == ProcessingState.FAILED && processingAttempts < 3

    val ageInMinutes: Double
        get() {
            val duration = Clock.System.now() - captureTimestamp
            return duration.inWholeMinutes.toDouble()
        }
}

enum class ProcessingState {
    PENDING,
    PROCESSING,
    COMPLETED,
    FAILED,
    RETRYING
}
