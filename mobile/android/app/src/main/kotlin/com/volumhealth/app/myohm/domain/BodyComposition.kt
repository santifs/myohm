package com.volumhealth.app.myohm.domain

import kotlin.math.pow
import kotlin.math.sqrt

/**
 * Fat-free mass prediction equations used by Myohm.
 *
 * Only equations with published coefficients checked against the original abstracts are
 * included. Each keeps the population it was validated in, so the app can explain why it
 * was chosen and when it should not be used. Mirrors the iOS implementation.
 */
enum class BodyEquation {
    /** Kyle UG et al. Nutrition 2001;17:248–253. doi:10.1016/S0899-9007(00)00553-0 */
    GENEVA,
    /** Matias CN, Campa F et al. Int J Sports Med 2021. doi:10.1055/a-1179-6236 */
    ATHLETES,
    /** Houtkooper LB et al. J Appl Physiol 1992;72:366–373. */
    YOUTH;

    /** Fat-free mass in kg from height (cm), weight (kg), R and Xc at 50 kHz (Ω). */
    fun fatFreeMass(heightCm: Double, weightKg: Double, r: Double, xc: Double, isMale: Boolean): Double {
        val sex = if (isMale) 1.0 else 0.0
        val index = heightCm * heightCm / r
        return when (this) {
            GENEVA -> -4.104 + 0.518 * index + 0.231 * weightKg + 0.130 * xc + 4.229 * sex
            ATHLETES -> -2.261 + 0.327 * index + 0.525 * weightKg + 5.462 * sex
            YOUTH -> 0.61 * index + 0.25 * weightKg + 1.31
        }
    }

    /** Standard error of estimate for fat-free mass in the original abstract (kg), if verified. */
    val standardErrorKg: Double?
        get() = if (this == GENEVA) 1.72 else null

    val shortName: String
        get() = when (this) {
            GENEVA -> "Geneva"
            ATHLETES -> "Matias–Campa"
            YOUTH -> "Houtkooper"
        }

    val citation: String
        get() = when (this) {
            GENEVA -> "Kyle UG, Genton L, Karsegard L, Slosman DO, Pichard C. Single prediction equation for bioelectrical impedance analysis in adults aged 20–94 years. Nutrition 2001;17:248–253."
            ATHLETES -> "Matias CN, Campa F, Santos DA, et al. Fat-free mass bioelectrical impedance analysis predictive equation for athletes using a 4-compartment model. Int J Sports Med 2021;42:27–32."
            YOUTH -> "Houtkooper LB, Going SB, Lohman TG, Roche AF, Van Loan M. Bioelectrical impedance estimation of fat-free body mass in children and youth: a cross-validation study. J Appl Physiol 1992;72:366–373."
        }

    val doi: String
        get() = when (this) {
            GENEVA -> "10.1016/S0899-9007(00)00553-0"
            ATHLETES -> "10.1055/a-1179-6236"
            YOUTH -> "10.1152/jappl.1992.72.1.366"
        }

    val year: Int
        get() = when (this) {
            GENEVA -> 2001
            ATHLETES -> 2021
            YOUTH -> 1992
        }

    /** Validated age range (years), when checked against the abstract. */
    val ageRange: ClosedFloatingPointRange<Double>?
        get() = when (this) {
            GENEVA -> 20.0..94.0
            ATHLETES -> null
            YOUTH -> 10.0..19.0
        }

    /** Validated BMI range, when the study reports one. */
    val bmiRange: ClosedFloatingPointRange<Double>?
        get() = if (this == GENEVA) 17.0..33.8 else null
}

data class BodyInputs(
    val heightCm: Double,
    val weightKg: Double,
    val ageYears: Double,
    val isMale: Boolean,
    val isAthlete: Boolean,
    /** Resistance at 50 kHz (Ω) */
    val r50: Double,
    /** Reactance at 50 kHz (Ω, positive) */
    val xc50: Double
) {
    val bmi: Double get() = weightKg / (heightCm / 100).pow(2)
}

sealed interface EquationSelection {
    data class Equation(val equation: BodyEquation) : EquationSelection
    /** Under 10 years: no validated equation; show phase angle only. */
    data object TooYoung : EquationSelection
    /** BMI above 34: prediction equations are not valid; show water from the spectrum only. */
    data object HighBmi : EquationSelection
}

data class FatEstimate(
    val equation: BodyEquation,
    val fatFreeMassKg: Double,
    val fatMassKg: Double,
    val fatPercent: Double,
    /** Error in fat percentage points derived from the equation's SEE, when known. */
    val fatPercentError: Double?
)

object BodyComposition {
    const val MAX_BMI = 34.0

    fun select(inputs: BodyInputs): EquationSelection = when {
        inputs.ageYears < 10 -> EquationSelection.TooYoung
        inputs.bmi > MAX_BMI -> EquationSelection.HighBmi
        inputs.ageYears < 20 -> EquationSelection.Equation(BodyEquation.YOUTH)
        inputs.isAthlete -> EquationSelection.Equation(BodyEquation.ATHLETES)
        else -> EquationSelection.Equation(BodyEquation.GENEVA)
    }

    fun estimate(inputs: BodyInputs, equation: BodyEquation): FatEstimate {
        val ffm = equation.fatFreeMass(inputs.heightCm, inputs.weightKg, inputs.r50, inputs.xc50, inputs.isMale)
        val fat = inputs.weightKg - ffm
        return FatEstimate(
            equation = equation,
            fatFreeMassKg = ffm,
            fatMassKg = fat,
            fatPercent = fat / inputs.weightKg * 100,
            fatPercentError = equation.standardErrorKg?.let { it / inputs.weightKg * 100 }
        )
    }

    fun estimate(inputs: BodyInputs): FatEstimate? =
        (select(inputs) as? EquationSelection.Equation)?.let { estimate(inputs, it.equation) }
}

/**
 * Body water from the Cole fit, following Moissl et al. Physiol Meas 2006;27:921–933.
 * doi:10.1088/0967-3334/27/9/012
 */
data class BodyWater(val extracellularL: Double, val intracellularL: Double) {
    val totalL: Double get() = extracellularL + intracellularL
    val extracellularRatio: Double get() = extracellularL / totalL
    /** Fat-free mass assuming 73 % hydration. */
    val fatFreeMassKg: Double get() = totalL / 0.73

    companion object {
        fun estimate(heightCm: Double, weightKg: Double, r0: Double, rInf: Double): BodyWater? {
            if (!(r0 > rInf && rInf > 0 && heightCm > 0 && weightKg > 0)) return null
            val bmi = weightKg / (heightCm / 100).pow(2)
            val ri = 1 / (1 / rInf - 1 / r0)
            val base = heightCm * heightCm * sqrt(weightKg)
            val kEcw = 0.188 / bmi + 0.2883
            val kIcw = 5.8758 / bmi + 0.4194
            val ecw = kEcw * (base / r0).pow(2.0 / 3.0)
            val icw = kIcw * (base / ri).pow(2.0 / 3.0)
            return BodyWater(ecw, icw)
        }
    }
}
