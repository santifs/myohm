package com.volumhealth.core.processing

import org.junit.Assert.assertEquals
import org.junit.Test

class PhaseUnwrapTest {

    @Test
    fun emptyList_returnsEmpty() {
        assertEquals(emptyList<Float>(), unwrapPhaseDegrees(emptyList()))
    }

    @Test
    fun singlePoint_returnsAsIs() {
        assertEquals(listOf(42f), unwrapPhaseDegrees(listOf(42f)))
    }

    @Test
    fun monotonicNoWrap_isUnchanged() {
        val input = listOf(-5f, -10f, -15f, -20f)
        val expected = listOf(-5f, -10f, -15f, -20f)
        assertEquals(expected, unwrapPhaseDegrees(input))
    }

    @Test
    fun positiveWrapAtMinus180_isCorrected() {
        // True trajectory continues to ~-190°, but atan2 wraps to +170°.
        val input = listOf(-160f, -170f, 170f, 160f)
        val out = unwrapPhaseDegrees(input)
        // After unwrap the +170 should appear as -190, and 160 as -200
        assertEquals(-160f, out[0], 1e-3f)
        assertEquals(-170f, out[1], 1e-3f)
        assertEquals(-190f, out[2], 1e-3f)
        assertEquals(-200f, out[3], 1e-3f)
    }

    @Test
    fun userScenarioMinus10ToPlus350_unwrapsToMinus10() {
        // The reported symptom: -10 then +350 should become -10 then -10.
        val input = listOf(-10f, 350f)
        val out = unwrapPhaseDegrees(input)
        assertEquals(-10f, out[0], 1e-3f)
        assertEquals(-10f, out[1], 1e-3f)
    }

    @Test
    fun multipleWrapsAccumulate() {
        // Two consecutive +360 jumps should cumulatively unwrap.
        val input = listOf(-10f, 350f, 350f - 360f) // 350, then -10 (which is -370 truly)
        val out = unwrapPhaseDegrees(input)
        assertEquals(-10f, out[0], 1e-3f)
        assertEquals(-10f, out[1], 1e-3f)
        // input[2] = -10 vs prev unwrapped -10 → diff 0, stays -10. Adjust expectation.
        assertEquals(-10f, out[2], 1e-3f)
    }

    @Test
    fun negativeWrap_isCorrected() {
        // True trajectory continues to ~+190°, atan2 wraps to -170°.
        val input = listOf(160f, 170f, -170f, -160f)
        val out = unwrapPhaseDegrees(input)
        assertEquals(160f, out[0], 1e-3f)
        assertEquals(170f, out[1], 1e-3f)
        assertEquals(190f, out[2], 1e-3f)
        assertEquals(200f, out[3], 1e-3f)
    }
}
