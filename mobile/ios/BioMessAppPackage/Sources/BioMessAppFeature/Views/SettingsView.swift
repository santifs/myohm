import SwiftUI
import SwiftData

/// Simplified settings view
struct SettingsView: View {
    @Environment(StudyPreferencesService.self) private var studyPrefs
    @Environment(\.modelContext) private var modelContext
    @State private var showingExportSheet = false
    @State private var showingClearAlert = false
    @State private var showingNoDataAlert = false
    @State private var exportURL: URL?

    @Query private var measurements: [Measurement]
    @Query(sort: \MeasurementSession.startedAt, order: .reverse)
    private var sessions: [MeasurementSession]
    @Query private var athletes: [Athlete]

    var body: some View {
        NavigationView {
            List {
                Section("Almacenamiento local") {
                    Label("Sin cuenta ni conexión a la nube", systemImage: "iphone")
                    Text("Las medidas se guardan en este dispositivo. Exporta una copia antes de desinstalar la app.").font(.caption).foregroundStyle(.secondary)
                }

                // MARK: - Dispositivo
                Section("Dispositivo") {
                    NavigationLink {
                        FrequencyConfigurationView()
                    } label: {
                        Label("Configuración de medición", systemImage: "slider.horizontal.3")
                    }
                    Text("Barrido, puntos y repeticiones del AD5940. Requiere el dispositivo conectado.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Estudio activo
                Section("Estudio activo") {
                    Picker("Estudio", selection: Binding(
                        get: { studyPrefs.activeStudy },
                        set: { studyPrefs.setActiveStudy($0) }
                    )) {
                        Text("Ninguno").tag(Optional<Study>.none)
                        ForEach(Study.allCases) { study in
                            Text(study.label).tag(Optional<Study>.some(study))
                        }
                    }
                    if let study = studyPrefs.activeStudy {
                        Text("Músculos: \(study.muscleGroups.map(\.displayName).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Lados: \(study.sides.map(\.displayName).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Datos
                Section("Datos") {
                    Button {
                        exportAllData()
                    } label: {
                        Label("Exportar datos (CSV)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(measurements.isEmpty)

                    Button(role: .destructive) {
                        showingClearAlert = true
                    } label: {
                        Label("Borrar todos los datos", systemImage: "trash")
                    }
                    .disabled(measurements.isEmpty)
                }

                // MARK: - Acerca de
                Section("Acerca de") {
                    Text("Myohm \u{00B7} Versión 0.3.0")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
            .alert("Borrar datos", isPresented: $showingClearAlert) {
                Button("Cancelar", role: .cancel) { }
                Button("Borrar", role: .destructive) {
                    clearAllData()
                }
            } message: {
                Text("Se eliminarán todas las mediciones y sesiones. Esta acción no se puede deshacer.")
            }
            .alert("Sin datos", isPresented: $showingNoDataAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("No hay mediciones para exportar.")
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    // MARK: - Data Export

    private func exportAllData() {
        guard !sessions.isEmpty else {
            showingNoDataAlert = true
            return
        }

        let csv = generateCSV(for: sessions)
        exportURL = createCSVFile(from: csv)
        showingExportSheet = true
    }

    private func clearAllData() {
        for session in sessions {
            if let measurements = session.measurements {
                for measurement in measurements {
                    modelContext.delete(measurement)
                }
            }
            modelContext.delete(session)
        }
        try? modelContext.save()
    }

    private func generateCSV(for sessions: [MeasurementSession]) -> String {
        var csv = "SessionID,SessionDate,AthleteID,AthleteName,MeasurementID,MuscleGroup,Side,PerceivedFatigue,MeasuredAt,SignalQuality\n"

        for session in sessions {
            let sessionDate = session.startedAt.ISO8601Format()
            let athleteId = session.athlete?.id.uuidString ?? "N/A"
            let athleteName = session.athlete?.displayName ?? "N/A"

            if let measurements = session.measurements {
                for measurement in measurements {
                    let measuredAt = measurement.measuredAt.ISO8601Format()
                    let quality = "N/A"

                    csv += "\(session.id),\(sessionDate),\(athleteId),\(athleteName),"
                    csv += "\(measurement.id),\(measurement.muscleGroup),\(measurement.side),"
                    csv += "\(measurement.perceivedFatigue),\(measuredAt),\(quality)\n"
                }
            }
        }

        return csv
    }

    private func createCSVFile(from csvString: String) -> URL {
        let fileName = "biomess_datos_\(Date().ISO8601Format()).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? csvString.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Measurement.self, MeasurementSession.self, Athlete.self], inMemory: true)
}
