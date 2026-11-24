import SwiftUI

/// Compact, reusable measurement configuration card
/// Used inline in MeasurementView and AutoMeasurementConfigView
struct MeasurementConfigCard: View {
    @Binding var sweepStart: Double
    @Binding var sweepStop: Double
    @Binding var sweepPoints: Int
    @Binding var numRepetitions: Int
    @State private var selectedPreset: Preset?

    let mode: ConfigMode
    var onApply: (() async -> Void)?

    enum ConfigMode {
        case manual  // Quick presets for manual measurements
        case auto    // Balanced presets for auto measurements
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Text("Configuración de Medición")
                    .font(.headline)
            }

            // Presets
            presetButtons

            Divider()

            // Repetitions
            repetitionsSection

            // Sweep Points
            sweepPointsSection

            // Frequency Range
            frequencyRangeSection

            // Estimates
            estimatesSection

            // Apply button (if provided)
            if let onApply {
                Button(action: {
                    Task {
                        await onApply()
                    }
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Aplicar Configuración")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.systemBackground)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
    }

    // MARK: - Subviews

    private var presetButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(presetsForMode, id: \.id) { preset in
                    PresetChip(
                        preset: preset,
                        isSelected: selectedPreset?.id == preset.id,
                        onTap: {
                            applyPreset(preset)
                        }
                    )
                }
            }
        }
    }

    private var repetitionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
                Text("Repeticiones")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(numRepetitions)×")
                    .font(.title3.bold())
                    .foregroundStyle(.blue)
                    .contentTransition(.numericText())
            }

            Picker("", selection: $numRepetitions) {
                ForEach(1...10, id: \.self) { num in
                    Text("\(num)").tag(num)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: repetitionQualityIcon)
                    .foregroundStyle(repetitionQualityColor)
                    .symbolEffect(.bounce, value: numRepetitions)
                Text(repetitionQualityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sweepPointsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.purple)
                Text("Puntos de Barrido")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(sweepPoints)")
                    .font(.title3.bold())
                    .foregroundStyle(.purple)
                    .contentTransition(.numericText())
            }

            Picker("", selection: $sweepPoints) {
                ForEach([16, 24, 36, 48, 64, 96, 100], id: \.self) { points in
                    Text("\(points) pts").tag(points)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var frequencyRangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(.green)
                Text("Rango de Frecuencia")
                    .font(.subheadline.bold())
            }

            VStack(spacing: 12) {
                // Start Frequency
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Inicio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(formatFrequency(sweepStart)) Hz")
                            .font(.caption.bold())
                            .contentTransition(.numericText())
                    }

                    Slider(value: $sweepStart, in: 1000...198000, step: 1000)
                        .tint(.green)
                }

                // Stop Frequency
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Fin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(formatFrequency(sweepStop)) Hz")
                            .font(.caption.bold())
                            .contentTransition(.numericText())
                    }

                    Slider(value: $sweepStop, in: sweepStart...198000, step: 1000)
                        .tint(.green)
                }

                // Quick frequency presets
                HStack(spacing: 8) {
                    FrequencyPresetButton(label: "4-198 kHz", start: 4000, stop: 198000) {
                        withAnimation {
                            sweepStart = 4000
                            sweepStop = 198000
                        }
                    }
                    FrequencyPresetButton(label: "10-100 kHz", start: 10000, stop: 100000) {
                        withAnimation {
                            sweepStart = 10000
                            sweepStop = 100000
                        }
                    }
                    FrequencyPresetButton(label: "50-150 kHz", start: 50000, stop: 150000) {
                        withAnimation {
                            sweepStart = 50000
                            sweepStop = 150000
                        }
                    }
                }
            }
        }
    }

    private var estimatesSection: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Duración", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(estimatedDuration)
                    .font(.caption.bold())
                    .contentTransition(.numericText())
            }

            HStack {
                Label("Puntos Totales", systemImage: "chart.xyaxis.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(totalPoints)")
                    .font(.caption.bold())
                    .contentTransition(.numericText())
            }

            HStack {
                Label("Impacto en Batería", systemImage: "battery.75")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(batteryImpact)
                    .font(.caption.bold())
                    .foregroundStyle(batteryImpactColor)
            }
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Presets

    private var presetsForMode: [Preset] {
        switch mode {
        case .manual:
            return [
                Preset(
                    id: "fast",
                    name: "Rápido",
                    icon: "hare.fill",
                    repetitions: 1,
                    sweepPoints: 24,
                    description: "Medición rápida (~2 seg)"
                ),
                Preset(
                    id: "standard",
                    name: "Estándar",
                    icon: "checkmark.circle.fill",
                    repetitions: 3,
                    sweepPoints: 48,
                    description: "Recomendado (~9 seg)"
                ),
                Preset(
                    id: "quality",
                    name: "Calidad",
                    icon: "star.fill",
                    repetitions: 5,
                    sweepPoints: 48,
                    description: "Alta calidad (~15 seg)"
                ),
                Preset(
                    id: "maximum",
                    name: "Máximo",
                    icon: "crown.fill",
                    repetitions: 8,
                    sweepPoints: 48,
                    description: "Mejor calidad (~19 seg)"
                )
            ]
        case .auto:
            return [
                Preset(
                    id: "balanced",
                    name: "Balanceado",
                    icon: "scale.3d",
                    repetitions: 3,
                    sweepPoints: 36,
                    description: "Buena calidad, eficiente (~7 seg)"
                ),
                Preset(
                    id: "detailed",
                    name: "Detallado",
                    icon: "chart.line.uptrend.xyaxis",
                    repetitions: 5,
                    sweepPoints: 48,
                    description: "Alto detalle (~15 seg)"
                )
            ]
        }
    }

    private func applyPreset(_ preset: Preset) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            numRepetitions = preset.repetitions
            sweepPoints = preset.sweepPoints
            selectedPreset = preset
        }
    }

    // MARK: - Computed Properties

    private var totalPoints: Int {
        numRepetitions * sweepPoints
    }

    private var estimatedDuration: String {
        let seconds = Double(totalPoints) * 0.05  // ~50ms per point
        if seconds < 60 {
            return String(format: "~%.0f sec", seconds)
        } else {
            let minutes = Int(seconds / 60)
            let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(remainingSeconds)s"
        }
    }

    private var batteryImpact: String {
        let mAh = Double(totalPoints) * 0.015  // ~15 µAh per point estimate
        if mAh < 1 {
            return "< 1 mAh"
        } else {
            return String(format: "~%.1f mAh", mAh)
        }
    }

    private var batteryImpactColor: Color {
        let points = totalPoints
        if points < 100 {
            return .green
        } else if points < 200 {
            return .orange
        } else {
            return .red
        }
    }

    private var repetitionQualityText: String {
        switch numRepetitions {
        case 1:
            return "Medición rápida"
        case 2...3:
            return "Calidad estándar"
        case 4...6:
            return "Alta calidad"
        default:
            return "Máxima calidad"
        }
    }

    private var repetitionQualityIcon: String {
        switch numRepetitions {
        case 1:
            return "gauge.with.dots.needle.0percent"
        case 2...3:
            return "gauge.with.dots.needle.50percent"
        case 4...6:
            return "gauge.with.dots.needle.67percent"
        default:
            return "gauge.with.dots.needle.100percent"
        }
    }

    private var repetitionQualityColor: Color {
        switch numRepetitions {
        case 1:
            return .orange
        case 2...3:
            return .blue
        case 4...6:
            return .green
        default:
            return .purple
        }
    }

    private func formatFrequency(_ freq: Double) -> String {
        if freq >= 1000 {
            return String(format: "%.1f k", freq / 1000)
        } else {
            return String(format: "%.0f", freq)
        }
    }
}

// MARK: - Preset Model

struct Preset: Identifiable {
    let id: String
    let name: String
    let icon: String
    let repetitions: Int
    let sweepPoints: Int
    let description: String
}

// MARK: - Frequency Preset Button

struct FrequencyPresetButton: View {
    let label: String
    let start: Double
    let stop: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.caption2.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.tertiarySystemBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preset Chip

struct PresetChip: View {
    let preset: Preset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: preset.icon)
                    .font(.title3)
                    .symbolEffect(.bounce, value: isSelected)

                Text(preset.name)
                    .font(.caption.bold())

                Text(preset.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 130)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color.secondarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Manual Mode") {
    ScrollView {
        MeasurementConfigCard(
            sweepStart: .constant(4000),
            sweepStop: .constant(198000),
            sweepPoints: .constant(48),
            numRepetitions: .constant(3),
            mode: .manual,
            onApply: {
                print("Applied")
            }
        )
        .padding()
    }
}

#Preview("Auto Mode") {
    ScrollView {
        MeasurementConfigCard(
            sweepStart: .constant(4000),
            sweepStop: .constant(198000),
            sweepPoints: .constant(36),
            numRepetitions: .constant(3),
            mode: .auto
        )
        .padding()
    }
}
