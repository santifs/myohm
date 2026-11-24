import Foundation

/// Raw measurement that gets saved immediately after capture, before processing
/// Follows the capture-first, process-later pattern used by professional medical devices
/// Links to athlete/session system per design doc: docs/plans/2025-01-26-athlete-profiles-design.md
public struct RawMeasurement: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let rawData: ImpedanceData
    public let captureTimestamp: Date
    public var processingState: ProcessingState
    public var results: ColeParameters?
    public var processingAttempts: Int
    public var lastProcessingAttempt: Date?
    public var processingError: String?

    // MARK: - Session Context (new athlete/session system)

    /// Reference to the measurement session (links to MeasurementSession.id)
    public let sessionId: UUID?

    /// Which muscle group was measured
    public let muscleGroup: String?

    /// Which side (left/right)
    public let side: String?

    /// Perceived fatigue for this specific muscle (0-10)
    public let perceivedFatigue: Int?

    // MARK: - Firmware Data

    /// V2.1 Firmware: Multiple repetitions (5 sweeps per measurement)
    /// If present, contains 5 ImpedanceData objects (one per repetition)
    /// rawData contains the median/average for backward compatibility
    public let repetitions: [ImpedanceData]?

    /// Signal quality (0-1) for V2.1 measurements with repetitions
    public let signalQuality: Float?

    /// Processing state of the measurement
    public enum ProcessingState: String, Sendable, Codable, CaseIterable {
        case pending = "pending"           // Captured but not processed
        case processing = "processing"     // Currently being processed
        case completed = "completed"       // Successfully processed
        case failed = "failed"            // Processing failed
        case retrying = "retrying"         // Retrying after failure

        public var displayName: String {
            switch self {
            case .pending: return "Pending Analysis"
            case .processing: return "Analyzing..."
            case .completed: return "Complete"
            case .failed: return "Failed"
            case .retrying: return "Retrying..."
            }
        }

        public var canRetry: Bool {
            switch self {
            case .failed: return true
            default: return false
            }
        }
    }

    public init(
        id: UUID = UUID(),
        rawData: ImpedanceData,
        captureTimestamp: Date = Date(),
        processingState: ProcessingState = .pending,
        results: ColeParameters? = nil,
        processingAttempts: Int = 0,
        lastProcessingAttempt: Date? = nil,
        processingError: String? = nil,
        sessionId: UUID? = nil,
        muscleGroup: String? = nil,
        side: String? = nil,
        perceivedFatigue: Int? = nil,
        repetitions: [ImpedanceData]? = nil,
        signalQuality: Float? = nil
    ) {
        self.id = id
        self.rawData = rawData
        self.captureTimestamp = captureTimestamp
        self.processingState = processingState
        self.results = results
        self.processingAttempts = processingAttempts
        self.lastProcessingAttempt = lastProcessingAttempt
        self.processingError = processingError
        self.sessionId = sessionId
        self.muscleGroup = muscleGroup
        self.side = side
        self.perceivedFatigue = perceivedFatigue
        self.repetitions = repetitions
        self.signalQuality = signalQuality
    }

    /// Mark measurement as processing started
    public mutating func markProcessingStarted() {
        self.processingState = .processing
        self.processingAttempts += 1
        self.lastProcessingAttempt = Date()
        self.processingError = nil
    }

    /// Mark measurement as successfully processed
    public mutating func markProcessingCompleted(results: ColeParameters) {
        self.processingState = .completed
        self.results = results
        self.processingError = nil
    }

    /// Mark measurement as processing failed
    public mutating func markProcessingFailed(error: String) {
        self.processingState = .failed
        self.processingError = error
    }

    /// Check if this measurement should be retried
    public var shouldRetry: Bool {
        return processingState == .failed && processingAttempts < 3
    }

    /// Get age of this measurement in minutes
    public var ageInMinutes: Double {
        Date().timeIntervalSince(captureTimestamp) / 60.0
    }

    /// Display-friendly capture time
    public var displayTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: captureTimestamp)
    }

    /// Display-friendly muscle description (e.g., "Quadriceps Left")
    public var muscleDescription: String? {
        guard let muscle = muscleGroup else { return nil }
        let sideStr = side.map { " (\($0.capitalized))" } ?? ""
        return "\(muscle.capitalized)\(sideStr)"
    }

    /// Whether this measurement has session context
    public var hasSessionContext: Bool {
        sessionId != nil
    }
}