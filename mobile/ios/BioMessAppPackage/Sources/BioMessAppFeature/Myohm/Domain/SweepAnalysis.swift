import Foundation

/// A single averaged point of a sweep, in the conventions shown to people:
/// phase angle positive, reactance positive for capacitive tissue.
public struct SweepPoint: Sendable, Equatable, Identifiable {
    public var id: Double { frequencyHz }
    public let frequencyHz: Double
    public let magnitude: Double
    /// Phase angle in degrees, as a positive number for tissue.
    public let phaseAngle: Double
    public var resistance: Double { magnitude * cos(phaseAngle * .pi / 180) }
    public var reactance: Double { magnitude * sin(phaseAngle * .pi / 180) }
}

/// Summary of a whole sweep: repetitions combined by median and values read at 50 kHz.
public struct SweepAnalysis: Sendable, Equatable {
    public let points: [SweepPoint]
    public let repetitions: Int

    public static let referenceFrequencyHz = 50_000.0

    public init(points: [SweepPoint], repetitions: Int) {
        self.points = points.sorted { $0.frequencyHz < $1.frequencyHz }
        self.repetitions = repetitions
    }

    public init?(_ data: ImpedanceData) {
        let reps = data.repetitions.filter { !$0.isEmpty }
        guard let first = reps.first, !first.isEmpty else { return nil }
        let count = reps.map(\.count).min() ?? 0
        var combined: [SweepPoint] = []
        for index in 0..<count {
            let samples = reps.map { $0[index] }.filter { $0.magnitude.isFinite && $0.phase.isFinite && $0.magnitude > 0 }
            guard !samples.isEmpty else { continue }
            let re = Self.median(samples.map { Double($0.magnitude) * cos(Double($0.phase) * .pi / 180) })
            let im = Self.median(samples.map { Double($0.magnitude) * sin(Double($0.phase) * .pi / 180) })
            let magnitude = (re * re + im * im).squareRoot()
            let phase = abs(atan2(im, re) * 180 / .pi)
            combined.append(SweepPoint(frequencyHz: Double(samples[0].frequency), magnitude: magnitude, phaseAngle: phase))
        }
        guard !combined.isEmpty else { return nil }
        self.init(points: combined, repetitions: reps.count)
    }

    /// Value at 50 kHz by linear interpolation on a log-frequency axis.
    public var atReference: SweepPoint? { interpolated(at: Self.referenceFrequencyHz) }

    public func interpolated(at frequency: Double) -> SweepPoint? {
        guard let lower = points.last(where: { $0.frequencyHz <= frequency }) else { return points.first }
        guard let upper = points.first(where: { $0.frequencyHz >= frequency }) else { return points.last }
        guard upper.frequencyHz > lower.frequencyHz else { return lower }
        let t = (log(frequency) - log(lower.frequencyHz)) / (log(upper.frequencyHz) - log(lower.frequencyHz))
        let r = lower.resistance + t * (upper.resistance - lower.resistance)
        let x = lower.reactance + t * (upper.reactance - lower.reactance)
        return SweepPoint(
            frequencyHz: frequency,
            magnitude: (r * r + x * x).squareRoot(),
            phaseAngle: atan2(x, r) * 180 / .pi
        )
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
