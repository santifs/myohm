package com.volumhealth.core.database

import com.volumhealth.core.database.util.Serialization
import com.volumhealth.core.model.ColeParameters
import com.volumhealth.core.model.ContactQuality
import com.volumhealth.core.model.ConvergenceMetrics
import com.volumhealth.core.model.FrequencyResponseQuality
import com.volumhealth.core.model.Gender
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.MeasurementPoint
import com.volumhealth.core.model.MeasurementType
import com.volumhealth.core.model.ParameterErrors
import com.volumhealth.core.model.PatientSnapshot
import com.volumhealth.core.model.ProcessingTier
import com.volumhealth.core.model.QualityMetrics
import com.volumhealth.core.model.SignalQuality
import com.volumhealth.core.model.StabilityMetrics
import com.volumhealth.core.model.InterferenceLevel
import kotlinx.datetime.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class ConvertersTest {

    @Test
    fun impedanceRoundTrip() {
        val data = ImpedanceData(
            repetitions = listOf(
                listOf(
                    MeasurementPoint(frequency = 1000f, magnitude = 40f, phase = -10f),
                    MeasurementPoint(frequency = 2000f, magnitude = 35f, phase = -15f)
                )
            ),
            timestamp = Instant.fromEpochMilliseconds(1234),
            deviceInfo = null
        )

        val encoded = Serialization.encodeImpedance(data)
        val decoded = Serialization.decodeImpedance(encoded)
        assertNotNull(decoded)
        assertEquals(data.measurements.size, decoded.measurements.size)
        assertEquals(data.measurements.first().frequency, decoded.measurements.first().frequency)
    }

    @Test
    fun coleParametersRoundTrip() {
        val quality = QualityMetrics(
            score = 0.9f,
            contactQuality = ContactQuality(electrodeImpedance = 3000f, mismatchPercentage = 3f),
            signalQuality = SignalQuality(
                snr = 45f,
                phaseStability = 1.5f,
                frequencyResponse = FrequencyResponseQuality.EXCELLENT
            ),
            convergence = ConvergenceMetrics(
                iterations = 10,
                residualError = 0.01f,
                parameterErrors = ParameterErrors(1f, 1f, 1f, 1f, 1f),
                converged = true
            ),
            stabilityMetrics = StabilityMetrics(
                movementDetected = false,
                quaternionStability = 0.0f,
                impedanceStability = 0.01f,
                interferenceLevel = InterferenceLevel.MINIMAL
            )
        )
        val parameters = ColeParameters(
            Re = 40f,
            Ri = 25f,
            Cm = 1.2f,
            fc = 50f,
            alpha = 0.8f,
            error = 2f,
            processingTier = ProcessingTier.COMPLETE,
            quality = quality,
            patient = PatientSnapshot(
                name = "Test",
                exerciseName = "Cycle",
                measurementNumber = 1,
                age = 30,
                gender = Gender.MALE,
                height = 180f,
                weight = 80f,
                bmi = 25f,
                timestamp = Instant.fromEpochMilliseconds(100)
            ),
            measurementType = MeasurementType.BODY,
            rawData = null,
            timestamp = Instant.fromEpochMilliseconds(200)
        )

        val encoded = Serialization.encodeColeParameters(parameters)
        val decoded = Serialization.decodeColeParameters(encoded)

        assertNotNull(decoded)
        assertEquals(parameters.Re, decoded!!.Re, 0.0001f)
        assertEquals(parameters.quality.signalQuality.snr, decoded.quality.signalQuality.snr, 0.0001f)
        assertEquals(parameters.patient?.name, decoded.patient?.name)
    }
}
