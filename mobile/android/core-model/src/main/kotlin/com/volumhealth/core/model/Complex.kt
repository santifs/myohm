package com.volumhealth.core.model

import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** Simple complex number representation used by the Cole model calculations. */
data class Complex(
    val real: Float,
    val imaginary: Float
) {
    val magnitude: Float get() = sqrt(real * real + imaginary * imaginary)
    val phase: Float get() = atan2(imaginary, real) * 180f / PI.toFloat()

    operator fun plus(other: Complex) = Complex(real + other.real, imaginary + other.imaginary)
    operator fun minus(other: Complex) = Complex(real - other.real, imaginary - other.imaginary)
    operator fun times(other: Complex) = Complex(
        real * other.real - imaginary * other.imaginary,
        real * other.imaginary + imaginary * other.real
    )

    operator fun div(other: Complex): Complex {
        val denominator = other.real * other.real + other.imaginary * other.imaginary
        return Complex(
            (real * other.real + imaginary * other.imaginary) / denominator,
            (imaginary * other.real - real * other.imaginary) / denominator
        )
    }

    companion object {
        fun fromPolar(magnitude: Float, phaseDegrees: Float): Complex {
            val radians = phaseDegrees * PI.toFloat() / 180f
            return Complex(
                real = magnitude * cos(radians),
                imaginary = magnitude * sin(radians)
            )
        }
    }
}
