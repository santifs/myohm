package com.volumhealth.app.myohm.domain

import com.volumhealth.core.model.ImpedanceData
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * A single averaged point of a sweep, in the conventions shown to people:
 * phase angle positive, reactance positive for capacitive tissue.
 */
data class SweepPoint(val frequencyHz: Double, val magnitude: Double, val phaseAngle: Double) {
    val resistance: Double get() = magnitude * cos(phaseAngle * PI / 180)
    val reactance: Double get() = magnitude * sin(phaseAngle * PI / 180)
}

/** Summary of a whole sweep: repetitions combined by median and values read at 50 kHz. */
class SweepAnalysis(points: List<SweepPoint>, val repetitions: Int) {
    val points: List<SweepPoint> = points.sortedBy { it.frequencyHz }

    /**
     * Living tissue gives phase angles of a few degrees to a few tens of degrees.
     * Anything else usually means an electrode without contact or a loose cable.
     */
    val looksLikeTissue: Boolean
        get() {
            if (points.isEmpty()) return false
            val inRange = points.count { it.phaseAngle in 0.3..45.0 }
            return inRange.toDouble() / points.size >= 0.9
        }

    /** Value at 50 kHz by linear interpolation on a log-frequency axis. */
    val atReference: SweepPoint? get() = interpolated(REFERENCE_FREQUENCY_HZ)

    fun interpolated(frequency: Double): SweepPoint? {
        if (points.isEmpty()) return null
        val lower = points.lastOrNull { it.frequencyHz <= frequency } ?: return points.first()
        val upper = points.firstOrNull { it.frequencyHz >= frequency } ?: return points.last()
        if (upper.frequencyHz <= lower.frequencyHz) return lower
        val t = (ln(frequency) - ln(lower.frequencyHz)) / (ln(upper.frequencyHz) - ln(lower.frequencyHz))
        val r = lower.resistance + t * (upper.resistance - lower.resistance)
        val x = lower.reactance + t * (upper.reactance - lower.reactance)
        return SweepPoint(frequency, sqrt(r * r + x * x), atan2(x, r) * 180 / PI)
    }

    companion object {
        const val REFERENCE_FREQUENCY_HZ = 50_000.0

        fun from(data: ImpedanceData): SweepAnalysis? {
            val reps = data.repetitions.filter { it.isNotEmpty() }
            if (reps.isEmpty()) return null
            val count = reps.minOf { it.size }
            val combined = mutableListOf<SweepPoint>()
            for (index in 0 until count) {
                val samples = reps.map { it[index] }
                    .filter { it.magnitude.isFinite() && it.phase.isFinite() && it.magnitude > 0 }
                if (samples.isEmpty()) continue
                val re = median(samples.map { it.magnitude * cos(it.phase * PI / 180) })
                val im = median(samples.map { it.magnitude * sin(it.phase * PI / 180) })
                combined += SweepPoint(
                    frequencyHz = samples[0].frequency.toDouble(),
                    magnitude = sqrt(re * re + im * im),
                    phaseAngle = abs(atan2(im, re) * 180 / PI)
                )
            }
            return if (combined.isEmpty()) null else SweepAnalysis(combined, reps.size)
        }

        fun median(values: List<Double>): Double {
            val sorted = values.sorted()
            val mid = sorted.size / 2
            return if (sorted.size % 2 == 0) (sorted[mid - 1] + sorted[mid]) / 2 else sorted[mid]
        }
    }
}

/**
 * Cole model fitted to a sweep: Z(f) = R∞ + (R0 − R∞) / (1 + (j f / fc)^α).
 * Nelder–Mead on (R0, R∞, ln fc, α) minimising relative complex residuals.
 */
data class ColeFit(
    val r0: Double,
    val rInf: Double,
    /** Characteristic frequency (Hz) */
    val fc: Double,
    val alpha: Double,
    /** Root-mean-square relative residual (%) */
    val errorPercent: Double
) {
    companion object {
        /** Reactance returned positive for capacitive tissue. */
        fun model(f: Double, r0: Double, rInf: Double, fc: Double, alpha: Double): Pair<Double, Double> {
            val w = Math.pow(f / fc, alpha)
            val a = alpha * PI / 2
            val dr = 1 + w * cos(a)
            val di = w * sin(a)
            val den = dr * dr + di * di
            return Pair(rInf + (r0 - rInf) * dr / den, (r0 - rInf) * di / den)
        }

        fun fit(sweep: SweepAnalysis): ColeFit? {
            val pts = sweep.points.filter { it.magnitude.isFinite() && it.magnitude > 0 }
            if (pts.size < 8) return null
            val rs = pts.map { it.resistance }
            val rMax = rs.max()
            val rMin = rs.min()
            if (rMax <= 0) return null
            val peak = pts.maxByOrNull { it.reactance } ?: pts[pts.size / 2]

            fun cost(p: DoubleArray): Double {
                val r0 = p[0]; val rInf = p[1]; val fc = Math.exp(p[2]); val alpha = p[3]
                if (!(r0 > rInf && rInf > 0 && alpha > 0.3 && alpha <= 1)) return Double.POSITIVE_INFINITY
                var sum = 0.0
                for (q in pts) {
                    val (re, x) = model(q.frequencyHz, r0, rInf, fc, alpha)
                    val dr = re - q.resistance
                    val dx = x - q.reactance
                    sum += (dr * dr + dx * dx) / (q.magnitude * q.magnitude)
                }
                return sum / pts.size
            }

            var best: Pair<DoubleArray, Double>? = null
            for (alpha0 in listOf(0.65, 0.8, 0.95)) {
                val start = doubleArrayOf(rMax * 1.08, rMin * 0.9, ln(maxOf(peak.frequencyHz, 1_000.0)), alpha0)
                val result = nelderMead(start, doubleArrayOf(rMax * 0.1, rMin * 0.1, 0.5, 0.08), ::cost)
                if (best == null || result.second < best.second) best = result
            }
            val b = best ?: return null
            if (!b.second.isFinite()) return null
            return ColeFit(b.first[0], b.first[1], Math.exp(b.first[2]), b.first[3], sqrt(b.second) * 100)
        }

        internal fun nelderMead(
            start: DoubleArray,
            steps: DoubleArray,
            cost: (DoubleArray) -> Double,
            iterations: Int = 1_500
        ): Pair<DoubleArray, Double> {
            val n = start.size
            var simplex = MutableList(n + 1) { i ->
                start.copyOf().also { if (i > 0) it[i - 1] += steps[i - 1] }
            }
            var values = simplex.map(cost).toMutableList()
            for (iteration in 0 until iterations) {
                val order = values.indices.sortedBy { values[it] }
                simplex = order.map { simplex[it] }.toMutableList()
                values = order.map { values[it] }.toMutableList()
                if (abs(values[n] - values[0]) < 1e-14) break
                val centroid = DoubleArray(n)
                for (v in simplex.dropLast(1)) for (i in 0 until n) centroid[i] += v[i] / n
                val worst = simplex[n]
                fun along(t: Double) = DoubleArray(n) { centroid[it] + t * (worst[it] - centroid[it]) }
                val reflected = along(-1.0)
                val fr = cost(reflected)
                if (fr < values[0]) {
                    val expanded = along(-2.0)
                    val fe = cost(expanded)
                    if (fe < fr) { simplex[n] = expanded; values[n] = fe } else { simplex[n] = reflected; values[n] = fr }
                } else if (fr < values[n - 1]) {
                    simplex[n] = reflected; values[n] = fr
                } else {
                    val contracted = along(if (fr < values[n]) -0.5 else 0.5)
                    val fcn = cost(contracted)
                    if (fcn < minOf(fr, values[n])) {
                        simplex[n] = contracted; values[n] = fcn
                    } else {
                        for (k in 1..n) {
                            simplex[k] = DoubleArray(n) { simplex[0][it] + 0.5 * (simplex[k][it] - simplex[0][it]) }
                            values[k] = cost(simplex[k])
                        }
                    }
                }
            }
            val i = values.indices.minBy { values[it] }
            return Pair(simplex[i], values[i])
        }
    }
}
