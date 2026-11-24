import Foundation
import SwiftData

/// Main athlete profile for bioimpedance measurements
/// Matches Supabase `athletes` table schema for sync compatibility
@Model
public final class Athlete {

    // MARK: - Properties

    /// Unique identifier (client-generated UUID)
    public var id: UUID

    /// Full name of the athlete
    public var fullName: String

    /// Date of birth for age calculations
    public var dateOfBirth: Date

    /// Dominant leg for bilateral comparisons
    public var dominantLeg: DominantLeg

    /// Biological sex for physiological tracking
    public var biologicalSex: BiologicalSex?

    /// Medical history notes (nullable)
    public var medicalHistory: String?

    /// Current medications (nullable)
    public var medications: String?

    /// Diet type (nullable)
    public var dietType: String?

    /// Daily caloric intake (nullable)
    public var dailyCalories: Int?

    /// Known allergies (nullable array)
    public var allergies: [String]?

    /// Usual physical activities (nullable array)
    public var usualActivities: [String]?

    /// Record creation timestamp
    public var createdAt: Date

    /// Last update timestamp
    public var updatedAt: Date

    // MARK: - Auth Properties

    /// User ID from Supabase Auth (owner of this athlete profile)
    public var userId: UUID?

    // MARK: - Sync Properties

    /// Sync status for cloud synchronization
    public var syncStatus: SyncStatus

    /// Last sync attempt timestamp
    public var lastSyncAttempt: Date?

    /// Sync error message if failed
    public var syncError: String?

    // MARK: - Relationships

    /// Anthropometric measurements history
    @Relationship(deleteRule: .cascade, inverse: \Anthropometrics.athlete)
    public var anthropometrics: [Anthropometrics]?

    /// Injury history
    @Relationship(deleteRule: .cascade, inverse: \Injury.athlete)
    public var injuries: [Injury]?

    /// Measurement sessions
    @Relationship(deleteRule: .cascade, inverse: \MeasurementSession.athlete)
    public var measurementSessions: [MeasurementSession]?

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        fullName: String,
        dateOfBirth: Date,
        dominantLeg: DominantLeg = .right,
        biologicalSex: BiologicalSex? = nil,
        medicalHistory: String? = nil,
        medications: String? = nil,
        dietType: String? = nil,
        dailyCalories: Int? = nil,
        allergies: [String]? = nil,
        usualActivities: [String]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        userId: UUID? = nil,
        syncStatus: SyncStatus = .pending,
        lastSyncAttempt: Date? = nil,
        syncError: String? = nil
    ) {
        self.id = id
        self.fullName = fullName
        self.dateOfBirth = dateOfBirth
        self.dominantLeg = dominantLeg
        self.biologicalSex = biologicalSex
        self.medicalHistory = medicalHistory
        self.medications = medications
        self.dietType = dietType
        self.dailyCalories = dailyCalories
        self.allergies = allergies
        self.usualActivities = usualActivities
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userId = userId
        self.syncStatus = syncStatus
        self.lastSyncAttempt = lastSyncAttempt
        self.syncError = syncError
    }

    // MARK: - Computed Properties

    /// Age in years calculated from date of birth
    public var age: Int {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dateOfBirth, to: Date())
        return ageComponents.year ?? 0
    }

    /// Age group classification for clinical context
    public var ageGroup: String {
        switch age {
        case 0..<18:
            return "Pediatric (\(age)y)"
        case 18..<65:
            return "Adult (\(age)y)"
        case 65...:
            return "Senior (\(age)y)"
        default:
            return "Unknown"
        }
    }

    /// Latest anthropometric measurements
    public var latestAnthropometrics: Anthropometrics? {
        anthropometrics?.sorted { $0.measuredAt > $1.measuredAt }.first
    }

    /// Active injuries (not resolved)
    public var activeInjuries: [Injury] {
        injuries?.filter { $0.isActive } ?? []
    }

    /// BMI from latest anthropometrics (if available)
    public var bmi: Double? {
        latestAnthropometrics?.bmi
    }

    /// BMI category from latest anthropometrics (if available)
    public var bmiCategory: String? {
        latestAnthropometrics?.bmiCategory
    }

    /// Check if profile has minimum required data
    public var isComplete: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Display name for UI
    public var displayName: String {
        let trimmed = fullName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Unnamed Athlete" : trimmed
    }

    // MARK: - Methods

    /// Update the updatedAt timestamp
    public func touch() {
        updatedAt = Date()
        markModified()
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

    /// Get formatted date of birth
    public func formattedDateOfBirth(style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: dateOfBirth)
    }
}

// MARK: - DominantLeg Enum

/// Dominant leg for bilateral comparisons
public enum DominantLeg: String, Sendable, Codable, CaseIterable {
    case right = "right"
    case left = "left"
    case ambidextrous = "ambidextrous"

    public var displayName: String {
        switch self {
        case .right: return "Right"
        case .left: return "Left"
        case .ambidextrous: return "Ambidextrous"
        }
    }

    public var shortName: String {
        switch self {
        case .right: return "R"
        case .left: return "L"
        case .ambidextrous: return "A"
        }
    }
}

// MARK: - BiologicalSex Enum

/// Biological sex for physiological considerations (e.g., menstrual cycle tracking)
public enum BiologicalSex: String, Sendable, Codable, CaseIterable {
    case female = "female"
    case male = "male"

    public var displayName: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        }
    }

    public var spanishDisplayName: String {
        switch self {
        case .female: return "Mujer"
        case .male: return "Hombre"
        }
    }
}
