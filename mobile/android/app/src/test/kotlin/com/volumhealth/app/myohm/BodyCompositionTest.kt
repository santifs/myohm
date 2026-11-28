package com.volumhealth.app.myohm

import com.volumhealth.app.myohm.domain.BodyComposition
import com.volumhealth.app.myohm.domain.BodyEquation
import com.volumhealth.app.myohm.domain.BodyInputs
import com.volumhealth.app.myohm.domain.BodyWater
import com.volumhealth.app.myohm.domain.ColeFit
import com.volumhealth.app.myohm.domain.EquationSelection
import com.volumhealth.app.myohm.domain.LimbSide
import com.volumhealth.app.myohm.domain.MeasurementKind
import com.volumhealth.app.myohm.domain.MyohmMuscle
import com.volumhealth.app.myohm.domain.SweepAnalysis
import com.volumhealth.app.myohm.domain.SweepPoint
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.MeasurementPoint
import kotlinx.datetime.Clock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.pow
import kotlin.math.sqrt

/** Same cases as the iOS BodyCompositionTests, so both apps compute identical results. */
class BodyCompositionTest {
    // Woman, 34 y, 168 cm, 61.6 kg, R50 580 Ω, Xc50 65 Ω (design example).
    private val ana = BodyInputs(168.0, 61.6, 34.0, isMale = false, isAthlete = false, r50 = 580.0, xc50 = 65.0)

    @Test fun genevaMatchesHandCalculation() {
        val e = BodyComposition.estimate(ana)!!
        assertEquals(BodyEquation.GENEVA, e.equation)
        assertEquals(43.79, e.fatFreeMassKg, 0.01)
        assertEquals(28.9, e.fatPercent, 0.05)
        assertEquals(2.79, e.fatPercentError!!, 0.01)
    }

    @Test fun selectsByPopulation() {
        var p = ana.copy(isAthlete = true)
        assertEquals(EquationSelection.Equation(BodyEquation.ATHLETES), BodyComposition.select(p))
        p = p.copy(ageYears = 15.0)
        assertEquals(EquationSelection.Equation(BodyEquation.YOUTH), BodyComposition.select(p))
        p = p.copy(ageYears = 8.0)
        assertEquals(EquationSelection.TooYoung, BodyComposition.select(p))
        val heavy = ana.copy(weightKg = 100.0)
        assertEquals(EquationSelection.HighBmi, BodyComposition.select(heavy))
        assertNull(BodyComposition.estimate(heavy))
    }

    @Test fun moisslWater() {
        val w = BodyWater.estimate(168.0, 61.6, 700.0, 470.0)!!
        assertEquals(13.8, w.extracellularL, 0.05)
        assertEquals(19.9, w.intracellularL, 0.05)
    }

    @Test fun sweepMedianAndReference() {
        fun point(f: Float, r: Double, x: Double) = MeasurementPoint(
            frequency = f, magnitude = sqrt(r * r + x * x).toFloat(), phase = (-atan2(x, r) * 180 / PI).toFloat()
        )
        val rep = listOf(point(40_000f, 590.0, 64.0), point(60_000f, 570.0, 66.0))
        val outlier = listOf(point(40_000f, 900.0, 10.0), point(60_000f, 900.0, 10.0))
        val sweep = SweepAnalysis.from(ImpedanceData(listOf(rep, rep, outlier), Clock.System.now(), null))!!
        val ref = sweep.atReference!!
        assertEquals(579.0, ref.resistance, 1.0)
        assertEquals(65.1, ref.reactance, 0.5)
        assertTrue(ref.phaseAngle > 6 && ref.phaseAngle < 7)
    }

    @Test fun coleFitRecoversSyntheticParameters() {
        val points = (0 until 48).map { i ->
            val f = 4_000 * (198_000.0 / 4_000).pow(i / 47.0)
            val (re, x) = ColeFit.model(f, 700.0, 470.0, 46_000.0, 0.72)
            SweepPoint(f, sqrt(re * re + x * x), atan2(x, re) * 180 / PI)
        }
        val fit = ColeFit.fit(SweepAnalysis(points, 1))!!
        assertEquals(700.0, fit.r0, 1.0)
        assertEquals(470.0, fit.rInf, 1.0)
        assertEquals(0.0, (fit.fc - 46_000) / 46_000, 0.01)
        assertEquals(0.72, fit.alpha, 0.01)
    }

    @Test fun flagsNonTissuePhase() {
        val good = SweepAnalysis((0 until 48).map { SweepPoint(4_000.0 + it * 4_000, 500.0, 6.0) }, 1)
        val bad = SweepAnalysis((0 until 48).map { SweepPoint(4_000.0 + it * 4_000, 500.0, 100.0) }, 1)
        assertTrue(good.looksLikeTissue)
        assertFalse(bad.looksLikeTissue)
    }

    @Test fun measurementKindRoundTrips() {
        val kinds = listOf(
            MeasurementKind.Muscle(MyohmMuscle.QUADRICEPS, LimbSide.LEFT, 100),
            MeasurementKind.WholeBody(62.4, restCompleted = false)
        )
        kinds.forEach { assertEquals(it, MeasurementKind.decode(it.encode())) }
    }

    @Test fun outlinesMirrorBySide() {
        val front = MyohmMuscle.BICEPS.outlines
        assertEquals(520f - front[0][0].first, front[1][0].first, 0.001f)
        // Back view: traced side is the person's left, so index 0 (right) is the mirrored one.
        val back = MyohmMuscle.TRICEPS.outlines
        assertEquals(118f, back[1][0].first, 0.001f)
    }
}
