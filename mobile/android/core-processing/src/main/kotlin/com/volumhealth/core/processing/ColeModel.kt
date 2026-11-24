package com.volumhealth.core.processing

import com.volumhealth.core.model.Complex
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.sin

/** Utility helpers for evaluating the Cole impedance model. */
object ColeModel {

    /**
     * Evaluate the Cole equation Z(jω) = Rinf + (R0 - Rinf) / (1 + (jωτ)^α)
     * and return the complex impedance at [frequency] Hz.
     */
    fun calculateImpedance(
        r0: Float,
        rinf: Float,
        tau: Float,
        alpha: Float,
        frequency: Float
    ): Complex {
        if (r0.isNaN() || rinf.isNaN() || tau <= 0f || alpha <= 0f || frequency <= 0f) {
            return Complex(r0, 0f)
        }

        val omega = 2 * PI.toFloat() * frequency
        val jOmegaTau = max(omega * tau, 1e-12f)

        val logJOmegaTau = ln(jOmegaTau)
        val alphaLogTerm = alpha * logJOmegaTau

        val powerMagnitude = exp(alphaLogTerm)
        val powerPhase = alpha * PI.toFloat() / 2f

        val powerReal = powerMagnitude * cos(powerPhase)
        val powerImag = powerMagnitude * sin(powerPhase)

        val denomReal = 1f + powerReal
        val denomImag = powerImag
        val denomMagSq = denomReal * denomReal + denomImag * denomImag

        if (denomMagSq <= 1e-20f) {
            return Complex(r0, 0f)
        }

        val numerator = r0 - rinf
        val fractionReal = numerator * denomReal / denomMagSq
        val fractionImag = -numerator * denomImag / denomMagSq

        return Complex(
            real = rinf + fractionReal,
            imaginary = fractionImag
        )
    }
}
