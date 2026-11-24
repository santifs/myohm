import Foundation
import SwiftData
import SwiftUI

/// ViewModel for the athlete creation wizard
/// Manages step navigation, validation, and athlete creation
///
/// Steps 0-6: Essential data — Name, DOB, Sex, Dominant Leg, Weight+Height, Right Thigh, Left Thigh
/// Steps 7-12: Optional data — Medical History, Medications, Diet, Allergies, Activities, Injuries
///
/// All 13 steps are shown in sequence. Optional steps (7-12) display a "Skip" link.
@Observable
@MainActor
final class AthleteWizardViewModel {

    // MARK: - Published Properties

    /// Shared data object holding all wizard state
    var wizardData = AthleteWizardData()

    /// Current step index (0-based)
    var currentStep: Int = 0

    /// Error message to display
    var errorMessage: String?

    /// Whether the wizard is currently saving
    var isSaving: Bool = false

    // MARK: - Step Configurations

    /// All step configs (steps 0-12)
    let stepConfigs: [StepConfig] = [
        // Essential steps
        StepConfig(title: "Nombre", subtitle: "Nombre completo del atleta"),                         // 0
        StepConfig(title: "Fecha de nacimiento", subtitle: "Para calcular la edad"),                 // 1
        StepConfig(title: "Sexo biológico", subtitle: "Para seguimiento fisiológico", autoAdvance: true), // 2
        StepConfig(title: "Pierna dominante", subtitle: "Para comparaciones bilaterales", autoAdvance: true), // 3
        StepConfig(title: "Peso y altura", subtitle: "Medidas corporales básicas"),                  // 4
        StepConfig(title: "Muslo derecho", subtitle: "Longitud y circunferencia"),                   // 5
        StepConfig(title: "Muslo izquierdo", subtitle: "Longitud y circunferencia"),                 // 6

        // Optional steps
        StepConfig(title: "Historial médico", subtitle: "Condiciones relevantes", isOptional: true), // 7
        StepConfig(title: "Medicamentos", subtitle: "Medicación actual", isOptional: true),          // 8
        StepConfig(title: "Dieta", subtitle: "Tipo de alimentación y calorías", isOptional: true),   // 9
        StepConfig(title: "Alergias", subtitle: "Alergias conocidas", isOptional: true),             // 10
        StepConfig(title: "Actividades", subtitle: "Actividades habituales", isOptional: true),      // 11
        StepConfig(title: "Lesiones", subtitle: "Lesiones actuales", isOptional: true),              // 12
    ]

    /// Total number of steps
    var totalSteps: Int { stepConfigs.count }

    // MARK: - Computed Properties

    /// All step configs are always active — no phase gating
    var activeStepConfigs: [StepConfig] {
        stepConfigs
    }

    /// Whether the current step can proceed.
    /// Only step 0 (name) has a hard validation requirement.
    var canProceedFromCurrentStep: Bool {
        switch currentStep {
        case 0:
            return !wizardData.fullName.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return true
        }
    }

    // MARK: - Navigation Methods

    /// Move to the next step
    func nextStep() {
        guard canProceedFromCurrentStep else { return }

        if currentStep < stepConfigs.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep += 1
            }
        }
    }

    // MARK: - Data Methods

    /// Create the athlete and save to SwiftData
    /// - Parameter context: The SwiftData model context
    /// - Returns: The created athlete, or nil if creation failed
    @discardableResult
    func createAthlete(context: ModelContext) -> Athlete? {
        guard wizardData.canCreateAthlete else {
            errorMessage = "Por favor, completa los datos obligatorios"
            return nil
        }

        isSaving = true
        defer { isSaving = false }

        // Create the athlete
        let athlete = wizardData.toAthlete()

        // Insert into context
        context.insert(athlete)

        // Create and link anthropometrics if provided
        if let anthropometrics = wizardData.toAnthropometrics(for: athlete) {
            context.insert(anthropometrics)
            athlete.anthropometrics = [anthropometrics]
        }

        // Create and link injury if reported
        if let injury = wizardData.toInjury(for: athlete) {
            context.insert(injury)
            athlete.injuries = [injury]
        }

        // Save context
        do {
            try context.save()
            return athlete
        } catch {
            errorMessage = "Error al guardar: \(error.localizedDescription)"
            return nil
        }
    }

    /// Reset the wizard to initial state
    func reset() {
        wizardData.reset()
        currentStep = 0
        errorMessage = nil
        isSaving = false
    }
}
