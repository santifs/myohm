import Foundation

/// Cole model parameters extracted from bioimpedance measurements
public struct ColeParameters: Sendable, Equatable, Codable {
    /// Extracellular resistance (Ω)
    public let Re: Float
    
    /// Intracellular resistance (Ω) 
    public let Ri: Float
    
    /// Membrane capacitance (nF)
    public let Cm: Float
    
    /// Characteristic frequency (kHz)
    public let fc: Float
    
    /// Dispersion parameter (0-1)
    public let alpha: Float
    
    /// Fitting error (%)
    public let error: Float
    
    /// Processing tier used for calculation
    public let processingTier: ProcessingTier
    
    /// Quality metrics
    public let quality: QualityMetrics
    
    /// Timestamp of calculation
    public let timestamp: Date
    
    public init(
        Re: Float,
        Ri: Float, 
        Cm: Float,
        fc: Float,
        alpha: Float,
        error: Float,
        processingTier: ProcessingTier,
        quality: QualityMetrics,
        timestamp: Date = Date()
    ) {
        self.Re = Re
        self.Ri = Ri
        self.Cm = Cm
        self.fc = fc
        self.alpha = alpha
        self.error = error
        self.processingTier = processingTier
        self.quality = quality
        self.timestamp = timestamp
    }
}

/// Processing tier classification
public enum ProcessingTier: String, Sendable, Codable, CaseIterable {
    case immediate = "immediate"    // Tier 1: <1s, single-start, ~85% accuracy
    case complete = "complete"      // Tier 2: 2-5s, multi-start, >95% accuracy
    
    public var description: String {
        switch self {
        case .immediate: return "Immediate"
        case .complete: return "Complete"
        }
    }
    
    public var expectedAccuracy: Float {
        switch self {
        case .immediate: return 0.85
        case .complete: return 0.95
        }
    }
}

/// Quality assessment metrics for bioimpedance measurements
public struct QualityMetrics: Sendable, Equatable, Codable {
    /// Overall quality score (0-1, where 1 is excellent)
    public let score: Float
    
    /// Electrode contact quality
    public let contactQuality: ContactQuality
    
    /// Signal-to-noise ratio assessment  
    public let signalQuality: SignalQuality
    
    /// Fit convergence metrics
    public let convergence: ConvergenceMetrics
    
    /// Movement/artifact detection
    public let stabilityMetrics: StabilityMetrics
    
    public init(
        score: Float,
        contactQuality: ContactQuality,
        signalQuality: SignalQuality,
        convergence: ConvergenceMetrics,
        stabilityMetrics: StabilityMetrics
    ) {
        self.score = score
        self.contactQuality = contactQuality
        self.signalQuality = signalQuality
        self.convergence = convergence
        self.stabilityMetrics = stabilityMetrics
    }
}

/// Electrode contact quality assessment
public struct ContactQuality: Sendable, Equatable, Codable {
    /// Electrode impedance (Ω) - should be <5kΩ for good contact
    public let electrodeImpedance: Float
    
    /// Mismatch between electrodes (%) - should be <5%
    public let mismatchPercentage: Float
    
    /// Contact status
    public let status: ContactStatus
    
    public init(electrodeImpedance: Float, mismatchPercentage: Float) {
        self.electrodeImpedance = electrodeImpedance
        self.mismatchPercentage = mismatchPercentage
        
        // Determine status based on thresholds from documentation
        if electrodeImpedance < 5000 && mismatchPercentage < 5 {
            self.status = .excellent
        } else if electrodeImpedance < 10000 && mismatchPercentage < 10 {
            self.status = .good
        } else if electrodeImpedance < 20000 && mismatchPercentage < 15 {
            self.status = .fair
        } else {
            self.status = .poor
        }
    }
}

public enum ContactStatus: String, Sendable, Codable, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    
    public var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "orange"
        case .poor: return "red"
        }
    }
}

/// Signal quality metrics
public struct SignalQuality: Sendable, Equatable, Codable {
    /// Signal-to-noise ratio (dB)
    public let snr: Float
    
    /// Phase stability (degrees of variation)
    public let phaseStability: Float
    
    /// Frequency response quality
    public let frequencyResponse: FrequencyResponseQuality
    
    public init(snr: Float, phaseStability: Float, frequencyResponse: FrequencyResponseQuality) {
        self.snr = snr
        self.phaseStability = phaseStability
        self.frequencyResponse = frequencyResponse
    }
}

public enum FrequencyResponseQuality: String, Sendable, Codable, CaseIterable {
    case excellent = "excellent"   // Smooth Cole circle
    case good = "good"             // Minor deviations
    case fair = "fair"             // Some noise/artifacts
    case poor = "poor"             // Significant artifacts
}

/// Convergence metrics for Cole fitting
public struct ConvergenceMetrics: Sendable, Equatable, Codable {
    /// Number of iterations required
    public let iterations: Int
    
    /// Final residual error
    public let residualError: Float
    
    /// Parameter standard errors
    public let parameterErrors: ParameterErrors
    
    /// Did the optimization converge?
    public let converged: Bool
    
    public init(iterations: Int, residualError: Float, parameterErrors: ParameterErrors, converged: Bool) {
        self.iterations = iterations
        self.residualError = residualError
        self.parameterErrors = parameterErrors
        self.converged = converged
    }
}

public struct ParameterErrors: Sendable, Equatable, Codable {
    public let reError: Float
    public let riError: Float
    public let cmError: Float
    public let fcError: Float
    public let alphaError: Float
    
    public init(reError: Float, riError: Float, cmError: Float, fcError: Float, alphaError: Float) {
        self.reError = reError
        self.riError = riError
        self.cmError = cmError
        self.fcError = fcError
        self.alphaError = alphaError
    }
}

/// Measurement stability and movement detection
public struct StabilityMetrics: Sendable, Equatable, Codable {
    /// Movement detected during measurement
    public let movementDetected: Bool
    
    /// Quaternion stability (variance)
    public let quaternionStability: Float
    
    /// Impedance stability across measurement
    public let impedanceStability: Float
    
    /// Environmental interference level
    public let interferenceLevel: InterferenceLevel
    
    public init(
        movementDetected: Bool,
        quaternionStability: Float,
        impedanceStability: Float,
        interferenceLevel: InterferenceLevel
    ) {
        self.movementDetected = movementDetected
        self.quaternionStability = quaternionStability
        self.impedanceStability = impedanceStability
        self.interferenceLevel = interferenceLevel
    }
}

public enum InterferenceLevel: String, Sendable, Codable, CaseIterable {
    case minimal = "minimal"
    case low = "low"
    case moderate = "moderate"
    case high = "high"
    
    public var description: String {
        switch self {
        case .minimal: return "Minimal interference"
        case .low: return "Low interference"
        case .moderate: return "Moderate interference"  
        case .high: return "High interference"
        }
    }
}