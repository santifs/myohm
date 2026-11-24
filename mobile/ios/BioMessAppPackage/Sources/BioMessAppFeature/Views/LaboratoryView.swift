import SwiftUI
import SwiftData

struct LaboratoryView: View {
    @Binding var selectedTab: Int
    @Query(sort: \Measurement.measuredAt, order: .reverse) private var measurements: [Measurement]
    private var laboratoryMeasurements: [Measurement] {
        measurements.filter { $0.session == nil && $0.muscleGroup == "laboratory" }
    }
    var body: some View {
        List {
            Section {
                Text("Configura el barrido y pulsa Medir. Cada captura se guarda automáticamente en este dispositivo, sin atleta ni cuestionario.")
                NavigationLink {
                    MeasurementView(selectedTab: $selectedTab, laboratoryMode: true, embeddedMode: false, muscleGroup: "laboratory")
                } label: {
                    Label("Nueva medición", systemImage: "plus.circle")
                }
            }
            Section("Mediciones guardadas") {
                if laboratoryMeasurements.isEmpty {
                    Text("Todavía no hay mediciones de laboratorio.").foregroundStyle(.secondary)
                }
                ForEach(laboratoryMeasurements) { measurement in
                    NavigationLink {
                        if let raw = measurement.asRawMeasurement {
                            RawMeasurementDetailView(measurement: raw)
                        } else {
                            Text("No se pueden leer los datos de esta medición.")
                        }
                    } label: {
                        Label(measurement.measuredAt.formatted(date: .abbreviated, time: .standard), systemImage: "waveform.path")
                    }
                }
            }
        }
        .navigationTitle("Laboratorio")
    }
}
