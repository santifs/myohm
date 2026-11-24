import Foundation

/// Study protocol that a measurement session belongs to.
///
/// Each `Study` declares the catalog of muscles, sides, and session-type
/// labels (chips) that the operator should see in the UI. The `rawValue`
/// is what gets persisted to Supabase as `measurement_sessions.study_id`.
public enum Study: String, Sendable, Codable, CaseIterable, Identifiable {
    case bicepsTFG = "biceps_tfg"
    case sentadillaTFM = "sentadilla_tfm"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .bicepsTFG: return "Bíceps TFG"
        case .sentadillaTFM: return "Sentadilla TFM"
        }
    }

    /// Catalog of muscles the protocol allows. If only one element, no picker.
    public var muscleGroups: [MuscleGroup] {
        switch self {
        case .bicepsTFG: return [.bicepsBrachii]
        case .sentadillaTFM: return [.vastusLateralis, .bicepsFemoris]
        }
    }

    /// Sides the protocol measures. If only one element, no picker.
    public var sides: [BodySide] {
        switch self {
        case .bicepsTFG: return [.right]
        case .sentadillaTFM: return [.right, .left]
        }
    }

    /// Suggestion chips for the `session_type` field. The operator can tap
    /// a chip or type freely; free text is normalized via `SessionTypeNormalizer`.
    /// Chips here must already be in canonical form (lowercase, underscores).
    public var sessionTypeSuggestions: [String] {
        switch self {
        case .bicepsTFG:
            return [
                "basal",
                "post_serie_1", "post_serie_2", "post_serie_3", "post_serie_4", "post_serie_5",
                "12h", "24h", "36h", "48h", "60h", "72h"
            ]
        case .sentadillaTFM:
            return [
                "baseline",
                "post_inc_1", "post_inc_2", "post_inc_3", "post_inc_4",
                "post_inc_5", "post_inc_6", "post_inc_7", "post_inc_8",
                "post_30s_1", "post_30s_2", "post_30s_3", "post_30s_4"
            ]
        }
    }
}
