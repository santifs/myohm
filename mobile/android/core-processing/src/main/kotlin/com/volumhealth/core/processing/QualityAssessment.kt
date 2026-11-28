package com.volumhealth.core.processing

import com.volumhealth.core.model.ContactQuality
import com.volumhealth.core.model.ContactStatus
import com.volumhealth.core.model.ConvergenceMetrics
import com.volumhealth.core.model.FrequencyResponseQuality
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.InterferenceLevel
import com.volumhealth.core.model.QualityMetrics
import com.volumhealth.core.model.SignalQuality
import com.volumhealth.core.model.StabilityMetrics
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

@Singleton
class QualityAssessment @Inject constructor() {

    fun assessQuality(data: ImpedanceData): QualityMetrics {
        val contactQuality = assessContactQuality(data)
        val signalQuality = assessSignalQuality(data)
        val stability = assessStability(data)

        val stabilityScore = if (stability.movementDetected) 0.5f else 1.0f
        val overallScore = (
            contactQuality.status.qualityScore * 0.4f +
                signalQuality.qualityScore * 0.3f +
                stabilityScore * 0.3f
            ).coerceIn(0f, 1f)

        return QualityMetrics(
            score = overallScore,
            contactQuality = contactQuality,
            signalQuality = signalQuality,
            convergence = ConvergenceMetrics(
                iterations = 0,
                residualError = null,
                parameterErrors = null,
                converged = false
            ),
            stabilityMetrics = stability
        )
    }

    private fun assessContactQuality(data: ImpedanceData): ContactQuality {
        val magnitudeStd = data.magnitudes.standardDeviation()
        val phaseStd = data.phases.standardDeviation()

        val estimatedElectrodeImpedance = magnitudeStd * 1000f
        val estimatedMismatch = phaseStd * 2f

        return ContactQuality(
            electrodeImpedance = estimatedElectrodeImpedance,
            mismatchPercentage = estimatedMismatch
        )
    }

    private fun assessSignalQuality(data: ImpedanceData): SignalQuality {
        val magnitudes = data.magnitudes
        val phases = data.phases

        val magnitudeStd = magnitudes.standardDeviation()
        val magnitudeMean = magnitudes.average().toFloat().coerceAtLeast(1e-6f)
        val estimatedSnr = 20f * log10((magnitudeMean / (magnitudeStd + 1e-6f)).toDouble()).toFloat()

        val phaseStability = phases.standardDeviation()

        val responseQuality = when {
            phaseStability < 2f && estimatedSnr > 40 -> FrequencyResponseQuality.EXCELLENT
            phaseStability < 5f && estimatedSnr > 30 -> FrequencyResponseQuality.GOOD
            phaseStability < 10f && estimatedSnr > 20 -> FrequencyResponseQuality.FAIR
            else -> FrequencyResponseQuality.POOR
        }

        return SignalQuality(
            snr = estimatedSnr,
            phaseStability = phaseStability,
            frequencyResponse = responseQuality
        )
    }

    private fun assessStability(data: ImpedanceData): StabilityMetrics {
        val quaternionVariance = data.deviceInfo?.quaternionVariance
        val quaternionStability = quaternionVariance?.magnitude ?: 0f
        val movementDetected = quaternionStability > 0.01f

        val magnitudeStd = data.magnitudes.standardDeviation()
        val magnitudeMean = data.magnitudes.average().toFloat().coerceAtLeast(1e-6f)
        val impedanceStability = magnitudeStd / magnitudeMean

        val interferenceLevel = when {
            impedanceStability < 0.02f -> InterferenceLevel.MINIMAL
            impedanceStability < 0.05f -> InterferenceLevel.LOW
            impedanceStability < 0.1f -> InterferenceLevel.MODERATE
            else -> InterferenceLevel.HIGH
        }

        return StabilityMetrics(
            movementDetected = movementDetected,
            quaternionStability = quaternionStability,
            impedanceStability = impedanceStability,
            interferenceLevel = interferenceLevel
        )
    }
}

private fun List<Float>.standardDeviation(): Float {
    if (size < 2) return 0f
    val mean = average().toFloat()
    val variance = fold(0f) { acc, value ->
        val diff = value - mean
        acc + diff * diff
    } / (size - 1)
    return sqrt(max(variance, 0f))
}

private val ContactStatus.qualityScore: Float
    get() = when (this) {
        ContactStatus.EXCELLENT -> 1.0f
        ContactStatus.GOOD -> 0.8f
        ContactStatus.FAIR -> 0.6f
        ContactStatus.POOR -> 0.3f
    }

private val FrequencyResponseQuality.qualityScore: Float
    get() = when (this) {
        FrequencyResponseQuality.EXCELLENT -> 1.0f
        FrequencyResponseQuality.GOOD -> 0.8f
        FrequencyResponseQuality.FAIR -> 0.6f
        FrequencyResponseQuality.POOR -> 0.3f
    }

private val SignalQuality.qualityScore: Float
    get() {
        val snrScore = ((snr - 10f) / 50f).coerceIn(0f, 1f)
        val stabilityScore = (1f - phaseStability / 10f).coerceIn(0f, 1f)
        val responseScore = frequencyResponse.qualityScore
        return (snrScore + stabilityScore + responseScore) / 3f
    }
