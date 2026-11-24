import Foundation
import SwiftData

/// Injury history for athletes
/// Matches Supabase `injuries` table schema for sync compatibility
@Model
public final class Injury {

    // MARK: - Properties

    /// Unique identifier (client-generated UUID)
    public var id: UUID

    /// Reference to the athlete
    public var athlete: Athlete?

    /// Date when injury was reported
    public var reportedAt: Date

    /// Type of injury (muscular or non-muscular)
    public var injuryType: InjuryType

    /// Details for muscular injuries (nullable)
    public var muscularDetail: String?

    /// Details for non-muscular injuries (nullable)
    public var nonMuscularDetail: String?

    /// Whether the injury is currently active
    public var isActive: Bool

    /// Date when injury was resolved (nullable)
    public var resolvedAt: Date?

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        athlete: Athlete? = nil,
        reportedAt: Date = Date(),
        injuryType: InjuryType = .muscular,
        muscularDetail: String? = nil,
        nonMuscularDetail: String? = nil,
        isActive: Bool = true,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.athlete = athlete
        self.reportedAt = reportedAt
        self.injuryType = injuryType
        self.muscularDetail = muscularDetail
        self.nonMuscularDetail = nonMuscularDetail
        self.isActive = isActive
        self.resolvedAt = resolvedAt
    }

    // MARK: - Computed Properties

    /// Get the detail based on injury type
    public var detail: String? {
        switch injuryType {
        case .muscular:
            return muscularDetail
        case .nonMuscular:
            return nonMuscularDetail
        }
    }

    /// Duration since injury was reported
    public var duration: TimeInterval {
        let end = resolvedAt ?? Date()
        return end.timeIntervalSince(reportedAt)
    }

    /// Duration in days since injury was reported
    public var durationDays: Int {
        Int(duration / 86400)
    }

    /// Duration formatted as string
    public var durationFormatted: String {
        let days = durationDays

        if days < 7 {
            return "\(days) día\(days == 1 ? "" : "s")"
        } else if days < 30 {
            let weeks = days / 7
            return "\(weeks) semana\(weeks == 1 ? "" : "s")"
        } else {
            let months = days / 30
            return "\(months) mes\(months == 1 ? "" : "es")"
        }
    }

    /// Status description for display
    public var statusDescription: String {
        if isActive {
            return "Activa - \(durationFormatted)"
        } else if let resolved = resolvedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "Resuelta el \(formatter.string(from: resolved))"
        } else {
            return "Resuelta"
        }
    }

    /// Display name for the injury
    public var displayName: String {
        let typeStr = injuryType.displayName

        if let detail = detail, !detail.isEmpty {
            return "\(typeStr): \(detail)"
        }

        return typeStr
    }

    // MARK: - Methods

    /// Mark the injury as resolved
    public func resolve(at date: Date = Date()) {
        isActive = false
        resolvedAt = date
    }

    /// Reactivate a previously resolved injury
    public func reactivate() {
        isActive = true
        resolvedAt = nil
    }

    /// Get formatted reported date
    public func formattedReportedAt(style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: reportedAt)
    }

    /// Get formatted resolved date (if available)
    public func formattedResolvedAt(style: DateFormatter.Style = .medium) -> String? {
        guard let resolved = resolvedAt else { return nil }

        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: resolved)
    }
}

// MARK: - InjuryType Enum

/// Type of injury classification
public enum InjuryType: String, Sendable, Codable, CaseIterable {
    case muscular = "muscular"
    case nonMuscular = "non_muscular"

    public var displayName: String {
        switch self {
        case .muscular: return "Muscular"
        case .nonMuscular: return "Non-Muscular"
        }
    }

    public var description: String {
        switch self {
        case .muscular:
            return "Injuries affecting muscle tissue (strains, tears, etc.)"
        case .nonMuscular:
            return "Other injuries (joints, bones, ligaments, etc.)"
        }
    }

    public var iconName: String {
        switch self {
        case .muscular: return "figure.strengthtraining.traditional"
        case .nonMuscular: return "bandage"
        }
    }
}

// MARK: - Common Muscular Injury Types

/// Muscular injury classifications
/// Matches Supabase `muscular_detail` enum: overload, cramp, tear_1, tear_2, tear_3
public enum MuscularInjuryDetail: String, Sendable, Codable, CaseIterable {
    case overload = "overload"
    case cramp = "cramp"
    case tear1 = "tear_1"
    case tear2 = "tear_2"
    case tear3 = "tear_3"

    public var displayName: String {
        switch self {
        case .overload: return "Sobrecarga muscular"
        case .cramp: return "Calambre muscular"
        case .tear1: return "Desgarro Tipo I"
        case .tear2: return "Desgarro Tipo II"
        case .tear3: return "Desgarro Tipo III"
        }
    }

    public var description: String {
        switch self {
        case .overload: return "Sobrecarga muscular - fatiga o tensión excesiva"
        case .cramp: return "Calambre muscular - contracción involuntaria"
        case .tear1: return "Desgarro Tipo I - lesión leve de fibras"
        case .tear2: return "Desgarro Tipo II - lesión moderada de fibras"
        case .tear3: return "Desgarro Tipo III - rotura completa"
        }
    }
}

// MARK: - Common Non-Muscular Injury Types

/// Common non-muscular injury classifications for convenience
public enum NonMuscularInjuryDetail: String, Sendable, CaseIterable {
    case ligamentSprain = "Ligament Sprain"
    case fracture = "Bone Fracture"
    case jointDislocation = "Joint Dislocation"
    case bursitis = "Bursitis"
    case cartilage = "Cartilage Injury"
    case nerve = "Nerve Injury"
    case other = "Other"

    public var description: String {
        switch self {
        case .ligamentSprain: return "Stretching or tearing of ligaments"
        case .fracture: return "Broken bone"
        case .jointDislocation: return "Displacement of bones at a joint"
        case .bursitis: return "Inflammation of bursa"
        case .cartilage: return "Damage to cartilage tissue"
        case .nerve: return "Damage or compression of nerves"
        case .other: return "Other non-muscular injury"
        }
    }
}
