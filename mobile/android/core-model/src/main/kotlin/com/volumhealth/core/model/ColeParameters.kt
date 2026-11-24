package com.volumhealth.core.model

import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/**
 * Cole model parameters extracted after fitting the impedance sweep.
 */
data class ColeParameters(
    val Re: Float,
    val Ri: Float,
    val Cm: Float,           // nanoFarads
    val fc: Float,           // kiloHertz
    val alpha: Float,
    val error: Float,
    val processingTier: ProcessingTier,
    val quality: QualityMetrics,
    val patient: PatientSnapshot? = null,
    val measurementType: MeasurementType = MeasurementType.UNKNOWN,
    val rawData: ImpedanceData? = null,
    val timestamp: Instant = Clock.System.now()
) {
    val R0: Float get() = Re
    val Rinf: Float get() = (Re * Ri) / (Re + Ri)
}

enum class ProcessingTier(val displayName: String, val expectedAccuracy: Float) {
    IMMEDIATE("Rápido", 0.85f),
    COMPLETE("Completo", 0.95f)
}

enum class MeasurementType {
    BODY,
    CIRCUIT,
    UNKNOWN
}
