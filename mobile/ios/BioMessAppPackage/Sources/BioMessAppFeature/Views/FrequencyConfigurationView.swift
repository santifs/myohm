import SwiftUI

/// Modern, beautiful view for configuring AD5940 measurement parameters
/// Features iOS 18+ design with smooth animations and intuitive controls
@MainActor
public struct FrequencyConfigurationView: View {

    @Environment(BioMessBLEManager.self) private var bleManager
    @State private var configManager = AD5940ConfigurationManager()

    // Configuration state
    @State private var sweepStart: Double = 4000
    @State private var sweepStop: Double = 198000
    @State private var sweepPoints: Int = 48
    @State private var numRepetitions: Int = 5
    @State private var showingApplyConfirmation = false
    @State private var selectedPreset: Preset? = .standard

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header card with connection status
                headerCard

                // Quick presets
                presetsGrid

                // Repetitions control (NEW - Featured prominently)
                repetitionsCard

                // Frequency range
                frequencyCard

                // Points control
                pointsCard

                // Measurement summary
                summaryCard

                // Apply button
                applyButton
            }
            .padding()
        }
        .background(Color.systemGroupedBackground)
        .navigationTitle("Configuración de Medición")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            await loadCurrentConfiguration()
        }
        .alert("Configuración Aplicada", isPresented: $showingApplyConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Tus ajustes de medición han sido sincronizados con el dispositivo.")
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: bleManager.connectionState == .connected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.title2)
                    .foregroundStyle(bleManager.connectionState == .connected ? .green : .secondary)
                    .symbolEffect(.variableColor, isActive: bleManager.connectionState == .connected)

                VStack(alignment: .leading, spacing: 4) {
                    Text(bleManager.connectionState == .connected ? "Dispositivo Conectado" : "Dispositivo Desconectado")
                        .font(.headline)
                    Text(bleManager.connectionState == .connected ? "Listo para configurar" : "Conectar dispositivo para continuar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color.secondarySystemGroupedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }

    // MARK: - Presets Grid

    private var presetsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preajustes Rápidos")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Preset.allCases, id: \.self) { preset in
                    PresetButton(
                        preset: preset,
                        isSelected: selectedPreset == preset
                    ) {
                        applyPreset(preset)
                    }
                }
            }
        }
    }

    // MARK: - Repetitions Card (NEW - Most Important Feature)

    private var repetitionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Repeticiones")
                    .font(.headline)
                Spacer()
                Text("\(numRepetitions)×")
                    .font(.title2.bold())
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 8) {
                Picker("", selection: $numRepetitions) {
                    ForEach(1...10, id: \.self) { num in
                        Text("\(num)").tag(num)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(repetitionQualityText)
                            .font(.subheadline.bold())
                        Text(repetitionDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: repetitionIcon)
                        .font(.title)
                        .foregroundStyle(repetitionColor)
                        .symbolEffect(.bounce, value: numRepetitions)
                }
                .padding(.top, 8)
            }

            // Duration estimate
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("Duración estimada:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(estimatedDuration)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.tertiarySystemGroupedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.05), Color.blue.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Frequency Card

    private var frequencyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "waveform.path")
                    .font(.title2)
                    .foregroundStyle(.purple)
                Text("Rango de Frecuencia")
                    .font(.headline)
            }

            VStack(spacing: 20) {
                FrequencySlider(
                    value: $sweepStart,
                    range: 1000...50000,
                    label: "Inicio",
                    color: .green
                )

                FrequencySlider(
                    value: $sweepStop,
                    range: 50000...200000,
                    label: "Fin",
                    color: .red
                )
            }

            // Preview of calculated range
            HStack {
                Text("Rango:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formatFrequency(Float(sweepStart))) → \(formatFrequency(Float(sweepStop)))")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.tertiarySystemGroupedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .background(Color.secondarySystemGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    // MARK: - Points Card

    private var pointsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Puntos de Medición")
                    .font(.headline)
            }

            VStack(spacing: 12) {
                HStack {
                    Text("\(sweepPoints)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                        .contentTransition(.numericText())

                    Spacer()

                    VStack(spacing: 8) {
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                if sweepPoints < 100 { sweepPoints += 12 }
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title)
                                .foregroundStyle(.orange)
                        }

                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                if sweepPoints > 16 { sweepPoints -= 12 }
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Slider(value: Binding(
                    get: { Double(sweepPoints) },
                    set: { sweepPoints = Int($0) }
                ), in: 16...100, step: 1)
                .tint(.orange)

                HStack {
                    Text("16 pts")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("100 pts")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.secondarySystemGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resumen de Medición")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Label("Puntos Totales", systemImage: "number")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(totalPoints)")
                        .bold()
                }

                Divider()

                GridRow {
                    Label("Datos por Barrido", systemImage: "chart.bar")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(sweepPoints) puntos")
                        .bold()
                }

                Divider()

                GridRow {
                    Label("Número de Barridos", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(numRepetitions)×")
                        .bold()
                }

                Divider()

                GridRow {
                    Label("Duración", systemImage: "clock")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(estimatedDuration)
                        .bold()
                }

                Divider()

                GridRow {
                    Label("Calidad", systemImage: "star.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(repetitionQualityText)
                        .bold()
                        .foregroundStyle(repetitionColor)
                }
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color.secondarySystemGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    // MARK: - Apply Button

    private var applyButton: some View {
        Button {
            Task { await applyConfiguration() }
        } label: {
            HStack {
                if configManager.isSyncing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Aplicar Configuración")
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                bleManager.connectionState == .connected ?
                LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                LinearGradient(colors: [.gray, .gray.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
        }
        .disabled(configManager.isSyncing || bleManager.connectionState != .connected)
        .animation(.spring(response: 0.3), value: configManager.isSyncing)
    }

    // MARK: - Computed Properties

    private var totalPoints: Int {
        sweepPoints * numRepetitions
    }

    private var estimatedDuration: String {
        let seconds = Double(totalPoints) * 0.05 // ~50ms per point
        if seconds < 60 {
            return String(format: "~%.0f sec", seconds)
        } else {
            let minutes = Int(seconds / 60)
            let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes) min \(remainingSeconds) sec"
        }
    }

    private var repetitionQualityText: String {
        switch numRepetitions {
        case 1: return "Rápido"
        case 2...3: return "Estándar"
        case 4...6: return "Alta Calidad"
        default: return "Máxima Calidad"
        }
    }

    private var repetitionDescription: String {
        switch numRepetitions {
        case 1: return "Medición rápida, filtrado mínimo"
        case 2...3: return "Buen balance entre velocidad y precisión"
        case 4...6: return "Filtrado avanzado de ruido"
        default: return "Mejor relación señal-ruido"
        }
    }

    private var repetitionIcon: String {
        switch numRepetitions {
        case 1: return "hare.fill"
        case 2...3: return "figure.walk"
        case 4...6: return "star.fill"
        default: return "crown.fill"
        }
    }

    private var repetitionColor: Color {
        switch numRepetitions {
        case 1: return .orange
        case 2...3: return .blue
        case 4...6: return .purple
        default: return .yellow
        }
    }

    // MARK: - Actions

    private func applyPreset(_ preset: Preset) {
        withAnimation(.spring(response: 0.4)) {
            sweepStart = preset.startFreq
            sweepStop = preset.stopFreq
            sweepPoints = preset.points
            numRepetitions = preset.repetitions
            selectedPreset = preset
        }
    }

    private func loadCurrentConfiguration() async {
        guard bleManager.connectionState == .connected else {
            return
        }

        do {
            let config = try await configManager.readConfiguration(from: bleManager)
            sweepStart = Double(config.sweepStart)
            sweepStop = Double(config.sweepStop)
            sweepPoints = Int(config.sweepPoints)
            numRepetitions = Int(config.numRepetitions)
        } catch {
            print("Failed to read configuration: \(error)")
        }
    }

    private func applyConfiguration() async {
        let config = AD5940ConfigurationManager.Configuration(
            numOfData: Int32(totalPoints),
            sweepStart: Float(sweepStart),
            sweepStop: Float(sweepStop),
            sweepPoints: UInt32(sweepPoints),
            sweepEnable: true,
            numRepetitions: UInt8(numRepetitions)
        )

        do {
            try await configManager.writeConfiguration(config, to: bleManager)
            showingApplyConfirmation = true
        } catch {
            print("Failed to apply configuration: \(error)")
        }
    }

    // MARK: - Helpers

    private func formatFrequency(_ hz: Float) -> String {
        if hz >= 1000 {
            return String(format: "%.1f kHz", hz / 1000)
        } else {
            return String(format: "%.0f Hz", hz)
        }
    }
}

// MARK: - Presets

extension FrequencyConfigurationView {
    enum Preset: CaseIterable {
        case fast
        case standard
        case quality
        case maximum

        var name: String {
            switch self {
            case .fast: return "Rápido"
            case .standard: return "Estándar"
            case .quality: return "Calidad"
            case .maximum: return "Máximo"
            }
        }

        var icon: String {
            switch self {
            case .fast: return "hare.fill"
            case .standard: return "checkmark.circle.fill"
            case .quality: return "star.fill"
            case .maximum: return "crown.fill"
            }
        }

        var description: String {
            switch self {
            case .fast: return "Escaneo rápido"
            case .standard: return "Recomendado"
            case .quality: return "Alta precisión"
            case .maximum: return "Mejor precisión"
            }
        }

        var startFreq: Double {
            switch self {
            case .fast: return 10000
            case .standard: return 4000
            case .quality: return 4000
            case .maximum: return 1000
            }
        }

        var stopFreq: Double {
            switch self {
            case .fast: return 150000
            case .standard: return 198000
            case .quality: return 198000
            case .maximum: return 198000
            }
        }

        var points: Int {
            switch self {
            case .fast: return 24
            case .standard: return 48
            case .quality: return 48
            case .maximum: return 48
            }
        }

        var repetitions: Int {
            switch self {
            case .fast: return 1
            case .standard: return 3
            case .quality: return 5
            case .maximum: return 8
            }
        }

        var color: Color {
            switch self {
            case .fast: return .orange
            case .standard: return .blue
            case .quality: return .purple
            case .maximum: return .yellow
            }
        }
    }
}

// MARK: - Supporting Views

struct PresetButton: View {
    let preset: FrequencyConfigurationView.Preset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : preset.color)

                Text(preset.name)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(preset.description)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                Group {
                    if isSelected {
                        LinearGradient(colors: [preset.color, preset.color.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else {
                        Color.secondarySystemGroupedBackground
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? preset.color : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? preset.color.opacity(0.3) : .black.opacity(0.05), radius: 8, y: 4)
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

struct FrequencySlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(label)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatFrequency(Float(value)))
                    .font(.subheadline.bold())
                    .foregroundStyle(color)
            }

            Slider(value: $value, in: range, step: 1000)
                .tint(color)

            HStack {
                Text(formatFrequency(Float(range.lowerBound)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatFrequency(Float(range.upperBound)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatFrequency(_ hz: Float) -> String {
        if hz >= 1000 {
            return String(format: "%.0f kHz", hz / 1000)
        } else {
            return String(format: "%.0f Hz", hz)
        }
    }
}

#Preview {
    NavigationStack {
        FrequencyConfigurationView()
            .environment(BioMessBLEManager())
    }
}
