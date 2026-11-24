import SwiftUI
import SwiftData

/// Main wizard view for creating a new athlete profile
/// Shows all 13 steps in sequence; optional steps (7-12) display a "Skip" link.
struct AthleteWizardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalPersistenceService.self) private var syncService: LocalPersistenceService?

    @State private var viewModel = AthleteWizardViewModel()

    /// Callback when athlete is created successfully
    var onAthleteCreated: ((Athlete) -> Void)?

    var body: some View {
        NavigationStack {
            StepFlowView(
                steps: viewModel.activeStepConfigs,
                currentStep: $viewModel.currentStep,
                canProceed: viewModel.canProceedFromCurrentStep,
                lastButtonTitle: "Crear Atleta",
                onComplete: {
                    createAthlete()
                },
                content: { stepIndex in
                    stepContent(for: stepIndex)
                        .padding(.horizontal)
                }
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("Aceptar") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private func stepContent(for step: Int) -> some View {
        switch step {
        case 0:
            nameStep
        case 1:
            dobStep
        case 2:
            sexStep
        case 3:
            dominantLegStep
        case 4:
            weightHeightStep
        case 5:
            rightThighStep
        case 6:
            leftThighStep
        case 7:
            medicalHistoryStep
        case 8:
            medicationsStep
        case 9:
            dietStep
        case 10:
            allergiesStep
        case 11:
            activitiesStep
        case 12:
            injuriesStep
        default:
            EmptyView()
        }
    }

    // MARK: - Essential Steps (0-6)

    // Step 0: Name
    private var nameStep: some View {
        TextField("Nombre completo", text: $viewModel.wizardData.fullName)
            .font(.system(size: 22, weight: .medium))
            .multilineTextAlignment(.center)
            #if os(iOS)
            .textInputAutocapitalization(.words)
            #endif
            .autocorrectionDisabled()
            .padding()
            .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    // Step 1: Date of Birth
    private var dobStep: some View {
        VStack(spacing: 20) {
            DatePicker(
                "Fecha de nacimiento",
                selection: $viewModel.wizardData.dateOfBirth,
                in: viewModel.wizardData.minimumDateOfBirth...viewModel.wizardData.maximumDateOfBirth,
                displayedComponents: .date
            )
            #if os(iOS)
            .datePickerStyle(.wheel)
            #endif
            .labelsHidden()

            // Calculated age
            let age = Calendar.current.dateComponents(
                [.year],
                from: viewModel.wizardData.dateOfBirth,
                to: Date()
            ).year ?? 0

            Text("\(age) años")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.secondarySystemGroupedBackground, in: Capsule())
        }
    }

    // Step 2: Sex
    private var sexStep: some View {
        VStack(spacing: 12) {
            SelectionCard(
                title: "Mujer",
                icon: "venus",
                isSelected: viewModel.wizardData.biologicalSex == .female
            ) {
                viewModel.wizardData.biologicalSex = .female
                autoAdvanceAfterDelay()
            }

            SelectionCard(
                title: "Hombre",
                icon: "mars",
                isSelected: viewModel.wizardData.biologicalSex == .male
            ) {
                viewModel.wizardData.biologicalSex = .male
                autoAdvanceAfterDelay()
            }

            SelectionCard(
                title: "Sin especificar",
                icon: "person.fill.questionmark",
                isSelected: viewModel.wizardData.biologicalSex == nil
            ) {
                viewModel.wizardData.biologicalSex = nil
                autoAdvanceAfterDelay()
            }
        }
    }

    // Step 3: Dominant Leg
    private var dominantLegStep: some View {
        VStack(spacing: 12) {
            SelectionCard(
                title: "Derecha",
                icon: "arrow.right.circle",
                isSelected: viewModel.wizardData.dominantLeg == .right
            ) {
                viewModel.wizardData.dominantLeg = .right
                autoAdvanceAfterDelay()
            }

            SelectionCard(
                title: "Izquierda",
                icon: "arrow.left.circle",
                isSelected: viewModel.wizardData.dominantLeg == .left
            ) {
                viewModel.wizardData.dominantLeg = .left
                autoAdvanceAfterDelay()
            }

            SelectionCard(
                title: "Ambas",
                icon: "arrow.left.arrow.right.circle",
                isSelected: viewModel.wizardData.dominantLeg == .ambidextrous
            ) {
                viewModel.wizardData.dominantLeg = .ambidextrous
                autoAdvanceAfterDelay()
            }
        }
    }

    // Step 4: Weight + Height
    private var weightHeightStep: some View {
        VStack(spacing: 24) {
            VisualStepper(
                value: $viewModel.wizardData.weightKgValue,
                range: 20...200,
                step: 0.5,
                unit: "kg",
                format: "%.1f"
            )

            Divider()

            VisualStepper(
                value: $viewModel.wizardData.heightCmValue,
                range: 100...230,
                step: 1,
                unit: "cm",
                format: "%.0f"
            )

            // BMI badge
            if let bmi = viewModel.wizardData.bmi {
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.square")
                        .foregroundStyle(.secondary)
                    Text(String(format: "IMC: %.1f", bmi))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(bmiCategory(bmi))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.secondarySystemGroupedBackground, in: Capsule())
            }
        }
    }

    // Step 5: Right Thigh
    private var rightThighStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Longitud")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Desde el pliegue inguinal hasta el borde superior de la rótula")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                VisualStepper(
                    value: $viewModel.wizardData.rightThighLengthValue,
                    range: 20...70,
                    step: 0.5,
                    unit: "cm",
                    format: "%.1f"
                )
            }

            Divider()

            VStack(spacing: 4) {
                Text("Circunferencia")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("En el punto más ancho del muslo (zona media)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                VisualStepper(
                    value: $viewModel.wizardData.rightThighCircumferenceValue,
                    range: 25...90,
                    step: 0.5,
                    unit: "cm",
                    format: "%.1f"
                )
            }
        }
    }

    // Step 6: Left Thigh
    private var leftThighStep: some View {
        VStack(spacing: 24) {
            // Copy from right button
            Button {
                viewModel.wizardData.copyRightToLeft()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                    Text("Copiar del derecho")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.brandPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.brandPrimary.opacity(0.1), in: Capsule())
            }

            VStack(spacing: 4) {
                Text("Longitud")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Desde el pliegue inguinal hasta el borde superior de la rótula")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                VisualStepper(
                    value: $viewModel.wizardData.leftThighLengthValue,
                    range: 20...70,
                    step: 0.5,
                    unit: "cm",
                    format: "%.1f"
                )
            }

            Divider()

            VStack(spacing: 4) {
                Text("Circunferencia")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("En el punto más ancho del muslo (zona media)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                VisualStepper(
                    value: $viewModel.wizardData.leftThighCircumferenceValue,
                    range: 25...90,
                    step: 0.5,
                    unit: "cm",
                    format: "%.1f"
                )
            }
        }
    }

    // MARK: - Optional Steps (7-12)

    // Step 7: Medical History
    private var medicalHistoryStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notas de historial médico")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.wizardData.medicalHistory)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.systemGray4, lineWidth: 1)
                )
        }
    }

    // Step 8: Medications
    private var medicationsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Medicación actual")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.wizardData.medications)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.systemGray4, lineWidth: 1)
                )
        }
    }

    // Step 9: Diet
    private var dietStep: some View {
        VStack(spacing: 24) {
            ChipRow(
                options: [
                    (label: "Omnivora", icon: "fork.knife"),
                    (label: "Vegetariana", icon: "leaf"),
                    (label: "Vegana", icon: "leaf.fill"),
                    (label: "Otra", icon: "ellipsis.circle")
                ],
                selected: $viewModel.wizardData.dietType
            )

            Divider()

            VStack(spacing: 4) {
                Text("Calorías diarias")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VisualStepper(
                    value: $viewModel.wizardData.dailyCaloriesValue,
                    range: 500...6000,
                    step: 100,
                    unit: "kcal",
                    format: "%.0f"
                )
            }
        }
    }

    // Step 10: Allergies
    private var allergiesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            MultiSelectChipGrid(
                options: CommonAllergy.allCases.map { allergy in
                    (label: allergy.displayName, icon: allergy.iconName)
                },
                selected: $viewModel.wizardData.allergies
            )
        }
    }

    // Step 11: Activities
    private var activitiesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            MultiSelectChipGrid(
                options: CommonActivity.allCases.map { activity in
                    (label: activity.displayName, icon: activity.iconName)
                },
                selected: $viewModel.wizardData.usualActivities
            )
        }
    }

    // Step 12: Injuries
    private var injuriesStep: some View {
        VStack(spacing: 16) {
            // Has injury selection
            SelectionCard(
                title: "Sí",
                icon: "bandage",
                isSelected: viewModel.wizardData.hasInjury
            ) {
                viewModel.wizardData.hasInjury = true
            }

            SelectionCard(
                title: "No",
                icon: "hand.thumbsup",
                isSelected: !viewModel.wizardData.hasInjury
            ) {
                viewModel.wizardData.hasInjury = false
                // This is the last step, so auto-advance triggers onComplete
                autoAdvanceAfterDelay()
            }

            // Conditional injury detail UI
            if viewModel.wizardData.hasInjury {
                Divider()

                // Injury type
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tipo de lesión")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 12) {
                        injuryTypeButton(type: .muscular, label: "Muscular", icon: "figure.strengthtraining.traditional")
                        injuryTypeButton(type: .nonMuscular, label: "No muscular", icon: "bandage")
                    }
                }

                // Detail based on type
                if viewModel.wizardData.injuryType == .muscular {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detalle")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ForEach(MuscularInjuryDetail.allCases, id: \.rawValue) { detail in
                            SelectionCard(
                                title: detail.displayName,
                                icon: "cross.circle",
                                isSelected: viewModel.wizardData.muscularDetail == detail
                            ) {
                                viewModel.wizardData.muscularDetail = detail
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Describe la lesión")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextEditor(text: $viewModel.wizardData.nonMuscularDetail)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.systemGray4, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func injuryTypeButton(type: InjuryType, label: String, icon: String) -> some View {
        let isSelected = viewModel.wizardData.injuryType == type

        return Button {
            viewModel.wizardData.injuryType = type
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isSelected ? Color.brandPrimary.opacity(0.15) : Color.secondarySystemGroupedBackground,
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.brandPrimary : .primary)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.brandPrimary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func autoAdvanceAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            viewModel.nextStep()
        }
    }

    private func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "Bajo peso"
        case 18.5..<25: return "Normal"
        case 25..<30: return "Sobrepeso"
        default: return "Obesidad"
        }
    }

    // MARK: - Actions

    private func createAthlete() {
        if let athlete = viewModel.createAthlete(context: modelContext) {
            onAthleteCreated?(athlete)

            // Trigger sync to Supabase
            Task {
                await syncService?.syncAll()
            }

            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    AthleteWizardView()
        .modelContainer(for: [Athlete.self, Anthropometrics.self, Injury.self], inMemory: true)
}
