import SwiftUI
import SwiftData

/// History view showing past measurements and trends
public struct HistoryView: View {
    @Environment(MeasurementStorageService.self) private var storageService
    @State private var storedMeasurements: [StoredMeasurement] = []
    @State private var isLoading = false
    @State private var loadError: Error?
    @State private var showingError = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    LoadingView()
                } else if storedMeasurements.isEmpty {
                    EmptyHistoryView()
                } else {
                    MeasurementListView(measurements: storedMeasurements)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: {
                    #if os(iOS)
                    .topBarTrailing
                    #else
                    .primaryAction
                    #endif
                }()) {
                    Button("Export") {
                        exportMeasurements()
                    }
                    .disabled(storedMeasurements.isEmpty)
                }
            }
        }
        .onAppear {
            loadMeasurements()
        }
        .refreshable {
            loadMeasurements()
        }
        .alert("Load Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            if let error = loadError {
                Text("Failed to load measurements: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadMeasurements() {
        isLoading = true
        
        Task {
            do {
                let measurements = try storageService.loadAllMeasurements()
                await MainActor.run {
                    self.storedMeasurements = measurements
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.loadError = error
                    self.showingError = true
                    self.isLoading = false
                }
            }
        }
    }
    
    private func exportMeasurements() {
        Task {
            do {
                let csvData = try storageService.exportMeasurementsAsCSV()
                // TODO: Implement actual export (share sheet, etc.)
                print("CSV data generated, size: \(csvData.count) bytes")
            } catch {
                await MainActor.run {
                    self.loadError = error
                    self.showingError = true
                }
            }
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading measurements...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 64))
                .foregroundStyle(.gray)
            
            Text("No Measurements Yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            Text("Your measurement history will appear here after you complete your first bioimpedance analysis.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

private struct MeasurementListView: View {
    let measurements: [StoredMeasurement]
    
    var body: some View {
        List(measurements, id: \.timestamp) { measurement in
            NavigationLink(destination: MeasurementDetailView(measurement: measurement)) {
                MeasurementRow(measurement: measurement)
            }
        }
    }
}

private struct MeasurementRow: View {
    let measurement: StoredMeasurement
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(measurement.timestamp, style: .date)
                        .font(.headline)
                    Text(measurement.deviceName)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                Spacer()
                QualityBadge(score: measurement.qualityScore)
            }
            
            Text(measurement.timestamp, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Re: \(measurement.extracellularResistance, specifier: "%.1f") Ω")
                    Text("Ri: \(measurement.intracellularResistance, specifier: "%.1f") Ω")
                }
                .font(.caption)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Cm: \(measurement.membraneCapacitance, specifier: "%.2f") nF")
                    Text("fc: \(measurement.characteristicFrequency, specifier: "%.1f") kHz")
                }
                .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct QualityBadge: View {
    let score: Float
    
    var body: some View {
        Text(qualityText)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(qualityColor.opacity(0.2), in: Capsule())
            .foregroundStyle(qualityColor)
    }
    
    private var qualityText: String {
        if score >= 0.9 { return "★★★★★" }
        if score >= 0.8 { return "★★★★☆" }
        if score >= 0.6 { return "★★★☆☆" }
        return "★★☆☆☆"
    }
    
    private var qualityColor: Color {
        if score >= 0.9 { return .green }
        if score >= 0.8 { return .blue }
        if score >= 0.6 { return .orange }
        return .red
    }
}

/// Detail view for a specific measurement from history
private struct MeasurementDetailView: View {
    let measurement: StoredMeasurement
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Device and timestamp info
                MeasurementInfoCard(measurement: measurement)
                
                // Bode Plot
                if let rawData = measurement.getRawMeasurementData() {
                    BodePlotView(data: rawData)
                }
                
                // Cole Parameters
                ColeParametersCard(parameters: measurement.toColeParameters())
                
                // Processing Information
                ProcessingInfoCard(measurement: measurement)
            }
            .padding(.bottom, 100) // Extra padding for safe scrolling
        }
        .navigationTitle("Measurement Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct MeasurementInfoCard: View {
    let measurement: StoredMeasurement
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Measurement Info")
                    .font(.headline)
                Spacer()
                QualityBadge(score: measurement.qualityScore)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Date", value: measurement.timestamp, style: .abbreviated)
                InfoRow(label: "Time", value: measurement.timestamp, style: .shortened)
                InfoRow(label: "Device", value: measurement.deviceName)
                InfoRow(label: "Serial", value: measurement.deviceSerialNumber)
                InfoRow(label: "Processing Time", value: String(format: "%.1f seconds", measurement.processingTime))
            }
        }
        .padding()
        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    
    init(label: String, value: String) {
        self.label = label
        self.value = value
    }
    
    init(label: String, value: Date, style: Date.FormatStyle.DateStyle) {
        self.label = label
        self.value = value.formatted(date: style, time: .omitted)
    }
    
    init(label: String, value: Date, style: Date.FormatStyle.TimeStyle) {
        self.label = label
        self.value = value.formatted(date: .omitted, time: style)
    }
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }
}

private struct ColeParametersCard: View {
    let parameters: ColeParameters
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cole Analysis")
                    .font(.headline)
                Spacer()
                QualityBadge(score: parameters.quality.score)
            }
            
            VStack(spacing: 8) {
                ParameterRow(label: "Re (Extracellular)", value: String(format: "%.1f Ω", parameters.Re))
                ParameterRow(label: "Ri (Intracellular)", value: String(format: "%.1f Ω", parameters.Ri))
                ParameterRow(label: "Cm (Membrane)", value: String(format: "%.2f nF", parameters.Cm))
                ParameterRow(label: "fc (Characteristic)", value: String(format: "%.1f kHz", parameters.fc))
                ParameterRow(label: "α (Dispersion)", value: String(format: "%.3f", parameters.alpha))
                ParameterRow(label: "Fit Error", value: String(format: "%.2f%%", parameters.error))
            }
        }
        .padding()
        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

private struct ParameterRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.medium)
        }
    }
}

private struct ProcessingInfoCard: View {
    let measurement: StoredMeasurement
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processing Information")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Processing Time", value: String(format: "%.1f seconds", measurement.processingTime))
                if let rawData = measurement.getRawMeasurementData() {
                    InfoRow(label: "Data Points", value: "\(rawData.measurements.count) frequencies")
                }
                let coleParams = measurement.toColeParameters()
                InfoRow(label: "Algorithm", value: "Cole Model (\(coleParams.processingTier.displayName))")
                InfoRow(label: "Signal Quality", value: String(format: "SNR: %.1f dB", coleParams.quality.signalQuality.snr))
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// Extension to make ProcessingTier display-friendly
private extension ProcessingTier {
    var displayName: String {
        switch self {
        case .immediate:
            return "Immediate"
        case .complete:
            return "Complete"
        }
    }
}

#Preview {
    HistoryView()
}