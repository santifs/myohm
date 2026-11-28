import Foundation
import BioMessCore

/// Type of bioimpedance measurement based on impedance characteristics
public enum MeasurementType: String, Sendable, Codable, CaseIterable {
    case body = "body"           // Human tissue (10-100Ω, ±20° phase)
    case circuit = "circuit"     // Electronic circuit (100-20000Ω, ±90° phase)
    case unknown = "unknown"     // Cannot determine type

    public var expectedMagnitudeRange: (min: Double, max: Double) {
        switch self {
        case .body: return (min: 5, max: 100)
        case .circuit: return (min: 50, max: 25000)
        case .unknown: return (min: 0, max: 1000)
        }
    }

    public var expectedPhaseRange: (min: Double, max: Double) {
        switch self {
        case .body: return (min: -20, max: 5)
        case .circuit: return (min: -95, max: 95)
        case .unknown: return (min: -45, max: 5)
        }
    }
}

/// Cole model parameters extracted from bioimpedance measurements
public struct ColeParameters: Sendable, Equatable {
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

    // MARK: - Additional Cole Parameters

    /// R0: DC resistance (low frequency) = Re (Ω)
    /// At low frequency, cell membrane blocks current → only extracellular flow
    /// Physiologically represents extracellular water (ECW) resistance
    public var R0: Float {
        Re
    }

    /// Rinf (R∞): High frequency resistance = Re || Ri (Ω)
    /// At high frequency, membrane capacitance short-circuits → parallel flow through both compartments
    /// Physiologically represents total body water (TBW) resistance
    public var Rinf: Float {
        (Re * Ri) / (Re + Ri)
    }
    
    /// Processing tier used for calculation
    public let processingTier: ProcessingTier
    
    /// Quality metrics
    public let quality: QualityMetrics
    
    /// Patient information snapshot
    public let patient: PatientSnapshot?

    /// Type of measurement (body tissue vs circuit)
    public let measurementType: MeasurementType

    /// Raw measurement data
    private enum CodingKeys: String, CodingKey {
        case Re, Ri, Cm, fc, alpha, error, processingTier, quality, patient, measurementType, timestamp, rawData
    }

    public let rawData: ImpedanceData?

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
        patient: PatientSnapshot? = nil,
        measurementType: MeasurementType? = nil,
        rawData: ImpedanceData? = nil,
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
        self.patient = patient
        self.rawData = rawData
        self.timestamp = timestamp

        // Auto-detect measurement type if not provided
        if let providedType = measurementType {
            self.measurementType = providedType
        } else {
            self.measurementType = Self.detectMeasurementType(rawData: rawData, parameters: (Re, Ri, Cm, fc, alpha))
        }
    }

    /// Automatically detect measurement type based on data characteristics
    static func detectMeasurementType(
        rawData: ImpedanceData?,
        parameters: (Re: Float, Ri: Float, Cm: Float, fc: Float, alpha: Float)
    ) -> MeasurementType {
        // Use raw data if available, otherwise fall back to Cole parameters
        if let data = rawData {
            let magnitudes = data.measurements.map { Double($0.magnitude) }
            let phases = data.measurements.map { Double($0.phase) }

            let avgMagnitude = magnitudes.reduce(0, +) / Double(magnitudes.count)
            let minPhase = phases.min() ?? 0
            let maxPhase = phases.max() ?? 0
            let phaseRange = maxPhase - minPhase

            // Body tissue characteristics:
            // - Lower impedance (10-100Ω)
            // - Smaller phase range (typically ±15°)
            // - Phase values between -20° and +5°
            if avgMagnitude < 150 && phaseRange < 40 && minPhase > -25 && maxPhase < 10 {
                return .body
            }

            // Circuit characteristics:
            // - Higher impedance (>100Ω, often thousands)
            // - Larger phase range (can span ±90°)
            // - Phase values can reach -90° to +90°
            if avgMagnitude > 100 || phaseRange > 60 || minPhase < -80 || maxPhase > 80 {
                return .circuit
            }
        }

        // Fallback to Cole parameters
        let totalResistance = parameters.Re + parameters.Ri

        // Body tissue typically has lower total resistance
        if totalResistance < 150 && parameters.fc > 10 && parameters.fc < 200 {
            return .body
        }

        // Circuit elements typically have higher resistance values
        if totalResistance > 150 {
            return .circuit
        }

        return .unknown
    }
}

/// Processing tier classification
public enum ProcessingTier: String, Sendable, Codable, CaseIterable {
    case immediate = "immediate"    // Tier 1: <1s, single-start, ~85% accuracy
    case complete = "complete"      // Tier 2: 2-5s, multi-start, >95% accuracy
    
    public var description: String {
        switch self {
        case .immediate: return "Rápido"
        case .complete: return "Completo"
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
    public let residualError: Float?
    
    /// Parameter standard errors
    public let parameterErrors: ParameterErrors?
    
    /// Did the optimization converge?
    public let converged: Bool
    
    public init(iterations: Int, residualError: Float?, parameterErrors: ParameterErrors?, converged: Bool) {
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

// MARK: - ColeParameters Codable Implementation

extension ColeParameters: Codable {
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.Re = try container.decode(Float.self, forKey: .Re)
        self.Ri = try container.decode(Float.self, forKey: .Ri)
        self.Cm = try container.decode(Float.self, forKey: .Cm)
        self.fc = try container.decode(Float.self, forKey: .fc)
        self.alpha = try container.decode(Float.self, forKey: .alpha)
        self.error = try container.decode(Float.self, forKey: .error)
        self.processingTier = try container.decode(ProcessingTier.self, forKey: .processingTier)
        self.quality = try container.decode(QualityMetrics.self, forKey: .quality)
        self.patient = try container.decodeIfPresent(PatientSnapshot.self, forKey: .patient)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)

        // Try to decode measurement type, fallback to detection if not available
        if let storedType = try container.decodeIfPresent(MeasurementType.self, forKey: .measurementType) {
            self.measurementType = storedType
        } else {
            // For legacy data, detect measurement type from parameters
            self.measurementType = Self.detectMeasurementType(
                rawData: nil,
                parameters: (Re, Ri, Cm, fc, alpha)
            )
        }

        // Decode rawData if available
        self.rawData = try container.decodeIfPresent(ImpedanceData.self, forKey: .rawData)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(Re, forKey: .Re)
        try container.encode(Ri, forKey: .Ri)
        try container.encode(Cm, forKey: .Cm)
        try container.encode(fc, forKey: .fc)
        try container.encode(alpha, forKey: .alpha)
        try container.encode(error, forKey: .error)
        try container.encode(processingTier, forKey: .processingTier)
        try container.encode(quality, forKey: .quality)
        try container.encodeIfPresent(patient, forKey: .patient)
        try container.encode(measurementType, forKey: .measurementType)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(rawData, forKey: .rawData)
    }
}