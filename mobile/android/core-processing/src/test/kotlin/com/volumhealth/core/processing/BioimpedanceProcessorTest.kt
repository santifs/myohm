package com.volumhealth.core.processing

import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.MeasurementPoint
import kotlin.math.abs
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertTrue
import org.junit.Test

class BioimpedanceProcessorTest {

    private val processor = BioimpedanceProcessor(QualityAssessment())

    @Test
    fun `test Nelder-Mead with synthetic Cole data`() = runTest {
        val trueR0 = 40f
        val trueRinf = 22f
        val trueTau = 3.18e-6f
        val trueAlpha = 0.8f

        val frequencies = listOf(
            1_000f, 1_430f, 2_046f, 2_926f, 4_185f, 5_987f,
            8_563f, 12_247f, 17_518f, 25_056f, 35_839f,
            51_261f, 73_320f, 104_871f, 150_000f
        )

        val points = frequencies.map { freq ->
            val impedance = ColeModel.calculateImpedance(trueR0, trueRinf, trueTau, trueAlpha, freq)
            MeasurementPoint(
                frequency = freq,
                magnitude = impedance.magnitude,
                phase = impedance.phase
            )
        }

        val data = ImpedanceData.fromSingleRepetition(points)

        val result = processor.processComplete(data)

        val reError = abs(result.Re - trueR0) / trueR0 * 100f
        val fcError = abs(result.fc - 50f) / 50f * 100f

        assertTrue("Re error should be < 5% (was $reError)", reError < 5f)
        assertTrue("fc error should be < 20% (was $fcError)", fcError < 20f)
    }
}
