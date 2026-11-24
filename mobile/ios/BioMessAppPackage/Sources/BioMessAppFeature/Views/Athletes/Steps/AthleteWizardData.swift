import Foundation
import SwiftData

/// Shared data object that holds all wizard state for athlete creation
@Observable
public final class AthleteWizardData {

    // MARK: - Step 1: Basic Info (Obligatorio)

    /// Full name of the athlete
    var fullName: String = ""

    /// Date of birth for age calculations
    var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()

    /// Dominant leg for bilateral comparisons
    var dominantLeg: DominantLeg = .right

    /// Biological sex for physiological tracking
    var biologicalSex: BiologicalSex?

    // MARK: - Step 2: Anthropometrics (Obligatorio)

    /// Body weight in kilograms
    var weightKg: Double? = 70

    /// Height in centimeters
    var heightCm: Double? = 170

    /// Right thigh length in centimeters (hip crease to knee)
    var rightThighLengthCm: Double? = 40

    /// Right thigh circumference in centimeters
    var rightThighCircumferenceCm: Double? = 50

    /// Left thigh length in centimeters (hip crease to knee)
    var leftThighLengthCm: Double? = 40

    /// Left thigh circumference in centimeters
    var leftThighCircumferenceCm: Double? = 50

    // MARK: - Step 3: Medical History (Opcional)

    /// Medical history notes
    var medicalHistory: String = ""

    /// Current medications
    var medications: String = ""

    // MARK: - Step 4: Nutrition (Opcional)

    /// Diet type (e.g., "Omnivora", "Vegetariana", "Vegana")
    var dietType: String = ""

    /// Daily caloric intake
    var dailyCalories: Int?

    /// Known allergies
    var allergies: Set<String> = []

    // MARK: - Step 5: Activity (Opcional)

    /// Usual physical activities
    var usualActivities: Set<String> = []

    // MARK: - Step 6: Injuries (Opcional)

    /// Whether the athlete has any current injury
    var hasInjury: Bool = false

    /// Type of injury (muscular or non-muscular)
    var injuryType: InjuryType = .muscular

    /// Details for muscular injuries
    var muscularDetail: MuscularInjuryDetail?

    /// Details for non-muscular injuries
    var nonMuscularDetail: String = ""

    // MARK: - Validation

    /// Check if basic info step is valid (required fields)
    var isBasicInfoValid: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Check if anthropometrics step is valid (required fields)
    var isAnthropometricsValid: Bool {
        weightKg != nil &&
        heightCm != nil &&
        rightThighLengthCm != nil &&
        rightThighCircumferenceCm != nil &&
        leftThighLengthCm != nil &&
        leftThighCircumferenceCm != nil
    }

    /// Check if the wizard has minimum required data to create an athlete
    var canCreateAthlete: Bool {
        isBasicInfoValid && isAnthropometricsValid
    }

    // MARK: - Stepper-friendly values

    var weightKgValue: Double {
        get { weightKg ?? 70 }
        set { weightKg = newValue }
    }

    var heightCmValue: Double {
        get { heightCm ?? 170 }
        set { heightCm = newValue }
    }

    var rightThighLengthValue: Double {
        get { rightThighLengthCm ?? 40 }
        set { rightThighLengthCm = newValue }
    }

    var rightThighCircumferenceValue: Double {
        get { rightThighCircumferenceCm ?? 50 }
        set { rightThighCircumferenceCm = newValue }
    }

    var leftThighLengthValue: Double {
        get { leftThighLengthCm ?? 40 }
        set { leftThighLengthCm = newValue }
    }

    var leftThighCircumferenceValue: Double {
        get { leftThighCircumferenceCm ?? 50 }
        set { leftThighCircumferenceCm = newValue }
    }

    var dailyCaloriesValue: Double {
        get { Double(dailyCalories ?? 2000) }
        set { dailyCalories = Int(newValue) }
    }

    func copyRightToLeft() {
        leftThighLengthCm = rightThighLengthCm
        leftThighCircumferenceCm = rightThighCircumferenceCm
    }

    // MARK: - Computed Properties

    /// Calculate BMI if height and weight are available
    var bmi: Double? {
        guard let weight = weightKg,
              let height = heightCm,
              height > 0 else { return nil }

        let heightInMeters = height / 100.0
        return weight / (heightInMeters * heightInMeters)
    }

    /// Minimum date of birth (100 years ago)
    var minimumDateOfBirth: Date {
        Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date()
    }

    /// Maximum date of birth (today)
    var maximumDateOfBirth: Date {
        Date()
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Conversion

    /// Convert wizard data to an Athlete model
    func toAthlete() -> Athlete {
        let athlete = Athlete(
            fullName: fullName.trimmingCharacters(in: .whitespaces),
            dateOfBirth: dateOfBirth,
            dominantLeg: dominantLeg,
            biologicalSex: biologicalSex,
            medicalHistory: medicalHistory.isEmpty ? nil : medicalHistory,
            medications: medications.isEmpty ? nil : medications,
            dietType: dietType.isEmpty ? nil : dietType,
            dailyCalories: dailyCalories,
            allergies: allergies.isEmpty ? nil : Array(allergies),
            usualActivities: usualActivities.isEmpty ? nil : Array(usualActivities)
        )

        return athlete
    }

    /// Create anthropometrics data if any measurements were provided
    func toAnthropometrics(for athlete: Athlete) -> Anthropometrics? {
        // Only create if at least one measurement is provided
        guard weightKg != nil ||
              heightCm != nil ||
              rightThighLengthCm != nil ||
              rightThighCircumferenceCm != nil ||
              leftThighLengthCm != nil ||
              leftThighCircumferenceCm != nil else {
            return nil
        }

        return Anthropometrics(
            athlete: athlete,
            measuredAt: Date(),
            weightKg: weightKg,
            heightCm: heightCm,
            rightThighLengthCm: rightThighLengthCm,
            rightThighCircumferenceCm: rightThighCircumferenceCm,
            leftThighLengthCm: leftThighLengthCm,
            leftThighCircumferenceCm: leftThighCircumferenceCm
        )
    }

    /// Create injury data if an injury was reported
    func toInjury(for athlete: Athlete) -> Injury? {
        guard hasInjury else { return nil }

        let muscularDetailString: String?
        let nonMuscularDetailString: String?

        if injuryType == .muscular {
            muscularDetailString = muscularDetail?.rawValue
            nonMuscularDetailString = nil
        } else {
            muscularDetailString = nil
            nonMuscularDetailString = nonMuscularDetail.isEmpty ? nil : nonMuscularDetail
        }

        return Injury(
            athlete: athlete,
            reportedAt: Date(),
            injuryType: injuryType,
            muscularDetail: muscularDetailString,
            nonMuscularDetail: nonMuscularDetailString,
            isActive: true
        )
    }

    // MARK: - Reset

    /// Reset all wizard data to defaults
    func reset() {
        // Step 1
        fullName = ""
        dateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
        dominantLeg = .right
        biologicalSex = nil

        // Step 2
        weightKg = 70
        heightCm = 170
        rightThighLengthCm = 40
        rightThighCircumferenceCm = 50
        leftThighLengthCm = 40
        leftThighCircumferenceCm = 50

        // Step 3
        medicalHistory = ""
        medications = ""

        // Step 4
        dietType = ""
        dailyCalories = nil
        allergies = []

        // Step 5
        usualActivities = []

        // Step 6
        hasInjury = false
        injuryType = .muscular
        muscularDetail = nil
        nonMuscularDetail = ""
    }
}

// MARK: - Common Allergies

/// Common allergies for selection chips
enum CommonAllergy: String, CaseIterable, Identifiable {
    case lacteos = "Lácteos"
    case gluten = "Gluten"
    case frutosSecos = "Frutos secos"
    case mariscos = "Mariscos"
    case huevos = "Huevos"
    case soja = "Soja"
    case otro = "Otro"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var iconName: String {
        switch self {
        case .lacteos: return "cup.and.saucer"
        case .gluten: return "leaf"
        case .frutosSecos: return "leaf.circle"
        case .mariscos: return "fish"
        case .huevos: return "oval"
        case .soja: return "leaf.fill"
        case .otro: return "plus.circle"
        }
    }
}

// MARK: - Common Activities

/// Common physical activities for selection chips
enum CommonActivity: String, CaseIterable, Identifiable {
    case running = "Running"
    case gimnasio = "Gimnasio"
    case ciclismo = "Ciclismo"
    case natacion = "Natación"
    case baloncesto = "Baloncesto"
    case tenis = "Tenis"
    case otro = "Otro"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var iconName: String {
        switch self {
        case .running: return "figure.run"
        case .gimnasio: return "dumbbell"
        case .ciclismo: return "bicycle"
        case .natacion: return "figure.pool.swim"
        case .baloncesto: return "basketball"
        case .tenis: return "tennis.racket"
        case .otro: return "plus.circle"
        }
    }
}

// MARK: - Dominant Leg Spanish Display

extension DominantLeg {
    var spanishDisplayName: String {
        switch self {
        case .right: return "Derecha"
        case .left: return "Izquierda"
        case .ambidextrous: return "Ambas"
        }
    }
}

// MARK: - Injury Type Spanish Display

extension InjuryType {
    var spanishDisplayName: String {
        switch self {
        case .muscular: return "Muscular"
        case .nonMuscular: return "No muscular"
        }
    }
}
