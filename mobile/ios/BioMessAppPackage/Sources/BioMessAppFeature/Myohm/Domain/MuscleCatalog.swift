import Foundation
import CoreGraphics

/// Muscles that can be measured with a local band, plus the whole-body montage.
public enum MyohmMuscle: String, CaseIterable, Sendable, Codable, Identifiable {
    case quadriceps
    case hamstrings
    case calf
    case tibialis
    case biceps
    case triceps
    case forearm
    case glutes
    case other

    public static let wholeBodyKey = "whole_body"

    public var id: String { rawValue }

    public enum BodyView: Sendable { case front, back }

    public var view: BodyView? {
        switch self {
        case .quadriceps, .tibialis, .biceps, .forearm: return .front
        case .hamstrings, .calf, .triceps, .glutes: return .back
        case .other: return nil
        }
    }

    /// Suggested band (distance between V+ and V−, mm). A starting point, not a rule.
    public var suggestedBand: Int? {
        switch self {
        case .quadriceps, .hamstrings: return 100
        case .calf, .tibialis, .biceps, .triceps: return 75
        case .forearm: return 50
        case .glutes: return 150
        case .other: return nil
        }
    }

    public var name: String {
        switch self {
        case .quadriceps: return L("Quadriceps")
        case .hamstrings: return L("Hamstrings")
        case .calf: return L("Calf")
        case .tibialis: return L("Tibialis anterior")
        case .biceps: return L("Biceps")
        case .triceps: return L("Triceps")
        case .forearm: return L("Forearm")
        case .glutes: return L("Glutes")
        case .other: return L("Other")
        }
    }

    /// Hit areas on the 520 × 1000 body illustrations: centre, radii and rotation (degrees).
    /// Index 0 is the person's right side, index 1 the left side.
    public var zones: [(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, rot: Double)] {
        switch self {
        case .biceps: return [(148, 302, 22, 50, 12), (372, 302, 22, 50, -12)]
        case .forearm: return [(100, 428, 19, 55, 25), (420, 428, 19, 55, -25)]
        case .quadriceps: return [(214, 578, 38, 80, 4), (306, 578, 38, 80, -4)]
        case .tibialis: return [(224, 780, 17, 62, 0), (296, 780, 17, 62, 0)]
        // Back view: the person's right side is on the viewer's right.
        case .triceps: return [(378, 300, 23, 50, -10), (142, 300, 23, 50, 10)]
        case .glutes: return [(302, 455, 45, 50, 0), (218, 455, 45, 50, 0)]
        case .hamstrings: return [(298, 605, 36, 78, 0), (222, 605, 36, 78, 0)]
        case .calf: return [(298, 760, 28, 56, 0), (222, 760, 28, 56, 0)]
        case .other: return []
        }
    }
}

public enum LimbSide: String, CaseIterable, Sendable, Codable {
    case right, left

    public var name: String { self == .right ? L("Right") : L("Left") }
}

public enum MeasurementKind: Sendable, Hashable {
    case muscle(MyohmMuscle, LimbSide, band: Int)
    case wholeBody(weightKg: Double, restCompleted: Bool)

    public var storageKey: String {
        switch self {
        case .muscle(let muscle, _, _): return muscle.rawValue
        case .wholeBody: return MyohmMuscle.wholeBodyKey
        }
    }
}

public extension Measurement {
    var isWholeBody: Bool { muscleGroup == MyohmMuscle.wholeBodyKey }
    var muscle: MyohmMuscle? { MyohmMuscle(rawValue: muscleGroup) }
    var bodySide: LimbSide? { LimbSide(rawValue: side) }

    var myohmTitle: String {
        if isWholeBody { return L("Whole body") }
        let muscleName = muscle?.name ?? muscleGroup.capitalized
        guard let side = bodySide else { return muscleName }
        return L("\(muscleName) · \(side.name.lowercased())")
    }
}
