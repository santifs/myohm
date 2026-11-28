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

    /// Outlines traced on the 520 × 1000 body illustrations, for the side drawn on the viewer's left.
    /// Front view shows the person's right on the viewer's left; the back view, the person's left.
    private var tracedOutline: [CGPoint] {
        let pts: [(CGFloat, CGFloat)]
        switch self {
        case .biceps: pts = [(126, 266), (158, 262), (166, 288), (160, 318), (147, 345), (131, 358), (112, 350), (114, 316), (118, 288)]
        case .forearm: pts = [(102, 372), (146, 370), (140, 408), (124, 446), (106, 466), (86, 460), (88, 420), (94, 392)]
        case .quadriceps: pts = [(182, 442), (222, 446), (249, 492), (247, 560), (237, 612), (218, 632), (196, 628), (173, 594), (163, 530), (167, 476)]
        case .tibialis: pts = [(172, 690), (194, 688), (199, 740), (195, 798), (184, 828), (173, 800), (167, 742)]
        case .triceps: pts = [(118, 264), (160, 262), (165, 290), (153, 328), (135, 352), (110, 346), (111, 310), (114, 284)]
        case .glutes: pts = [(200, 398), (240, 393), (257, 412), (257, 470), (249, 499), (215, 502), (189, 488), (181, 450), (187, 414)]
        case .hamstrings: pts = [(174, 516), (249, 513), (247, 570), (239, 624), (227, 674), (201, 679), (185, 650), (174, 590)]
        case .calf: pts = [(173, 702), (222, 699), (231, 745), (224, 789), (200, 800), (177, 792), (163, 750)]
        case .other: pts = []
        }
        return pts.map { CGPoint(x: $0.0, y: $0.1) }
    }

    /// Tap outlines for each side: index 0 is the person's right, index 1 the left.
    public var outlines: [[CGPoint]] {
        let traced = tracedOutline
        guard !traced.isEmpty else { return [] }
        let mirrored = traced.map { CGPoint(x: 520 - $0.x, y: $0.y) }
        return view == .back ? [mirrored, traced] : [traced, mirrored]
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
