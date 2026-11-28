import Foundation
import SwiftData

/// SwiftData model for persisting bioimpedance measurements
@Model
public final class StoredMeasurement {
    // Core measurement data
    public var timestamp: Date
    public var deviceName: String
    public var deviceSerialNumber: String
    
    // Cole parameters (stored as individual properties for efficient querying)
    public var extracellularResistance: Float  // Re (Ω)
    public var intracellularResistance: Float  // Ri (Ω)  
    public var membraneCapacitance: Float      // Cm (nF)
    public var characteristicFrequency: Float  // fc (kHz)
    public var dispersionParameter: Float      // α (0-1)
    public var fittingError: Float             // Error (%)
    
    // Processing information
    public var processingTier: String          // "immediate" or "complete"
    public var processingTime: TimeInterval    // seconds
    
    // Quality metrics (simplified for storage)
    public var qualityScore: Float             // Overall score (0-1)
    public var contactQualityStatus: String    // excellent/good/fair/poor
    public var electrodeImpedance: Float       // Ω
    public var mismatchPercentage: Float       // %
    public var signalToNoiseRatio: Float       // dB
    public var phaseStability: Float           // degrees
    public var frequencyResponseQuality: String // excellent/good/fair/poor
    public var fitConverged: Bool?
    public var fitParameterErrors: Data?
    public var convergenceIterations: Int      // number of iterations
    public var residualError: Float?            // final error
    public var impedanceStability: Float?
    public var movementDetected: Bool          // movement during measurement
    public var interferenceLevel: String       // minimal/low/moderate/high
    
    // Raw measurement data (encoded as JSON for storage)
    public var rawMeasurementData: Data
    
    // Computed properties
    public var totalResistance: Float {
        extracellularResistance + intracellularResistance
    }
    
    public var measurementQuality: MeasurementQuality {
        if qualityScore >= 0.9 { return .excellent }
        if qualityScore >= 0.8 { return .good }  
        if qualityScore >= 0.6 { return .fair }
        return .poor
    }
    
    public init(
        timestamp: Date = Date(),
        deviceName: String,
        deviceSerialNumber: String,
        parameters: ColeParameters,
        processingTime: TimeInterval,
        rawData: ImpedanceData
    ) {
        self.timestamp = timestamp
        self.deviceName = deviceName
        self.deviceSerialNumber = deviceSerialNumber
        
        // Map Cole parameters
        self.extracellularResistance = parameters.Re
        self.intracellularResistance = parameters.Ri
        self.membraneCapacitance = parameters.Cm
        self.characteristicFrequency = parameters.fc
        self.dispersionParameter = parameters.alpha
        self.fittingError = parameters.error
        
        // Processing info
        self.processingTier = parameters.processingTier.rawValue
        self.processingTime = processingTime
        
        // Quality metrics
        self.qualityScore = parameters.quality.score
        self.contactQualityStatus = parameters.quality.contactQuality.status.rawValue
        self.electrodeImpedance = parameters.quality.contactQuality.electrodeImpedance
        self.mismatchPercentage = parameters.quality.contactQuality.mismatchPercentage
        self.signalToNoiseRatio = parameters.quality.signalQuality.snr
        self.phaseStability = parameters.quality.signalQuality.phaseStability
        self.frequencyResponseQuality = parameters.quality.signalQuality.frequencyResponse.rawValue
        self.fitConverged = parameters.quality.convergence.converged
        self.fitParameterErrors = parameters.quality.convergence.parameterErrors.flatMap { try? JSONEncoder().encode($0) }
        self.convergenceIterations = parameters.quality.convergence.iterations
        self.residualError = parameters.quality.convergence.residualError
        self.impedanceStability = parameters.quality.stabilityMetrics.impedanceStability
        self.movementDetected = parameters.quality.stabilityMetrics.movementDetected
        self.interferenceLevel = parameters.quality.stabilityMetrics.interferenceLevel.rawValue
        
        // Encode raw data as JSON
        do {
            self.rawMeasurementData = try JSONEncoder().encode(rawData)
        } catch {
            // Fallback to empty data if encoding fails
            self.rawMeasurementData = Data()
            print("Failed to encode raw measurement data: \(error)")
        }
    }
    
    /// Convert stored measurement back to ColeParameters
    public func toColeParameters() -> ColeParameters {
        let contactQuality = ContactQuality(
            electrodeImpedance: electrodeImpedance,
            mismatchPercentage: mismatchPercentage
        )
        
        let signalQuality = SignalQuality(
            snr: signalToNoiseRatio,
            phaseStability: phaseStability,
            frequencyResponse: FrequencyResponseQuality(rawValue: frequencyResponseQuality) ?? .fair
        )
        
        let parameterErrors = fitParameterErrors.flatMap { try? JSONDecoder().decode(ParameterErrors.self, from: $0) }

        let convergenceMetrics = ConvergenceMetrics(
            iterations: convergenceIterations,
            residualError: residualError,
            parameterErrors: parameterErrors,
            converged: fitConverged ?? false
        )
        
        let stabilityMetrics = StabilityMetrics(
            movementDetected: movementDetected,
            quaternionStability: movementDetected ? 0.05 : 0.001,
            impedanceStability: impedanceStability ?? residualError ?? 0,
            interferenceLevel: InterferenceLevel(rawValue: interferenceLevel) ?? .minimal
        )
        
        let quality = QualityMetrics(
            score: qualityScore,
            contactQuality: contactQuality,
            signalQuality: signalQuality,
            convergence: convergenceMetrics,
            stabilityMetrics: stabilityMetrics
        )
        
        return ColeParameters(
            Re: extracellularResistance,
            Ri: intracellularResistance,
            Cm: membraneCapacitance,
            fc: characteristicFrequency,
            alpha: dispersionParameter,
            error: fittingError,
            processingTier: ProcessingTier(rawValue: processingTier) ?? .immediate,
            quality: quality,
            timestamp: timestamp
        )
    }
    
    /// Decode raw measurement data
    public func getRawMeasurementData() -> ImpedanceData? {
        guard !rawMeasurementData.isEmpty else { return nil }
        
        do {
            return try JSONDecoder().decode(ImpedanceData.self, from: rawMeasurementData)
        } catch {
            print("Failed to decode raw measurement data: \(error)")
            return nil
        }
    }
}

/// Quality classification for UI display
public enum MeasurementQuality: String, CaseIterable, Sendable {
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
    
    public var stars: String {
        switch self {
        case .excellent: return "★★★★★"
        case .good: return "★★★★☆"
        case .fair: return "★★★☆☆"
        case .poor: return "★★☆☆☆"
        }
    }
}