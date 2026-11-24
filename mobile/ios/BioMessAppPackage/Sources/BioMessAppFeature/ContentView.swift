import SwiftUI
import SwiftData
import BioMessCore
#if canImport(UIKit)
import UIKit
#endif

public struct ContentView: View {
    public var body: some View {
        BioMess()
    }

    public init() {}
}

/// Main app view using environment-based architecture (no ViewModels)
struct BioMess: View {

    // Shared services via environment
    @State private var bleManager = BioMessBLEManager()  // Real BLE manager for PCB connection
    @State private var processor = BioimpedanceProcessor()
    @State private var patientInfo = PatientInfo()
    @State private var configManager = AD5940ConfigurationManager()  // Configuration manager for AD5940 parameters
    @State private var notificationManager = LocalNotificationManager()
    @State private var syncService = LocalPersistenceService()
    @State private var studyPrefs = StudyPreferencesService()

    // Migration state
    @State private var showMigrationAlert = false
    @State private var migratedAthleteName: String?

    // SwiftData model container for all app models
    @State private var modelContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for: Athlete.self,
                Anthropometrics.self,
                Injury.self,
                MeasurementSession.self,
                Measurement.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some View {
        mainContent.modelContainer(modelContainer)
    }

    @ViewBuilder
    private var mainContent: some View {
        MainView()
            .environment(bleManager)
            .environment(processor)
            .environment(patientInfo)
            .environment(configManager)
            .environment(notificationManager)
            .environment(syncService)
            .environment(studyPrefs)
            .onAppear {
                // Request notification permissions on first launch
                Task {
                    try? await notificationManager.requestAuthorization()
                    await notificationManager.registerNotificationCategories()
                }

                // Configure sync service with model context and auth service
                syncService.setModelContext(modelContainer.mainContext)

                // Perform PatientInfo -> Athlete migration if needed
                performMigrationIfNeeded()
            }
            .alert("Perfil migrado", isPresented: $showMigrationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                if let name = migratedAthleteName {
                    Text("Hemos migrado tu perfil anterior (\(name)) al nuevo sistema de atletas.")
                } else {
                    Text("Hemos migrado tu perfil anterior al nuevo sistema de atletas.")
                }
            }
    }

    // MARK: - Migration

    /// Perform migration from legacy PatientInfo to Athlete if needed
    private func performMigrationIfNeeded() {
        guard PatientInfoMigration.needsMigration() else { return }

        let context = modelContainer.mainContext
        if let athlete = PatientInfoMigration.migrate(context: context) {
            migratedAthleteName = athlete.fullName
            showMigrationAlert = true
        }
    }
}

/// Main navigation view - BioMess Dashboard
struct MainView: View {
    @Environment(BioMessBLEManager.self) private var bleManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {

            // Inicio Tab
            NavigationStack {
                DashboardView(selectedTab: $selectedTab)
            }
            .tabItem {
                Label("Inicio", systemImage: "house")
            }
            .tag(0)

            // Medir Tab
            NavigationStack {
                List {
                    NavigationLink {
                        LaboratoryView(selectedTab: $selectedTab)
                    } label: {
                        Label("Laboratorio · sin atleta", systemImage: "waveform.path")
                    }
                    NavigationLink {
                        MeasurementFlowView(selectedTab: $selectedTab)
                    } label: {
                        Label("Medición con atleta", systemImage: "person")
                    }
                }
                .navigationTitle("Medir")
            }
            .tabItem {
                Label("Medir", systemImage: "waveform.path.ecg")
            }
            .tag(1)

            // Atletas Tab
            NavigationStack {
                AthleteListView()
            }
            .tabItem {
                Label("Atletas", systemImage: "person.2")
            }
            .tag(2)

            // Historial Tab
            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("Historial", systemImage: "clock")
            }
            .tag(3)

            // Ajustes Tab
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Ajustes", systemImage: "gearshape")
            }
            .tag(4)
        }
    }
}

// MARK: - Dashboard View

/// Simple athlete list dashboard showing last measurement per athlete
struct DashboardView: View {
    @Binding var selectedTab: Int

    @Query(sort: \Athlete.fullName)
    private var athletes: [Athlete]

    @Query(sort: \MeasurementSession.startedAt, order: .reverse)
    private var sessions: [MeasurementSession]

    var body: some View {
        Group {
            if athletes.isEmpty {
                emptyState
            } else {
                athleteList
            }
        }
        .background(Color.systemGroupedBackground)
        .navigationTitle("Mis Atletas")
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.3")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Crea tu primer atleta para empezar a medir")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                selectedTab = 2
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Crear atleta")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentBlue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Athlete List

    @ViewBuilder
    private var athleteList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(athletes) { athlete in
                    NavigationLink {
                        HistoryView(athleteID: athlete.id)
                    } label: {
                        HStack {
                            AthleteDashboardCard(athlete: athlete, lastSession: lastSession(for: athlete))
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Abrir las sesiones y mediciones de este atleta")
                }

                // Nueva medición button
                Button {
                    selectedTab = 1
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Nueva medición")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentBlue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private func lastSession(for athlete: Athlete) -> MeasurementSession? {
        sessions.first { $0.athlete?.id == athlete.id }
    }
}

// MARK: - Athlete Dashboard Card

private struct AthleteDashboardCard: View {
    let athlete: Athlete
    let lastSession: MeasurementSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(athlete.displayName)
                    .font(.headline)

                Spacer()

                if !hasMeasurementToday {
                    Circle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }

            if let session = lastSession {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let muscleInfo = sessionMuscleInfo(session) {
                    Text(muscleInfo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Sin mediciones")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var hasMeasurementToday: Bool {
        guard let session = lastSession else { return false }
        return Calendar.current.isDateInToday(session.startedAt)
    }

    private func sessionMuscleInfo(_ session: MeasurementSession) -> String? {
        guard let measurements = session.measurements, !measurements.isEmpty else { return nil }
        let muscles = Set(measurements.map { $0.muscleGroup })
        return muscles.joined(separator: ", ")
    }
}


#Preview {
    ContentView()
}
