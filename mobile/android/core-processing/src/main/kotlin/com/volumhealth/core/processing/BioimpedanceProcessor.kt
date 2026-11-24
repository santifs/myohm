package com.volumhealth.core.processing

import com.volumhealth.core.model.ColeParameters
import com.volumhealth.core.model.Complex
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.MeasurementType
import com.volumhealth.core.model.ParameterErrors
import com.volumhealth.core.model.ProcessingTier
import com.volumhealth.core.model.QualityMetrics
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.yield

@Singleton
class BioimpedanceProcessor @Inject constructor(
    private val qualityAssessment: QualityAssessment
) {
    data class ProcessingConfig(
        val maxStarts: Int,
        val maxIterations: Int,
        val convergenceThreshold: Float,
        val useEarlyTermination: Boolean
    ) {
        companion object {
            val IMMEDIATE = ProcessingConfig(
                maxStarts = 1,
                maxIterations = 20,
                convergenceThreshold = 1e-6f,
                useEarlyTermination = true
            )

            val COMPLETE = ProcessingConfig(
                maxStarts = 20,
                maxIterations = 120,
                convergenceThreshold = 1e-6f,
                useEarlyTermination = true
            )
        }
    }

    suspend fun processImmediate(data: ImpedanceData): ColeParameters {
        return process(data, ProcessingConfig.IMMEDIATE, ProcessingTier.IMMEDIATE)
    }

    suspend fun processComplete(data: ImpedanceData): ColeParameters {
        return process(data, ProcessingConfig.COMPLETE, ProcessingTier.COMPLETE)
    }

    suspend fun processQuick(data: ImpedanceData): ColeParameters {
        require(data.measurements.isNotEmpty()) { "Measurement data required" }

        val magnitudes = data.magnitudes
        val phases = data.phases
        val frequencies = data.frequencies

        val reLowFreqMag = magnitudes.first()
        val reLowFreqPhase = phases.first() * PI.toFloat() / 180f
        val re = reLowFreqMag * cos(reLowFreqPhase)

        val rinfHighFreqMag = magnitudes.last()
        val rinfHighFreqPhase = phases.last() * PI.toFloat() / 180f
        val rinf = rinfHighFreqMag * cos(rinfHighFreqPhase)

        val ri = rinf2ri(re, rinf)
        val minPhaseIndex = phases.indices.minByOrNull { phases[it] } ?: 0
        val fcFreq = frequencies[minPhaseIndex].coerceAtLeast(1f)
        val fc = fcFreq / 1000f

        val tau = 1f / (2f * PI.toFloat() * fcFreq)
        val cm = (tau / (re + ri)).coerceAtLeast(1e-10f)

        val alpha = 0.8f

        return ColeParameters(
            Re = re,
            Ri = ri,
            Cm = (cm * 1e9f).coerceAtLeast(0.1f),
            fc = fc,
            alpha = alpha,
            error = 15f,
            processingTier = ProcessingTier.IMMEDIATE,
            quality = createQuickQualityMetrics(data),
            measurementType = detectMeasurementType(data),
            rawData = data
        )
    }

    private suspend fun process(
        data: ImpedanceData,
        config: ProcessingConfig,
        tier: ProcessingTier
    ): ColeParameters = withContext(Dispatchers.Default) {
        require(data.measurements.size >= 15) { "Minimum 15 frequency points required" }

        val frequencies = data.frequencies
        val impedances = data.complexImpedances

        require(frequencies.first() > 500 && frequencies.last() < 500_000) {
            "Invalid frequency range"
        }

        val fitResult = fitColeModel(frequencies, impedances, config)
        val quality = createQualityMetrics(fitResult, data)

        ColeParameters(
            Re = fitResult.Re,
            Ri = fitResult.Ri,
            Cm = (fitResult.Cm * 1e9f).coerceAtLeast(0.1f),
            fc = fitResult.fc,
            alpha = fitResult.alpha,
            error = fitResult.error,
            processingTier = tier,
            quality = quality,
            measurementType = detectMeasurementType(data),
            rawData = data
        )
    }

    private suspend fun fitColeModel(
        frequencies: List<Float>,
        impedances: List<Complex>,
        config: ProcessingConfig
    ): FitResult {
        var bestResult: FitResult? = null
        var bestError = Float.MAX_VALUE

        repeat(config.maxStarts) { startIndex ->
            val initialParams = generateInitialParameters(frequencies, impedances, startIndex)

            val result = nelderMeadOptimization(
                initialParams = initialParams,
                frequencies = frequencies,
                impedances = impedances,
                config = config
            )

            if (result.error < bestError && result.converged) {
                bestError = result.error
                bestResult = result
            }

            if (config.useEarlyTermination && result.error < config.convergenceThreshold) {
                return result
            }
        }

        return bestResult ?: throw ProcessingException("Optimization failed to converge")
    }

    private suspend fun nelderMeadOptimization(
        initialParams: FloatArray,
        frequencies: List<Float>,
        impedances: List<Complex>,
        config: ProcessingConfig
    ): FitResult {
        val n = initialParams.size
        val alpha = NelderMeadCoefficients.ALPHA
        val gamma = NelderMeadCoefficients.GAMMA
        val rho = NelderMeadCoefficients.RHO
        val sigma = NelderMeadCoefficients.SIGMA

        val simplex = mutableListOf<FloatArray>()
        simplex.add(initialParams.copyOf())

        repeat(n) { i ->
            val vertex = initialParams.copyOf()
            val perturbation = abs(initialParams[i]) * 0.05f + 0.01f
            vertex[i] += perturbation
            simplex.add(applyConstraints(vertex, frequencies, impedances))
        }

        val errors = simplex.map { calculateError(it, frequencies, impedances) }.toMutableList()
        var iteration = 0

        while (iteration < config.maxIterations) {
            val sortedIndices = errors.indices.sortedBy { errors[it] }
            val best = simplex[sortedIndices[0]]
            val worst = simplex[sortedIndices[n]]
            val bestError = errors[sortedIndices[0]]
            val worstError = errors[sortedIndices[n]]

            if (abs(worstError - bestError) < config.convergenceThreshold) {
                return convertToFitResult(best, bestError, iteration, true)
            }

            val centroid = FloatArray(n) { j ->
                (0 until n).sumOf { simplex[sortedIndices[it]][j].toDouble() }.toFloat() / n
            }

            val reflected = FloatArray(n) { j ->
                centroid[j] + alpha * (centroid[j] - worst[j])
            }.let { applyConstraints(it, frequencies, impedances) }
            val reflectedError = calculateError(reflected, frequencies, impedances)

            when {
                reflectedError < bestError -> {
                    val expanded = FloatArray(n) { j ->
                        centroid[j] + gamma * (reflected[j] - centroid[j])
                    }.let { applyConstraints(it, frequencies, impedances) }
                    val expandedError = calculateError(expanded, frequencies, impedances)

                    if (expandedError < reflectedError) {
                        simplex[sortedIndices[n]] = expanded
                        errors[sortedIndices[n]] = expandedError
                    } else {
                        simplex[sortedIndices[n]] = reflected
                        errors[sortedIndices[n]] = reflectedError
                    }
                }

                reflectedError < errors[sortedIndices[n - 1]] -> {
                    simplex[sortedIndices[n]] = reflected
                    errors[sortedIndices[n]] = reflectedError
                }

                else -> {
                    val contracted = if (reflectedError < worstError) {
                        FloatArray(n) { j -> centroid[j] + rho * (reflected[j] - centroid[j]) }
                    } else {
                        FloatArray(n) { j -> centroid[j] + rho * (worst[j] - centroid[j]) }
                    }.let { applyConstraints(it, frequencies, impedances) }

                    val contractedError = calculateError(contracted, frequencies, impedances)

                    if (contractedError < min(reflectedError, worstError)) {
                        simplex[sortedIndices[n]] = contracted
                        errors[sortedIndices[n]] = contractedError
                    } else {
                        for (i in 1..n) {
                            val idx = sortedIndices[i]
                            for (j in 0 until n) {
                                simplex[idx][j] = best[j] + sigma * (simplex[idx][j] - best[j])
                            }
                            simplex[idx] = applyConstraints(simplex[idx], frequencies, impedances)
                            errors[idx] = calculateError(simplex[idx], frequencies, impedances)
                        }
                    }
                }
            }

            iteration++

            if (iteration % 10 == 0) {
                yield()
            }
        }

        val sortedIndices = errors.indices.sortedBy { errors[it] }
        return convertToFitResult(simplex[sortedIndices[0]], errors[sortedIndices[0]], iteration, false)
    }

    private fun calculateError(
        params: FloatArray,
        frequencies: List<Float>,
        impedances: List<Complex>
    ): Float {
        val r0 = params[0]
        val rinf = params[1]
        val tau = params[2]
        val alpha = params[3]

        if (r0 <= rinf || rinf <= 0f || tau <= 0f || alpha <= 0f || alpha > 1f) {
            return Float.MAX_VALUE
        }

        var totalError = 0f
        var validPoints = 0

        frequencies.forEachIndexed { index, freq ->
            val omega = 2 * PI.toFloat() * freq
            val jOmegaTau = omega * tau
            if (jOmegaTau <= 0f || !jOmegaTau.isFinite()) return@forEachIndexed

            val logJOmegaTau = ln(jOmegaTau)
            val alphaLogTerm = alpha * logJOmegaTau
            if (abs(alphaLogTerm) > 50f) return@forEachIndexed

            val powerMagnitude = exp(alphaLogTerm)
            val powerPhase = alpha * PI.toFloat() / 2f
            val powerReal = powerMagnitude * cos(powerPhase)
            val powerImag = powerMagnitude * sin(powerPhase)

            val denomReal = 1 + powerReal
            val denomImag = powerImag
            val denomMagSq = denomReal * denomReal + denomImag * denomImag
            if (denomMagSq < 1e-20f) return@forEachIndexed

            val numerator = r0 - rinf
            val fractionReal = numerator * denomReal / denomMagSq
            val fractionImag = -numerator * denomImag / denomMagSq

            val zReal = rinf + fractionReal
            val zImag = fractionImag

            val predictedMag = sqrt(zReal * zReal + zImag * zImag)
            val measuredMag = impedances[index].magnitude

            val error = predictedMag - measuredMag
            totalError += error * error
            validPoints++
        }

        if (validPoints < frequencies.size / 2) return Float.MAX_VALUE

        return sqrt(totalError / validPoints)
    }

    private fun convertToFitResult(
        params: FloatArray,
        error: Float,
        iterations: Int,
        converged: Boolean
    ): FitResult {
        val r0 = params[0]
        val rinf = params[1]
        val tau = params[2]
        val alpha = params[3]

        val re = r0
        val ri = rinf2ri(re, rinf)
        val fc = 1f / (2f * PI.toFloat() * tau) / 1000f
        val cm = tau / (re + ri)

        return FitResult(re, ri, cm, fc, alpha, error, iterations, converged)
    }

    private fun generateInitialParameters(
        frequencies: List<Float>,
        impedances: List<Complex>,
        startIndex: Int
    ): FloatArray {
        val magnitudes = impedances.map { it.magnitude }
        val phases = impedances.map { it.phase }
        val avgMagnitude = magnitudes.average().toFloat()
        val maxMagnitude = magnitudes.maxOrNull() ?: 500f
        val minMagnitude = magnitudes.minOrNull() ?: 10f
        val isBiological = avgMagnitude < 200f && maxMagnitude < 500f

        return if (startIndex == 0) {
            val r0Init = magnitudes.firstOrNull() ?: maxMagnitude
            val rinfInit = magnitudes.lastOrNull() ?: minMagnitude
            val validRinf = min(rinfInit, r0Init * 0.95f)

            val minPhaseIndex = phases.indices.minByOrNull { phases[it] } ?: 0
            val fcEstimate = frequencies[minPhaseIndex].coerceAtLeast(500f)
            val tauInit = 1f / (2f * PI.toFloat() * fcEstimate)
            val alphaInit = if (isBiological) 0.8f else 0.7f

            floatArrayOf(r0Init, validRinf, tauInit, alphaInit)
        } else {
            val random = Random(startIndex * 9973 + 17)
            val r0Init = if (isBiological) {
                randomFloat(minMagnitude, maxMagnitude * 1.2f, random)
            } else {
                randomFloat(minMagnitude, maxMagnitude * 2f, random)
            }

            val rinfInit = if (isBiological) {
                randomFloat(minMagnitude * 0.5f, r0Init * 0.9f, random)
            } else {
                randomFloat(minMagnitude * 0.1f, r0Init * 0.8f, random)
            }

            val tauRange = if (isBiological) 1e-6f..1e-4f else 1e-7f..1e-3f
            val tauInit = randomFloat(tauRange.start, tauRange.endInclusive, random)
            val alphaInit = if (isBiological) {
                randomFloat(0.6f, 1.0f, random)
            } else {
                randomFloat(0.2f, 1.0f, random)
            }

            floatArrayOf(r0Init, min(rinfInit, r0Init * 0.95f), tauInit, alphaInit)
        }
    }

    private fun applyConstraints(
        params: FloatArray,
        @Suppress("UNUSED_PARAMETER") frequencies: List<Float>,
        impedances: List<Complex>
    ): FloatArray {
        val magnitudes = impedances.map { it.magnitude }
        val maxMagnitude = magnitudes.maxOrNull() ?: 1000f
        val minMagnitude = magnitudes.minOrNull() ?: 10f
        val avgMagnitude = magnitudes.average().toFloat()
        val isBiological = avgMagnitude < 200f && maxMagnitude < 500f

        val constrained = params.copyOf()

        val r0Lower = maxMagnitude * 0.85f
        val r0Upper = maxMagnitude * 1.2f
        constrained[0] = constrained[0].coerceIn(r0Lower, r0Upper)

        val rinfLower = minMagnitude * 0.8f
        val rinfUpper = min(minMagnitude * 1.15f, constrained[0] * 0.95f)
        constrained[1] = constrained[1].coerceIn(rinfLower, rinfUpper)
        if (constrained[1] >= constrained[0]) {
            constrained[1] = constrained[0] * 0.95f
        }

        val minTau = 1f / (2f * PI.toFloat() * 200_000f)
        val maxTau = 1f / (2f * PI.toFloat() * 5_000f)
        constrained[2] = constrained[2].coerceIn(minTau, maxTau)

        constrained[3] = if (isBiological) {
            constrained[3].coerceIn(0.7f, 0.9f)
        } else {
            constrained[3].coerceIn(0.1f, 1f)
        }

        return constrained
    }

    private fun createQuickQualityMetrics(data: ImpedanceData): QualityMetrics {
        val base = qualityAssessment.assessQuality(data)
        val convergence = base.convergence.copy(converged = false)
        return base.copy(convergence = convergence)
    }

    private fun createQualityMetrics(result: FitResult, data: ImpedanceData): QualityMetrics {
        val base = qualityAssessment.assessQuality(data)
        val parameterErrors = ParameterErrors(0f, 0f, 0f, 0f, 0f)
        val convergence = base.convergence.copy(
            iterations = result.iterations,
            residualError = result.error,
            converged = result.converged,
            parameterErrors = parameterErrors
        )
        return base.copy(convergence = convergence)
    }

    private fun detectMeasurementType(data: ImpedanceData): MeasurementType {
        val magnitudes = data.magnitudes
        val avgMagnitude = magnitudes.average().toFloat()
        val maxMagnitude = magnitudes.maxOrNull() ?: 0f
        return when {
            avgMagnitude < 200f && maxMagnitude < 500f -> MeasurementType.BODY
            avgMagnitude > 1000f -> MeasurementType.CIRCUIT
            else -> MeasurementType.UNKNOWN
        }
    }

    private fun rinf2ri(re: Float, rinf: Float): Float {
        return if (re <= rinf || rinf <= 0f) {
            max(1f, re - rinf)
        } else {
            re * rinf / (re - rinf)
        }
    }

    @Suppress("unused")
    private fun ri2rinf(re: Float, ri: Float): Float {
        return re * ri / (re + ri)
    }

    data class FitResult(
        val Re: Float,
        val Ri: Float,
        val Cm: Float,
        val fc: Float,
        val alpha: Float,
        val error: Float,
        val iterations: Int,
        val converged: Boolean
    )
}

class ProcessingException(message: String) : Exception(message)

private fun randomFloat(min: Float, max: Float, random: Random): Float {
    if (max <= min) return min
    return min + random.nextFloat() * (max - min)
}
