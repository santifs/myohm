import Foundation
import SwiftData

// MARK: - Date Formatters

/// Static date formatters for Supabase API communication
/// Using static instances for performance (DateFormatter is expensive to create)
/// Note: These formatters are thread-safe for reading operations (formatting/parsing)
enum SupabaseDateFormatters {
    /// ISO8601 formatter for TIMESTAMPTZ fields
    /// nonisolated(unsafe) is used because ISO8601DateFormatter is thread-safe for read operations
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// ISO8601 formatter without fractional seconds (fallback)
    nonisolated(unsafe) static let iso8601NoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Date-only formatter for DATE fields (yyyy-MM-dd)
    static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Parse ISO8601 date string (tries with and without fractional seconds)
    static func parseISO8601(_ string: String) -> Date? {
        iso8601.date(from: string) ?? iso8601NoFractional.date(from: string)
    }

    /// Format date as ISO8601 string
    static func formatISO8601(_ date: Date) -> String {
        iso8601.string(from: date)
    }

    /// Parse date-only string (yyyy-MM-dd)
    static func parseDateOnly(_ string: String) -> Date? {
        dateOnly.date(from: string)
    }

    /// Format date as date-only string (yyyy-MM-dd)
    static func formatDateOnly(_ date: Date) -> String {
        dateOnly.string(from: date)
    }
}

// MARK: - AthleteDTO

/// Data Transfer Object for Supabase `athletes` table
/// Maps between snake_case API columns and camelCase SwiftData model
public struct AthleteDTO: Codable, Sendable {
    public let id: UUID
    public let fullName: String
    public let dateOfBirth: String  // DATE format: yyyy-MM-dd
    public let dominantLeg: String?
    public let biologicalSex: String?
    public let medicalHistory: String?
    public let medications: String?
    public let dietType: String?
    public let dailyCalories: Int?
    public let allergies: [String]?
    public let usualActivities: [String]?
    public let createdAt: String?  // TIMESTAMPTZ format: ISO8601
    public let updatedAt: String?  // TIMESTAMPTZ format: ISO8601
    public let userId: UUID?  // Foreign key to auth.users

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case dateOfBirth = "date_of_birth"
        case dominantLeg = "dominant_leg"
        case biologicalSex = "biological_sex"
        case medicalHistory = "medical_history"
        case medications
        case dietType = "diet_type"
        case dailyCalories = "daily_calories"
        case allergies
        case usualActivities = "usual_activities"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userId = "user_id"
    }

    // MARK: - Conversion from SwiftData Model

    /// Create DTO from SwiftData Athlete model
    public init(from athlete: Athlete) {
        self.id = athlete.id
        self.fullName = athlete.fullName
        self.dateOfBirth = SupabaseDateFormatters.formatDateOnly(athlete.dateOfBirth)
        self.dominantLeg = athlete.dominantLeg.rawValue
        self.biologicalSex = athlete.biologicalSex?.rawValue
        self.medicalHistory = athlete.medicalHistory
        self.medications = athlete.medications
        self.dietType = athlete.dietType
        self.dailyCalories = athlete.dailyCalories
        self.allergies = athlete.allergies
        self.usualActivities = athlete.usualActivities
        self.createdAt = SupabaseDateFormatters.formatISO8601(athlete.createdAt)
        self.updatedAt = SupabaseDateFormatters.formatISO8601(athlete.updatedAt)
        self.userId = athlete.userId
    }

    // MARK: - Conversion to SwiftData Model

    /// Create new SwiftData Athlete model from DTO
    /// Note: This creates a new model instance, not linked to any context
    public func toModel() -> Athlete {
        let dob = SupabaseDateFormatters.parseDateOnly(dateOfBirth) ?? Date()
        let created = createdAt.flatMap { SupabaseDateFormatters.parseISO8601($0) } ?? Date()
        let updated = updatedAt.flatMap { SupabaseDateFormatters.parseISO8601($0) } ?? Date()
        let leg = dominantLeg.flatMap { DominantLeg(rawValue: $0) } ?? .right
        let sex = biologicalSex.flatMap { BiologicalSex(rawValue: $0) }

        return Athlete(
            id: id,
            fullName: fullName,
            dateOfBirth: dob,
            dominantLeg: leg,
            biologicalSex: sex,
            medicalHistory: medicalHistory,
            medications: medications,
            dietType: dietType,
            dailyCalories: dailyCalories,
            allergies: allergies,
            usualActivities: usualActivities,
            createdAt: created,
            updatedAt: updated,
            userId: userId
        )
    }

    /// Update an existing SwiftData Athlete model with DTO values
    public func updateModel(_ athlete: Athlete) {
        let dob = SupabaseDateFormatters.parseDateOnly(dateOfBirth) ?? Date()
        let created = createdAt.flatMap { SupabaseDateFormatters.parseISO8601($0) } ?? Date()
        let updated = updatedAt.flatMap { SupabaseDateFormatters.parseISO8601($0) } ?? Date()
        let leg = dominantLeg.flatMap { DominantLeg(rawValue: $0) } ?? .right
        let sex = biologicalSex.flatMap { BiologicalSex(rawValue: $0) }

        athlete.fullName = fullName
        athlete.dateOfBirth = dob
        athlete.dominantLeg = leg
        athlete.biologicalSex = sex
        athlete.medicalHistory = medicalHistory
        athlete.medications = medications
        athlete.dietType = dietType
        athlete.dailyCalories = dailyCalories
        athlete.allergies = allergies
        athlete.usualActivities = usualActivities
        athlete.createdAt = created
        athlete.updatedAt = updated
        athlete.userId = userId
    }
}

// MARK: - AnthropometricsDTO

/// Data Transfer Object for Supabase `anthropometrics` table
/// Maps between snake_case API columns and camelCase SwiftData model
public struct AnthropometricsDTO: Codable, Sendable {
    public let id: UUID
    public let athleteId: UUID?
    public let measuredAt: String  // DATE format: yyyy-MM-dd
    public let weightKg: Double?
    public let heightCm: Double?
    public let rightThighLengthCm: Double?
    public let rightThighCircumferenceCm: Double?
    public let leftThighLengthCm: Double?
    public let leftThighCircumferenceCm: Double?
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case measuredAt = "measured_at"
        case weightKg = "weight_kg"
        case heightCm = "height_cm"
        case rightThighLengthCm = "right_thigh_length_cm"
        case rightThighCircumferenceCm = "right_thigh_circumference_cm"
        case leftThighLengthCm = "left_thigh_length_cm"
        case leftThighCircumferenceCm = "left_thigh_circumference_cm"
        case notes
    }

    // MARK: - Conversion from SwiftData Model

    /// Create DTO from SwiftData Anthropometrics model
    public init(from anthropometrics: Anthropometrics) {
        self.id = anthropometrics.id
        self.athleteId = anthropometrics.athlete?.id
        self.measuredAt = SupabaseDateFormatters.formatDateOnly(anthropometrics.measuredAt)
        self.weightKg = anthropometrics.weightKg
        self.heightCm = anthropometrics.heightCm
        self.rightThighLengthCm = anthropometrics.rightThighLengthCm
        self.rightThighCircumferenceCm = anthropometrics.rightThighCircumferenceCm
        self.leftThighLengthCm = anthropometrics.leftThighLengthCm
        self.leftThighCircumferenceCm = anthropometrics.leftThighCircumferenceCm
        self.notes = anthropometrics.notes
    }

    // MARK: - Conversion to SwiftData Model

    /// Create new SwiftData Anthropometrics model from DTO
    /// Note: athlete relationship must be set separately
    public func toModel() -> Anthropometrics {
        let measured = SupabaseDateFormatters.parseDateOnly(measuredAt) ?? Date()

        return Anthropometrics(
            id: id,
            athlete: nil,  // Must be set separately using athleteId
            measuredAt: measured,
            weightKg: weightKg,
            heightCm: heightCm,
            rightThighLengthCm: rightThighLengthCm,
            rightThighCircumferenceCm: rightThighCircumferenceCm,
            leftThighLengthCm: leftThighLengthCm,
            leftThighCircumferenceCm: leftThighCircumferenceCm,
            notes: notes
        )
    }

    /// Update an existing SwiftData Anthropometrics model with DTO values
    /// Note: athlete relationship is not updated
    public func updateModel(_ anthropometrics: Anthropometrics) {
        let measured = SupabaseDateFormatters.parseDateOnly(measuredAt) ?? Date()

        anthropometrics.measuredAt = measured
        anthropometrics.weightKg = weightKg
        anthropometrics.heightCm = heightCm
        anthropometrics.rightThighLengthCm = rightThighLengthCm
        anthropometrics.rightThighCircumferenceCm = rightThighCircumferenceCm
        anthropometrics.leftThighLengthCm = leftThighLengthCm
        anthropometrics.leftThighCircumferenceCm = leftThighCircumferenceCm
        anthropometrics.notes = notes
    }
}

// MARK: - InjuryDTO

/// Data Transfer Object for Supabase `injuries` table
/// Maps between snake_case API columns and camelCase SwiftData model
public struct InjuryDTO: Codable, Sendable {
    public let id: UUID
    public let athleteId: UUID?
    public let reportedAt: String  // DATE format: yyyy-MM-dd
    public let injuryType: String?
    public let muscularDetail: String?
    public let nonMuscularDetail: String?
    public let isActive: Bool?
    public let resolvedAt: String?  // DATE format: yyyy-MM-dd (nullable)

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case reportedAt = "reported_at"
        case injuryType = "injury_type"
        case muscularDetail = "muscular_detail"
        case nonMuscularDetail = "non_muscular_detail"
        case isActive = "is_active"
        case resolvedAt = "resolved_at"
    }

    // MARK: - Conversion from SwiftData Model

    /// Create DTO from SwiftData Injury model
    public init(from injury: Injury) {
        self.id = injury.id
        self.athleteId = injury.athlete?.id
        self.reportedAt = SupabaseDateFormatters.formatDateOnly(injury.reportedAt)
        self.injuryType = injury.injuryType.rawValue
        self.muscularDetail = injury.muscularDetail
        self.nonMuscularDetail = injury.nonMuscularDetail
        self.isActive = injury.isActive
        self.resolvedAt = injury.resolvedAt.map { SupabaseDateFormatters.formatDateOnly($0) }
    }

    // MARK: - Conversion to SwiftData Model

    /// Create new SwiftData Injury model from DTO
    /// Note: athlete relationship must be set separately
    public func toModel() -> Injury {
        let reported = SupabaseDateFormatters.parseDateOnly(reportedAt) ?? Date()
        let resolved = resolvedAt.flatMap { SupabaseDateFormatters.parseDateOnly($0) }
        let type = injuryType.flatMap { InjuryType(rawValue: $0) } ?? .muscular

        return Injury(
            id: id,
            athlete: nil,  // Must be set separately using athleteId
            reportedAt: reported,
            injuryType: type,
            muscularDetail: muscularDetail,
            nonMuscularDetail: nonMuscularDetail,
            isActive: isActive ?? true,
            resolvedAt: resolved
        )
    }

    /// Update an existing SwiftData Injury model with DTO values
    /// Note: athlete relationship is not updated
    public func updateModel(_ injury: Injury) {
        let reported = SupabaseDateFormatters.parseDateOnly(reportedAt) ?? Date()
        let resolved = resolvedAt.flatMap { SupabaseDateFormatters.parseDateOnly($0) }
        let type = injuryType.flatMap { InjuryType(rawValue: $0) } ?? .muscular

        injury.reportedAt = reported
        injury.injuryType = type
        injury.muscularDetail = muscularDetail
        injury.nonMuscularDetail = nonMuscularDetail
        injury.isActive = isActive ?? true
        injury.resolvedAt = resolved
    }
}

// MARK: - MeasurementSessionDTO

/// Data Transfer Object for Supabase `measurement_sessions` table
/// Maps between snake_case API columns and camelCase SwiftData model
public struct MeasurementSessionDTO: Codable, Sendable {
    public let id: UUID
    public let athleteId: UUID?
    public let startedAt: String?  // TIMESTAMPTZ format: ISO8601
    public let hoursSinceActivity: Double?
    public let lastActivityType: String?
    public let sleepHours: Double?
    public let generalFatigue: Int?
    public let recentPhysio: Bool?
    public let recentPhysioHoursAgo: Int?
    public let newIssues: String?
    public let menstrualCyclePhase: String?
    public let involvedLegs: Bool?
    public let legMuscleGroup: String?
    public let sessionType: String?
    public let studyId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case startedAt = "started_at"
        case hoursSinceActivity = "hours_since_activity"
        case lastActivityType = "last_activity_type"
        case sleepHours = "sleep_hours"
        case generalFatigue = "general_fatigue"
        case recentPhysio = "recent_physio"
        case recentPhysioHoursAgo = "recent_physio_hours_ago"
        case newIssues = "new_issues"
        case menstrualCyclePhase = "menstrual_cycle_phase"
        case involvedLegs = "involved_legs"
        case legMuscleGroup = "leg_muscle_group"
        case sessionType = "session_type"
        case studyId = "study_id"
    }

    // MARK: - Conversion from SwiftData Model

    /// Create DTO from SwiftData MeasurementSession model
    public init(from session: MeasurementSession) {
        self.id = session.id
        self.athleteId = session.athlete?.id
        self.startedAt = SupabaseDateFormatters.formatISO8601(session.startedAt)
        self.hoursSinceActivity = session.hoursSinceActivity
        self.lastActivityType = session.lastActivityType
        self.sleepHours = session.sleepHours
        self.generalFatigue = session.generalFatigue
        self.recentPhysio = session.recentPhysio
        self.recentPhysioHoursAgo = session.recentPhysioHoursAgo
        self.newIssues = session.newIssues
        self.menstrualCyclePhase = session.menstrualCyclePhase?.rawValue
        self.involvedLegs = session.involvedLegs
        self.legMuscleGroup = session.legMuscleGroup
        self.sessionType = session.sessionType
        self.studyId = session.studyId
    }

    // MARK: - Conversion to SwiftData Model

    /// Create new SwiftData MeasurementSession model from DTO
    /// Note: athlete relationship must be set separately
    public func toModel() -> MeasurementSession {
        let started = startedAt.flatMap { SupabaseDateFormatters.parseISO8601($0) } ?? Date()
        let cyclePhase = menstrualCyclePhase.flatMap { MenstrualCyclePhase(rawValue: $0) }

        return MeasurementSession(
            id: id,
            athlete: nil,  // Must be set separately using athleteId
            startedAt: started,
            hoursSinceActivity: hoursSinceActivity,
            lastActivityType: lastActivityType,
            sleepHours: sleepHours,
            generalFatigue: generalFatigue,
            recentPhysio: recentPhysio,
            recentPhysioHoursAgo: recentPhysioHoursAgo,
            newIssues: newIssues,
            menstrualCyclePhase: cyclePhase,
            involvedLegs: involvedLegs,
            legMuscleGroup: legMuscleGroup,
            sessionType: sessionType,
            studyId: studyId
        )
    }

    /// Update an existing SwiftData MeasurementSession model with DTO values
    /// Note: athlete relationship is not updated
    public func updateModel(_ session: MeasurementSession) {
        let started = startedAt.flatMap { SupabaseDateFormatters.parseISO8601($0) } ?? Date()
        let cyclePhase = menstrualCyclePhase.flatMap { MenstrualCyclePhase(rawValue: $0) }

        session.startedAt = started
        session.hoursSinceActivity = hoursSinceActivity
        session.lastActivityType = lastActivityType
        session.sleepHours = sleepHours
        session.generalFatigue = generalFatigue
        session.recentPhysio = recentPhysio
        session.recentPhysioHoursAgo = recentPhysioHoursAgo
        session.newIssues = newIssues
        session.menstrualCyclePhase = cyclePhase
        session.involvedLegs = involvedLegs
        session.legMuscleGroup = legMuscleGroup
        session.sessionType = sessionType
        session.studyId = studyId
    }
}

// MARK: - Supabase Response Wrappers

/// Generic wrapper for Supabase single-item responses
public struct SupabaseResponse<T: Codable>: Codable where T: Sendable {
    public let data: T?
    public let error: SupabaseError?
}

/// Generic wrapper for Supabase array responses
public struct SupabaseArrayResponse<T: Codable>: Codable where T: Sendable {
    public let data: [T]?
    public let error: SupabaseError?
}

/// Supabase API error structure
public struct SupabaseError: Codable, Sendable, Error {
    public let message: String
    public let code: String?
    public let details: String?
    public let hint: String?

    public var localizedDescription: String {
        var description = message
        if let details = details {
            description += " - \(details)"
        }
        if let hint = hint {
            description += " (Hint: \(hint))"
        }
        return description
    }
}

// MARK: - Convenience Extensions

extension Array where Element == AthleteDTO {
    /// Convert array of DTOs to SwiftData models
    public func toModels() -> [Athlete] {
        map { $0.toModel() }
    }
}

extension Array where Element == AnthropometricsDTO {
    /// Convert array of DTOs to SwiftData models
    public func toModels() -> [Anthropometrics] {
        map { $0.toModel() }
    }
}

extension Array where Element == InjuryDTO {
    /// Convert array of DTOs to SwiftData models
    public func toModels() -> [Injury] {
        map { $0.toModel() }
    }
}

extension Array where Element == MeasurementSessionDTO {
    /// Convert array of DTOs to SwiftData models
    public func toModels() -> [MeasurementSession] {
        map { $0.toModel() }
    }
}

extension Array where Element == Athlete {
    /// Convert array of SwiftData models to DTOs
    public func toDTOs() -> [AthleteDTO] {
        map { AthleteDTO(from: $0) }
    }
}

extension Array where Element == Anthropometrics {
    /// Convert array of SwiftData models to DTOs
    public func toDTOs() -> [AnthropometricsDTO] {
        map { AnthropometricsDTO(from: $0) }
    }
}

extension Array where Element == Injury {
    /// Convert array of SwiftData models to DTOs
    public func toDTOs() -> [InjuryDTO] {
        map { InjuryDTO(from: $0) }
    }
}

extension Array where Element == MeasurementSession {
    /// Convert array of SwiftData models to DTOs
    public func toDTOs() -> [MeasurementSessionDTO] {
        map { MeasurementSessionDTO(from: $0) }
    }
}
