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
    YOUTH,
    /**
     * Whole spectrum: Moissl ECW/ICW from the Cole fit, then the Chamney three-compartment model.
     * Chamney PW et al. Am J Clin Nutr 2007;85:80–89. doi:10.1093/ajcn/85.1.80
     */
    SPECTROSCOPY;

    /** True when the method needs R0 and R∞ from the Cole fit instead of R and Xc at 50 kHz. */
    val usesSpectrum: Boolean get() = this == SPECTROSCOPY

    /** Fat-free mass in kg from height (cm), weight (kg), R and Xc at 50 kHz (Ω); null for the spectrum model. */
    fun fatFreeMass(heightCm: Double, weightKg: Double, r: Double, xc: Double, isMale: Boolean): Double? {
        val sex = if (isMale) 1.0 else 0.0
        val index = heightCm * heightCm / r
        return when (this) {
            SPECTROSCOPY -> null
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
            SPECTROSCOPY -> "Moissl–Chamney"
        }

    val citation: String
        get() = when (this) {
            GENEVA -> "Kyle UG, Genton L, Karsegard L, Slosman DO, Pichard C. Single prediction equation for bioelectrical impedance analysis in adults aged 20–94 years. Nutrition 2001;17:248–253."
            ATHLETES -> "Matias CN, Campa F, Santos DA, et al. Fat-free mass bioelectrical impedance analysis predictive equation for athletes using a 4-compartment model. Int J Sports Med 2021;42:27–32."
            YOUTH -> "Houtkooper LB, Going SB, Lohman TG, Roche AF, Van Loan M. Bioelectrical impedance estimation of fat-free body mass in children and youth: a cross-validation study. J Appl Physiol 1992;72:366–373."
            SPECTROSCOPY -> "Chamney PW, Wabel P, Moissl UM, et al. A whole-body model to distinguish excess fluid from the hydration of major body tissues. Am J Clin Nutr 2007;85:80–89. Moissl UM, Wabel P, Chamney PW, et al. Body fluid volume determination via body composition spectroscopy in health and disease. Physiol Meas 2006;27:921–933."
        }

    val doi: String
        get() = when (this) {
            GENEVA -> "10.1016/S0899-9007(00)00553-0"
            ATHLETES -> "10.1055/a-1179-6236"
            YOUTH -> "10.1152/jappl.1992.72.1.366"
            SPECTROSCOPY -> "10.1093/ajcn/85.1.80"
        }

    val year: Int
        get() = when (this) {
            GENEVA -> 2001
            ATHLETES -> 2021
            YOUTH -> 1992
            SPECTROSCOPY -> 2007
        }

    /** Validated age range (years), when checked against the abstract. */
    val ageRange: ClosedFloatingPointRange<Double>?
        get() = when (this) {
            GENEVA -> 20.0..94.0
            ATHLETES -> null
            YOUTH -> 10.0..19.0
            // Healthy controls of Chamney 2007, Table 1.
            SPECTROSCOPY -> 21.0..68.0
        }

    /** Validated BMI range, when the study reports one. */
    val bmiRange: ClosedFloatingPointRange<Double>?
        get() = when (this) {
            GENEVA -> 17.0..33.8
            SPECTROSCOPY -> 17.5..36.1
            else -> null
        }
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
    val xc50: Double,
    /** Resistance at zero and infinite frequency from the Cole fit (Ω), once available. */
    val r0: Double? = null,
    val rInf: Double? = null
) {
    val bmi: Double get() = weightKg / (heightCm / 100).pow(2)
}

sealed interface EquationSelection {
    val equation: BodyEquation? get() = (this as? Equation)?.equation

    data class Equation(override val equation: BodyEquation) : EquationSelection
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
    val fatPercentError: Double?,
    /** Spectrum model only: the three compartments and the water they come from. */
    val tissues: ChamneyTissues? = null
)

/**
 * Three-compartment model of Chamney et al. Am J Clin Nutr 2007;85:80–89, equations 2–5.
 *
 * Body weight is split into normally hydrated lean tissue, normally hydrated adipose tissue
 * and excess fluid, using fixed tissue hydrations derived against DXA. Fat is 75.3 % of the
 * adipose tissue. Water from the Cole fit (litres) is converted to kg with the density of body
 * water at 36 °C, 0.99371 kg/L, as in the paper.
 */
data class ChamneyTissues(val water: BodyWater, val weightKg: Double) {
    val excessFluidKg: Double
    val leanTissueKg: Double
    val adiposeTissueKg: Double
    val fatMassKg: Double get() = 0.753 * adiposeTissueKg

    init {
        val ecw = water.extracellularL * WATER_DENSITY
        val icw = water.intracellularL * WATER_DENSITY
        excessFluidKg = 1.136 * ecw - 0.430 * icw - 0.114 * weightKg
        leanTissueKg = 2.725 * icw + 0.191 * excessFluidKg - 0.191 * weightKg
        adiposeTissueKg = weightKg - excessFluidKg - leanTissueKg
    }

    /**
     * Excess fluid beyond this (either sign) in a person who should be healthy usually means a
     * poor spectrum, for example R∞ extrapolated from a sweep that stops at 198 kHz.
     * App limit, not a published reference range.
     */
    val excessFluidIsUnusual: Boolean get() = kotlin.math.abs(excessFluidKg) > EXCESS_FLUID_ALERT_KG

    companion object {
        const val WATER_DENSITY = 0.99371
        const val EXCESS_FLUID_ALERT_KG = 2.0
    }
}

/**
 * Sanity gates for a whole-body (wrist–ankle) reading before any composition is computed.
 *
 * Deliberately wide app limits, not published reference ranges: adult NHANES Xitron data
 * (R0 ≈ 600–700 Ω) and phase-angle norms (≈ 5–7°) sit well inside them. Values outside
 * mean a loose cable or an electrode without contact, and a regression fed with them
 * returns nonsense (for example negative body fat).
 */
object WholeBodySignal {
    val resistance = 250.0..1100.0
    val reactance = 15.0..130.0
    val phaseAngle = 2.0..14.0

    fun isPlausible(r50: Double, xc50: Double): Boolean {
        val phase = Math.toDegrees(kotlin.math.atan2(xc50, r50))
        return r50 in resistance && xc50 in reactance && phase in phaseAngle
    }
}

object BodyComposition {
    const val MAX_BMI = 34.0
    /** Fat percentages outside this range are reported as not computable. */
    val plausibleFatPercent = 3.0..65.0

    fun select(inputs: BodyInputs): EquationSelection = when {
        inputs.ageYears < 10 -> EquationSelection.TooYoung
        inputs.bmi > MAX_BMI -> EquationSelection.HighBmi
        inputs.ageYears < 20 -> EquationSelection.Equation(BodyEquation.YOUTH)
        inputs.isAthlete -> EquationSelection.Equation(BodyEquation.ATHLETES)
        else -> EquationSelection.Equation(BodyEquation.GENEVA)
    }

    /** Raw estimate without plausibility gates; null only when the spectrum model has no Cole fit yet. */
    fun estimate(inputs: BodyInputs, equation: BodyEquation): FatEstimate? {
        if (equation.usesSpectrum) {
            val r0 = inputs.r0 ?: return null
            val rInf = inputs.rInf ?: return null
            val water = BodyWater.estimate(inputs.heightCm, inputs.weightKg, r0, rInf) ?: return null
            val tissues = ChamneyTissues(water, inputs.weightKg)
            val fatKg = tissues.fatMassKg
            return FatEstimate(equation, inputs.weightKg - fatKg, fatKg, fatKg / inputs.weightKg * 100, null, tissues)
        }
        val ffm = equation.fatFreeMass(inputs.heightCm, inputs.weightKg, inputs.r50, inputs.xc50, inputs.isMale) ?: return null
        val fat = inputs.weightKg - ffm
        return FatEstimate(
            equation = equation,
            fatFreeMassKg = ffm,
            fatMassKg = fat,
            fatPercent = fat / inputs.weightKg * 100,
            fatPercentError = equation.standardErrorKg?.let { it / inputs.weightKg * 100 }
        )
    }

    /** Automatic choice, or null when the population or the signal does not allow one. */
    fun estimate(inputs: BodyInputs): FatEstimate? =
        select(inputs).equation?.let { checkedEstimate(inputs, it) }

    /** Estimate with a given equation, or null when the reading or the result is implausible. */
    fun checkedEstimate(inputs: BodyInputs, equation: BodyEquation): FatEstimate? {
        if (!WholeBodySignal.isPlausible(inputs.r50, inputs.xc50)) return null
        return estimate(inputs, equation)?.takeIf { it.fatPercent in plausibleFatPercent }
    }
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
