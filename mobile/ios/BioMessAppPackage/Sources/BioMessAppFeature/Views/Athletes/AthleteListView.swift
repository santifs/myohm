import SwiftUI
import SwiftData

/// Main view for displaying and managing the list of athletes
/// Shows all athletes with ability to select an active one for measurements
struct AthleteListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = AthleteListViewModel()

    /// Optional callback when an athlete is selected
    var onAthleteSelected: ((Athlete) -> Void)?

    /// Whether this view is being used for athlete selection (vs browsing)
    private var isSelectionMode: Bool {
        onAthleteSelected != nil
    }

    var body: some View {
        let content = Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.hasAthletes {
                athleteListContent
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Atletas")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            if isSelectionMode {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        // Dismiss by not selecting anyone — the sheet binding handles it
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showingWizard = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        #if os(iOS)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Buscar atleta...")
        )
        #else
        .searchable(
            text: $viewModel.searchText,
            prompt: Text("Buscar atleta...")
        )
        #endif
        .sheet(isPresented: $viewModel.showingWizard) {
            AthleteWizardView { athlete in
                viewModel.handleAthleteCreated(athlete)
                onAthleteSelected?(athlete)
            }
        }
        .alert(
            "Error",
            isPresented: .constant(viewModel.errorMessage != nil)
        ) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .onAppear {
            viewModel.loadAthletes(context: modelContext)
        }

        // When in selection mode (presented as sheet), provide our own NavigationStack
        if isSelectionMode {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Cargando atletas...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.systemGray5)
                    .frame(width: 100, height: 100)

                Image(systemName: "person.3")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }

            // Text
            VStack(spacing: 8) {
                Text("No hay atletas")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Crea tu primer atleta para comenzar a registrar mediciones.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Create button
            Button {
                viewModel.showingWizard = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Crear Primer Atleta")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 48)

            Spacer()
        }
        .padding()
    }

    private var athleteListContent: some View {
        List {
            if isSelectionMode {
                // Selection mode: all athletes in a single list, tappable rows
                Section {
                    ForEach(viewModel.filteredAthletes, id: \.id) { athlete in
                        let isActive = athlete.id == viewModel.activeAthleteId
                        Button {
                            viewModel.setActiveAthlete(athlete)
                            onAthleteSelected?(athlete)
                        } label: {
                            AthleteRowView(
                                athlete: athlete,
                                isActive: isActive
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Seleccionar Atleta")
                        Spacer()
                        Text("(\(viewModel.filteredAthletes.count))")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if viewModel.filteredAthletes.isEmpty && !viewModel.searchText.isEmpty {
                        Text("No se encontraron atletas con ese nombre.")
                    }
                }
            } else {
                // Browse mode: active athlete section + all others with NavigationLinks
                if let activeAthlete = viewModel.activeAthlete {
                    Section {
                        NavigationLink {
                            AthleteDetailView(athlete: activeAthlete)
                        } label: {
                            AthleteRowView(
                                athlete: activeAthlete,
                                isActive: true
                            )
                        }
                    } header: {
                        Text("Atleta Activo")
                    }
                }

                Section {
                    ForEach(viewModel.nonActiveAthletes, id: \.id) { athlete in
                        NavigationLink {
                            AthleteDetailView(athlete: athlete)
                        } label: {
                            AthleteRowView(
                                athlete: athlete,
                                isActive: false,
                                onSelect: {
                                    viewModel.setActiveAthlete(athlete)
                                    onAthleteSelected?(athlete)
                                }
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                viewModel.deleteAthlete(athlete, context: modelContext)
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Todos los Atletas")
                        Spacer()
                        Text("(\(viewModel.filteredAthletes.count))")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if viewModel.filteredAthletes.isEmpty && !viewModel.searchText.isEmpty {
                        Text("No se encontraron atletas con ese nombre.")
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }
}

// MARK: - Athlete Detail View (Placeholder)

/// Detail view for viewing and editing an athlete's information
struct AthleteDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let athlete: Athlete

    @State private var showingDeleteConfirmation = false
    @State private var showingAnthropometricsEditor = false

    var body: some View {
        List {
            basicInfoSection
            anthropometricsSection
            medicalHistorySection
            activitiesSection
            injuriesSection
            measurementSessionsSection
            deleteSection
        }
        .navigationTitle(athlete.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog(
            "¿Eliminar Atleta?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                modelContext.delete(athlete)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta acción eliminará permanentemente al atleta y todos sus datos asociados.")
        }
        .sheet(isPresented: $showingAnthropometricsEditor) {
            AnthropometricsEditView(athlete: athlete)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var basicInfoSection: some View {
        Section {
            InfoRow(label: "Nombre", value: athlete.displayName)
            InfoRow(
                label: "Fecha de Nacimiento",
                value: athlete.formattedDateOfBirth()
            )
            InfoRow(
                label: "Edad",
                value: "\(athlete.age) años"
            )
            InfoRow(
                label: "Pierna Dominante",
                value: athlete.dominantLeg.displayName
            )
        } header: {
            Text("Información Básica")
        }
    }

    @ViewBuilder
    private var anthropometricsSection: some View {
        Section {
            if let anthropometrics = athlete.latestAnthropometrics {
                if let weight = anthropometrics.weightKg {
                    InfoRow(
                        label: "Peso",
                        value: String(format: "%.1f kg", weight)
                    )
                }
                if let height = anthropometrics.heightCm {
                    InfoRow(
                        label: "Altura",
                        value: String(format: "%.0f cm", height)
                    )
                }
                if let bmi = anthropometrics.bmi {
                    InfoRow(
                        label: "IMC",
                        value: String(format: "%.1f (%@)", bmi, anthropometrics.bmiCategory)
                    )
                }
                // Thigh measurements
                if let rightLength = anthropometrics.rightThighLengthCm,
                   let rightCirc = anthropometrics.rightThighCircumferenceCm {
                    InfoRow(
                        label: "Muslo derecho",
                        value: String(format: "%.1f cm / %.1f cm", rightLength, rightCirc)
                    )
                }
                if let leftLength = anthropometrics.leftThighLengthCm,
                   let leftCirc = anthropometrics.leftThighCircumferenceCm {
                    InfoRow(
                        label: "Muslo izquierdo",
                        value: String(format: "%.1f cm / %.1f cm", leftLength, leftCirc)
                    )
                }
            }

            // Edit button
            Button {
                showingAnthropometricsEditor = true
            } label: {
                HStack {
                    Image(systemName: "pencil")
                    Text("Editar")
                }
            }
        } header: {
            Text("Antropometría")
        } footer: {
            if let anthropometrics = athlete.latestAnthropometrics {
                Text(String(format: "Medido el %@", anthropometrics.formattedMeasuredAt()))
            }
        }
    }

    @ViewBuilder
    private var medicalHistorySection: some View {
        if athlete.medicalHistory != nil || athlete.medications != nil {
            Section {
                if let history = athlete.medicalHistory, !history.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Historial")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(history)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
                if let meds = athlete.medications, !meds.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Medicamentos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(meds)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Historial Médico")
            }
        }
    }

    @ViewBuilder
    private var activitiesSection: some View {
        if let activities = athlete.usualActivities, !activities.isEmpty {
            Section {
                ForEach(activities, id: \.self) { activity in
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundStyle(.secondary)
                        Text(activity)
                    }
                }
            } header: {
                Text("Actividades")
            }
        }
    }

    @ViewBuilder
    private var injuriesSection: some View {
        if !athlete.activeInjuries.isEmpty {
            Section {
                ForEach(athlete.activeInjuries, id: \.id) { injury in
                    InjuryRowView(injury: injury)
                }
            } header: {
                Text("Lesiones Activas")
            }
        }
    }

    @ViewBuilder
    private var measurementSessionsSection: some View {
        if let sessions = athlete.measurementSessions, !sessions.isEmpty {
            Section {
                Text(String(format: "%d sesiones registradas", sessions.count))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Mediciones")
            }
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Eliminar Atleta")
                }
            }
        }
    }
}

// MARK: - Helper Views

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

private struct InjuryRowView: View {
    let injury: Injury

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(injury.injuryType.spanishDisplayName)
                .font(.headline)
            if let detail = injury.detail, !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(injury.statusDescription)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Anthropometrics Edit View

/// View for editing athlete anthropometric measurements
struct AnthropometricsEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalPersistenceService.self) private var syncService: LocalPersistenceService?

    let athlete: Athlete

    // Form state
    @State private var weightText: String = ""
    @State private var heightText: String = ""
    @State private var rightThighLengthText: String = ""
    @State private var rightThighCircumferenceText: String = ""
    @State private var leftThighLengthText: String = ""
    @State private var leftThighCircumferenceText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Peso (kg)")
                        Spacer()
                        TextField("0.0", text: $weightText)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Altura (cm)")
                        Spacer()
                        TextField("0.0", text: $heightText)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(width: 80)
                    }
                } header: {
                    Text("Medidas básicas")
                }

                Section {
                    HStack {
                        Text("Longitud (cm)")
                        Spacer()
                        TextField("0.0", text: $rightThighLengthText)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Perímetro (cm)")
                        Spacer()
                        TextField("0.0", text: $rightThighCircumferenceText)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(width: 80)
                    }
                } header: {
                    Text("Muslo Derecho")
                } footer: {
                    Text("Longitud: desde el pliegue de la cadera hasta la rodilla")
                }

                Section {
                    HStack {
                        Text("Longitud (cm)")
                        Spacer()
                        TextField("0.0", text: $leftThighLengthText)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Perímetro (cm)")
                        Spacer()
                        TextField("0.0", text: $leftThighCircumferenceText)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(width: 80)
                    }
                } header: {
                    Text("Muslo Izquierdo")
                }
            }
            .navigationTitle("Editar Medidas")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Hecho") {
                        #if os(iOS)
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                        #endif
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        saveChanges()
                        dismiss()
                    }
                    .disabled(!isFormValid)
                }
            }
            .onAppear {
                loadCurrentValues()
            }
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        parseDouble(weightText) != nil &&
        parseDouble(heightText) != nil &&
        parseDouble(rightThighLengthText) != nil &&
        parseDouble(rightThighCircumferenceText) != nil &&
        parseDouble(leftThighLengthText) != nil &&
        parseDouble(leftThighCircumferenceText) != nil
    }

    // MARK: - Actions

    private func loadCurrentValues() {
        if let anthropometrics = athlete.latestAnthropometrics {
            if let value = anthropometrics.weightKg {
                weightText = String(format: "%.1f", value)
            }
            if let value = anthropometrics.heightCm {
                heightText = String(format: "%.1f", value)
            }
            if let value = anthropometrics.rightThighLengthCm {
                rightThighLengthText = String(format: "%.1f", value)
            }
            if let value = anthropometrics.rightThighCircumferenceCm {
                rightThighCircumferenceText = String(format: "%.1f", value)
            }
            if let value = anthropometrics.leftThighLengthCm {
                leftThighLengthText = String(format: "%.1f", value)
            }
            if let value = anthropometrics.leftThighCircumferenceCm {
                leftThighCircumferenceText = String(format: "%.1f", value)
            }
        }
    }

    private func saveChanges() {
        // Create new anthropometrics record (keeps history)
        let newAnthropometrics = Anthropometrics(
            athlete: athlete,
            measuredAt: Date(),
            weightKg: parseDouble(weightText),
            heightCm: parseDouble(heightText),
            rightThighLengthCm: parseDouble(rightThighLengthText),
            rightThighCircumferenceCm: parseDouble(rightThighCircumferenceText),
            leftThighLengthCm: parseDouble(leftThighLengthText),
            leftThighCircumferenceCm: parseDouble(leftThighCircumferenceText)
        )

        modelContext.insert(newAnthropometrics)

        // Add to athlete's anthropometrics array
        if athlete.anthropometrics == nil {
            athlete.anthropometrics = []
        }
        athlete.anthropometrics?.append(newAnthropometrics)

        // Mark athlete as modified for sync
        athlete.syncStatus = .modified

        try? modelContext.save()

        // Trigger sync to Supabase
        Task {
            await syncService?.syncAll()
        }
    }

    private func parseDouble(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}

// MARK: - Preview

#Preview("With Athletes") {
    AthleteListView()
        .modelContainer(previewContainer)
}

#Preview("Empty State") {
    AthleteListView()
        .modelContainer(for: [Athlete.self, Anthropometrics.self, Injury.self], inMemory: true)
}

// MARK: - Preview Container

@MainActor
private var previewContainer: ModelContainer {
    let container = try! ModelContainer(
        for: Athlete.self, Anthropometrics.self, Injury.self, MeasurementSession.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = container.mainContext

    // Create sample athletes
    let athlete1 = Athlete(
        fullName: "Juan Garcia",
        dateOfBirth: Calendar.current.date(byAdding: .year, value: -25, to: Date())!
    )
    let anthro1 = Anthropometrics(athlete: athlete1, weightKg: 75, heightCm: 180)
    athlete1.anthropometrics = [anthro1]

    let athlete2 = Athlete(
        fullName: "Maria Lopez",
        dateOfBirth: Calendar.current.date(byAdding: .year, value: -22, to: Date())!
    )
    let anthro2 = Anthropometrics(athlete: athlete2, weightKg: 62, heightCm: 168)
    athlete2.anthropometrics = [anthro2]

    let athlete3 = Athlete(
        fullName: "Pedro Sanchez",
        dateOfBirth: Calendar.current.date(byAdding: .year, value: -28, to: Date())!,
        usualActivities: ["Running", "Ciclismo"]
    )
    let anthro3 = Anthropometrics(athlete: athlete3, weightKg: 82, heightCm: 185)
    athlete3.anthropometrics = [anthro3]

    context.insert(athlete1)
    context.insert(athlete2)
    context.insert(athlete3)
    context.insert(anthro1)
    context.insert(anthro2)
    context.insert(anthro3)

    return container
}
