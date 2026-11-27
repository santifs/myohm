import Foundation
import Testing
@testable import BioMessAppFeature

@Suite("Body composition")
struct BodyCompositionTests {
    // Woman, 34 y, 168 cm, 61.6 kg, R50 580 Ω, Xc50 65 Ω (design example).
    let ana = BodyInputs(heightCm: 168, weightKg: 61.6, ageYears: 34, isMale: false, isAthlete: false, r50: 580, xc50: 65)

    @Test func genevaMatchesHandCalculation() throws {
        let e = try #require(BodyComposition.estimate(ana))
        #expect(e.equation == .geneva)
        #expect(abs(e.fatFreeMassKg - 43.79) < 0.01)
        #expect(abs(e.fatPercent - 28.9) < 0.05)
        #expect(abs((e.fatPercentError ?? 0) - 2.79) < 0.01)
    }

    @Test func selectsByPopulation() {
        var p = ana
        p.isAthlete = true
        #expect(BodyComposition.select(for: p) == .equation(.athletes))
        p.ageYears = 15
        #expect(BodyComposition.select(for: p) == .equation(.youth))
        p.ageYears = 8
        #expect(BodyComposition.select(for: p) == .tooYoung)
        var heavy = ana
        heavy.weightKg = 100
        #expect(BodyComposition.select(for: heavy) == .highBMI)
        #expect(BodyComposition.estimate(heavy) == nil)
    }

    @Test func moisslWater() throws {
        let w = try #require(BodyWater.estimate(heightCm: 168, weightKg: 61.6, r0: 700, rInf: 470))
        #expect(abs(w.extracellularL - 13.8) < 0.05)
        #expect(abs(w.intracellularL - 19.9) < 0.05)
    }

    @Test func sweepMedianAndReference() throws {
        func point(_ f: Float, _ r: Double, _ x: Double) -> ImpedanceData.MeasurementPoint {
            let mag = (r * r + x * x).squareRoot()
            return .init(frequency: f, magnitude: Float(mag), phase: Float(-atan2(x, r) * 180 / .pi))
        }
        let rep = [point(40_000, 590, 64), point(60_000, 570, 66)]
        let outlier = [point(40_000, 900, 10), point(60_000, 900, 10)]
        let data = ImpedanceData(repetitions: [rep, rep, outlier])
        let sweep = try #require(SweepAnalysis(data))
        let ref = try #require(sweep.atReference)
        #expect(abs(ref.resistance - 579.0) < 1)
        #expect(abs(ref.reactance - 65.1) < 0.5)
        #expect(ref.phaseAngle > 6 && ref.phaseAngle < 7)
    }
}
