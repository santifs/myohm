import SwiftUI
import Charts

/// Detailed view showing measurement analysis with Cole parameters and Bode plots
public struct MeasurementDetailView: View {
    let parameters: ColeParameters

    public init(parameters: ColeParameters) {
        self.parameters = parameters
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Quality and Timestamp Header
                HeaderSection(parameters: parameters)

                // Cole Parameters
                ParametersSection(parameters: parameters)

                // Magnitude/Phase Bode Plots
                if let rawData = parameters.rawData {
                    ResistanceReactancePlotSection(data: rawData)
                }

                // Resistance/Reactance Plots
                BodePlotsSection(parameters: parameters)
            }
            .padding()
        }
        .background(Color.systemGroupedBackground)
        .navigationTitle("Detalles de Medición")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Magnitude/Phase Plot Section

private struct ResistanceReactancePlotSection: View {
    let data: ImpedanceData
    @State private var selectedTab = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Impedancia")
                .font(.headline)
                .foregroundStyle(.secondary)

            Picker("Tipo de Gráfica", selection: $selectedTab) {
                Text("Resistencia").tag(0)
                Text("Reactancia").tag(1)
            }
            .pickerStyle(.segmented)

            VStack {
                if selectedTab == 0 {
                    ResistancePlotView(data: data, isLandscape: isLandscape)
                } else {
                    ReactancePlotView(data: data, isLandscape: isLandscape)
                }
            }
            .frame(height: isLandscape ? 400 : 250)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Text("Rango de Frecuencia:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formatFrequency(data.frequencies.first ?? 0)) - \(formatFrequency(data.frequencies.last ?? 0))")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }

    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.0f kHz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }
}

// MARK: - Resistance Plot

private struct ResistancePlotView: View {
    let data: ImpedanceData
    let isLandscape: Bool

    private var chartData: [(frequency: Double, resistance: Double)] {
        data.measurements.map { point in
            (frequency: Double(point.frequency), resistance: Double(point.complexImpedance.real))
        }
    }

    private var resistanceRange: (min: Double, max: Double) {
        let values = chartData.map(\.resistance)
        let dataMin = values.min() ?? 0
        let dataMax = values.max() ?? 100
        let padding = 5.0
        return (min: dataMin - padding, max: dataMax + padding)
    }

    var body: some View {
        Chart(chartData, id: \.frequency) { point in
            LineMark(
                x: .value("Frequency", Darwin.log10(point.frequency)),
                y: .value("Resistance", point.resistance)
            )
            .foregroundStyle(.blue.gradient)
            .lineStyle(StrokeStyle(lineWidth: isLandscape ? 3 : 2))

            PointMark(
                x: .value("Frequency", Darwin.log10(point.frequency)),
                y: .value("Resistance", point.resistance)
            )
            .foregroundStyle(.blue)
            .symbolSize(isLandscape ? 40 : 25)
        }
        .chartXScale(domain: Darwin.log10(1000.0)...Darwin.log10(500000.0))
        .chartYScale(domain: resistanceRange.min...resistanceRange.max)
        .chartXAxis {
            AxisMarks(values: [Darwin.log10(1000.0), Darwin.log10(10000.0), Darwin.log10(100000.0), Darwin.log10(500000.0)]) { value in
                if let logFreq = value.as(Double.self) {
                    let freq = Darwin.pow(10.0, logFreq)
                    AxisValueLabel {
                        if freq >= 1000 {
                            Text("\(Int(freq/1000))k")
                                .font(isLandscape ? .caption : .caption2)
                        } else {
                            Text("\(Int(freq))")
                                .font(isLandscape ? .caption : .caption2)
                        }
                    }
                    AxisGridLine()
                    AxisTick()
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                if let resistance = value.as(Double.self) {
                    AxisValueLabel {
                        Text("\(Int(round(resistance)))")
                            .font(isLandscape ? .caption : .caption2)
                    }
                    AxisGridLine()
                    AxisTick()
                }
            }
        }
        .chartXAxisLabel(position: .bottom, alignment: .center) {
            Text("Frecuencia (Hz)")
                .font(isLandscape ? .caption : .caption2)
                .foregroundStyle(.secondary)
        }
        .chartYAxisLabel(position: .leading, alignment: .center) {
            Text("Resistencia (Ω)")
                .font(isLandscape ? .caption : .caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Reactance Plot

private struct ReactancePlotView: View {
    let data: ImpedanceData
    let isLandscape: Bool

    private var chartData: [(frequency: Double, reactance: Double)] {
        data.measurements.map { point in
            (frequency: Double(point.frequency), reactance: Double(point.complexImpedance.imaginary))
        }
    }

    private var reactanceRange: (min: Double, max: Double) {
        let values = chartData.map(\.reactance)
        let dataMin = values.min() ?? 0
        let dataMax = values.max() ?? 20
        let range = abs(dataMax - dataMin)
        let padding = max(range * 0.1, 2.0)
        return (min: dataMin - padding, max: dataMax + padding)
    }

    var body: some View {
        Chart(chartData, id: \.frequency) { point in
            LineMark(
                x: .value("Frequency", Darwin.log10(point.frequency)),
                y: .value("Reactance", point.reactance)
            )
            .foregroundStyle(.orange.gradient)
            .lineStyle(StrokeStyle(lineWidth: isLandscape ? 3 : 2))

            PointMark(
                x: .value("Frequency", Darwin.log10(point.frequency)),
                y: .value("Reactance", point.reactance)
            )
            .foregroundStyle(.orange)
            .symbolSize(isLandscape ? 40 : 25)
        }
        .chartXScale(domain: Darwin.log10(1000.0)...Darwin.log10(500000.0))
        .chartYScale(domain: reactanceRange.min...reactanceRange.max)
        .chartXAxis {
            AxisMarks(values: [Darwin.log10(1000.0), Darwin.log10(10000.0), Darwin.log10(100000.0), Darwin.log10(500000.0)]) { value in
                if let logFreq = value.as(Double.self) {
                    let freq = Darwin.pow(10.0, logFreq)
                    AxisValueLabel {
                        if freq >= 1000 {
                            Text("\(Int(freq/1000))k")
                                .font(isLandscape ? .caption : .caption2)
                        } else {
                            Text("\(Int(freq))")
                                .font(isLandscape ? .caption : .caption2)
                        }
                    }
                    AxisGridLine()
                    AxisTick()
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                if let reactance = value.as(Double.self) {
                    AxisValueLabel {
                        Text(String(format: "%.1f", reactance))
                            .font(isLandscape ? .caption : .caption2)
                    }
                    AxisGridLine()
                    AxisTick()
                }
            }
        }
        .chartXAxisLabel(position: .bottom, alignment: .center) {
            Text("Frecuencia (Hz)")
                .font(isLandscape ? .caption : .caption2)
                .foregroundStyle(.secondary)
        }
        .chartYAxisLabel(position: .leading, alignment: .center) {
            Text("Reactancia (Ω)")
                .font(isLandscape ? .caption : .caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Header Section

private struct HeaderSection: View {
    let parameters: ColeParameters

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(parameters.timestamp.formatted(date: .long, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let patient = parameters.patient {
                        Text("\(patient.name), \(patient.age)y")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                QualityIndicator(score: parameters.quality.score)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Parameters Section

private struct ParametersSection: View {
    let parameters: ColeParameters

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parámetros de Cole")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                CompactParameterCard(
                    title: "Re",
                    subtitle: "Extracelular",
                    value: String(format: "%.1f", parameters.Re),
                    unit: "Ω",
                    color: Color.parameterPrimary
                )

                CompactParameterCard(
                    title: "Ri",
                    subtitle: "Intracelular",
                    value: String(format: "%.1f", parameters.Ri),
                    unit: "Ω",
                    color: Color.parameterSecondary
                )

                CompactParameterCard(
                    title: "Cm",
                    subtitle: "Membrana",
                    value: String(format: "%.2f", parameters.Cm),
                    unit: "nF",
                    color: Color.parameterTertiary
                )

                CompactParameterCard(
                    title: "fc",
                    subtitle: "Característica",
                    value: String(format: "%.1f", parameters.fc),
                    unit: "kHz",
                    color: Color.accentPurple
                )
            }
        }
    }
}

private struct CompactParameterCard: View {
    let title: String
    let subtitle: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(color)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Bode Plots Section

private struct BodePlotsSection: View {
    let parameters: ColeParameters
    @State private var selectedRepetition = 0
    @State private var chartMode: ChartDisplayMode = .measured

    enum ChartDisplayMode: String, CaseIterable {
        case measured = "Medido"
        case model = "Modelo"
        case both = "Ambos"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Gráficos de Bode")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Modo", selection: $chartMode) {
                    ForEach(ChartDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            // Resistance Plot
            ResistancePlot(
                parameters: parameters,
                repetitionIndex: selectedRepetition,
                mode: chartMode
            )

            // Reactance Plot
            ReactancePlot(
                parameters: parameters,
                repetitionIndex: selectedRepetition,
                mode: chartMode
            )

            // Repetition Picker (if multiple repetitions)
            if let rawData = parameters.rawData, rawData.repetitions.count > 1 {
                Picker("Repetición", selection: $selectedRepetition) {
                    ForEach(0..<rawData.repetitions.count, id: \.self) { index in
                        Text("Rep \(index + 1)").tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

// MARK: - Resistance Plot

private struct ResistancePlot: View {
    let parameters: ColeParameters
    let repetitionIndex: Int
    let mode: BodePlotsSection.ChartDisplayMode
    @State private var selectedFrequency: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resistencia")
                .font(.subheadline)
                .fontWeight(.medium)

            Chart {
                if mode != .model {
                    ForEach(measuredData, id: \.frequency) { point in
                        PointMark(
                            x: .value("Frequency", point.frequency),
                            y: .value("Resistance", point.resistance)
                        )
                        .foregroundStyle(Color.parameterPrimary)
                        .symbol(.circle)
                        .symbolSize(60)

                        LineMark(
                            x: .value("Frequency", point.frequency),
                            y: .value("Resistance", point.resistance)
                        )
                        .foregroundStyle(Color.parameterPrimary)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }

                if mode != .measured {
                    ForEach(modelData, id: \.frequency) { point in
                        LineMark(
                            x: .value("Frequency", point.frequency),
                            y: .value("Resistance", point.resistance)
                        )
                        .foregroundStyle(Color.parameterSecondary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    }
                }

                if let selectedFrequency {
                    RuleMark(x: .value("Selected", selectedFrequency))
                        .foregroundStyle(.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartXScale(type: .log)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartXSelection(value: $selectedFrequency)
            .frame(height: 250)

            if let selectedFrequency, let point = measuredData.first(where: { abs($0.frequency - selectedFrequency) < 1000 }) {
                Text("f: \(Int(point.frequency)) Hz, R: \(String(format: "%.2f", point.resistance)) Ω")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var measuredData: [DataPoint] {
        guard let rawData = parameters.rawData,
              repetitionIndex < rawData.repetitions.count else { return [] }
        let measurements = rawData.repetitions[repetitionIndex]
        return measurements.map { measurement in
            let resistance = Double(measurement.complexImpedance.real)
            return DataPoint(frequency: Double(measurement.frequency), resistance: resistance)
        }
    }

    private var modelData: [DataPoint] {
        let frequencies = stride(from: 1000.0, through: 1_000_000.0, by: 5000.0)
        return frequencies.map { freq in
            let z = ColeModel.impedance(frequency: freq, parameters: parameters)
            return DataPoint(frequency: freq, resistance: Double(z.real))
        }
    }

    struct DataPoint {
        let frequency: Double
        let resistance: Double
    }
}

// MARK: - Reactance Plot

private struct ReactancePlot: View {
    let parameters: ColeParameters
    let repetitionIndex: Int
    let mode: BodePlotsSection.ChartDisplayMode
    @State private var selectedFrequency: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reactancia")
                .font(.subheadline)
                .fontWeight(.medium)

            Chart {
                if mode != .model {
                    ForEach(measuredData, id: \.frequency) { point in
                        PointMark(
                            x: .value("Frequency", point.frequency),
                            y: .value("Reactance", point.reactance)
                        )
                        .foregroundStyle(Color.parameterTertiary)
                        .symbol(.circle)
                        .symbolSize(60)

                        LineMark(
                            x: .value("Frequency", point.frequency),
                            y: .value("Reactance", point.reactance)
                        )
                        .foregroundStyle(Color.parameterTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }

                if mode != .measured {
                    ForEach(modelData, id: \.frequency) { point in
                        LineMark(
                            x: .value("Frequency", point.frequency),
                            y: .value("Reactance", point.reactance)
                        )
                        .foregroundStyle(Color.accentPurple.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    }
                }

                if let selectedFrequency {
                    RuleMark(x: .value("Selected", selectedFrequency))
                        .foregroundStyle(.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartXScale(type: .log)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartXSelection(value: $selectedFrequency)
            .frame(height: 250)

            if let selectedFrequency, let point = measuredData.first(where: { abs($0.frequency - selectedFrequency) < 1000 }) {
                Text("f: \(Int(point.frequency)) Hz, X: \(String(format: "%.2f", point.reactance)) Ω")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var measuredData: [DataPoint] {
        guard let rawData = parameters.rawData,
              repetitionIndex < rawData.repetitions.count else { return [] }
        let measurements = rawData.repetitions[repetitionIndex]
        return measurements.map { measurement in
            let reactance = -Double(measurement.complexImpedance.imaginary) // Negative for capacitive
            return DataPoint(frequency: Double(measurement.frequency), reactance: reactance)
        }
    }

    private var modelData: [DataPoint] {
        let frequencies = stride(from: 1000.0, through: 1_000_000.0, by: 5000.0)
        return frequencies.map { freq in
            let z = ColeModel.impedance(frequency: freq, parameters: parameters)
            return DataPoint(frequency: freq, reactance: -Double(z.imaginary))
        }
    }

    struct DataPoint {
        let frequency: Double
        let reactance: Double
    }
}

// MARK: - Cole Model Helper

private enum ColeModel {
    static func impedance(frequency: Double, parameters: ColeParameters) -> (real: Float, imaginary: Float) {
        let omega = 2.0 * .pi * frequency
        let Ri = Double(parameters.Ri)
        let Re = Double(parameters.Re)
        let Cm = Double(parameters.Cm) * 1e-9 // Convert nF to F
        let alpha = Double(parameters.alpha)
        let fc = Double(parameters.fc) * 1000.0 // Convert kHz to Hz

        let omegaRatio = omega / (2.0 * .pi * fc)
        let jOmegaRCm = (0.0, omega * (Ri * Cm))

        let cosArg = cos(alpha * .pi / 2.0)
        let sinArg = sin(alpha * .pi / 2.0)
        let denomReal = pow(omegaRatio, alpha) * cosArg
        let denomImag = pow(omegaRatio, alpha) * sinArg

        let numeratorReal = 1.0 + jOmegaRCm.1 * denomImag
        let numeratorImag = jOmegaRCm.1 * (1.0 + denomReal)

        let denomMagSq = pow(1.0 + denomReal, 2.0) + pow(denomImag, 2.0)

        let fractionReal = (numeratorReal * (1.0 + denomReal) + numeratorImag * denomImag) / denomMagSq
        let fractionImag = (numeratorImag * (1.0 + denomReal) - numeratorReal * denomImag) / denomMagSq

        let zReal = Float(Re + Ri * fractionReal)
        let zImag = Float(Ri * fractionImag)

        return (zReal, zImag)
    }
}

// Preview removed due to complex ColeParameters initialization
