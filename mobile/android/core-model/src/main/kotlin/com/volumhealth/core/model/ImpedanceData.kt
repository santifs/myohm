package com.volumhealth.core.model

import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import java.util.UUID
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * Core bioimpedance measurement data streamed by the Volum device.
 * Supports multiple repetitions (firmware V2.1 captures 5 sweeps per measurement).
 */
data class ImpedanceData(
    val repetitions: List<List<MeasurementPoint>>,
    val timestamp: Instant,
    val deviceInfo: DeviceInfo?
) {
    /** Convenience accessor referencing the first repetition for backwards compatibility. */
    val measurements: List<MeasurementPoint>
        get() = repetitions.firstOrNull() ?: emptyList()

    val frequencies: List<Float> get() = measurements.map { it.frequency }
    val magnitudes: List<Float> get() = measurements.map { it.magnitude }
    val phases: List<Float> get() = measurements.map { it.phase }
    val complexImpedances: List<Complex> get() = measurements.map { it.complexImpedance }

    companion object {
        fun fromSingleRepetition(
            measurements: List<MeasurementPoint>,
            timestamp: Instant = Clock.System.now(),
            deviceInfo: DeviceInfo? = null
        ): ImpedanceData = ImpedanceData(
            repetitions = listOf(measurements),
            timestamp = timestamp,
            deviceInfo = deviceInfo
        )
    }
}

data class MeasurementPoint(
    val id: String = UUID.randomUUID().toString(),
    val frequency: Float,    // Hz
    val magnitude: Float,    // Ohms
    val phase: Float         // Degrees
) {
    val complexImpedance: Complex
        get() {
            val radians = phase * PI.toFloat() / 180f
            return Complex(
                real = magnitude * cos(radians),
                imaginary = magnitude * sin(radians)
            )
        }
}
