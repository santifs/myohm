package com.volumhealth.core.processing

/**
 * Unwraps a sequence of phase values in degrees so consecutive samples differ by
 * less than 180°, eliminating ±360° jumps introduced by atan2.
 *
 * Caller is responsible for sorting the input by frequency (or whatever ordering
 * is meaningful) before passing it in.
 */
fun unwrapPhaseDegrees(phases: List<Float>): List<Float> {
    if (phases.size <= 1) return phases
    val out = ArrayList<Float>(phases.size)
    out.add(phases[0])
    for (i in 1 until phases.size) {
        var diff = phases[i] - out[i - 1]
        while (diff > 180f) diff -= 360f
        while (diff < -180f) diff += 360f
        out.add(out[i - 1] + diff)
    }
    return out
}
