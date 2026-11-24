import Foundation

/// Calibration system for bioimpedance measurements
/// Implements 3-point Lagrange interpolation calibration based on MATLAB reference

// MARK: - Calibration Types

/// Individual calibration circuit being measured
public enum CalibrationCircuit: String, Sendable, Codable, CaseIterable {
    case c1 = "C1"
    case c2 = "C2"  
    case c3 = "C3"
    
    public var displayName: String {
        return self.rawValue
    }
    
    public var stepNumber: Int {
        switch self {
        case .c1: return 1
        case .c2: return 2
        case .c3: return 3
        }
    }
    
    public var description: String {
        switch self {
        case .c1: return "High resistance calibration circuit"
        case .c2: return "Medium resistance calibration circuit" 
        case .c3: return "Low resistance calibration circuit"
        }
    }
    
    /// Reference circuit parameters [Re, Ri, Cm] - MATLAB values
    public var referenceParameters: [Float] {
        switch self {
        case .c1: return [1270, 432, 1.8e-9]  // High resistance
        case .c2: return [422, 316, 3.3e-9]   // Medium resistance  
        case .c3: return [100, 332, 4.7e-9]   // Low resistance
        }
    }
}

// MARK: - Core Data Structures

/// Complete calibration constants for impedance correction
/// Follows MATLAB structure: cal1Measured, cal2Measured, cal3Measured + models
public struct CalibrationConstants: Sendable, Codable, Equatable {
    /// Measured data from C1 calibration circuit
    public let cal1Measured: CalibrationMeasurement
    
    /// Measured data from C2 calibration circuit  
    public let cal2Measured: CalibrationMeasurement
    
    /// Measured data from C3 calibration circuit
    public let cal3Measured: CalibrationMeasurement
    
    /// Theoretical model for C1 circuit
    public let cal1Model: BodyModel
    
    /// Theoretical model for C2 circuit
    public let cal2Model: BodyModel
    
    /// Theoretical model for C3 circuit
    public let cal3Model: BodyModel
    
    /// Quality assessment of calibration
    public let quality: CalibrationQuality
    
    /// Timestamp when calibration was performed
    public let timestamp: Date
    
    public init(
        cal1Measured: CalibrationMeasurement,
        cal2Measured: CalibrationMeasurement,
        cal3Measured: CalibrationMeasurement,
        cal1Model: BodyModel,
        cal2Model: BodyModel,
        cal3Model: BodyModel,
        quality: CalibrationQuality,
        timestamp: Date = Date()
    ) {
        self.cal1Measured = cal1Measured
        self.cal2Measured = cal2Measured
        self.cal3Measured = cal3Measured
        self.cal1Model = cal1Model
        self.cal2Model = cal2Model
        self.cal3Model = cal3Model
        self.quality = quality
        self.timestamp = timestamp
    }
    
    /// Convenience accessors for MATLAB-style usage
    public var calibrationMeasurements: [CalibrationMeasurement] {
        return [cal1Measured, cal2Measured, cal3Measured]
    }
    
    public var calibrationModels: [BodyModel] {
        return [cal1Model, cal2Model, cal3Model]
    }
}

/// Measured calibration data from a single reference circuit
public struct CalibrationMeasurement: Sendable, Codable, Equatable {
    /// Circuit identifier (C1, C2, etc.)
    public let circuitName: String
    
    /// Measurement frequencies (Hz)
    public let frequencies: [Float]
    
    /// Complex impedance measurements (averaged)
    public let complexAverage: [Complex]
    
    /// Precision (CV%) for each frequency point
    public let precision: [Float]
    
    /// Standard deviation of measurements
    public let standardDeviation: [Float]
    
    public init(
        circuitName: String,
        frequencies: [Float],
        complexAverage: [Complex],
        precision: [Float],
        standardDeviation: [Float]
    ) {
        self.circuitName = circuitName
        self.frequencies = frequencies
        self.complexAverage = complexAverage
        self.precision = precision
        self.standardDeviation = standardDeviation
    }
}

/// Theoretical body model for calibration reference
public struct BodyModel: Sendable, Codable, Equatable {
    /// Extracellular resistance (Ω)
    public let Re: Float
    
    /// Intracellular resistance (Ω)
    public let Ri: Float
    
    /// Membrane capacitance (F)
    public let Cm: Float
    
    /// Frequencies for model calculation
    public let frequencies: [Float]
    
    /// Theoretical complex impedance
    public let complexImpedance: [Complex]
    
    public init(Re: Float, Ri: Float, Cm: Float, frequencies: [Float]) {
        self.Re = Re
        self.Ri = Ri
        self.Cm = Cm
        self.frequencies = frequencies
        self.complexImpedance = BodyModel.generateBodyModel(
            frequencies: frequencies,
            Re: Re,
            Ri: Ri,
            Cm: Cm
        )
    }
    
    /// Generate theoretical body model impedance
    /// Model: Re || (Ri + 1/(jωCm))
    public static func generateBodyModel(
        frequencies: [Float],
        Re: Float,
        Ri: Float,
        Cm: Float
    ) -> [Complex] {
        return frequencies.map { freq in
            let omega = 2 * Float.pi * freq
            
            // Membrane impedance: Zcm = 1/(jωCm)
            let Zcm = Complex(real: 0, imaginary: -1.0 / (omega * Cm))
            
            // Series combination: Ri + Zcm
            let series = Complex(real: Ri, imaginary: 0) + Zcm
            
            // Parallel combination: Re || (Ri + Zcm)
            let Re_complex = Complex(real: Re, imaginary: 0)
            let numerator = Re_complex * series
            let denominator = Re_complex + series
            
            return numerator / denominator
        }
    }
}

// MARK: - Calibration Quality Assessment

/// Quality metrics for calibration validation
public struct CalibrationQuality: Sendable, Codable, Equatable {
    /// Precision score based on CV% (0-1, higher is better)
    public let precisionScore: Float
    
    /// Fit quality score based on residual error (0-1, higher is better)
    public let fitScore: Float
    
    /// Frequency coverage score (0-1, higher is better)
    public let coverageScore: Float
    
    /// Overall calibration quality (0-1, higher is better)
    public let overallScore: Float
    
    /// Maximum CV% across all measurements
    public let maxPrecisionError: Float
    
    /// Mean residual error vs theoretical models
    public let meanResidualError: Float
    
    public init(
        precisionScore: Float,
        fitScore: Float,
        coverageScore: Float,
        maxPrecisionError: Float,
        meanResidualError: Float
    ) {
        self.precisionScore = precisionScore
        self.fitScore = fitScore
        self.coverageScore = coverageScore
        self.maxPrecisionError = maxPrecisionError
        self.meanResidualError = meanResidualError
        self.overallScore = (precisionScore + fitScore + coverageScore) / 3.0
    }
    
    /// Is the calibration valid for research use?
    public var isValid: Bool {
        return overallScore > 0.8 && maxPrecisionError < 5.0
    }
    
    /// Does the calibration need to be redone?
    public var needsRecalibration: Bool {
        return overallScore < 0.6 || maxPrecisionError > 10.0
    }
    
    /// Quality status for UI display
    public var status: CalibrationStatus {
        if overallScore > 0.9 { return .excellent }
        if overallScore > 0.8 { return .good }
        if overallScore > 0.6 { return .fair }
        return .poor
    }
}

public enum CalibrationStatus: String, Sendable, Codable, CaseIterable {
    case excellent = "excellent"
    case good = "good" 
    case fair = "fair"
    case poor = "poor"
    
    public var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }
    
    public var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "orange" 
        case .poor: return "red"
        }
    }
    
    public var recommendation: String {
        switch self {
        case .excellent: return "Calibration is excellent for research use"
        case .good: return "Calibration is good for most applications"
        case .fair: return "Calibration is acceptable but consider recalibrating"
        case .poor: return "Calibration is poor - recalibration required"
        }
    }
}

// MARK: - Calibration State Management

/// State of the calibration process
public enum CalibrationState: Equatable, Sendable {
    case idle
    case preparing(circuit: CalibrationCircuit)
    case measuring(circuit: CalibrationCircuit, progress: Float)
    case processing
    case completed(CalibrationConstants)
    case error(String)
    
    public var isActive: Bool {
        switch self {
        case .idle, .completed, .error: return false
        case .preparing, .measuring, .processing: return true
        }
    }
    
    public var progressDescription: String {
        switch self {
        case .idle: return "Ready to calibrate"
        case .preparing(let circuit): return "Prepare circuit \(circuit.displayName)"
        case .measuring(let circuit, let progress): 
            return "Measuring circuit \(circuit.displayName) (\(Int(progress * 100))%)"
        case .processing: return "Processing calibration data"
        case .completed: return "Calibration completed"
        case .error(let message): return "Error: \(message)"
        }
    }
    
    public var currentCircuit: CalibrationCircuit? {
        switch self {
        case .preparing(let circuit), .measuring(let circuit, _):
            return circuit
        default:
            return nil
        }
    }
}