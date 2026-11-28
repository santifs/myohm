package com.volumhealth.core.model

/** Quality assessment metrics computed after processing. */
data class QualityMetrics(
    val score: Float,
    val contactQuality: ContactQuality,
    val signalQuality: SignalQuality,
    val convergence: ConvergenceMetrics,
    val stabilityMetrics: StabilityMetrics
)

data class ContactQuality(
    val electrodeImpedance: Float,
    val mismatchPercentage: Float
) {
    val status: ContactStatus = when {
        electrodeImpedance < 5_000 && mismatchPercentage < 5 -> ContactStatus.EXCELLENT
        electrodeImpedance < 10_000 && mismatchPercentage < 10 -> ContactStatus.GOOD
        electrodeImpedance < 20_000 && mismatchPercentage < 15 -> ContactStatus.FAIR
        else -> ContactStatus.POOR
    }
}

enum class ContactStatus { EXCELLENT, GOOD, FAIR, POOR }

data class SignalQuality(
    val snr: Float,
    val phaseStability: Float,
    val frequencyResponse: FrequencyResponseQuality
)

enum class FrequencyResponseQuality { EXCELLENT, GOOD, FAIR, POOR }

data class ConvergenceMetrics(
    val iterations: Int,
    val residualError: Float?,
    val parameterErrors: ParameterErrors?,
    val converged: Boolean
)

data class ParameterErrors(
    val reError: Float,
    val riError: Float,
    val cmError: Float,
    val fcError: Float,
    val alphaError: Float
)

data class StabilityMetrics(
    val movementDetected: Boolean,
    val quaternionStability: Float,
    val impedanceStability: Float,
    val interferenceLevel: InterferenceLevel
)

enum class InterferenceLevel { MINIMAL, LOW, MODERATE, HIGH }
