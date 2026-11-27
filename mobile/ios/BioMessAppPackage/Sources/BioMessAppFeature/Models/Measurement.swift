import Foundation
import SwiftData

/// Individual muscle measurement within a session
/// Matches Supabase `measurements` table schema for sync compatibility
@Model
public final class Measurement {

    // MARK: - Properties

    /// Unique identifier (client-generated UUID)
    public var id: UUID

    /// Reference to the measurement session
    public var session: MeasurementSession?

    /// Muscle group measured (quadriceps, hamstring) - stored as string for Supabase compatibility
    public var muscleGroup: String

    /// Body side (left, right) - stored as string for Supabase compatibility
    public var side: String

    /// Perceived fatigue level for this specific muscle (0-10)
    public var perceivedFatigue: Int

    /// Raw impedance data as JSON (stored as Data for SwiftData compatibility)
    public var rawDataJSON: Data?

    /// Measurement timestamp
    public var measuredAt: Date

    /// Sync status for cloud synchronization
    public var syncStatus: SyncStatus

    /// Last sync attempt timestamp
    public var lastSyncAttempt: Date?

    /// Sync error message if failed
    public var syncError: String?

    /// Person measured (new Myohm flow). Older records may only link through a session.
    public var personID: UUID?

    /// Distance between V+ and V− of the band used for local measurements (mm).
    public var bandMillimeters: Int?

    /// Body weight entered for a whole-body measurement (kg).
    public var bodyWeightKg: Double?

    /// Whether the five-minute supine rest was completed before a whole-body measurement.
    public var restCompleted: Bool?

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        session: MeasurementSession? = nil,
        muscleGroup: String,
        side: String,
        perceivedFatigue: Int,
        rawDataJSON: Data? = nil,
        measuredAt: Date = Date(),
        syncStatus: SyncStatus = .pending,
        lastSyncAttempt: Date? = nil,
        syncError: String? = nil
    ) {
        self.id = id
        self.session = session
        self.muscleGroup = muscleGroup
        self.side = side
        self.perceivedFatigue = perceivedFatigue
        self.rawDataJSON = rawDataJSON
        self.measuredAt = measuredAt
        self.syncStatus = syncStatus
        self.lastSyncAttempt = lastSyncAttempt
        self.syncError = syncError
    }

    // MARK: - Computed Properties

    /// Full display name (e.g., "Quadriceps (Left)")
    public var fullDisplayName: String {
        let muscleDisplay: String
        switch muscleGroup {
        case "quadriceps": muscleDisplay = "Cuádriceps"
        case "hamstrings": muscleDisplay = "Isquiotibiales"
        default: muscleDisplay = muscleGroup.capitalized
        }
        let sideDisplay = side == "left" ? "Izquierdo" : "Derecho"
        return "\(muscleDisplay) (\(sideDisplay))"
    }

    /// Short display name (e.g., "Quad L")
    public var shortDisplayName: String {
        let muscleShort = muscleGroup == "quadriceps" ? "Cuád" : "Isq"
        let sideShort = side == "left" ? "I" : "D"
        return "\(muscleShort) \(sideShort)"
    }

    /// Fatigue level description
    public var fatigueDescription: String {
        switch perceivedFatigue {
        case 0...2: return "Baja"
        case 3...5: return "Moderada"
        case 6...8: return "Alta"
        case 9...10: return "Muy Alta"
        default: return "Desconocida"
        }
    }

    /// Whether this measurement has raw data
    public var hasRawData: Bool {
        rawDataJSON != nil
    }

    /// Decoded raw impedance data from JSON storage
    public var impedanceData: ImpedanceData? {
        guard let data = rawDataJSON else { return nil }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return try? decoder.decode(ImpedanceData.self, from: data)
    }

    /// Convert to RawMeasurement for use with RawMeasurementDetailView
    public var asRawMeasurement: RawMeasurement? {
        guard let rawData = impedanceData else { return nil }

        var extractedRepetitions: [ImpedanceData]? = nil
        if rawData.numRepetitions > 1 {
            extractedRepetitions = rawData.repetitions.map { measurementPoints in
                ImpedanceData(
                    measurements: measurementPoints,
                    timestamp: rawData.timestamp,
                    deviceInfo: rawData.deviceInfo
                )
            }
        }

        return RawMeasurement(
            id: id,
            rawData: rawData,
            captureTimestamp: measuredAt,
            processingState: .pending,
            results: nil,
            processingAttempts: 0,
            lastProcessingAttempt: nil,
            processingError: nil,
            sessionId: session?.id,
            muscleGroup: muscleGroup == "laboratory" ? nil : muscleGroup,
            side: muscleGroup == "laboratory" ? nil : side,
            perceivedFatigue: muscleGroup == "laboratory" ? nil : perceivedFatigue,
            repetitions: extractedRepetitions,
            signalQuality: nil
        )
    }

    // MARK: - Sync Methods

    /// Mark as needing sync (for local modifications)
    public func markModified() {
        if syncStatus == .synced {
            syncStatus = .modified
        }
    }

    /// Mark sync as started
    public func markSyncing() {
        syncStatus = .syncing
        lastSyncAttempt = Date()
        syncError = nil
    }

    /// Mark sync as successful
    public func markSynced() {
        syncStatus = .synced
        syncError = nil
    }

    /// Mark sync as failed
    public func markSyncFailed(error: String) {
        syncStatus = .failed
        syncError = error
    }
}
