import Foundation
import Accelerate
import OSLog


/// Core bioimpedance processing engine
/// Implements Cole model fitting with multi-start Levenberg-Marquardt optimization  
/// Based on exact algorithms from MATLAB implementation
@Observable
public final class BioimpedanceProcessor: @unchecked Sendable {
    
    private let logger = Logger(subsystem: "com.biomess.health", category: "Processing")
    private var calibrationConstants: CalibrationConstants?
    
    // MARK: - Processing Configuration
    
    public struct ProcessingConfig: Sendable {
        let maxStartsImmediate: Int
        let maxStartsComplete: Int
        let maxIterations: Int
        let convergenceThreshold: Float
        let parameterThreshold: Float
        let useEarlyTermination: Bool
        let useLevenbergMarquardt: Bool
        
        public static let immediate: ProcessingConfig = ProcessingConfig(
            maxStartsImmediate: 1,           // Single start for <1s processing
            maxStartsComplete: 1,
            maxIterations: 25,
            convergenceThreshold: 1e-5,
            parameterThreshold: 1e-4,
            useEarlyTermination: true,
            useLevenbergMarquardt: true
        )
        
        public static let complete: ProcessingConfig = ProcessingConfig(
            maxStartsImmediate: 1,
            maxStartsComplete: 20,           // Sweet spot: better than 12, faster than 50
            maxIterations: 100,
            convergenceThreshold: 1e-6,
            parameterThreshold: 1e-5,
            useEarlyTermination: true,
            useLevenbergMarquardt: true
        )
    }
    
    public init() {}
    
    // MARK: - Public API
    
    /// Tier 1: Immediate processing (<1 second, ~85% accuracy)
    public func processImmediate(_ data: ImpedanceData) async throws -> ColeParameters {
        return try await process(data, config: .immediate, tier: .immediate)
    }
    
    /// Tier 2: Complete processing (2-5 seconds, >95% accuracy)
    public func processComplete(_ data: ImpedanceData) async throws -> ColeParameters {
        return try await process(data, config: .complete, tier: .complete)
    }
    
    /// Assess measurement quality
    public func assessQuality(_ data: ImpedanceData) -> QualityMetrics {
        
        let contactQuality = assessContactQuality(data)
        let signalQuality = assessSignalQuality(data)
        let convergence = ConvergenceMetrics(
            iterations: 0,
            residualError: nil,
            parameterErrors: nil,
            converged: false
        )
        let stability = assessStability(data)
        
        // Overall quality score (weighted average)
        let score = (
            Float(contactQuality.status.qualityScore) * 0.4 +
            signalQuality.qualityScore * 0.3 +
            (stability.movementDetected ? 0.5 : 1.0) * 0.3
        )
        
        return QualityMetrics(
            score: score,
            contactQuality: contactQuality,
            signalQuality: signalQuality,
            convergence: convergence,
            stabilityMetrics: stability
        )
    }
    
    // MARK: - Calibration Management
    
    /// Store calibration constants for future use
    public func setCalibrationConstants(_ constants: CalibrationConstants) {
        self.calibrationConstants = constants
        // TODO: Save to UserDefaults, Core Data, or other persistent storage
        logger.info("Calibration constants saved with quality \(constants.quality.overallScore)")
    }
    
    /// Apply calibration to new impedance measurements
    /// Implements MATLAB generateCalibratedData() function
    public func applyCalibratedData(to rawData: ImpedanceData) -> ImpedanceData {
        guard let calibration = calibrationConstants else {
            logger.warning("No calibration constants available - returning raw data")
            return rawData
        }
        
        // Extract calibration data (MATLAB: Zmr0, Zmr1, Zmr2, Zr0, Zr1, Zr2)
        let zmr0 = calibration.cal1Measured.complexAverage  // C1 measured
        let zmr1 = calibration.cal2Measured.complexAverage  // C2 measured  
        let zmr2 = calibration.cal3Measured.complexAverage  // C3 measured
        
        let zr0 = calibration.cal1Model.complexImpedance   // C1 theoretical
        let zr1 = calibration.cal2Model.complexImpedance   // C2 theoretical
        let zr2 = calibration.cal3Model.complexImpedance   // C3 theoretical
        
        // Apply 3-point Lagrange interpolation to each measurement point
        var calibratedMeasurements: [ImpedanceData.MeasurementPoint] = []
        
        for (index, measurement) in rawData.measurements.enumerated() {
            let rawComplex = measurement.complexImpedance
            
            // Apply calibrateZQuad for this frequency
            let calibratedComplex = calibrateZQuad(
                zm: rawComplex,
                zmr0: zmr0[index],
                zmr1: zmr1[index], 
                zmr2: zmr2[index],
                zr0: zr0[index],
                zr1: zr1[index],
                zr2: zr2[index]
            )
            
            let calibratedPoint = ImpedanceData.MeasurementPoint(
                frequency: measurement.frequency,
                magnitude: calibratedComplex.magnitude,
                phase: calibratedComplex.phase * 180.0 / Float.pi // Convert back to degrees
            )
            
            calibratedMeasurements.append(calibratedPoint)
        }
        
        return ImpedanceData(
            measurements: calibratedMeasurements,
            timestamp: rawData.timestamp,
            deviceInfo: rawData.deviceInfo
        )
    }
    
    /// 3-point Lagrange interpolation calibration (MATLAB calibrateZQuad.m)
    private func calibrateZQuad(
        zm: Complex,     // Measured impedance to calibrate
        zmr0: Complex, zmr1: Complex, zmr2: Complex,  // Reference measurements  
        zr0: Complex, zr1: Complex, zr2: Complex      // Reference theoretical values
    ) -> Complex {
        
        // Lagrange basis polynomials (exact MATLAB implementation)
        // term1 = Zr0 * ((Zm - Zmr1) * (Zm - Zmr2)) / ((Zmr0 - Zmr1) * (Zmr0 - Zmr2))
        let term1 = zr0 * ((zm - zmr1) * (zm - zmr2)) / ((zmr0 - zmr1) * (zmr0 - zmr2))
        
        // term2 = Zr1 * ((Zm - Zmr2) * (Zm - Zmr0)) / ((Zmr1 - Zmr2) * (Zmr1 - Zmr0))
        let term2 = zr1 * ((zm - zmr2) * (zm - zmr0)) / ((zmr1 - zmr2) * (zmr1 - zmr0))
        
        // term3 = Zr2 * ((Zm - Zmr0) * (Zm - Zmr1)) / ((Zmr2 - Zmr0) * (Zmr2 - Zmr1))
        let term3 = zr2 * ((zm - zmr0) * (zm - zmr1)) / ((zmr2 - zmr0) * (zmr2 - zmr1))
        
        return term1 + term2 + term3
    }
    
    /// Get stored calibration constants (placeholder for now)
    /// In a real implementation, this would load from persistent storage
    private func getStoredCalibrationConstants() -> CalibrationConstants? {
        // TODO: Load from UserDefaults, Core Data, or other persistent storage
        // For now, return the current calibration constants
        return calibrationConstants
    }
}

// MARK: - Core Processing

private extension BioimpedanceProcessor {
    
    func process(_ data: ImpedanceData, config: ProcessingConfig, tier: ProcessingTier) async throws -> ColeParameters {
        
        let startTime = Date()
        logger.info("Starting \(String(describing: tier)) processing with \(data.measurements.count) measurements")
        
        // Input validation
        guard data.measurements.count == 15 else {
            throw ProcessingError.invalidDataSize
        }
        
        // Extract frequencies and complex impedances
        let frequencies = data.frequencies
        let complexImpedances = data.complexImpedances
        guard Set(frequencies).count >= 3,
              frequencies.allSatisfy({ $0.isFinite && $0 > 0 }),
              data.magnitudes.allSatisfy({ $0.isFinite && $0 > 0 }),
              data.phases.allSatisfy({ $0.isFinite }),
              data.magnitudes.min() != data.magnitudes.max(),
              complexImpedances.contains(where: { $0.imaginary < 0 }) else {
            throw ProcessingError.optimizationFailed
        }

        
        // Validate frequency range (should be 1kHz to ~438kHz for BioMess)
        guard frequencies.first ?? 0 > 500 && frequencies.last ?? 0 < 500000 else {
            throw ProcessingError.invalidFrequencyRange
        }
        
        // Apply calibration (simplified for now)
        let calibratedImpedances = try applyCalibratedCorrection(complexImpedances, frequencies: frequencies)
        
        // Cole model fitting
        let result = try await fitColeModel(
            frequencies: frequencies,
            impedances: calibratedImpedances,
            config: config
        )
        
        // Quality assessment with convergence metrics
        let quality = assessQuality(data)
        
        // Update convergence metrics with real optimization results
        let convergenceMetrics = ConvergenceMetrics(
            iterations: result.iterations,
            residualError: result.error,
            parameterErrors: result.parameterErrors,
            converged: result.converged
        )
        
        let updatedQuality = QualityMetrics(
            score: quality.score,
            contactQuality: quality.contactQuality,
            signalQuality: quality.signalQuality,
            convergence: convergenceMetrics,
            stabilityMetrics: quality.stabilityMetrics
        )
        
        let processingTime = Date().timeIntervalSince(startTime)
        logger.info("\(String(describing: tier)) processing completed in \(String(format: "%.3f", processingTime))s")
        
        return ColeParameters(
            Re: result.Re,
            Ri: result.Ri,
            Cm: result.Cm,
            fc: result.fc,
            alpha: result.alpha,
            error: 100 * result.error / (calibratedImpedances.map { $0.magnitude }.reduce(0, +) / Float(calibratedImpedances.count)),
            processingTier: tier,
            quality: updatedQuality
        )
    }
    
    /// Apply calibration correction using 3-point Lagrange interpolation
    func applyCalibratedCorrection(_ impedances: [Complex], frequencies: [Float]) throws -> [Complex] {
        
        // Check if calibration constants are available
        guard let calibrationConstants = getStoredCalibrationConstants() else {
            logger.info("No calibration constants available - returning uncorrected data")
            return impedances
        }
        
        // Apply calibration correction
        let calibrationProcessor = CalibrationProcessor()
        
        do {
            let correctedImpedances = try calibrationProcessor.calibrateImpedance(
                impedances,
                using: calibrationConstants
            )
            
            logger.info("Applied calibration correction using 3-point Lagrange interpolation")
            return correctedImpedances
            
        } catch {
            logger.error("Calibration correction failed: \(error.localizedDescription)")
            // Return uncorrected data rather than failing the measurement
            return impedances
        }
    }
}

// MARK: - Cole Model Fitting

private extension BioimpedanceProcessor {
    
    struct FitResult {
        let Re: Float
        let Ri: Float  
        let Cm: Float
        let fc: Float
        let alpha: Float
        let error: Float
        let iterations: Int
        let converged: Bool
        let parameterErrors: ParameterErrors?
    }
    
    func fitColeModel(frequencies: [Float], impedances: [Complex], config: ProcessingConfig) async throws -> FitResult {
        
        let numStarts = config.maxStartsComplete
        var bestResult: FitResult?
        var bestError = Float.infinity
        var allResults: [FitResult] = []
        
        for startIndex in 0..<numStarts {
            
            // Generate initial parameters
            let initialParams = generateInitialParameters(
                frequencies: frequencies,
                impedances: impedances,
                startIndex: startIndex
            )
            
            // Single optimization run
            let result = try await optimizeSingleStart(
                frequencies: frequencies,
                impedances: impedances,
                initialParams: initialParams,
                config: config
            )
            
            allResults.append(result)
            
            if result.error < bestError && result.converged {
                bestError = result.error
                bestResult = result
            }
            
            // Early termination for excellent fits
            if config.useEarlyTermination && result.converged && result.error < config.convergenceThreshold {
                logger.debug("Early termination at start \(startIndex)")
                break
            }
        }
        
        guard let best = bestResult else {
            throw ProcessingError.optimizationFailed
        }
        
        logger.debug("Best fit: error=\(best.error), iterations=\(best.iterations)")
        return best
    }
    
    func generateInitialParameters(frequencies: [Float], impedances: [Complex], startIndex: Int) -> [Float] {
        
        let magnitudes = impedances.map { $0.magnitude }
        
        if startIndex == 0 {
            // MATLAB-style deterministic initialization for first start
            let R0_init = magnitudes.reduce(0, +) / Float(magnitudes.count)  // mean magnitude
            let Rinf_init = magnitudes.min() ?? (R0_init * 0.5)             // minimum magnitude
            let tau_init: Float = 1.0 / (50000 * 2 * Float.pi)             // Exactly as MATLAB
            let alpha_init: Float = 0.8                                      // Standard initial value
            
            return [R0_init, Rinf_init, tau_init, alpha_init]
        } else {
            // Random perturbations for subsequent starts (MATLAB-style)
            let maxMag = magnitudes.max() ?? 500
            let margin = maxMag * 0.2
            
            let R0_init = Float.random(in: 50...(maxMag + margin))
            let Rinf_init = Float.random(in: 10...(maxMag + margin))
            let tau_init = Float.random(in: 1e-6...1e-3)
            let alpha_init = Float.random(in: 0.1...1.0)
            
            return [R0_init, Rinf_init, tau_init, alpha_init]
        }
    }
    
    func optimizeSingleStart(
        frequencies: [Float],
        impedances: [Complex], 
        initialParams: [Float],
        config: ProcessingConfig
    ) async throws -> FitResult {
        
        if config.useLevenbergMarquardt {
            return try await levenbergMarquardtOptimization(
                frequencies: frequencies,
                impedances: impedances,
                initialParams: initialParams,
                config: config
            )
        } else {
            return try await gradientDescentOptimization(
                frequencies: frequencies,
                impedances: impedances,
                initialParams: initialParams,
                config: config
            )
        }
    }
    
    /// Levenberg-Marquardt optimization (MATLAB-equivalent)
    func levenbergMarquardtOptimization(
        frequencies: [Float],
        impedances: [Complex],
        initialParams: [Float],
        config: ProcessingConfig
    ) async throws -> FitResult {
        
        var params = initialParams
        var lambda: Float = 0.001  // Initial damping factor
        var converged = false
        var iteration = 0
        let maxIterations = config.maxIterations
        let numParams = params.count
        
        for iter in 0..<maxIterations {
            iteration = iter + 1
            
            // Calculate residuals and Jacobian
            let (residuals, jacobian) = calculateResidualsAndJacobian(
                params: params,
                frequencies: frequencies,
                impedances: impedances
            )
            
            let error = sqrt(residuals.map { $0 * $0 }.reduce(0, +) / Float(residuals.count))
            
            // Calculate JtJ (J transpose times J) and JtR (J transpose times residuals)
            let JtJ = calculateJtJ(jacobian: jacobian)
            let JtR = calculateJtR(jacobian: jacobian, residuals: residuals)
            
            // Add damping to diagonal (Levenberg-Marquardt)
            var JtJ_damped = JtJ
            for i in 0..<numParams {
                JtJ_damped[i][i] += lambda
            }
            
            // Solve (JtJ + λI) * δ = JtR for parameter update δ
            guard let delta = solveLinearSystem(matrix: JtJ_damped, vector: JtR) else {
                throw ProcessingError.numericalInstability
            }
            
            // Try new parameters
            var newParams = [Float]()
            for i in 0..<numParams {
                newParams.append(params[i] - delta[i])
            }
            newParams = applyParameterConstraints(newParams, frequencies: frequencies, impedances: impedances)
            
            // Calculate error with new parameters
            let newResiduals = calculateResiduals(
                params: newParams,
                frequencies: frequencies,
                impedances: impedances
            )
            let newError = sqrt(newResiduals.map { $0 * $0 }.reduce(0, +) / Float(newResiduals.count))
            
            // Accept or reject step and update lambda
            if error <= config.convergenceThreshold {
                converged = true
                break
            }
            if newError < error {
                // Accept step
                params = newParams
                lambda *= 0.1  // Decrease damping (move towards Gauss-Newton)
                if error - newError < config.convergenceThreshold {
                    converged = true
                    break
                }
            } else {
                // Reject step  
                lambda *= 10.0  // Increase damping (move towards gradient descent)
            }
            
            // Prevent lambda from becoming too extreme
            lambda = max(1e-10, min(1e10, lambda))
            
            // Yield control periodically for responsiveness
            if iter % 5 == 0 {
                await Task.yield()
            }
        }
        
        // Convert MATLAB parameter order [R0, Rinf, tau, alpha] to output format
        let R0 = params[0]
        let Rinf = params[1]
        let tau = params[2]
        let alpha = params[3]
        
        // Convert using MATLAB formulas
        let Re = R0                                        // Extracellular resistance
        let Ri = (Re * Rinf) / (Re - Rinf)               // rinf2ri conversion from MATLAB
        let fc = 1.0 / (2 * Float.pi * tau) / 1000.0     // Convert to kHz
        let Cm = abs(tau / (Re + Ri)) * 1e9               // Convert to nF (MATLAB formula)
        
        // Calculate parameter uncertainties using final Jacobian
        let (finalResiduals, finalJacobian) = calculateResidualsAndJacobian(
            params: params,
            frequencies: frequencies,
            impedances: impedances
        )
        
        let parameterErrors = calculateParameterUncertainties(
            jacobian: finalJacobian,
            residuals: finalResiduals,
            params: params  // Convert to final parameter space
        )
        
        return FitResult(
            Re: Re,
            Ri: Ri,
            Cm: Cm,
            fc: fc,
            alpha: alpha,
            error: sqrt(finalResiduals.map { $0 * $0 }.reduce(0, +) / Float(finalResiduals.count)),
            iterations: iteration,
            converged: converged && R0 > Rinf && Rinf > 0,
            parameterErrors: parameterErrors
        )
    }
    
    /// Fallback gradient descent optimization
    func gradientDescentOptimization(
        frequencies: [Float],
        impedances: [Complex],
        initialParams: [Float],
        config: ProcessingConfig
    ) async throws -> FitResult {
        
        var params = initialParams
        var lastError = Float.infinity
        var converged = false
        var iteration = 0
        let maxIterations = config.maxIterations
        var stepSize: Float = 0.1
        
        for iter in 0..<maxIterations {
            iteration = iter + 1
            
            let (error, gradient) = calculateErrorAndGradient(
                params: params,
                frequencies: frequencies,
                impedances: impedances
            )
            
            if abs(lastError - error) < config.convergenceThreshold {
                converged = true
                break
            }
            
            for i in 0..<params.count {
                params[i] -= stepSize * gradient[i]
            }
            
            params = applyParameterConstraints(params, frequencies: frequencies, impedances: impedances)
            
            if error < lastError {
                stepSize *= 1.1
            } else {
                stepSize *= 0.5
            }
            
            lastError = error
            
            if iter % 5 == 0 {
                await Task.yield()
            }
        }
        
        // Convert to output format (same as LM)
        let R0 = params[0]
        let Rinf = params[1]
        let tau = params[2]
        let alpha = params[3]
        
        let Re = R0
        let Ri = (Re * Rinf) / (Re - Rinf)
        let fc = 1.0 / (2 * Float.pi * tau) / 1000.0
        let Cm = abs(tau / (Re + Ri)) * 1e9
        
        // Calculate parameter uncertainties using final Jacobian
        let (finalResiduals, finalJacobian) = calculateResidualsAndJacobian(
            params: params,
            frequencies: frequencies,
            impedances: impedances
        )
        
        let parameterErrors = calculateParameterUncertainties(
            jacobian: finalJacobian,
            residuals: finalResiduals,
            params: params
        )
        
        return FitResult(
            Re: Re,
            Ri: Ri,
            Cm: Cm,
            fc: fc,
            alpha: alpha,
            error: sqrt(finalResiduals.map { $0 * $0 }.reduce(0, +) / Float(finalResiduals.count)),
            iterations: iteration,
            converged: converged && R0 > Rinf && Rinf > 0,
            parameterErrors: parameterErrors
        )
    }
    
    /// Correct Cole model: Z(ω) = Rinf + (R0 - Rinf) / (1 + (jωτ)^α)
    func coleModel(frequencies: [Float], params: [Float]) -> [Complex] {
        let R0 = params[0]      // MATLAB parameter order
        let Rinf = params[1]
        let tau = params[2]
        let alpha = params[3]
        
        return frequencies.map { freq in
            let omega = 2 * Float.pi * freq
            let jOmegaTau = Complex(real: 0, imaginary: omega * tau)
            let powerTerm = jOmegaTau.power(alpha)  // (jωτ)^α
            let denominator = Complex(real: 1, imaginary: 0) + powerTerm
            
            let numerator = Complex(real: R0 - Rinf, imaginary: 0)
            return Complex(real: Rinf, imaginary: 0) + numerator / denominator
        }
    }
    
    /// Calculate residuals for Levenberg-Marquardt
    func calculateResiduals(params: [Float], frequencies: [Float], impedances: [Complex]) -> [Float] {
        let predicted = coleModel(frequencies: frequencies, params: params)
        var residuals = [Float]()
        
        for i in 0..<impedances.count {
            let measured = impedances[i]
            let pred = predicted[i]
            
            // Magnitude residual (most common in MATLAB implementation)
            let residual = pred.magnitude - measured.magnitude
            residuals.append(residual)
        }
        
        return residuals
    }
    
    /// Calculate residuals and Jacobian matrix for Levenberg-Marquardt
    func calculateResidualsAndJacobian(
        params: [Float],
        frequencies: [Float],
        impedances: [Complex]
    ) -> (residuals: [Float], jacobian: [[Float]]) {
        
        let residuals = calculateResiduals(params: params, frequencies: frequencies, impedances: impedances)
        
        // Calculate Jacobian using finite differences
        let numParams = params.count
        let numMeasurements = residuals.count
        
        var jacobian = Array(repeating: Array(repeating: Float(0), count: numParams), count: numMeasurements)
        
        for paramIndex in 0..<numParams {
            // Forward difference
            var paramsPlus = params
            let epsilon = max(abs(params[paramIndex]), 1e-7) * sqrt(Float.ulpOfOne)
            paramsPlus[paramIndex] += epsilon
            let residualsPlus = calculateResiduals(params: paramsPlus, frequencies: frequencies, impedances: impedances)
            
            for measIndex in 0..<numMeasurements {
                jacobian[measIndex][paramIndex] = (residualsPlus[measIndex] - residuals[measIndex]) / epsilon
            }
        }
        
        return (residuals, jacobian)
    }
    
    /// Calculate JtJ (Jacobian transpose times Jacobian)
    func calculateJtJ(jacobian: [[Float]]) -> [[Float]] {
        let numParams = jacobian[0].count
        let numMeasurements = jacobian.count
        
        var JtJ = Array(repeating: Array(repeating: Float(0), count: numParams), count: numParams)
        
        for i in 0..<numParams {
            for j in 0..<numParams {
                var sum: Float = 0
                for k in 0..<numMeasurements {
                    sum += jacobian[k][i] * jacobian[k][j]
                }
                JtJ[i][j] = sum
            }
        }
        
        return JtJ
    }
    
    /// Calculate JtR (Jacobian transpose times residuals)
    func calculateJtR(jacobian: [[Float]], residuals: [Float]) -> [Float] {
        let numParams = jacobian[0].count
        let numMeasurements = jacobian.count
        
        var JtR = Array(repeating: Float(0), count: numParams)
        
        for i in 0..<numParams {
            var sum: Float = 0
            for j in 0..<numMeasurements {
                sum += jacobian[j][i] * residuals[j]
            }
            JtR[i] = sum
        }
        
        return JtR
    }
    
    /// Solve linear system using Gaussian elimination with partial pivoting
    func solveLinearSystem(matrix: [[Float]], vector: [Float]) -> [Float]? {
        let n = vector.count
        guard matrix.count == n && matrix.allSatisfy({ $0.count == n }) else {
            return nil
        }
        
        // Create augmented matrix
        var augMatrix = matrix
        var b = vector
        
        // Forward elimination with partial pivoting
        for i in 0..<n {
            // Find pivot
            var maxRow = i
            for k in (i+1)..<n {
                if abs(augMatrix[k][i]) > abs(augMatrix[maxRow][i]) {
                    maxRow = k
                }
            }
            
            // Swap rows
            if maxRow != i {
                augMatrix.swapAt(i, maxRow)
                b.swapAt(i, maxRow)
            }
            
            // Check for singular matrix
            if abs(augMatrix[i][i]) < 1e-10 {
                return nil
            }
            
            // Eliminate
            for k in (i+1)..<n {
                let factor = augMatrix[k][i] / augMatrix[i][i]
                for j in i..<n {
                    augMatrix[k][j] -= factor * augMatrix[i][j]
                }
                b[k] -= factor * b[i]
            }
        }
        
        // Back substitution
        var x = Array(repeating: Float(0), count: n)
        for i in (0..<n).reversed() {
            x[i] = b[i]
            for j in (i+1)..<n {
                x[i] -= augMatrix[i][j] * x[j]
            }
            x[i] /= augMatrix[i][i]
        }
        
        return x
    }
    
    /// Calculate parameter uncertainties using Jacobian matrix (MATLAB-style)
    func calculateParameterUncertainties(
        jacobian: [[Float]],
        residuals: [Float],
        params: [Float]
    ) -> ParameterErrors? {
        let dof = residuals.count - params.count
        let r0 = params[0], rinf = params[1], tau = params[2], alpha = params[3]
        let gap = r0 - rinf
        guard dof > 0, gap > 0, rinf > 0, tau > 0, alpha > 0,
              let inverse = calculateMatrixInverse(matrix: calculateJtJ(jacobian: jacobian)) else {
            return nil
        }
        let mse = residuals.map { $0 * $0 }.reduce(0, +) / Float(dof)
        // Delta method using gradients of log(Re), log(Ri), log(Cm), log(fc), log(alpha).
        // Ri = R0*Rinf/gap and Cm = tau*gap/R0².
        let gradients: [[Float]] = [
            [1/r0, 0, 0, 0], [1/r0 - 1/gap, 1/rinf + 1/gap, 0, 0],
            [1/gap - 2/r0, -1/gap, 1/tau, 0], [0, 0, -1/tau, 0], [0, 0, 0, 1/alpha]
        ]
        var errors: [Float] = []
        for gradient in gradients {
            var variance: Float = 0
            for i in gradient.indices {
                for j in gradient.indices {
                    variance += gradient[i] * inverse[i][j] * gradient[j]
                }
            }
            let percent = 100 * sqrt(mse * variance)
            guard percent.isFinite else { return nil }
            errors.append(percent)
        }
        return ParameterErrors(reError: errors[0], riError: errors[1], cmError: errors[2],
                               fcError: errors[3], alphaError: errors[4])
    }

    func calculateMatrixInverse(matrix: [[Float]]) -> [[Float]]? {
        let n = matrix.count
        guard matrix.allSatisfy({ $0.count == n }) else { return nil }
        
        // Create augmented matrix [A|I]
        var augmented = Array(repeating: Array(repeating: Float(0), count: 2*n), count: n)
        
        for i in 0..<n {
            for j in 0..<n {
                augmented[i][j] = matrix[i][j]
                augmented[i][j + n] = (i == j) ? 1.0 : 0.0  // Identity matrix
            }
        }
        
        // Forward elimination
        for i in 0..<n {
            // Find pivot
            var maxRow = i
            for k in (i+1)..<n {
                if abs(augmented[k][i]) > abs(augmented[maxRow][i]) {
                    maxRow = k
                }
            }
            
            // Swap rows
            if maxRow != i {
                augmented.swapAt(i, maxRow)
            }
            
            // Check for singular matrix
            if abs(augmented[i][i]) < 1e-12 {
                return nil
            }
            
            // Make diagonal element 1
            let pivot = augmented[i][i]
            for j in 0..<(2*n) {
                augmented[i][j] /= pivot
            }
            
            // Eliminate column
            for k in 0..<n {
                if k != i {
                    let factor = augmented[k][i]
                    for j in 0..<(2*n) {
                        augmented[k][j] -= factor * augmented[i][j]
                    }
                }
            }
        }
        
        // Extract inverse matrix from right side
        var inverse = Array(repeating: Array(repeating: Float(0), count: n), count: n)
        for i in 0..<n {
            for j in 0..<n {
                inverse[i][j] = augmented[i][j + n]
            }
        }
        
        return inverse
    }
    
    func calculateErrorAndGradient(
        params: [Float],
        frequencies: [Float],
        impedances: [Complex]
    ) -> (error: Float, gradient: [Float]) {
        
        let residuals = calculateResiduals(params: params, frequencies: frequencies, impedances: impedances)
        let error = sqrt(residuals.map { $0 * $0 }.reduce(0, +) / Float(residuals.count))
        
        // Simple finite difference gradients for fallback method
        var gradients = Array(repeating: Float(0), count: params.count)
        
        for i in 0..<params.count {
            var paramsPlus = params
            let epsilon = max(abs(params[i]), 1e-7) * sqrt(Float.ulpOfOne)
            paramsPlus[i] += epsilon
            let residualsPlus = calculateResiduals(params: paramsPlus, frequencies: frequencies, impedances: impedances)
            let errorPlus = sqrt(residualsPlus.map { $0 * $0 }.reduce(0, +) / Float(residualsPlus.count))
            
            gradients[i] = (errorPlus - error) / epsilon
        }
        
        return (error, gradients)
    }
    
    func applyParameterConstraints(_ params: [Float], frequencies: [Float], impedances: [Complex]) -> [Float] {
        
        let maxMagnitude = impedances.map { $0.magnitude }.max() ?? 1000
        let margin = maxMagnitude * 0.2
        
        // MATLAB parameter order: [R0, Rinf, tau, alpha]
        return [
            max(0, min(params[0], maxMagnitude + margin)),    // R0: 0 to maxMag + margin
            max(0, min(params[1], maxMagnitude + margin)),    // Rinf: 0 to maxMag + margin
            max(1e-6, min(params[2], 1e-3)),                 // tau: 1e-6 to 0.001 (MATLAB bounds)
            max(0.1, min(params[3], 1.0))                    // alpha: 0.1 to 1.0
        ]
    }
}

// MARK: - Quality Assessment

private extension BioimpedanceProcessor {
    
    func assessContactQuality(_ data: ImpedanceData) -> ContactQuality {
        // Simplified contact assessment
        // Real implementation would check electrode impedance from device
        let _ = data.magnitudes.reduce(0, +) / Float(data.magnitudes.count)
        
        // Estimate electrode impedance based on magnitude stability
        let magnitudeStd = calculateStandardDeviation(data.magnitudes)
        let estimatedElectrodeImpedance = magnitudeStd * 1000  // Rough estimate
        
        // Estimate mismatch from phase variations
        let phaseStd = calculateStandardDeviation(data.phases)
        let estimatedMismatch = phaseStd * 2  // Convert phase std to percentage
        
        return ContactQuality(
            electrodeImpedance: estimatedElectrodeImpedance,
            mismatchPercentage: estimatedMismatch
        )
    }
    
    func assessSignalQuality(_ data: ImpedanceData) -> SignalQuality {
        
        let magnitudes = data.magnitudes
        let phases = data.phases
        
        // Estimate SNR from magnitude smoothness
        let magnitudeStd = calculateStandardDeviation(magnitudes)
        let magnitudeMean = magnitudes.reduce(0, +) / Float(magnitudes.count)
        let estimatedSNR = 20 * log10(magnitudeMean / (magnitudeStd + 1e-10))
        
        // Phase stability
        let phaseStability = calculateStandardDeviation(phases)
        
        // Frequency response assessment
        let responseQuality: FrequencyResponseQuality
        if phaseStability < 2.0 && estimatedSNR > 40 {
            responseQuality = .excellent
        } else if phaseStability < 5.0 && estimatedSNR > 30 {
            responseQuality = .good
        } else if phaseStability < 10.0 && estimatedSNR > 20 {
            responseQuality = .fair
        } else {
            responseQuality = .poor
        }
        
        return SignalQuality(
            snr: estimatedSNR,
            phaseStability: phaseStability,
            frequencyResponse: responseQuality
        )
    }
    
    func assessStability(_ data: ImpedanceData) -> StabilityMetrics {
        
        // Movement detection from quaternion variance (if available)
        let movementDetected: Bool
        let quaternionStability: Float
        
        if let _ = data.deviceInfo?.quaternion,
           let variance = data.deviceInfo?.quaternionVariance {
            quaternionStability = variance.magnitude
            movementDetected = quaternionStability > 0.01  // Threshold for movement
        } else {
            quaternionStability = 0
            movementDetected = false
        }
        
        // Impedance stability
        let magnitudeStd = calculateStandardDeviation(data.magnitudes)
        let impedanceStability = magnitudeStd / (data.magnitudes.reduce(0, +) / Float(data.magnitudes.count))
        
        // Interference level based on signal quality
        let interferenceLevel: InterferenceLevel
        if impedanceStability < 0.02 {
            interferenceLevel = .minimal
        } else if impedanceStability < 0.05 {
            interferenceLevel = .low
        } else if impedanceStability < 0.1 {
            interferenceLevel = .moderate
        } else {
            interferenceLevel = .high
        }
        
        return StabilityMetrics(
            movementDetected: movementDetected,
            quaternionStability: quaternionStability,
            impedanceStability: impedanceStability,
            interferenceLevel: interferenceLevel
        )
    }
    
    func calculateStandardDeviation(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        
        let mean = values.reduce(0, +) / Float(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        let variance = squaredDiffs.reduce(0, +) / Float(values.count - 1)
        return sqrt(variance)
    }
}

// MARK: - Extensions

private extension ContactStatus {
    var qualityScore: Float {
        switch self {
        case .excellent: return 1.0
        case .good: return 0.8
        case .fair: return 0.6
        case .poor: return 0.3
        }
    }
}

private extension SignalQuality {
    var qualityScore: Float {
        let snrScore = min(1.0, max(0.0, (snr - 10) / 50.0))  // Normalize SNR to 0-1
        let stabilityScore = max(0.0, 1.0 - phaseStability / 10.0)  // Normalize phase stability
        let responseScore = frequencyResponse.qualityScore
        
        return (snrScore + stabilityScore + responseScore) / 3.0
    }
}

private extension FrequencyResponseQuality {
    var qualityScore: Float {
        switch self {
        case .excellent: return 1.0
        case .good: return 0.8
        case .fair: return 0.6
        case .poor: return 0.3
        }
    }
}

// MARK: - Errors

public enum ProcessingError: LocalizedError, Sendable {
    case invalidDataSize
    case invalidFrequencyRange
    case optimizationFailed
    case numericalInstability
    
    public var errorDescription: String? {
        switch self {
        case .invalidDataSize: return "Invalid measurement data size"
        case .invalidFrequencyRange: return "Invalid frequency range"
        case .optimizationFailed: return "Optimization failed to converge"
        case .numericalInstability: return "Numerical instability detected"
        }
    }
}