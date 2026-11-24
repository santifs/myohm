import Foundation
import OSLog

/// Calibration processor implementing 3-point Lagrange interpolation
/// Based on MATLAB calibrateZQuad.m and generateCalibratedData.m
@Observable
public final class CalibrationProcessor: Sendable {
    
    private let logger = Logger(subsystem: "com.biomess.health", category: "Calibration")
    
    public init() {}
    
    // MARK: - Core Calibration Functions
    
    /// Apply 3-point Lagrange interpolation calibration to raw impedance measurements
    /// This is the core MATLAB algorithm: calibrateZQuad.m
    public func calibrateImpedance(
        _ rawImpedance: [Complex],
        using calibrationConstants: CalibrationConstants
    ) throws -> [Complex] {
        
        guard calibrationConstants.calibrationMeasurements.count == 3 else {
            throw CalibrationError.invalidCalibrationData
        }
        
        guard rawImpedance.count == calibrationConstants.calibrationMeasurements[0].frequencies.count else {
            throw CalibrationError.frequencyMismatch
        }
        
        logger.info("Applying 3-point Lagrange calibration to \(rawImpedance.count) frequency points")
        
        var calibratedImpedance = [Complex]()
        
        for frequencyIndex in 0..<rawImpedance.count {
            let zm = rawImpedance[frequencyIndex]  // Raw measured impedance
            
            // Extract calibration reference measurements at this frequency
            let zmr0 = calibrationConstants.calibrationMeasurements[0].complexAverage[frequencyIndex]
            let zmr1 = calibrationConstants.calibrationMeasurements[1].complexAverage[frequencyIndex]
            let zmr2 = calibrationConstants.calibrationMeasurements[2].complexAverage[frequencyIndex]
            
            // Extract theoretical model values at this frequency
            let zr0 = calibrationConstants.calibrationModels[0].complexImpedance[frequencyIndex]
            let zr1 = calibrationConstants.calibrationModels[1].complexImpedance[frequencyIndex]
            let zr2 = calibrationConstants.calibrationModels[2].complexImpedance[frequencyIndex]
            
            // Apply 3-point Lagrange interpolation
            let calibratedValue = lagrangeInterpolation3Point(
                zm: zm,
                zmr0: zmr0, zmr1: zmr1, zmr2: zmr2,
                zr0: zr0, zr1: zr1, zr2: zr2
            )
            
            calibratedImpedance.append(calibratedValue)
        }
        
        logger.info("Calibration applied successfully")
        return calibratedImpedance
    }
    
    /// 3-point Lagrange interpolation algorithm (MATLAB calibrateZQuad.m)
    /// impedance = Zr0 * L0(Zm) + Zr1 * L1(Zm) + Zr2 * L2(Zm)
    /// where Li(Zm) are Lagrange basis polynomials
    private func lagrangeInterpolation3Point(
        zm: Complex,     // Measured impedance to calibrate
        zmr0: Complex, zmr1: Complex, zmr2: Complex,  // Reference measurements  
        zr0: Complex, zr1: Complex, zr2: Complex      // Reference theoretical values
    ) -> Complex {
        
        // Lagrange basis polynomials
        // L0(Zm) = (Zm - Zmr1)(Zm - Zmr2) / (Zmr0 - Zmr1)(Zmr0 - Zmr2)
        let l0_numerator = (zm - zmr1) * (zm - zmr2)
        let l0_denominator = (zmr0 - zmr1) * (zmr0 - zmr2)
        let l0 = l0_numerator / l0_denominator
        
        // L1(Zm) = (Zm - Zmr2)(Zm - Zmr0) / (Zmr1 - Zmr2)(Zmr1 - Zmr0)
        let l1_numerator = (zm - zmr2) * (zm - zmr0)
        let l1_denominator = (zmr1 - zmr2) * (zmr1 - zmr0)
        let l1 = l1_numerator / l1_denominator
        
        // L2(Zm) = (Zm - Zmr0)(Zm - Zmr1) / (Zmr2 - Zmr0)(Zmr2 - Zmr1)
        let l2_numerator = (zm - zmr0) * (zm - zmr1)
        let l2_denominator = (zmr2 - zmr0) * (zmr2 - zmr1)
        let l2 = l2_numerator / l2_denominator
        
        // Final interpolated value
        return zr0 * l0 + zr1 * l1 + zr2 * l2
    }
    
    // MARK: - Calibration Generation
    
    /// Generate calibration constants from measurements of known reference circuits
    /// Follows MATLAB structure: C1 → C2 → C3 sequential measurement
    public func generateCalibrationConstants(
        c1Measurement: CalibrationMeasurement,
        c2Measurement: CalibrationMeasurement,
        c3Measurement: CalibrationMeasurement
    ) throws -> CalibrationConstants {
        
        logger.info("Generating calibration constants from C1, C2, C3 measurements")
        
        let frequencies = c1Measurement.frequencies
        
        // Validate that all measurements have same frequencies
        guard c2Measurement.frequencies == frequencies && c3Measurement.frequencies == frequencies else {
            throw CalibrationError.frequencyMismatch
        }
        
        // Generate theoretical models for each calibration circuit using MATLAB parameters
        let c1Params = CalibrationCircuit.c1.referenceParameters
        let c2Params = CalibrationCircuit.c2.referenceParameters
        let c3Params = CalibrationCircuit.c3.referenceParameters
        
        let c1Model = BodyModel(
            Re: c1Params[0],    // 1270Ω
            Ri: c1Params[1],    // 432Ω  
            Cm: c1Params[2],    // 1.8nF
            frequencies: frequencies
        )
        
        let c2Model = BodyModel(
            Re: c2Params[0],    // 422Ω
            Ri: c2Params[1],    // 316Ω
            Cm: c2Params[2],    // 3.3nF
            frequencies: frequencies
        )
        
        let c3Model = BodyModel(
            Re: c3Params[0],    // 100Ω
            Ri: c3Params[1],    // 332Ω
            Cm: c3Params[2],    // 4.7nF
            frequencies: frequencies
        )
        
        logger.debug("Generated models: C1(Re=\(c1Params[0])Ω), C2(Re=\(c2Params[0])Ω), C3(Re=\(c3Params[0])Ω)")
        
        // Validate calibration quality
        let quality = try validateCalibrationQuality(
            measurements: [c1Measurement, c2Measurement, c3Measurement],
            models: [c1Model, c2Model, c3Model]
        )
        
        let constants = CalibrationConstants(
            cal1Measured: c1Measurement,
            cal2Measured: c2Measurement,
            cal3Measured: c3Measurement,
            cal1Model: c1Model,
            cal2Model: c2Model,
            cal3Model: c3Model,
            quality: quality
        )
        
        logger.info("Calibration constants generated with quality score: \(quality.overallScore)")
        
        if !quality.isValid {
            logger.warning("Calibration quality is below research standards")
        }
        
        return constants
    }
    
    /// Validate calibration quality by comparing measurements to theoretical models
    private func validateCalibrationQuality(
        measurements: [CalibrationMeasurement],
        models: [BodyModel]
    ) throws -> CalibrationQuality {
        
        // Calculate precision score (based on CV%)
        var maxPrecisionError: Float = 0
        var totalPrecisionError: Float = 0
        var precisionCount = 0
        
        for measurement in measurements {
            for precision in measurement.precision {
                maxPrecisionError = max(maxPrecisionError, precision)
                totalPrecisionError += precision
                precisionCount += 1
            }
        }
        
        let meanPrecisionError = totalPrecisionError / Float(precisionCount)
        let precisionScore = max(0, 1.0 - meanPrecisionError / 5.0)  // 5% is target threshold
        
        // Calculate fit quality score (residual error vs theoretical)
        var totalResidualError: Float = 0
        var residualCount = 0
        
        for (measurement, model) in zip(measurements, models) {
            for (measured, theoretical) in zip(measurement.complexAverage, model.complexImpedance) {
                let residual = abs(measured.magnitude - theoretical.magnitude) / theoretical.magnitude
                totalResidualError += residual
                residualCount += 1
            }
        }
        
        let meanResidualError = totalResidualError / Float(residualCount)
        let fitScore = max(0, 1.0 - meanResidualError)
        
        // Calculate frequency coverage score
        let frequencies = measurements[0].frequencies
        let minFreq = frequencies.min() ?? 0
        let maxFreq = frequencies.max() ?? 0
        let frequencyRange = maxFreq - minFreq
        let targetRange: Float = 500000 - 1000  // 1kHz to 500kHz
        let coverageScore = min(1.0, frequencyRange / targetRange)
        
        logger.debug("Calibration quality metrics:")
        logger.debug("  Precision score: \(precisionScore) (max CV%: \(maxPrecisionError))")
        logger.debug("  Fit score: \(fitScore) (mean residual: \(meanResidualError))")
        logger.debug("  Coverage score: \(coverageScore) (range: \(Int(frequencyRange))Hz)")
        
        return CalibrationQuality(
            precisionScore: precisionScore,
            fitScore: fitScore,
            coverageScore: coverageScore,
            maxPrecisionError: maxPrecisionError,
            meanResidualError: meanResidualError
        )
    }
    
    // MARK: - Calibration Measurement Processing
    
    /// Process raw calibration measurement data into averaged calibration measurement
    public func processCalibrationMeasurement(
        circuitName: String,
        rawMeasurements: [ImpedanceData],
        expectedFrequencies: [Float]
    ) throws -> CalibrationMeasurement {
        
        guard !rawMeasurements.isEmpty else {
            throw CalibrationError.noMeasurementData
        }
        
        logger.info("Processing \(rawMeasurements.count) raw measurements for circuit \(circuitName)")
        
        let frequencies = expectedFrequencies
        let numFrequencies = frequencies.count
        
        // Initialize arrays for averaging
        var magnitudeSum = Array(repeating: Float(0), count: numFrequencies)
        var phaseSum = Array(repeating: Float(0), count: numFrequencies)
        var magnitudeValues = Array(repeating: [Float](), count: numFrequencies)
        var phaseValues = Array(repeating: [Float](), count: numFrequencies)
        
        // Accumulate measurements
        for measurement in rawMeasurements {
            guard measurement.frequencies.count == numFrequencies else {
                throw CalibrationError.frequencyMismatch
            }
            
            for (index, freq) in measurement.frequencies.enumerated() {
                // Verify frequency matches expected value (within tolerance)
                guard abs(freq - frequencies[index]) < 0.01 * frequencies[index] else {
                    throw CalibrationError.frequencyMismatch
                }
                
                let magnitude = measurement.magnitudes[index]
                let phase = measurement.phases[index]
                
                magnitudeSum[index] += magnitude
                phaseSum[index] += phase
                magnitudeValues[index].append(magnitude)
                phaseValues[index].append(phase)
            }
        }
        
        // Calculate averages and statistics
        let numMeasurements = Float(rawMeasurements.count)
        var complexAverage = [Complex]()
        var precision = [Float]()
        var standardDeviation = [Float]()
        
        for index in 0..<numFrequencies {
            // Average values
            let avgMagnitude = magnitudeSum[index] / numMeasurements
            let avgPhase = phaseSum[index] / numMeasurements
            
            // Convert to complex
            let avgComplex = Complex(magnitude: avgMagnitude, phase: avgPhase * Float.pi / 180.0)
            complexAverage.append(avgComplex)
            
            // Calculate standard deviation
            let magStd = calculateStandardDeviation(magnitudeValues[index])
            let _ = calculateStandardDeviation(phaseValues[index]) // Phase std not used currently
            standardDeviation.append(magStd)
            
            // Calculate precision (CV%)
            let magnitudeCV = (magStd / avgMagnitude) * 100
            precision.append(magnitudeCV)
        }
        
        let measurement = CalibrationMeasurement(
            circuitName: circuitName,
            frequencies: frequencies,
            complexAverage: complexAverage,
            precision: precision,
            standardDeviation: standardDeviation
        )
        
        let maxCV = precision.max() ?? 0
        logger.info("Processed calibration measurement for \(circuitName): max CV% = \(String(format: "%.2f", maxCV))")
        
        return measurement
    }
    
    /// Calculate standard deviation of an array of values
    private func calculateStandardDeviation(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        
        let mean = values.reduce(0, +) / Float(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        let variance = squaredDiffs.reduce(0, +) / Float(values.count - 1)
        return sqrt(variance)
    }
}

// MARK: - Calibration Errors

public enum CalibrationError: LocalizedError, Sendable {
    case invalidCalibrationData
    case frequencyMismatch
    case insufficientMeasurements
    case invalidMeasurementCount
    case noMeasurementData
    case qualityTooLow
    case numericalInstability
    
    public var errorDescription: String? {
        switch self {
        case .invalidCalibrationData:
            return "Invalid calibration data - requires exactly 3 reference circuits"
        case .frequencyMismatch:
            return "Frequency mismatch between measurement and calibration data"
        case .insufficientMeasurements:
            return "Insufficient calibration measurements - need 3 reference circuits"
        case .invalidMeasurementCount:
            return "Invalid measurement count - need exactly 3 reference circuits"
        case .noMeasurementData:
            return "No measurement data provided for calibration"
        case .qualityTooLow:
            return "Calibration quality is too low for reliable correction"
        case .numericalInstability:
            return "Numerical instability in calibration calculation"
        }
    }
}