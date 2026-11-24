import Foundation
import SwiftData

/// Body measurements history for athletes
/// Matches Supabase `anthropometrics` table schema for sync compatibility
@Model
public final class Anthropometrics {

    // MARK: - Properties

    /// Unique identifier (client-generated UUID)
    public var id: UUID

    /// Reference to the athlete
    public var athlete: Athlete?

    /// Date when measurements were taken
    public var measuredAt: Date

    /// Body weight in kilograms (nullable)
    public var weightKg: Double?

    /// Height in centimeters (nullable)
    public var heightCm: Double?

    // MARK: - Thigh Measurements

    /// Right thigh length in centimeters (nullable)
    public var rightThighLengthCm: Double?

    /// Right thigh circumference in centimeters (nullable)
    public var rightThighCircumferenceCm: Double?

    /// Left thigh length in centimeters (nullable)
    public var leftThighLengthCm: Double?

    /// Left thigh circumference in centimeters (nullable)
    public var leftThighCircumferenceCm: Double?

    /// Additional notes (nullable)
    public var notes: String?

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        athlete: Athlete? = nil,
        measuredAt: Date = Date(),
        weightKg: Double? = nil,
        heightCm: Double? = nil,
        rightThighLengthCm: Double? = nil,
        rightThighCircumferenceCm: Double? = nil,
        leftThighLengthCm: Double? = nil,
        leftThighCircumferenceCm: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.athlete = athlete
        self.measuredAt = measuredAt
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.rightThighLengthCm = rightThighLengthCm
        self.rightThighCircumferenceCm = rightThighCircumferenceCm
        self.leftThighLengthCm = leftThighLengthCm
        self.leftThighCircumferenceCm = leftThighCircumferenceCm
        self.notes = notes
    }

    // MARK: - Computed Properties

    /// Calculate BMI if height and weight are valid
    public var bmi: Double? {
        guard let height = heightCm,
              let weight = weightKg,
              height > 0 else { return nil }

        let heightInMeters = height / 100.0
        return weight / (heightInMeters * heightInMeters)
    }

    /// BMI category description
    public var bmiCategory: String {
        guard let bmi = bmi else { return "Unknown" }

        switch bmi {
        case ..<18.5:
            return "Underweight"
        case 18.5..<25.0:
            return "Normal weight"
        case 25.0..<30.0:
            return "Overweight"
        case 30.0...:
            return "Obese"
        default:
            return "Unknown"
        }
    }

    /// Check if basic measurements are available
    public var hasBasicMeasurements: Bool {
        weightKg != nil && heightCm != nil
    }

    /// Check if right thigh measurements are complete
    public var hasRightThighMeasurements: Bool {
        rightThighLengthCm != nil &&
        rightThighCircumferenceCm != nil
    }

    /// Check if left thigh measurements are complete
    public var hasLeftThighMeasurements: Bool {
        leftThighLengthCm != nil &&
        leftThighCircumferenceCm != nil
    }

    /// Check if bilateral thigh measurements are complete
    public var hasBilateralThighMeasurements: Bool {
        hasRightThighMeasurements && hasLeftThighMeasurements
    }

    /// Thigh circumference asymmetry percentage (positive = right larger)
    public var thighCircumferenceAsymmetry: Double? {
        guard let right = rightThighCircumferenceCm,
              let left = leftThighCircumferenceCm,
              left > 0 else { return nil }

        return ((right - left) / left) * 100.0
    }

    // MARK: - Convenience Methods

    /// Get thigh length for a specific side
    public func thighLength(side: Side) -> Double? {
        switch side {
        case .right: return rightThighLengthCm
        case .left: return leftThighLengthCm
        }
    }

    /// Get thigh circumference for a specific side
    public func thighCircumference(side: Side) -> Double? {
        switch side {
        case .right: return rightThighCircumferenceCm
        case .left: return leftThighCircumferenceCm
        }
    }

    /// Get formatted measurement date
    public func formattedMeasuredAt(style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: measuredAt)
    }
}

// MARK: - Side Enum

/// Body side for bilateral measurements
public enum Side: String, Sendable, Codable, CaseIterable {
    case right = "right"
    case left = "left"

    public var displayName: String {
        switch self {
        case .right: return "Right"
        case .left: return "Left"
        }
    }

    public var shortName: String {
        switch self {
        case .right: return "R"
        case .left: return "L"
        }
    }

    /// Get the opposite side
    public var opposite: Side {
        switch self {
        case .right: return .left
        case .left: return .right
        }
    }
}

// MARK: - MuscleGroup Enum

/// Muscle groups for bioimpedance measurements.
///
/// Corresponds to the Supabase `muscle_group` enum. Adding a new value here
/// requires a backend migration adding it to that enum first.
public enum MuscleGroup: String, Sendable, Codable, CaseIterable, Identifiable {
    case quadriceps = "quadriceps"
    case hamstring = "hamstring"
    case bicepsBrachii = "biceps_brachii"      // BICEPS_TFG
    case vastusLateralis = "vastus_lateralis"  // SENTADILLA_TFM
    case bicepsFemoris = "biceps_femoris"      // SENTADILLA_TFM

    public var id: String { rawValue }

    /// Localized name shown to the user (Spanish).
    public var displayName: String {
        switch self {
        case .quadriceps: return "Cuadriceps"
        case .hamstring: return "Isquiotibial"
        case .bicepsBrachii: return "Bíceps braquial"
        case .vastusLateralis: return "Vasto lateral"
        case .bicepsFemoris: return "Bíceps femoral"
        }
    }

    /// Anatomical location description in Spanish.
    public var location: String {
        switch self {
        case .quadriceps: return "Parte frontal del muslo"
        case .hamstring: return "Parte posterior del muslo"
        case .bicepsBrachii: return "Músculo frontal del brazo"
        case .vastusLateralis: return "Cabeza lateral del cuádriceps"
        case .bicepsFemoris: return "Cabeza lateral del isquiotibial"
        }
    }

    /// SF Symbol icon name.
    public var iconName: String {
        switch self {
        case .quadriceps, .vastusLateralis: return "figure.walk"
        case .hamstring, .bicepsFemoris: return "figure.run"
        case .bicepsBrachii: return "figure.strengthtraining.traditional"
        }
    }
}
