import Foundation
import SwiftData

/// Pre-measurement questionnaire and session grouping
/// Matches Supabase `measurement_sessions` table schema for sync compatibility
@Model
public final class MeasurementSession {

    // MARK: - Properties

    /// Unique identifier (client-generated UUID)
    public var id: UUID

    /// Reference to the athlete
    public var athlete: Athlete?

    /// Session start timestamp
    public var startedAt: Date

    // MARK: - Pre-Measurement Questionnaire

    /// Hours since last physical activity (nullable)
    public var hoursSinceActivity: Double?

    /// Type of last physical activity (nullable)
    public var lastActivityType: String?

    /// Hours of sleep in last 24 hours (nullable)
    public var sleepHours: Double?

    /// General fatigue level 0-10 (nullable)
    public var generalFatigue: Int?

    /// Had recent physiotherapy treatment (nullable)
    public var recentPhysio: Bool?

    /// Hours since physiotherapy treatment (nullable)
    public var recentPhysioHoursAgo: Int?

    /// Any new issues to report (nullable)
    public var newIssues: String?

    /// Menstrual cycle phase for female athletes (nullable)
    public var menstrualCyclePhase: MenstrualCyclePhase?

    /// Whether the activity involved leg work (nullable)
    public var involvedLegs: Bool?

    /// Which leg muscle group was exercised: "quadriceps", "hamstrings", or "both" (nullable)
    public var legMuscleGroup: String?

    /// Session type: "basal" (single at-home measurement) or "match" (multi-measurement match day)
    public var sessionType: String?

    /// Study code this session belongs to (e.g. "biceps_tfg", "sentadilla_tfm")
    public var studyId: String?

    // MARK: - Sync Properties

    /// Sync status for cloud synchronization
    public var syncStatus: SyncStatus

    /// Last sync attempt timestamp
    public var lastSyncAttempt: Date?

    /// Sync error message if failed
    public var syncError: String?

    // MARK: - Relationships

    /// Individual muscle measurements within this session
    @Relationship(deleteRule: .cascade, inverse: \Measurement.session)
    public var measurements: [Measurement]?

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        athlete: Athlete? = nil,
        startedAt: Date = Date(),
        hoursSinceActivity: Double? = nil,
        lastActivityType: String? = nil,
        sleepHours: Double? = nil,
        generalFatigue: Int? = nil,
        recentPhysio: Bool? = nil,
        recentPhysioHoursAgo: Int? = nil,
        newIssues: String? = nil,
        menstrualCyclePhase: MenstrualCyclePhase? = nil,
        involvedLegs: Bool? = nil,
        legMuscleGroup: String? = nil,
        sessionType: String? = nil,
        studyId: String? = nil,
        syncStatus: SyncStatus = .pending,
        lastSyncAttempt: Date? = nil,
        syncError: String? = nil
    ) {
        self.id = id
        self.athlete = athlete
        self.startedAt = startedAt
        self.hoursSinceActivity = hoursSinceActivity
        self.lastActivityType = lastActivityType
        self.sleepHours = sleepHours
        self.generalFatigue = generalFatigue
        self.recentPhysio = recentPhysio
        self.recentPhysioHoursAgo = recentPhysioHoursAgo
        self.newIssues = newIssues
        self.menstrualCyclePhase = menstrualCyclePhase
        self.involvedLegs = involvedLegs
        self.legMuscleGroup = legMuscleGroup
        self.sessionType = sessionType
        self.studyId = studyId
        self.syncStatus = syncStatus
        self.lastSyncAttempt = lastSyncAttempt
        self.syncError = syncError
    }

    // MARK: - Computed Properties

    /// Whether the questionnaire has been filled out
    public var hasQuestionnaireData: Bool {
        hoursSinceActivity != nil ||
        lastActivityType != nil ||
        sleepHours != nil ||
        generalFatigue != nil ||
        recentPhysio != nil ||
        newIssues != nil ||
        menstrualCyclePhase != nil ||
        involvedLegs != nil
    }

    /// Fatigue level description
    public var fatigueDescription: String? {
        guard let fatigue = generalFatigue else { return nil }

        switch fatigue {
        case 0:
            return "Sin fatiga"
        case 1...3:
            return "Fatiga leve"
        case 4...6:
            return "Fatiga moderada"
        case 7...9:
            return "Fatiga alta"
        case 10:
            return "Fatiga extrema"
        default:
            return "Desconocida"
        }
    }

    /// Sleep quality assessment based on hours
    public var sleepQuality: SleepQuality? {
        guard let hours = sleepHours else { return nil }

        switch hours {
        case ..<5:
            return .poor
        case 5..<7:
            return .fair
        case 7..<9:
            return .good
        case 9...:
            return .excellent
        default:
            return nil
        }
    }

    /// Recovery status based on questionnaire data
    public var recoveryStatus: RecoveryStatus {
        var score = 0
        var factors = 0

        // Sleep factor
        if let hours = sleepHours {
            factors += 1
            if hours >= 7 { score += 2 }
            else if hours >= 5 { score += 1 }
        }

        // Fatigue factor
        if let fatigue = generalFatigue {
            factors += 1
            if fatigue <= 3 { score += 2 }
            else if fatigue <= 6 { score += 1 }
        }

        // Recovery time factor
        if let hours = hoursSinceActivity {
            factors += 1
            if hours >= 24 { score += 2 }
            else if hours >= 12 { score += 1 }
        }

        // Recent physio is positive
        if let hadPhysio = recentPhysio, hadPhysio {
            factors += 1
            score += 1
        }

        guard factors > 0 else { return .unknown }

        let averageScore = Double(score) / Double(factors)

        if averageScore >= 1.5 {
            return .good
        } else if averageScore >= 0.5 {
            return .moderate
        } else {
            return .poor
        }
    }

    /// Summary of key questionnaire data
    public var questionnaireSummary: String {
        var parts: [String] = []

        if let hours = hoursSinceActivity {
            parts.append("Actividad: \(String(format: "%.1f", hours)) horas")
        }

        if let sleep = sleepHours {
            parts.append("Sueño: \(String(format: "%.1f", sleep)) horas")
        }

        if let fatigue = generalFatigue {
            parts.append("Fatiga: \(fatigue)/10")
        }

        if let hasPhysio = recentPhysio, hasPhysio {
            if let hoursAgo = recentPhysioHoursAgo {
                parts.append("Fisio: \(hoursAgo) horas")
            } else {
                parts.append("Fisio reciente: Sí")
            }
        }

        if let legs = involvedLegs, legs {
            let group = legMuscleGroup ?? "general"
            let groupName: String
            switch group {
            case "quadriceps": groupName = "Cuádriceps"
            case "hamstrings": groupName = "Isquiotibiales"
            case "both": groupName = "Ambos"
            default: groupName = "General"
            }
            parts.append("Piernas: \(groupName)")
        }

        return parts.isEmpty ? "Sin datos del cuestionario" : parts.joined(separator: " | ")
    }

    // MARK: - Methods

    /// Get formatted session date
    public func formattedStartedAt(style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .short
        return formatter.string(from: startedAt)
    }

    /// Validate fatigue value (0-10)
    public static func validateFatigue(_ value: Int?) -> Bool {
        guard let fatigue = value else { return true }
        return fatigue >= 0 && fatigue <= 10
    }

    /// Validate sleep hours (reasonable range)
    public static func validateSleepHours(_ value: Double?) -> Bool {
        guard let hours = value else { return true }
        return hours >= 0 && hours <= 24
    }

    /// Validate hours since activity (reasonable range)
    public static func validateHoursSinceActivity(_ value: Double?) -> Bool {
        guard let hours = value else { return true }
        return hours >= 0 && hours <= 168  // Up to 1 week
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

    // MARK: - Measurement Helpers

    /// Total number of measurements in this session
    public var measurementCount: Int {
        measurements?.count ?? 0
    }

    /// Measurements for a specific muscle group
    public func measurements(for muscleGroup: String) -> [Measurement] {
        measurements?.filter { $0.muscleGroup == muscleGroup } ?? []
    }

    /// Measurements for a specific side
    public func measurementsForSide(_ side: String) -> [Measurement] {
        measurements?.filter { $0.side == side } ?? []
    }

    /// Get measurement for a specific muscle target
    public func measurement(muscleGroup: String, side: String) -> Measurement? {
        measurements?.first { $0.muscleGroup == muscleGroup && $0.side == side }
    }

    /// Check if all 4 muscle targets have been measured
    public var isComplete: Bool {
        let targets = [
            ("quadriceps", "left"),
            ("quadriceps", "right"),
            ("hamstring", "left"),
            ("hamstring", "right")
        ]
        return targets.allSatisfy { muscle, side in
            measurement(muscleGroup: muscle, side: side) != nil
        }
    }

    /// Calculate average fatigue across all measurements
    public var averageFatigue: Double? {
        guard let measurements = measurements, !measurements.isEmpty else { return nil }
        let total = measurements.reduce(0) { $0 + $1.perceivedFatigue }
        return Double(total) / Double(measurements.count)
    }

    /// Calculate bilateral difference for a muscle group
    public func bilateralDifference(for muscleGroup: String) -> Int? {
        guard let left = measurement(muscleGroup: muscleGroup, side: "left"),
              let right = measurement(muscleGroup: muscleGroup, side: "right") else {
            return nil
        }
        return abs(left.perceivedFatigue - right.perceivedFatigue)
    }
}

// MARK: - Sleep Quality Enum

/// Sleep quality assessment
public enum SleepQuality: String, Sendable, Codable, CaseIterable {
    case poor = "poor"
    case fair = "fair"
    case good = "good"
    case excellent = "excellent"

    public var displayName: String {
        switch self {
        case .poor: return "Mala"
        case .fair: return "Regular"
        case .good: return "Buena"
        case .excellent: return "Excelente"
        }
    }

    public var color: String {
        switch self {
        case .poor: return "red"
        case .fair: return "orange"
        case .good: return "green"
        case .excellent: return "blue"
        }
    }

    public var iconName: String {
        switch self {
        case .poor: return "moon.zzz"
        case .fair: return "moon"
        case .good: return "moon.stars"
        case .excellent: return "sparkles"
        }
    }
}

// MARK: - Recovery Status Enum

/// Overall recovery status assessment
public enum RecoveryStatus: String, Sendable, Codable, CaseIterable {
    case unknown = "unknown"
    case poor = "poor"
    case moderate = "moderate"
    case good = "good"

    public var displayName: String {
        switch self {
        case .unknown: return "Desconocido"
        case .poor: return "Recuperación deficiente"
        case .moderate: return "Recuperación moderada"
        case .good: return "Buena recuperación"
        }
    }

    public var color: String {
        switch self {
        case .unknown: return "gray"
        case .poor: return "red"
        case .moderate: return "orange"
        case .good: return "green"
        }
    }

    public var description: String {
        switch self {
        case .unknown:
            return "Insufficient data to assess recovery status"
        case .poor:
            return "Low recovery indicators - consider light activity only"
        case .moderate:
            return "Moderate recovery - normal training possible with monitoring"
        case .good:
            return "Good recovery indicators - ready for full training"
        }
    }
}

// MARK: - Common Activity Types

/// Common physical activity types for convenience
public enum ActivityType: String, Sendable, Codable, CaseIterable {
    case running = "Running"
    case cycling = "Cycling"
    case swimming = "Swimming"
    case weightTraining = "Weight Training"
    case teamSport = "Team Sport"
    case hiit = "HIIT"
    case yoga = "Yoga/Stretching"
    case walking = "Walking"
    case competition = "Competition"
    case other = "Other"

    public var iconName: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .weightTraining: return "dumbbell"
        case .teamSport: return "sportscourt"
        case .hiit: return "bolt.heart"
        case .yoga: return "figure.yoga"
        case .walking: return "figure.walk"
        case .competition: return "trophy"
        case .other: return "figure.mixed.cardio"
        }
    }

    public var intensity: ActivityIntensity {
        switch self {
        case .yoga, .walking:
            return .low
        case .cycling, .swimming, .weightTraining:
            return .moderate
        case .running, .teamSport, .hiit, .competition:
            return .high
        case .other:
            return .moderate
        }
    }
}

// MARK: - Activity Intensity

/// Activity intensity classification
public enum ActivityIntensity: String, Sendable, Codable, CaseIterable {
    case low = "low"
    case moderate = "moderate"
    case high = "high"

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        }
    }

    public var color: String {
        switch self {
        case .low: return "green"
        case .moderate: return "orange"
        case .high: return "red"
        }
    }

    /// Recommended recovery hours
    public var recommendedRecoveryHours: Int {
        switch self {
        case .low: return 12
        case .moderate: return 24
        case .high: return 48
        }
    }
}

// MARK: - Menstrual Cycle Phase

/// Menstrual cycle phase for female athletes (affects recovery)
public enum MenstrualCyclePhase: String, Sendable, Codable, CaseIterable, Identifiable {
    case menstruation = "menstruation"
    case follicular = "follicular"
    case ovulation = "ovulation"
    case luteal = "luteal"
    case unknown = "unknown"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .menstruation: return "Menstruation"
        case .follicular: return "Follicular"
        case .ovulation: return "Ovulation"
        case .luteal: return "Luteal"
        case .unknown: return "Unknown"
        }
    }

    public var spanishDisplayName: String {
        switch self {
        case .menstruation: return "Menstruación"
        case .follicular: return "Folicular"
        case .ovulation: return "Ovulación"
        case .luteal: return "Lútea"
        case .unknown: return "No lo sé"
        }
    }

    public var description: String {
        switch self {
        case .menstruation: return "Days 1-5: Period"
        case .follicular: return "Days 6-14: Pre-ovulation"
        case .ovulation: return "Days 14-16: Ovulation"
        case .luteal: return "Days 17-28: Post-ovulation"
        case .unknown: return "Not sure"
        }
    }

    public var spanishDescription: String {
        switch self {
        case .menstruation: return "Días 1-5: Período"
        case .follicular: return "Días 6-14: Pre-ovulación"
        case .ovulation: return "Días 14-16: Ovulación"
        case .luteal: return "Días 17-28: Post-ovulación"
        case .unknown: return "No estoy segura"
        }
    }

    /// Recovery impact factor (higher = more fatigue expected)
    public var recoveryImpact: Double {
        switch self {
        case .menstruation: return 1.2
        case .follicular: return 0.9
        case .ovulation: return 1.0
        case .luteal: return 1.1
        case .unknown: return 1.0
        }
    }
}
