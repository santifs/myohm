package com.volumhealth.core.model

import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import java.util.UUID
import kotlin.time.Duration

/**
 * Automatic measurement session for unattended periodic measurements
 *
 * Use cases: Sports events, long-term monitoring, research studies
 */
data class AutoMeasurementSession(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val intervalMinutes: Int,
    val sessionType: SessionType,
    val startTime: Instant,
    var endTime: Instant? = null,
    var status: SessionStatus = SessionStatus.SCHEDULED,
    var totalMeasurements: Int = 0,
    var successfulMeasurements: Int = 0,
    var failedMeasurements: Int = 0,
    var lastMeasurementTime: Instant? = null,
    var nextMeasurementTime: Instant? = null,
    val patientName: String? = null,
    val notes: String? = null
) {
    val duration: Duration
        get() = (endTime ?: Clock.System.now()) - startTime

    val successRate: Double
        get() = if (totalMeasurements > 0) {
            successfulMeasurements.toDouble() / totalMeasurements * 100
        } else 0.0

    val canStart: Boolean get() = status == SessionStatus.SCHEDULED || status == SessionStatus.PAUSED
    val canPause: Boolean get() = status == SessionStatus.ACTIVE
    val canResume: Boolean get() = status == SessionStatus.PAUSED
    val canStop: Boolean get() = status == SessionStatus.ACTIVE || status == SessionStatus.PAUSED

    fun recordSuccess() {
        totalMeasurements++
        successfulMeasurements++
        lastMeasurementTime = Clock.System.now()
    }

    fun recordFailure() {
        totalMeasurements++
        failedMeasurements++
        lastMeasurementTime = Clock.System.now()
    }
}

enum class SessionStatus {
    SCHEDULED,   // Planned but not started
    ACTIVE,      // Currently running
    PAUSED,      // Temporarily paused
    COMPLETED,   // Finished normally
    CANCELLED,   // Manually stopped
    ERROR        // Stopped due to error
}

enum class SessionType(val displayName: String) {
    SPORTS("Sports Activity"),
    RECOVERY("Recovery Monitoring"),
    TRAINING("Training Session"),
    CLINICAL("Clinical Monitoring"),
    RESEARCH("Research Study"),
    CUSTOM("Custom Session")
}
