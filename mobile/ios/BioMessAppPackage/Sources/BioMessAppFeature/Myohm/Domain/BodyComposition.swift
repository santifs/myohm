import Foundation

/// Fat-free mass prediction equations used by Myohm.
///
/// Only equations with published coefficients that were checked against the original
/// abstracts are included. Each one keeps the population it was validated in so the app
/// can explain why it was chosen and when it should not be used.
public enum BodyEquation: String, CaseIterable, Sendable, Codable {
    /// Kyle UG et al. Nutrition 2001;17:248–253. doi:10.1016/S0899-9007(00)00553-0
    case geneva
    /// Matias CN, Campa F et al. Int J Sports Med 2021. doi:10.1055/a-1179-6236
    case athletes
    /// Houtkooper LB et al. J Appl Physiol 1992;72:366–373.
    case youth

    /// Fat-free mass in kg.
    /// - Parameters: height in cm, weight in kg, resistance and reactance at 50 kHz in ohms.
    public func fatFreeMass(heightCm h: Double, weightKg w: Double, r: Double, xc: Double, isMale: Bool) -> Double {
        let sex = isMale ? 1.0 : 0.0
        let index = h * h / r
        switch self {
        case .geneva:
            return -4.104 + 0.518 * index + 0.231 * w + 0.130 * xc + 4.229 * sex
        case .athletes:
            return -2.261 + 0.327 * index + 0.525 * w + 5.462 * sex
        case .youth:
            return 0.61 * index + 0.25 * w + 1.31
        }
    }

    /// Standard error of estimate for fat-free mass reported in the original abstract (kg), if verified.
    public var standardErrorKg: Double? {
        switch self {
        case .geneva: return 1.72
        case .athletes, .youth: return nil
        }
    }

    public var shortName: String {
        switch self {
        case .geneva: return "Geneva"
        case .athletes: return "Matias–Campa"
        case .youth: return "Houtkooper"
        }
    }

    public var citation: String {
        switch self {
        case .geneva:
            return "Kyle UG, Genton L, Karsegard L, Slosman DO, Pichard C. Single prediction equation for bioelectrical impedance analysis in adults aged 20–94 years. Nutrition 2001;17:248–253."
        case .athletes:
            return "Matias CN, Campa F, Santos DA, et al. Fat-free mass bioelectrical impedance analysis predictive equation for athletes using a 4-compartment model. Int J Sports Med 2021;42:27–32."
        case .youth:
            return "Houtkooper LB, Going SB, Lohman TG, Roche AF, Van Loan M. Bioelectrical impedance estimation of fat-free body mass in children and youth: a cross-validation study. J Appl Physiol 1992;72:366–373."
        }
    }

    public var doi: String? {
        switch self {
        case .geneva: return "10.1016/S0899-9007(00)00553-0"
        case .athletes: return "10.1055/a-1179-6236"
        case .youth: return "10.1152/jappl.1992.72.1.366"
        }
    }

    public var year: Int {
        switch self {
        case .geneva: return 2001
        case .athletes: return 2021
        case .youth: return 1992
        }
    }

    /// Validated age range (years), when checked against the abstract.
    public var ageRange: ClosedRange<Double>? {
        switch self {
        case .geneva: return 20...94
        case .athletes: return nil
        case .youth: return 10...19
        }
    }

    /// Validated BMI range, when the study reports one.
    public var bmiRange: ClosedRange<Double>? {
        switch self {
        case .geneva: return 17.0...33.8
        case .athletes, .youth: return nil
        }
    }
}

public struct BodyInputs: Sendable, Equatable {
    public var heightCm: Double
    public var weightKg: Double
    public var ageYears: Double
    public var isMale: Bool
    public var isAthlete: Bool
    /// Resistance at 50 kHz (Ω)
    public var r50: Double
    /// Reactance at 50 kHz (Ω, positive)
    public var xc50: Double

    public init(heightCm: Double, weightKg: Double, ageYears: Double, isMale: Bool, isAthlete: Bool, r50: Double, xc50: Double) {
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.ageYears = ageYears
        self.isMale = isMale
        self.isAthlete = isAthlete
        self.r50 = r50
        self.xc50 = xc50
    }

    public var bmi: Double { weightKg / pow(heightCm / 100, 2) }
}

public enum EquationSelection: Sendable, Equatable {
    case equation(BodyEquation)
    /// Under 10 years: no validated equation; show phase angle only.
    case tooYoung
    /// BMI above 34: prediction equations are not valid; show water from the spectrum only.
    case highBMI

    public var equation: BodyEquation? {
        if case .equation(let e) = self { return e }
        return nil
    }
}

public struct FatEstimate: Sendable, Equatable {
    public let equation: BodyEquation
    public let fatFreeMassKg: Double
    public let fatMassKg: Double
    public let fatPercent: Double
    /// Error in fat percentage points derived from the equation's SEE, when known.
    public let fatPercentError: Double?
}

/// Sanity gates for a whole-body (wrist–ankle) reading before any composition is computed.
///
/// These are deliberately wide app limits, not published reference ranges: adult NHANES
/// Xitron data (R0 ≈ 600–700 Ω) and phase-angle norms (≈ 5–7°) sit well inside them.
/// Values outside mean a loose cable or an electrode without contact, and a regression
/// fed with them returns nonsense (for example negative body fat).
public enum WholeBodySignal {
    public static let resistance: ClosedRange<Double> = 250...1100
    public static let reactance: ClosedRange<Double> = 15...130
    public static let phaseAngle: ClosedRange<Double> = 2...14

    public static func isPlausible(r50: Double, xc50: Double) -> Bool {
        let phase = atan2(xc50, r50) * 180 / .pi
        return resistance.contains(r50) && reactance.contains(xc50) && phaseAngle.contains(phase)
    }
}

public enum BodyComposition {
    public static let maxBMI = 34.0
    /// Fat percentages outside this range are reported as not computable.
    public static let plausibleFatPercent: ClosedRange<Double> = 3...65

    public static func select(for inputs: BodyInputs) -> EquationSelection {
        if inputs.ageYears < 10 { return .tooYoung }
        if inputs.bmi > maxBMI { return .highBMI }
        if inputs.ageYears < 20 { return .equation(.youth) }
        if inputs.isAthlete { return .equation(.athletes) }
        return .equation(.geneva)
    }

    public static func estimate(_ inputs: BodyInputs, using equation: BodyEquation) -> FatEstimate {
        let ffm = equation.fatFreeMass(
            heightCm: inputs.heightCm, weightKg: inputs.weightKg,
            r: inputs.r50, xc: inputs.xc50, isMale: inputs.isMale
        )
        let fat = inputs.weightKg - ffm
        let error = equation.standardErrorKg.map { $0 / inputs.weightKg * 100 }
        return FatEstimate(
            equation: equation,
            fatFreeMassKg: ffm,
            fatMassKg: fat,
            fatPercent: fat / inputs.weightKg * 100,
            fatPercentError: error
        )
    }

    /// Automatic choice, or nil when the population or the signal does not allow one.
    public static func estimate(_ inputs: BodyInputs) -> FatEstimate? {
        guard case .equation(let equation) = select(for: inputs) else { return nil }
        return checkedEstimate(inputs, using: equation)
    }

    /// Estimate with a given equation, or nil when the reading or the result is implausible.
    public static func checkedEstimate(_ inputs: BodyInputs, using equation: BodyEquation) -> FatEstimate? {
        guard WholeBodySignal.isPlausible(r50: inputs.r50, xc50: inputs.xc50) else { return nil }
        let e = estimate(inputs, using: equation)
        return plausibleFatPercent.contains(e.fatPercent) ? e : nil
    }
}

/// Body water from the Cole fit, following Moissl et al. Physiol Meas 2006;27:921–933.
/// doi:10.1088/0967-3334/27/9/012
public struct BodyWater: Sendable, Equatable {
    public let extracellularL: Double
    public let intracellularL: Double
    public var totalL: Double { extracellularL + intracellularL }
    public var extracellularRatio: Double { extracellularL / totalL }
    /// Fat-free mass assuming 73 % hydration.
    public var fatFreeMassKg: Double { totalL / 0.73 }

    public static func estimate(heightCm h: Double, weightKg w: Double, r0: Double, rInf: Double) -> BodyWater? {
        guard r0 > rInf, rInf > 0, h > 0, w > 0 else { return nil }
        let bmi = w / pow(h / 100, 2)
        let ri = 1 / (1 / rInf - 1 / r0)
        let base = h * h * w.squareRoot()
        let kECW = 0.188 / bmi + 0.2883
        let kICW = 5.8758 / bmi + 0.4194
        let ecw = kECW * pow(base / r0, 2.0 / 3.0)
        let icw = kICW * pow(base / ri, 2.0 / 3.0)
        return BodyWater(extracellularL: ecw, intracellularL: icw)
    }
}
