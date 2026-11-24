import Foundation
import SwiftData
import SwiftUI

/// ViewModel for the pre-measurement session questionnaire
/// Manages form state, validation, and session creation
@Observable
@MainActor
final class PreSessionFormViewModel {

    // MARK: - Form Data (matches MeasurementSession fields)

    /// Hours since last physical activity
    var hoursSinceActivityText: String = ""

    /// Type of last activity performed
    var lastActivityType: String = "" {
        didSet {
            let activity = lastActivityType.lowercased()
            if ["carrera", "running", "correr", "ciclismo", "futbol", "fútbol", "baloncesto"].contains(activity) {
                involvedLegs = true
            } else {
                involvedLegs = nil
            }
            legMuscleGroup = nil
        }
    }

    /// Hours of sleep last night
    var sleepHoursText: String = ""

    /// General fatigue level 0-10 (default to middle)
    var generalFatigue: Int = 5

    /// Whether athlete had recent physiotherapy
    var recentPhysio: Bool = false

    /// Hours since physiotherapy session
    var recentPhysioHoursAgoText: String = ""

    /// Any new issues or discomfort to report
    var newIssues: String = ""

    /// Menstrual cycle phase (for female athletes)
    var menstrualCyclePhase: MenstrualCyclePhase?

    /// Whether the activity involved leg work
    var involvedLegs: Bool?

    /// Which leg muscle group: "quadriceps", "hamstrings", or "both"
    var legMuscleGroup: String?

    // MARK: - State

    /// Whether the form is currently being submitted
    var isSubmitting: Bool = false

    /// Error message to display
    var errorMessage: String?

    /// The athlete this session is for
    var athlete: Athlete?

    // MARK: - Computed Properties

    /// Parsed hours since activity
    var hoursSinceActivity: Double? {
        Double(hoursSinceActivityText.trimmingCharacters(in: .whitespaces))
    }

    /// Parsed sleep hours
    var sleepHours: Double? {
        Double(sleepHoursText.trimmingCharacters(in: .whitespaces))
    }

    /// Parsed hours since physio
    var recentPhysioHoursAgo: Int? {
        Int(recentPhysioHoursAgoText.trimmingCharacters(in: .whitespaces))
    }

    /// Current date formatted for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.string(from: Date())
    }

    /// Athlete display name
    var athleteDisplayName: String {
        athlete?.displayName ?? "Atleta no seleccionado"
    }

    /// Whether to show menstrual cycle section (only for female athletes)
    var shouldShowMenstrualCycleSection: Bool {
        athlete?.biologicalSex == .female
    }

    /// Common activity types for picker
    var commonActivityTypes: [String] {
        // Combine athlete's usual activities with common types
        var activities = athlete?.usualActivities ?? []

        // Add common activity types if not already present
        let commonTypes = [
            "Baloncesto",
            "Natación",
            "Ciclismo",
            "Carrera",
            "Pesas",
            "CrossFit",
            "Yoga",
            "HIIT",
            "Tenis",
            "Otro"
        ]

        for activity in commonTypes {
            if !activities.contains(where: { $0.lowercased() == activity.lowercased() }) {
                activities.append(activity)
            }
        }

        return activities
    }

    /// Whether the form has minimum required data to proceed
    var isFormValid: Bool {
        // At minimum, we need an athlete and fatigue level
        // Other fields are optional but recommended
        athlete != nil
    }

    /// Whether hours since activity is valid
    var isHoursSinceActivityValid: Bool {
        guard let hours = hoursSinceActivity else { return true }
        return hours >= 0 && hours <= 168 // Up to 1 week
    }

    /// Whether sleep hours is valid
    var isSleepHoursValid: Bool {
        guard let hours = sleepHours else { return true }
        return hours >= 0 && hours <= 24
    }

    /// Whether physio hours is valid
    var isPhysioHoursValid: Bool {
        guard recentPhysio, let hours = recentPhysioHoursAgo else { return true }
        return hours >= 0 && hours <= 168 // Up to 1 week
    }

    /// Whether all validations pass
    var hasValidationErrors: Bool {
        !isHoursSinceActivityValid || !isSleepHoursValid || !isPhysioHoursValid
    }

    // MARK: - Step Flow Properties

    /// Current step index
    var currentStep: Int = 0

    /// Hours since activity as Double for the visual stepper
    var hoursSinceActivityValue: Double = 0

    /// Sleep hours as Double for the visual stepper
    var sleepHoursValue: Double = 7

    /// Physio hours as Double for the visual stepper
    var recentPhysioHoursAgoValue: Double = 0

    /// Whether this is a basal session (skips the activity step)
    var isBasal: Bool {
        sessionType == "basal"
    }

    /// Total number of steps (depends on sessionType and athlete sex)
    var totalSteps: Int {
        stepConfigs.count
    }

    /// Step key enum for mapping step indices to content
    enum StepKey: Equatable {
        case activity
        case rest
        case fatigue
        case physiotherapy
        case observations
        case menstrualCycle
    }

    /// Ordered step keys for the current session type
    var stepKeys: [StepKey] {
        var keys: [StepKey] = []
        if !isBasal {
            keys.append(.activity)
        }
        keys.append(contentsOf: [.rest, .fatigue, .physiotherapy, .observations])
        if shouldShowMenstrualCycleSection {
            keys.append(.menstrualCycle)
        }
        return keys
    }

    /// Step configurations (adapted by sessionType)
    var stepConfigs: [StepConfig] {
        return stepKeys.map { key in
            switch key {
            case .activity:
                return StepConfig(title: "Última actividad física", subtitle: "¿Hace cuántas horas fue tu último entrenamiento?")
            case .rest:
                return StepConfig(title: "Descanso nocturno", subtitle: "¿Cuántas horas has dormido esta noche?")
            case .fatigue:
                return StepConfig(title: "Fatiga percibida", subtitle: "Valora cómo de cansado te encuentras hoy")
            case .physiotherapy:
                return StepConfig(title: "Fisioterapia", subtitle: "¿Has recibido algún tratamiento en las últimas horas?")
            case .observations:
                return StepConfig(title: "Observaciones", subtitle: "Cualquier molestia, dolor o novedad relevante", isOptional: true)
            case .menstrualCycle:
                return StepConfig(title: "Ciclo menstrual", subtitle: "Selecciona la fase actual de tu ciclo", autoAdvance: true)
            }
        }
    }

    /// Whether current step can proceed
    var canProceedFromCurrentStep: Bool {
        true // all steps have defaults or are optional
    }

    /// Whether we have Quick Start data (last session for this athlete)
    var hasQuickStartData: Bool {
        lastSession != nil
    }

    /// Whether the selected activity is an obvious leg activity
    var isObviousLegActivity: Bool {
        let activity = lastActivityType.lowercased()
        return ["carrera", "running", "correr", "ciclismo", "futbol", "fútbol", "baloncesto"].contains(activity)
    }

    /// Whether to show the "involved legs?" question
    var shouldAskAboutLegs: Bool {
        !lastActivityType.isEmpty && !isObviousLegActivity
    }

    /// Shows the quick start screen
    var showQuickStart: Bool = true

    /// Last session for pre-fill
    var lastSession: MeasurementSession?

    /// Session type: "basal" or "match"
    var sessionType: String?

    /// Study code this session belongs to (set by the caller before submitting)
    var studyId: String?

    // MARK: - Initialization

    init(athlete: Athlete? = nil, sessionType: String? = nil, studyId: String? = nil) {
        self.athlete = athlete
        self.sessionType = sessionType
        self.studyId = studyId
    }

    // MARK: - Step Flow Methods

    /// Advance to next step
    func nextStep() {
        if currentStep < totalSteps - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep += 1
            }
        }
    }

    /// Go back one step
    func previousStep() {
        if currentStep > 0 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep -= 1
            }
        }
    }

    /// Sync stepper values to text fields (for createSession compatibility)
    func syncStepperValues() {
        hoursSinceActivityText = String(format: "%.0f", hoursSinceActivityValue)
        sleepHoursText = String(format: "%.1f", sleepHoursValue)
        if recentPhysio {
            recentPhysioHoursAgoText = String(format: "%.0f", recentPhysioHoursAgoValue)
        }
    }

    /// Load last session data for quick start
    func loadLastSession(context: ModelContext) {
        guard let athlete = athlete else { return }
        let athleteId = athlete.id
        let descriptor = FetchDescriptor<MeasurementSession>(
            predicate: #Predicate { $0.athlete?.id == athleteId },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        lastSession = try? context.fetch(descriptor).first
        showQuickStart = lastSession != nil
    }

    /// Pre-fill from last session (quick start)
    func prefillFromLastSession() {
        guard let session = lastSession else { return }
        if let hours = session.hoursSinceActivity {
            hoursSinceActivityValue = hours
        }
        lastActivityType = session.lastActivityType ?? ""
        if let sleep = session.sleepHours {
            sleepHoursValue = sleep
        }
        if let fatigue = session.generalFatigue {
            generalFatigue = fatigue
        }
        recentPhysio = session.recentPhysio ?? false
        if let physioHours = session.recentPhysioHoursAgo {
            recentPhysioHoursAgoValue = Double(physioHours)
        }
        newIssues = "" // Don't carry over issues
        menstrualCyclePhase = session.menstrualCyclePhase
        involvedLegs = session.involvedLegs
        legMuscleGroup = session.legMuscleGroup
    }

    // MARK: - Methods

    /// Create a MeasurementSession from the form data
    /// - Parameter context: The SwiftData model context
    /// - Returns: The created session, or nil if validation fails
    @discardableResult
    func createSession(context: ModelContext) -> MeasurementSession? {
        guard isFormValid else {
            errorMessage = "Por favor, selecciona un atleta"
            return nil
        }

        guard !hasValidationErrors else {
            errorMessage = "Por favor, corrige los errores en el formulario"
            return nil
        }

        isSubmitting = true
        defer { isSubmitting = false }

        // Create the session with form data
        let session = MeasurementSession(
            id: UUID(),
            athlete: athlete,
            startedAt: Date(),
            hoursSinceActivity: isBasal ? nil : hoursSinceActivity,
            lastActivityType: isBasal ? nil : (lastActivityType.isEmpty ? nil : lastActivityType),
            sleepHours: sleepHours,
            generalFatigue: generalFatigue,
            recentPhysio: recentPhysio,
            recentPhysioHoursAgo: recentPhysio ? recentPhysioHoursAgo : nil,
            newIssues: newIssues.isEmpty ? nil : newIssues,
            menstrualCyclePhase: shouldShowMenstrualCycleSection ? menstrualCyclePhase : nil,
            involvedLegs: isBasal ? nil : (involvedLegs == true || isObviousLegActivity ? true : involvedLegs),
            legMuscleGroup: nil,
            sessionType: sessionType,
            studyId: studyId
        )

        // Insert into context
        context.insert(session)

        // Save context
        do {
            try context.save()
            return session
        } catch {
            errorMessage = "Error al crear la sesion: \(error.localizedDescription)"
            return nil
        }
    }

    /// Reset the form to initial state
    func reset() {
        hoursSinceActivityText = ""
        lastActivityType = ""
        sleepHoursText = ""
        generalFatigue = 5
        recentPhysio = false
        recentPhysioHoursAgoText = ""
        newIssues = ""
        menstrualCyclePhase = nil
        involvedLegs = nil
        legMuscleGroup = nil
        errorMessage = nil
        isSubmitting = false
    }

    /// Pre-fill form with athlete's typical data if available
    func prefillFromAthlete() {
        guard let athlete = athlete else { return }

        // If athlete has usual activities, suggest the first one
        if let firstActivity = athlete.usualActivities?.first {
            lastActivityType = firstActivity
        }
    }
}
