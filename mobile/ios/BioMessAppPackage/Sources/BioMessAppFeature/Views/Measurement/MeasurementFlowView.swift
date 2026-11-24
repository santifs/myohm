import SwiftUI
import SwiftData
import BioMessCore

/// Main view that wraps the entire measurement flow
/// Handles the state machine: athlete selection -> session form -> muscle selection -> measurement -> summary
struct MeasurementFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BioMessBLEManager.self) private var bleManager
    @Environment(BioimpedanceProcessor.self) private var processor
    @Environment(StudyPreferencesService.self) private var studyPrefs

    @State private var viewModel = MeasurementFlowViewModel()
    @Binding var selectedTab: Int

    var body: some View {
        VStack(spacing: 0) {
            // Connection status banner at top
            if bleManager.connectionState != .connected && viewModel.flowState == .selectingMuscle {
                ConnectionStatusBanner(
                    connectionState: bleConnectionState,
                    deviceName: bleManager.connectedDevice?.name
                )
            }

            // Main content based on flow state
            switch viewModel.flowState {
            case .needsAthlete:
                NeedsAthleteView(
                    onSelectAthlete: {
                        viewModel.showAthleteSelection()
                    }
                )

            case .needsSession:
                NeedsSessionView(
                    athleteName: viewModel.athleteDisplayName,
                    viewModel: viewModel,
                    activeStudy: studyPrefs.activeStudy,
                    onStartProtocol: {
                        viewModel.startProtocolSession()
                    },
                    onStartBasal: {
                        viewModel.startBasalSession()
                    },
                    onStartMatch: {
                        viewModel.startMatchSession()
                    },
                    onChangeAthlete: {
                        viewModel.showAthleteSelection()
                    }
                )

            case .selectingMuscle:
                if let study = studyPrefs.activeStudy,
                   study.muscleGroups.count == 1, study.sides.count == 1 {
                    // No deberíamos llegar aquí — startProtocolSession debería haber
                    // saltado a .measuring. Cinturón y tirantes para futuros cambios.
                    Color.clear.task { viewModel.startMeasurement() }
                } else {
                    MuscleSelectionView(
                        selectedMuscle: $viewModel.selectedMuscle,
                        perceivedFatigue: $viewModel.currentMuscleFatigue,
                        completedMuscles: viewModel.completedMuscleTargets,
                        onStartMeasurement: {
                            viewModel.startMeasurement()
                        },
                        onFinishSession: {
                            viewModel.finishSessionEarly()
                        },
                        availableMuscles: studyPrefs.activeStudy?.muscleGroups ?? [.quadriceps],
                        availableSides: studyPrefs.activeStudy?.sides ?? [.left, .right],
                        dominantSide: athleteDominantSide
                    )
                    .safeAreaInset(edge: .top) {
                        sessionHeaderBar
                    }
                }

            case .measuring:
                MeasurementExecutionView(
                    target: viewModel.selectedMuscle,
                    fatigue: viewModel.currentMuscleFatigue,
                    session: viewModel.currentSession,
                    flowViewModel: viewModel,
                    onMeasurementComplete: { measurementId in
                        viewModel.completeMeasurement(measurementId: measurementId)
                    },
                    onFinishSession: {
                        viewModel.finishCurrentSession()
                    },
                    selectedTab: $selectedTab
                )

            case .sessionSummary:
                SessionSummaryView(
                    measurements: viewModel.completedMeasurements,
                    statistics: viewModel.sessionStatistics,
                    athleteName: viewModel.athleteDisplayName,
                    onNewSession: {
                        viewModel.startNewSession()
                    },
                    onViewHistory: {
                        selectedTab = 3  // History tab
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.flowState)
        .onAppear {
            viewModel.initialize(context: modelContext)
            viewModel.setActiveStudy(studyPrefs.activeStudy)
        }
        .onDisappear {
            // Race-safe cleanup: si el operador abandona la pantalla mientras
            // está en mitad del flow (mid-protocolo, sin medidas todavía), borra
            // la sesión vacía. `cleanupIfEmpty` espera al saveTask en vuelo y
            // ya hace guard contra `activeSessionId == nil`, así que un tab
            // switch desde el summary o desde la selección de atleta es no-op.
            guard [.measuring, .selectingMuscle].contains(viewModel.flowState) else { return }
            Task { await viewModel.cleanupIfEmpty() }
        }
        .onChange(of: studyPrefs.activeStudy) { _, newValue in
            viewModel.setActiveStudy(newValue)
        }
        .sheet(isPresented: $viewModel.showingPreSessionForm) {
            if let formViewModel = viewModel.preSessionFormViewModel {
                PreSessionFormView(viewModel: formViewModel) { session in
                    viewModel.handleSessionCreated(session)
                }
            }
        }
        .sheet(isPresented: $viewModel.showingAthleteList) {
            AthleteListView { athlete in
                viewModel.setActiveAthlete(athlete)
                viewModel.hideAthleteSelection()
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .navigationTitle("Medir")
        .toolbar {
            if viewModel.flowState == .needsAthlete || viewModel.flowState == .needsSession {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Protocolo", selection: Binding(
                            get: { studyPrefs.activeStudy },
                            set: { studyPrefs.setActiveStudy($0) }
                        )) {
                            Text("Sin protocolo de estudio").tag(Optional<Study>.none)
                            ForEach(Study.allCases) { study in
                                Text(study.label).tag(Optional<Study>.some(study))
                            }
                        }
                    } label: {
                        Label("Protocolo", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var bleConnectionState: BLEConnectionState {
        switch bleManager.connectionState {
        case .disconnected:
            return .disconnected
        case .scanning, .connecting:
            return .connecting
        case .connected, .measuring:
            return .connected
        case .error:
            return .disconnected
        }
    }

    /// Convert athlete's dominant leg to BodySide for muscle selection
    private var athleteDominantSide: BodySide? {
        guard let athlete = viewModel.activeAthlete else { return nil }
        switch athlete.dominantLeg {
        case .right:
            return .right
        case .left:
            return .left
        case .ambidextrous:
            return nil  // Let user choose
        }
    }

    // MARK: - Session Header Bar

    private var sessionHeaderBar: some View {
        VStack(spacing: 0) {
            HStack {
                // Athlete info
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.secondary)
                    Text(viewModel.athleteDisplayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Spacer()

                // Session progress
                Text(viewModel.sessionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()
        }
    }
}

// MARK: - Needs Athlete View

/// Shown when no athlete is selected
private struct NeedsAthleteView: View {
    let onSelectAthlete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(spacing: 32) {
                    // Hero: icon + explanation
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 36))
                                .foregroundStyle(.orange)
                        }

                        VStack(spacing: 8) {
                            Text("Selecciona un Atleta")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Para comenzar a medir, primero selecciona o crea un perfil de atleta")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
                .padding(.horizontal, 24)
            }

            // Pinned bottom button
            Divider()

            Button {
                onSelectAthlete()
            } label: {
                HStack {
                    Image(systemName: "person.badge.plus")
                    Text("Seleccionar Atleta")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.brandPrimary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Needs Session View

/// Shown when athlete is selected but session not started.
///
/// When an active `Study` is configured, renders chips for
/// `study.sessionTypeSuggestions` plus a free-text field bound to
/// `viewModel.sessionTypeLabel`, a resumption banner if the VM detected a
/// matching recent session, and a primary "Medir" button that calls
/// `viewModel.startProtocolSession()`. Without an active study, falls back
/// to the legacy basal/match flow with a hint to configure a study.
private struct NeedsSessionView: View {
    let athleteName: String
    @Bindable var viewModel: MeasurementFlowViewModel
    let activeStudy: Study?
    let onStartProtocol: () -> Void
    let onStartBasal: () -> Void
    let onStartMatch: () -> Void
    let onChangeAthlete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(spacing: 28) {
                    // Hero: icon + explanation at top
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Image(systemName: "clipboard.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.green)
                        }

                        VStack(spacing: 8) {
                            Text("Sesión de Medición")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(activeStudy != nil
                                ? "Selecciona la fase del protocolo para continuar"
                                : "Selecciona el tipo de medición que vas a realizar")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)

                    // Athlete + study card
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.brandPrimary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Atleta")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(athleteName)
                                .font(.headline)
                            if let study = activeStudy {
                                Text("Estudio: \(study.label)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button {
                            onChangeAthlete()
                        } label: {
                            Text("Cambiar")
                                .font(.subheadline)
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.secondarySystemGroupedBackground)
                    )

                    // Protocol-driven UI when a Study is active
                    if let study = activeStudy {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Fase del protocolo")
                                .font(.headline)

                            FlowLayoutChips(
                                suggestions: study.sessionTypeSuggestions,
                                selected: viewModel.sessionTypeLabel,
                                onTap: viewModel.pickSessionTypeSuggestion
                            )

                            TextField(
                                "Toca un chip o escribe una",
                                text: $viewModel.sessionTypeLabel
                            )
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif

                            if viewModel.resumableSessionId != nil {
                                ResumableBanner(count: viewModel.resumableMeasurementCount)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)
            }

            // Pinned bottom action area
            Divider()

            VStack(spacing: 12) {
                if activeStudy != nil {
                    Button(action: onStartProtocol) {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                            Text("Medir")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            isStartEnabled
                                ? Color.brandPrimary
                                : Color.gray.opacity(0.5)
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!isStartEnabled)
                } else {
                    HStack(spacing: 12) {
                        SessionTypeCard(
                            title: "Basal",
                            subtitle: "Medición en reposo",
                            icon: "house.fill",
                            color: .blue,
                            action: onStartBasal
                        )

                        SessionTypeCard(
                            title: "Sesión repetida",
                            subtitle: "Pre / Descanso / Post",
                            icon: "sportscourt.fill",
                            color: .orange,
                            action: onStartMatch
                        )
                    }

                    Text("Elige un protocolo en el menú superior para configurar los músculos y lados del estudio.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
    }

    private var isStartEnabled: Bool {
        SessionTypeNormalizer.normalize(viewModel.sessionTypeLabel) != nil
            && !viewModel.isStartingSession
    }
}

// MARK: - Flow Layout Chips

/// Adaptive grid of suggestion chips. Highlights the chip matching
/// `selected` (case-insensitive). Suggestions in `Study.sessionTypeSuggestions`
/// are already canonical (lowercase, underscores), so we compare against
/// `selected.lowercased()`.
private struct FlowLayoutChips: View {
    let suggestions: [String]
    let selected: String
    let onTap: (String) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    onTap(suggestion)
                } label: {
                    Text(suggestion)
                        .font(.subheadline)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            selected.lowercased() == suggestion
                                ? Color.brandPrimary
                                : Color.secondary.opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(
                            selected.lowercased() == suggestion
                                ? Color.white
                                : Color.primary
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Resumable Banner

/// Shown when the VM detects a recent matching session that "Medir" will
/// resume rather than create anew.
private struct ResumableBanner: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(.orange)
            Text("Continuará sesión existente · \(count) medidas")
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Session Type Card

/// A card for selecting session type (Basal vs Match)
private struct SessionTypeCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(color)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondarySystemGroupedBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Measurement Execution View

/// Wraps the existing MeasurementView during actual measurement
private struct MeasurementExecutionView: View {
    let target: MuscleTarget?
    let fatigue: Int
    let session: MeasurementSession?
    let flowViewModel: MeasurementFlowViewModel?
    let onMeasurementComplete: (UUID?) -> Void
    let onFinishSession: () -> Void
    @Binding var selectedTab: Int

    @Environment(BioMessBLEManager.self) private var bleManager

    var body: some View {
        VStack(spacing: 0) {
            // Muscle context header
            if let target = target {
                muscleContextHeader(target: target)
            }

            // Existing measurement view with session context
            MeasurementView(
                selectedTab: $selectedTab,
                embeddedMode: true,
                session: session,
                muscleGroup: target?.muscle.rawValue,
                side: target?.side.rawValue,
                perceivedFatigue: fatigue,
                flowViewModel: flowViewModel,
                onMeasurementComplete: onMeasurementComplete
            )

            // Finish session button
            Button {
                onFinishSession()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle")
                    Text("Finalizar Sesión")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func muscleContextHeader(target: MuscleTarget) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: target.muscle.iconName)
                    .foregroundStyle(Color.brandPrimary)

                Text("Midiendo: \(target.muscle.displayName)")
                    .font(.headline)

                Spacer()
            }
            .padding()
            .background(Color.brandPrimary.opacity(0.1))

            Divider()
        }
    }
}

// MARK: - Preview

#Preview("Needs Athlete") {
    MeasurementFlowView(selectedTab: .constant(1))
        .environment(BioMessBLEManager())
        .environment(BioimpedanceProcessor())
        .environment(StudyPreferencesService())
        .modelContainer(for: [Athlete.self, MeasurementSession.self, Measurement.self], inMemory: true)
}
