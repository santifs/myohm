import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Pre-measurement session form that captures athlete state before measurements
/// This form is filled ONCE before starting a measurement session
struct PreSessionFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: PreSessionFormViewModel

    /// Callback when session is created successfully
    var onSessionCreated: ((MeasurementSession) -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.showQuickStart && viewModel.hasQuickStartData {
                    quickStartView
                } else {
                    stepFlowContent
                }
            }
            .navigationTitle("Iniciar Medición")
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
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                viewModel.loadLastSession(context: modelContext)
            }
        }
    }

    // MARK: - Quick Start View

    private var quickStartView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.brandPrimary)
            }

            // Title
            VStack(spacing: 8) {
                Text("Inicio rápido")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Utiliza los datos de tu última sesión o actualízalos antes de empezar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Last session summary
            if let session = viewModel.lastSession {
                lastSessionSummaryCard(session: session)
                    .padding(.horizontal)
            }

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button {
                    viewModel.prefillFromLastSession()
                    viewModel.syncStepperValues()
                    submitForm()
                } label: {
                    Text("Usar mismos valores")
                }
                .buttonStyle(.primary)

                Button {
                    viewModel.showQuickStart = false
                } label: {
                    Text("Actualizar valores")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(Color.systemGroupedBackground)
    }

    private func lastSessionSummaryCard(session: MeasurementSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.formattedStartedAt())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Summary rows
            VStack(spacing: 8) {
                if let hours = session.hoursSinceActivity {
                    summaryRow(
                        icon: "figure.run",
                        label: "Actividad",
                        value: "\(String(format: "%.0f", hours))h - \(session.lastActivityType ?? "---")"
                    )
                }

                if let sleep = session.sleepHours {
                    summaryRow(
                        icon: "bed.double.fill",
                        label: "Descanso",
                        value: "\(String(format: "%.1f", sleep))h"
                    )
                }

                if let fatigue = session.generalFatigue {
                    summaryRow(
                        icon: "gauge.with.needle",
                        label: "Fatiga",
                        value: "\(fatigue)/10"
                    )
                }

                if let physio = session.recentPhysio, physio {
                    summaryRow(
                        icon: "cross.case.fill",
                        label: "Fisioterapia",
                        value: session.recentPhysioHoursAgo.map { "\($0)h" } ?? "Sí"
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondarySystemGroupedBackground)
        )
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    // MARK: - Step Flow Content

    private var stepFlowContent: some View {
        StepFlowView(
            steps: viewModel.stepConfigs,
            currentStep: $viewModel.currentStep,
            canProceed: viewModel.canProceedFromCurrentStep,
            lastButtonTitle: "Comenzar Mediciones",
            onComplete: {
                viewModel.syncStepperValues()
                submitForm()
            },
            onSkip: {
                // For optional steps, just advance
                viewModel.nextStep()
            }
        ) { stepIndex in
            stepContent(for: stepIndex)
                .padding(.horizontal)
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private func stepContent(for step: Int) -> some View {
        let keys = viewModel.stepKeys
        if step < keys.count {
            switch keys[step] {
            case .activity:
                activityStepContent
            case .rest:
                restStepContent
            case .fatigue:
                fatigueStepContent
            case .physiotherapy:
                physiotherapyStepContent
            case .observations:
                issuesStepContent
            case .menstrualCycle:
                menstrualCycleStepContent
            }
        } else {
            EmptyView()
        }
    }

    // MARK: - Step 0: Activity

    private var activityStepContent: some View {
        VStack(spacing: 24) {
            VisualStepper(
                value: $viewModel.hoursSinceActivityValue,
                range: 0...168,
                step: 1,
                unit: "horas",
                format: "%.0f"
            )

            // Activity type chips
            VStack(alignment: .leading, spacing: 12) {
                Text("Tipo de actividad")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ChipRow(
                    options: viewModel.commonActivityTypes.map { (label: $0, icon: activityIcon(for: $0)) },
                    selected: $viewModel.lastActivityType
                )
            }

            // Conditional: Ask about legs for ambiguous activities
            if viewModel.shouldAskAboutLegs {
                VStack(alignment: .leading, spacing: 12) {
                    Text("¿Incluía trabajo de piernas?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        SelectionCard(
                            title: "Sí",
                            icon: "figure.strengthtraining.traditional",
                            isSelected: viewModel.involvedLegs == true
                        ) {
                            viewModel.involvedLegs = true
                        }
                        SelectionCard(
                            title: "No",
                            icon: "hand.raised",
                            isSelected: viewModel.involvedLegs == false
                        ) {
                            viewModel.involvedLegs = false
                            viewModel.legMuscleGroup = nil
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

        }
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.3), value: viewModel.shouldAskAboutLegs)
    }

    // MARK: - Step 1: Rest

    private var restStepContent: some View {
        VStack(spacing: 24) {
            VisualStepper(
                value: $viewModel.sleepHoursValue,
                range: 0...24,
                step: 0.5,
                unit: "horas",
                format: "%.1f"
            )

            // Sleep quality badge
            sleepQualityBadge(for: viewModel.sleepHoursValue)
        }
        .padding(.horizontal)
    }

    // MARK: - Step 2: Fatigue

    private var fatigueStepContent: some View {
        VStack(spacing: 20) {
            // Large fatigue number
            Text("\(viewModel.generalFatigue)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(fatigueColor(for: viewModel.generalFatigue))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: viewModel.generalFatigue)

            Text(fatigueDescription(for: viewModel.generalFatigue))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            // Colored slider
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { Double(viewModel.generalFatigue) },
                        set: { viewModel.generalFatigue = Int($0.rounded()) }
                    ),
                    in: 0...10,
                    step: 1
                )
                .tint(fatigueColor(for: viewModel.generalFatigue))

                HStack {
                    Text("Descansado")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Agotado")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Step 3: Physiotherapy

    private var physiotherapyStepContent: some View {
        VStack(spacing: 16) {
            SelectionCard(
                title: "Sí",
                icon: "checkmark.circle",
                isSelected: viewModel.recentPhysio
            ) {
                viewModel.recentPhysio = true
            }

            SelectionCard(
                title: "No",
                icon: "xmark.circle",
                isSelected: !viewModel.recentPhysio
            ) {
                viewModel.recentPhysio = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    viewModel.nextStep()
                }
            }

            if viewModel.recentPhysio {
                VStack(spacing: 12) {
                    Text("Horas desde el tratamiento")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VisualStepper(
                        value: $viewModel.recentPhysioHoursAgoValue,
                        range: 0...168,
                        step: 1,
                        unit: "horas",
                        format: "%.0f"
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.3), value: viewModel.recentPhysio)
    }

    // MARK: - Step 4: Issues

    private var issuesStepContent: some View {
        VStack(spacing: 16) {
            TextEditor(text: $viewModel.newIssues)
                .frame(minHeight: 150)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondarySystemGroupedBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.systemGray4, lineWidth: 1)
                )
                .scrollContentBackground(.hidden)
        }
        .padding(.horizontal)
    }

    // MARK: - Step 5: Menstrual Cycle

    private var menstrualCycleStepContent: some View {
        VStack(spacing: 12) {
            ForEach(MenstrualCyclePhase.allCases) { phase in
                SelectionCard(
                    title: phase.spanishDisplayName,
                    icon: menstrualPhaseIcon(for: phase),
                    isSelected: viewModel.menstrualCyclePhase == phase
                ) {
                    viewModel.menstrualCyclePhase = phase
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.syncStepperValues()
                        submitForm()
                    }
                }
            }

            Text("Esta información ayuda a contextualizar las mediciones")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(.horizontal)
    }

    // MARK: - Helper Views

    private func sleepQualityBadge(for hours: Double) -> some View {
        let (text, color): (String, Color) = {
            switch hours {
            case ..<5:
                return ("Insuficiente", .red)
            case 5..<7:
                return ("Regular", .orange)
            case 7..<9:
                return ("Bueno", .green)
            case 9...:
                return ("Excelente", .blue)
            default:
                return ("---", .gray)
            }
        }()

        return Text(text)
            .font(.headline)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func fatigueColor(for value: Int) -> Color {
        switch value {
        case 0...3:
            return .green
        case 4...6:
            return .orange
        case 7...10:
            return .red
        default:
            return .gray
        }
    }

    private func fatigueDescription(for value: Int) -> String {
        switch value {
        case 0:
            return "Sin fatiga"
        case 1...3:
            return "Fatiga baja"
        case 4...6:
            return "Fatiga moderada"
        case 7...9:
            return "Fatiga alta"
        case 10:
            return "Fatiga máxima"
        default:
            return "---"
        }
    }

    private func menstrualPhaseIcon(for phase: MenstrualCyclePhase) -> String {
        switch phase {
        case .menstruation:
            return "drop.fill"
        case .follicular:
            return "leaf.fill"
        case .ovulation:
            return "sun.max.fill"
        case .luteal:
            return "moon.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private func activityIcon(for activity: String) -> String? {
        switch activity.lowercased() {
        case "futbol", "fútbol": return "soccerball"
        case "running", "correr", "carrera": return "figure.run"
        case "gimnasio", "pesas": return "dumbbell"
        case "ciclismo": return "bicycle"
        case "natacion", "natación": return "figure.pool.swim"
        case "basquetbol", "baloncesto": return "basketball"
        case "tenis": return "tennis.racket"
        case "crossfit", "hiit": return "flame"
        case "yoga": return "figure.yoga"
        default: return "sportscourt"
        }
    }

    // MARK: - Actions

    private func submitForm() {
        viewModel.syncStepperValues()
        guard let session = viewModel.createSession(context: modelContext) else {
            return
        }

        onSessionCreated?(session)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Pre-Session Form") {
    struct PreviewWrapper: View {
        @State private var viewModel = PreSessionFormViewModel()

        var body: some View {
            PreSessionFormView(viewModel: viewModel) { session in
                print("Session created: \(session.id)")
            }
        }
    }

    return PreviewWrapper()
        .modelContainer(for: [Athlete.self, MeasurementSession.self], inMemory: true)
}

#Preview("With Athlete") {
    struct PreviewWrapper: View {
        @State private var viewModel: PreSessionFormViewModel

        init() {
            let athlete = Athlete(
                fullName: "Juan Garcia",
                dateOfBirth: Calendar.current.date(byAdding: .year, value: -25, to: Date())!,
                usualActivities: ["Gimnasio"]
            )
            _viewModel = State(initialValue: PreSessionFormViewModel(athlete: athlete))
        }

        var body: some View {
            PreSessionFormView(viewModel: viewModel)
        }
    }

    return PreviewWrapper()
        .modelContainer(for: [Athlete.self, MeasurementSession.self], inMemory: true)
}
