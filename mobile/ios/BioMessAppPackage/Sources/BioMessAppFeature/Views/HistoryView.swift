import SwiftUI
import SwiftData

/// History view showing past measurement sessions and trends
struct HistoryView: View {
    var athleteID: UUID? = nil
    @Environment(LocalPersistenceService.self) private var syncService: LocalPersistenceService?
    @Environment(\.modelContext) private var modelContext
    @State private var showingExportSheet = false
    @State private var csvToShare: String?

    @Query(sort: \MeasurementSession.startedAt, order: .reverse)
    private var allSessions: [MeasurementSession]

    private var sessions: [MeasurementSession] {
        guard let athleteID else { return allSessions }
        return allSessions.filter { $0.athlete?.id == athleteID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if athleteID == nil {
                NavigationLink {
                    LaboratoryView(selectedTab: .constant(3))
                } label: {
                    Label("Mediciones de laboratorio", systemImage: "waveform.path")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            // Sync status banner
            if (syncService?.pendingCount ?? 0) > 0 || (syncService?.isSyncing ?? false) {
                SyncStatusBanner()
            }

            // Content
            if sessions.isEmpty {
                EmptySessionsView()
            } else {
                SessionListView(sessions: sessions)
            }
        }
        .navigationTitle("Historial")
        .toolbar {
            ToolbarItem(placement: {
                    #if os(iOS)
                    .topBarTrailing
                    #else
                    .primaryAction
                    #endif
                }()) {
                    HStack(spacing: 12) {
                        // Sync indicator
                        SyncStatusIndicator(style: .compact)

                        // Export menu
                        if !sessions.isEmpty {
                            Menu {
                                Button(action: exportAllSessions) {
                                    Label("Exportar Todo", systemImage: "square.and.arrow.up")
                                }
                            } label: {
                                Label("Exportar", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
        .sheet(isPresented: $showingExportSheet) {
            if let csv = csvToShare {
                ShareSheet(items: [createCSVFile(from: csv)])
            }
        }
    }

    private func exportAllSessions() {
        csvToShare = generateCSV(for: sessions)
        showingExportSheet = true
    }

    private func generateCSV(for sessions: [MeasurementSession]) -> String {
        var csv = "SessionID,SessionDate,AthleteID,AthleteName,MeasurementID,MuscleGroup,Side,PerceivedFatigue,MeasuredAt,SignalQuality,SyncStatus\n"

        for session in sessions {
            let sessionDate = ISO8601DateFormatter().string(from: session.startedAt)
            let athleteId = session.athlete?.id.uuidString ?? "N/A"
            let athleteName = session.athlete?.displayName ?? "N/A"

            if let measurements = session.measurements {
                for measurement in measurements {
                    let measuredAt = ISO8601DateFormatter().string(from: measurement.measuredAt)
                    let quality = "N/A"

                    csv += "\(session.id),\(sessionDate),\(athleteId),\(athleteName),"
                    csv += "\(measurement.id),\(measurement.muscleGroup),\(measurement.side),"
                    csv += "\(measurement.perceivedFatigue),\(measuredAt),\(quality),"
                    csv += "\(measurement.syncStatus.rawValue)\n"
                }
            }
        }

        return csv
    }

    private func createCSVFile(from csvString: String) -> URL {
        let fileName = "biomess_sessions_\(ISO8601DateFormatter().string(from: Date())).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? csvString.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}

// MARK: - Sync Status Banner

private struct SyncStatusBanner: View {
    @Environment(LocalPersistenceService.self) private var syncService: LocalPersistenceService?

    var body: some View {
        HStack(spacing: 12) {
            if syncService?.isSyncing == true {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Sincronizando...")
            } else if (syncService?.pendingCount ?? 0) > 0 {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.orange)
                Text("\(syncService?.pendingCount ?? 0) pendientes de sincronizar")
            }

            Spacer()

            if syncService?.isSyncing != true && (syncService?.pendingCount ?? 0) > 0 {
                Button("Sincronizar") {
                    Task {
                        await syncService?.syncAll()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }
}

// MARK: - Empty Sessions View

private struct EmptySessionsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clipboard")
                .font(.system(size: 64))
                .foregroundStyle(.gray)

            Text("Sin Sesiones")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text("Las sesiones de medición aparecerán aquí cuando completes mediciones con un atleta seleccionado")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Session List View

private struct SessionListView: View {
    let sessions: [MeasurementSession]

    var body: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    SessionRowView(session: session)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }
}

// MARK: - Session Row View

private struct SessionRowView: View {
    let session: MeasurementSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.formattedStartedAt())
                        .font(.headline)

                    if let athlete = session.athlete {
                        Text(athlete.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Sync status indicator
                SyncStatusIcon(status: session.syncStatus)
            }

            // Measurements summary
            if let measurements = session.measurements, !measurements.isEmpty {
                HStack(spacing: 8) {
                    Label("\(measurements.count) mediciones", systemImage: "waveform.path.ecg")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if session.isComplete {
                        Label("Completa", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                // Muscle targets measured
                HStack(spacing: 4) {
                    ForEach(measurements.prefix(4), id: \.id) { measurement in
                        MuscleChip(muscleGroup: measurement.muscleGroup, side: measurement.side)
                    }
                }
            } else {
                Text("Sin mediciones")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Questionnaire summary if available
            if session.hasQuestionnaireData {
                Text(session.questionnaireSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sync Status Icon

private struct SyncStatusIcon: View {
    let status: SyncStatus

    var body: some View {
        Image(systemName: "internaldrive")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Guardado en este dispositivo")
    }
}

// MARK: - Muscle Chip

private struct MuscleChip: View {
    let muscleGroup: String
    let side: String

    var body: some View {
        Text(shortName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var shortName: String {
        let muscleShort = muscleGroup == "quadriceps" ? "Q" : (muscleGroup == "hamstring" || muscleGroup == "hamstrings" ? "H" : String(muscleGroup.prefix(3)).capitalized)
        let sideShort = side == "left" ? "I" : "D"
        return "\(muscleShort)\(sideShort)"
    }

    private var color: Color {
        muscleGroup == "quadriceps" ? .blue : .purple
    }
}

// MARK: - Session Detail View

private struct SessionDetailView: View {
    let session: MeasurementSession
    @Environment(LocalPersistenceService.self) private var syncService: LocalPersistenceService?

    var body: some View {
        List {
            // Session info section
            Section("Información de la Sesión") {
                LabeledContent("Fecha", value: session.formattedStartedAt())

                if let athlete = session.athlete {
                    LabeledContent("Atleta", value: athlete.displayName)
                }

                LabeledContent("Almacenamiento", value: "En este dispositivo")
            }

            // Questionnaire section
            if session.hasQuestionnaireData {
                Section("Cuestionario") {
                    if let hours = session.hoursSinceActivity {
                        LabeledContent("Horas desde actividad", value: String(format: "%.1f h", hours))
                    }

                    if let activity = session.lastActivityType {
                        LabeledContent("Tipo de actividad", value: activity)
                    }

                    if let sleep = session.sleepHours {
                        LabeledContent("Horas de sueño", value: String(format: "%.1f h", sleep))
                    }

                    if let fatigue = session.generalFatigue {
                        LabeledContent("Fatiga general", value: "\(fatigue)/10")
                    }

                    if let physio = session.recentPhysio, physio {
                        LabeledContent("Fisioterapia reciente", value: "Sí")
                        if let hoursAgo = session.recentPhysioHoursAgo {
                            LabeledContent("Hace", value: "\(hoursAgo) horas")
                        }
                    }

                    if let issues = session.newIssues, !issues.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nuevos problemas")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(issues)
                        }
                    }
                }
            }

            // Measurements section
            if let measurements = session.measurements, !measurements.isEmpty {
                Section("Mediciones (\(measurements.count))") {
                    ForEach(measurements.sorted { $0.measuredAt < $1.measuredAt }) { measurement in
                        if let rawMeasurement = measurement.asRawMeasurement {
                            NavigationLink {
                                RawMeasurementDetailView(measurement: rawMeasurement)
                            } label: {
                                MeasurementRowView(measurement: measurement)
                            }
                        } else {
                            NavigationLink {
                                List {
                                    LabeledContent("Medición", value: measurement.fullDisplayName)
                                    LabeledContent("Fecha", value: measurement.measuredAt.formatted())
                                    LabeledContent("Fatiga percibida", value: "\(measurement.perceivedFatigue)/10")
                                    Section("Datos de la curva no disponibles") {
                                        Text("Se conserva el registro, pero los datos de impedancia no se guardaron o no se pueden leer. No es posible reconstruir la gráfica a partir de este registro.")
                                    }
                                }
                                .navigationTitle("Medición")
                            } label: {
                                MeasurementRowView(measurement: measurement)
                            }
                        }
                    }
                }
            }

            // Bilateral analysis section
            if session.measurements?.contains(where: { ["quadriceps", "hamstring"].contains($0.muscleGroup) }) == true {
            Section("Análisis Bilateral") {
                if let quadDiff = session.bilateralDifference(for: "quadriceps") {
                    HStack {
                        Text("Cuadriceps")
                        Spacer()
                        BilateralDiffBadge(difference: quadDiff)
                    }
                }

                if let hamDiff = session.bilateralDifference(for: "hamstring") {
                    HStack {
                        Text("Isquiotibiales")
                        Spacer()
                        BilateralDiffBadge(difference: hamDiff)
                    }
                }

                if session.bilateralDifference(for: "quadriceps") == nil &&
                   session.bilateralDifference(for: "hamstring") == nil {
                    Text("Completa ambos lados de cada músculo para ver el análisis bilateral")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            }
        }
        .navigationTitle("Detalle de Sesión")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Measurement Row View (for sessions)

private struct MeasurementRowView: View {
    let measurement: Measurement

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(measurement.fullDisplayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(measurement.measuredAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Fatiga: \(measurement.perceivedFatigue)/10")
                    .font(.caption)
                    .foregroundStyle(fatigueColor)

                SyncStatusIcon(status: measurement.syncStatus)
            }
        }
    }

    private var fatigueColor: Color {
        switch measurement.perceivedFatigue {
        case 0...3: return .green
        case 4...6: return .orange
        default: return .red
        }
    }
}

// MARK: - Bilateral Diff Badge

private struct BilateralDiffBadge: View {
    let difference: Int

    var body: some View {
        HStack(spacing: 4) {
            if difference >= 3 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text("\(difference) puntos")
        }
        .font(.caption)
        .foregroundStyle(difference >= 3 ? .orange : .secondary)
    }
}

#Preview {
    HistoryView()
        .environment(LocalPersistenceService())
        .modelContainer(for: [MeasurementSession.self, Measurement.self, Athlete.self], inMemory: true)
}
