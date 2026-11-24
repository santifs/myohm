import SwiftUI
import Charts
import Foundation
import Darwin
#if os(iOS)
import UIKit
#endif

/// Detailed view showing RAW measurement data with Bode plots
/// Used when measurement hasn't been processed yet through Cole fitting
public struct RawMeasurementDetailView: View {
    let measurement: RawMeasurement
    @State private var selectedRepetition: Int = 0

    public init(measurement: RawMeasurement) {
        self.measurement = measurement
    }

    private var hasRepetitions: Bool {
        measurement.repetitions != nil && measurement.repetitions!.count > 1
    }

    private var selectedData: ImpedanceData {
        if hasRepetitions, let reps = measurement.repetitions, selectedRepetition < reps.count {
            return reps[selectedRepetition]
        }
        return measurement.rawData
    }

    private var displayData: ImpedanceData {
        ImpedanceData(measurements: selectedData.measurements.filter {
            $0.frequency.isFinite && $0.frequency > 0 && $0.magnitude.isFinite && $0.phase.isFinite
        }, timestamp: selectedData.timestamp, deviceInfo: selectedData.deviceInfo)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with date and status
                HeaderSection(measurement: measurement)

                // Cole Analysis Results (if processed)
                if let results = measurement.results {
                    ColeResultsSection(results: results)
                }

                // Raw Data Plots (with inline repetition selector)
                if displayData.measurements.count != selectedData.measurements.count {
                    Text("Hay puntos no representables en esta captura. Se conservan en los datos exportados, pero no se dibujan en las gráficas.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if !displayData.measurements.isEmpty {
                    RawDataPlotsSection(measurement: measurement, displayData: displayData, selectedRepetition: $selectedRepetition)
                } else {
                    Text("Esta repetición no contiene puntos válidos para representar.")
                    if hasRepetitions {
                        Picker("Repetición", selection: $selectedRepetition) {
                            ForEach(0..<(measurement.repetitions?.count ?? 0), id: \.self) { index in
                                Text("Repetición \(index + 1)").tag(index)
                            }
                        }
                    }
                }

                // Export section
                ExportSection(measurement: measurement)
            }
            .padding()
        }
        .navigationTitle("Medición Cruda")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}

// MARK: - Repetition Selector Section (V2.1)

private struct RepetitionSelectorSection: View {
    @Binding var selectedRepetition: Int
    let totalRepetitions: Int
    let signalQuality: Float?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Repeticiones")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                if let quality = signalQuality {
                    HStack(spacing: 4) {
                        Image(systemName: qualityIcon(quality))
                            .foregroundStyle(qualityColor(quality))
                        Text("\(Int(quality * 100))%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(qualityColor(quality))
                    }
                }
            }

            Text("Firmware V2.1: \(totalRepetitions) barridos por medición para reducción de ruido")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Repetition Selector with arrows
            HStack(spacing: 16) {
                Button {
                    if selectedRepetition > 0 {
                        selectedRepetition -= 1
                        #if os(iOS)
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        #endif
                    }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title)
                        .foregroundStyle(selectedRepetition > 0 ? .blue : .gray.opacity(0.3))
                }
                .disabled(selectedRepetition == 0)

                VStack(spacing: 4) {
                    Text("Repetición \(selectedRepetition + 1)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text("de \(totalRepetitions)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Button {
                    if selectedRepetition < totalRepetitions - 1 {
                        selectedRepetition += 1
                        #if os(iOS)
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        #endif
                    }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title)
                        .foregroundStyle(selectedRepetition < totalRepetitions - 1 ? .blue : .gray.opacity(0.3))
                }
                .disabled(selectedRepetition == totalRepetitions - 1)
            }
            .padding(.vertical, 8)

            // Repetition indicator dots
            HStack(spacing: 8) {
                Spacer()
                ForEach(0..<totalRepetitions, id: \.self) { index in
                    Circle()
                        .fill(index == selectedRepetition ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
                Spacer()
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func qualityIcon(_ quality: Float) -> String {
        if quality >= 0.9 { return "checkmark.seal.fill" }
        if quality >= 0.7 { return "checkmark.circle.fill" }
        if quality >= 0.5 { return "exclamationmark.circle.fill" }
        return "xmark.circle.fill"
    }

    private func qualityColor(_ quality: Float) -> Color {
        if quality >= 0.9 { return .green }
        if quality >= 0.7 { return .blue }
        if quality >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - Header Section

private struct HeaderSection: View {
    let measurement: RawMeasurement

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Datos de Bioimpedancia")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(measurement.captureTimestamp, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(measurement.captureTimestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            // Muscle information if available (session-based measurement)
            if let muscleDesc = measurement.muscleDescription {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Músculo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(muscleDesc)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let fatigue = measurement.perceivedFatigue {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text("Fatiga: \(fatigue)/10")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Raw Data Summary Section

private struct RawDataSummarySection: View {
    let measurement: RawMeasurement
    let displayData: ImpedanceData

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resumen de Datos")
                .font(.headline)
                .fontWeight(.semibold)

            let magnitudes = displayData.magnitudes
            let phases = displayData.phases
            let frequencies = displayData.frequencies

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                RawDataCard(
                    title: "Puntos de Medición",
                    value: "\(displayData.measurements.count)",
                    subtitle: "Muestras totales",
                    color: .blue
                )

                RawDataCard(
                    title: "Rango de Frecuencia",
                    value: "\(Int(frequencies.min() ?? 0))-\(Int(frequencies.max() ?? 0)) Hz",
                    subtitle: "Rango de barrido",
                    color: .green
                )

                RawDataCard(
                    title: "Rango de Magnitud",
                    value: "\(String(format: "%.1f", magnitudes.min() ?? 0))-\(String(format: "%.1f", magnitudes.max() ?? 0)) Ω",
                    subtitle: "Rango de impedancia",
                    color: .orange
                )

                RawDataCard(
                    title: "Rango de Fase",
                    value: "\(String(format: "%.1f", phases.min() ?? 0))° a \(String(format: "%.1f", phases.max() ?? 0))°",
                    subtitle: "Variación de fase",
                    color: .purple
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct RawDataCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Processing Status Section

private struct ProcessingStatusSection: View {
    let measurement: RawMeasurement

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estado de Procesamiento")
                .font(.headline)
                .fontWeight(.semibold)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estado Actual")
                        .font(.subheadline)
                    HStack {
                        ProcessingStatusBadge(state: measurement.processingState)
                        Text(statusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            if let error = measurement.processingError {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detalles del Error")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }

            Text("Los datos crudos están disponibles inmediatamente después de la medición. El procesamiento proporciona análisis de Cole y puede verse después.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusDescription: String {
        switch measurement.processingState {
        case .pending:
            return "Esperando procesamiento"
        case .processing:
            return "Analizando..."
        case .completed:
            return "Análisis completo"
        case .failed:
            return "Procesamiento fallido"
        case .retrying:
            return "Reintentando análisis"
        }
    }
}

// MARK: - Cole Results Section

private struct ColeResultsSection: View {
    let results: ColeParameters

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Análisis de Cole")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                // Validation indicator
                ValidationBadge(re: results.Re, ri: results.Ri)
            }

            // Main Cole parameters in a grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ColeParameterCard(
                    title: "Re (Extracelular)",
                    value: String(format: "%.1f Ω", results.Re),
                    description: "Resistencia extracelular",
                    color: .blue
                )

                ColeParameterCard(
                    title: "Ri (Intracelular)",
                    value: String(format: "%.1f Ω", results.Ri),
                    description: "Resistencia intracelular",
                    color: .green
                )

                ColeParameterCard(
                    title: "fc (Frecuencia)",
                    value: String(format: "%.2f kHz", results.fc),
                    description: "Frecuencia característica",
                    color: .orange
                )

                ColeParameterCard(
                    title: "Cm (Membrana)",
                    value: String(format: "%.2f nF", results.Cm),
                    description: "Capacitancia de membrana",
                    color: .purple
                )

                ColeParameterCard(
                    title: "α (Dispersión)",
                    value: String(format: "%.3f", results.alpha),
                    description: "Parámetro de dispersión",
                    color: .cyan
                )
            }

            // Derived parameters
            VStack(alignment: .leading, spacing: 8) {
                Text("Parámetros Derivados")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("R0 (DC)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f Ω", results.R0))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    VStack(alignment: .leading) {
                        Text("R∞ (HF)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f Ω", results.Rinf))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    VStack(alignment: .leading) {
                        Text("Ratio ICW/ECW")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f", results.Ri / results.Re))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ColeParameterCard: View {
    let title: String
    let value: String
    let description: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .minimumScaleFactor(0.7)

            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Validation Badge

private struct ValidationBadge: View {
    let re: Float
    let ri: Float
    @State private var showingDetail = false

    private var isReInRange: Bool {
        re >= 10 && re <= 70
    }

    private var isRiInRange: Bool {
        ri >= 10 && ri <= 70
    }

    private var isValid: Bool {
        isReInRange && isRiInRange
    }

    private var issueDescription: String {
        var issues: [String] = []
        if !isReInRange {
            issues.append("Re (\(String(format: "%.1f", re))Ω) fuera de rango 10-70Ω")
        }
        if !isRiInRange {
            issues.append("Ri (\(String(format: "%.1f", ri))Ω) fuera de rango 10-70Ω")
        }
        return issues.joined(separator: "\n")
    }

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                Text(isValid ? "Correcta" : "Revisar")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isValid ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isValid ? Color.green.opacity(0.1) : Color.orange.opacity(0.1), in: Capsule())
        }
        .alert(isValid ? "Medición correcta" : "Valores inusuales", isPresented: $showingDetail) {
            Button("OK", role: .cancel) { }
        } message: {
            if isValid {
                Text("Re y Ri están dentro del rango esperado (10-70Ω)")
            } else {
                Text(issueDescription + "\n\nSe recomienda repetir la medición.")
            }
        }
    }
}

// MARK: - Export Section

private struct ExportSection: View {
    let measurement: RawMeasurement
    @State private var showingShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exportar")
                .font(.headline)

            Button {
                showingShareSheet = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Exportar CSV")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingShareSheet) {
            if let url = generateCSV() {
                ShareSheet(items: [url])
            }
        }
    }

    private func generateCSV() -> URL? {
        var csv = "Repetition,Frequency(Hz),Magnitude(Ω),Phase(°)\n"

        for (index, repetition) in measurement.rawData.repetitions.enumerated() {
            for point in repetition {
                csv += "\(index + 1),\(point.frequency),\(point.magnitude),\(point.phase)\n"
            }
        }

        // Add Cole parameters if available
        if let results = measurement.results {
            csv += "\n# Cole Parameters\n"
            csv += "Re(Ω),\(results.Re)\n"
            csv += "Ri(Ω),\(results.Ri)\n"
            csv += "Cm(nF),\(results.Cm)\n"
            csv += "fc(kHz),\(results.fc)\n"
            csv += "alpha,\(results.alpha)\n"
        }

        let fileName = "measurement_\(ISO8601DateFormatter().string(from: measurement.captureTimestamp)).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }
}

// MARK: - Raw Data Plots Section

private struct RawDataPlotsSection: View {
    let measurement: RawMeasurement
    let displayData: ImpedanceData
    @Binding var selectedRepetition: Int

    private var totalRepetitions: Int {
        measurement.repetitions?.count ?? 1
    }

    private var hasMultipleRepetitions: Bool {
        totalRepetitions > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with inline repetition selector
            HStack {
                Text("Respuesta en Frecuencia (Cruda)")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                // Compact inline repetition selector
                if hasMultipleRepetitions {
                    HStack(spacing: 4) {
                        Button {
                            if selectedRepetition > 0 {
                                selectedRepetition -= 1
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption.bold())
                                .foregroundStyle(selectedRepetition > 0 ? .blue : .gray.opacity(0.3))
                        }
                        .disabled(selectedRepetition == 0)

                        Text("\(selectedRepetition + 1)/\(totalRepetitions)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                            .frame(minWidth: 35)

                        Button {
                            if selectedRepetition < totalRepetitions - 1 {
                                selectedRepetition += 1
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(selectedRepetition < totalRepetitions - 1 ? .blue : .gray.opacity(0.3))
                        }
                        .disabled(selectedRepetition == totalRepetitions - 1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1), in: Capsule())
                }
            }

            // Subheader info
            HStack(spacing: 8) {
                Text("\(displayData.measurements.count) puntos")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            }

            // Raw plots
            VStack(spacing: 20) {
                // Resistance plot
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resistencia (Ω)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if #available(iOS 16.0, *) {
                        RawResistancePlot(displayData: displayData)
                            .frame(height: 200)
                    } else {
                        PlaceholderPlot(title: "Resistencia vs Frecuencia")
                            .frame(height: 200)
                    }
                }

                // Reactance plot
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reactancia (Ω)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if #available(iOS 16.0, *) {
                        RawReactancePlot(displayData: displayData)
                            .frame(height: 200)
                    } else {
                        PlaceholderPlot(title: "Reactancia vs Frecuencia")
                            .frame(height: 200)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Placeholder Plot for older iOS versions

private struct PlaceholderPlot: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.gray.opacity(0.5))

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Gráficos disponibles en iOS 16+")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Raw Resistance Plot

@available(iOS 16.0, *)
private struct RawResistancePlot: View {
    let displayData: ImpedanceData
    @State private var selectedXValue: Double? = nil

    var body: some View {
        makeChart()
    }

    @ViewBuilder
    private func makeChart() -> some View {
        let frequencies = logarithmicFrequencies
        let freqRange = frequencyRange
        let yScale = resistanceYScale

        Chart {
            createMeasurementPoints()
            createSelectionIndicator()
        }
        .background(chartBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .chartXScale(domain: freqRange, type: .log)
        .chartYScale(domain: yScale)
        .chartXAxis { createXAxis(frequencies: frequencies) }
        .chartYAxis { createYAxis() }
        .chartXSelection(value: chartSelection)
        .chartGesture { proxy in
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    proxy.selectXValue(at: value.location.x)
                }
                .onEnded { _ in
                    selectedXValue = nil
                }
        }
        .overlay(alignment: .topTrailing) {
            createTooltip()
        }
    }

    private var logarithmicFrequencies: [Double] {
        [1000, 5000, 10000, 50000, 100000, 150000]
    }

    private var frequencyRange: ClosedRange<Double> {
        let frequencies = displayData.frequencies
        let minFreq = Double(frequencies.min() ?? 1000)
        let maxFreq = Double(frequencies.max() ?? 150000)
        return (minFreq * 0.8)...(maxFreq * 1.2)
    }

    private var resistanceYScale: ClosedRange<Double> {
        let resistances = displayData.measurements.map { Double($0.complexImpedance.real) }
        let minR = resistances.min() ?? 10.0
        let maxR = resistances.max() ?? 100.0
        let range = maxR - minR
        let padding = range * 0.15
        return (minR - padding)...(maxR + padding)
    }

    private var chartBackground: LinearGradient {
        LinearGradient(
            colors: [Color.systemGray6.opacity(0.1), Color.systemGray6.opacity(0.3)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var chartSelection: Binding<Double?> {
        .init(
            get: { selectedXValue },
            set: { newValue in
                selectedXValue = newValue
                #if os(iOS)
                if newValue != nil {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                }
                #endif
            }
        )
    }

    @ChartContentBuilder
    private func createMeasurementPoints() -> some ChartContent {
        ForEach(Array(displayData.measurements.enumerated()), id: \.offset) { index, point in
            let freq = Double(point.frequency)
            let resistance = Double(point.complexImpedance.real)
            let isSelected = selectedXValue != nil && abs(freq - selectedXValue!) < (freq * 0.1)

            PointMark(
                x: .value("Frequency", freq),
                y: .value("Resistance", resistance)
            )
            .foregroundStyle(isSelected ? .orange : .blue)
            .symbol(isSelected ? .diamond : .circle)
            .symbolSize(isSelected ? 120 : 80)
            .opacity(0.9)
        }
    }

    @ChartContentBuilder
    private func createSelectionIndicator() -> some ChartContent {
        if let selectedX = selectedXValue {
            RuleMark(x: .value("Selection", selectedX))
                .foregroundStyle(.gray.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }

    @AxisContentBuilder
    private func createXAxis(frequencies: [Double]) -> some AxisContent {
        AxisMarks(values: frequencies) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(.gray.opacity(0.3))
            AxisValueLabel {
                if let freq = value.as(Double.self) {
                    if freq >= 1000 {
                        Text("\(Int(freq/1000))k")
                            .font(.caption)
                            .fontWeight(.medium)
                    } else {
                        Text("\(Int(freq))")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }

    @AxisContentBuilder
    private func createYAxis() -> some AxisContent {
        AxisMarks { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(.gray.opacity(0.3))
            AxisValueLabel {
                if let r = value.as(Double.self) {
                    Text("\(Int(r))Ω")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
    }

    @ViewBuilder
    private func createTooltip() -> some View {
        if let selectedX = selectedXValue,
           let point = findClosestDataPoint(frequency: selectedX) {
            RawTooltipView(
                frequency: point.frequency,
                resistance: Double(point.complexImpedance.real)
            )
            .padding(8)
        }
    }

    private func findClosestDataPoint(frequency: Double) -> ImpedanceData.MeasurementPoint? {
        return displayData.measurements.min { point1, point2 in
            abs(Double(point1.frequency) - frequency) < abs(Double(point2.frequency) - frequency)
        }
    }
}

// MARK: - Raw Reactance Plot

@available(iOS 16.0, *)
private struct RawReactancePlot: View {
    let displayData: ImpedanceData
    @State private var selectedXValue: Double? = nil

    var body: some View {
        makeChart()
    }

    @ViewBuilder
    private func makeChart() -> some View {
        let frequencies = logarithmicFrequencies
        let freqRange = frequencyRange
        let yScale = reactanceYScale

        Chart {
            createReactanceMeasurementPoints()
            createReactanceSelectionIndicator()
        }
        .background(chartBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .chartXScale(domain: freqRange, type: .log)
        .chartYScale(domain: yScale)
        .chartXAxis { createReactanceXAxis(frequencies: frequencies) }
        .chartYAxis { createReactanceYAxis() }
        .chartXSelection(value: reactanceChartSelection)
        .chartGesture { proxy in
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    proxy.selectXValue(at: value.location.x)
                }
                .onEnded { _ in
                    selectedXValue = nil
                }
        }
        .overlay(alignment: .topTrailing) {
            createReactanceTooltip()
        }
    }

    private var logarithmicFrequencies: [Double] {
        [1000, 5000, 10000, 50000, 100000, 150000]
    }

    private var frequencyRange: ClosedRange<Double> {
        let frequencies = displayData.frequencies
        let minFreq = Double(frequencies.min() ?? 1000)
        let maxFreq = Double(frequencies.max() ?? 150000)
        return (minFreq * 0.8)...(maxFreq * 1.2)
    }

    private var reactanceYScale: ClosedRange<Double> {
        let reactances = displayData.measurements.map { Double($0.complexImpedance.imaginary) }
        let minX = reactances.min() ?? 0.0
        let maxX = reactances.max() ?? 20.0
        let range = maxX - minX
        let padding = max(range * 0.15, 2.0)
        return (minX - padding)...(maxX + padding)
    }

    private var chartBackground: LinearGradient {
        LinearGradient(
            colors: [Color.systemGray6.opacity(0.1), Color.systemGray6.opacity(0.3)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var reactanceChartSelection: Binding<Double?> {
        .init(
            get: { selectedXValue },
            set: { newValue in
                selectedXValue = newValue
                #if os(iOS)
                if newValue != nil {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                }
                #endif
            }
        )
    }

    @ChartContentBuilder
    private func createReactanceMeasurementPoints() -> some ChartContent {
        ForEach(Array(displayData.measurements.enumerated()), id: \.offset) { index, point in
            let freq = Double(point.frequency)
            let reactance = Double(point.complexImpedance.imaginary)
            let isSelected = selectedXValue != nil && abs(freq - selectedXValue!) < (freq * 0.1)

            PointMark(
                x: .value("Frequency", freq),
                y: .value("Reactance", reactance)
            )
            .foregroundStyle(isSelected ? .orange : .red)
            .symbol(isSelected ? .diamond : .circle)
            .symbolSize(isSelected ? 120 : 80)
            .opacity(0.9)
        }
    }

    @ChartContentBuilder
    private func createReactanceSelectionIndicator() -> some ChartContent {
        if let selectedX = selectedXValue {
            RuleMark(x: .value("Selection", selectedX))
                .foregroundStyle(.gray.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }

    @AxisContentBuilder
    private func createReactanceXAxis(frequencies: [Double]) -> some AxisContent {
        AxisMarks(values: frequencies) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(.gray.opacity(0.3))
            AxisValueLabel {
                if let freq = value.as(Double.self) {
                    if freq >= 1000 {
                        Text("\(Int(freq/1000))k")
                            .font(.caption)
                            .fontWeight(.medium)
                    } else {
                        Text("\(Int(freq))")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }

    @AxisContentBuilder
    private func createReactanceYAxis() -> some AxisContent {
        AxisMarks { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(.gray.opacity(0.3))
            AxisValueLabel {
                if let x = value.as(Double.self) {
                    Text("\(String(format: "%.1f", x))Ω")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
    }

    @ViewBuilder
    private func createReactanceTooltip() -> some View {
        if let selectedX = selectedXValue,
           let point = findClosestDataPoint(frequency: selectedX) {
            RawTooltipView(
                frequency: point.frequency,
                reactance: Double(point.complexImpedance.imaginary)
            )
            .padding(8)
        }
    }

    private func findClosestDataPoint(frequency: Double) -> ImpedanceData.MeasurementPoint? {
        return displayData.measurements.min { point1, point2 in
            abs(Double(point1.frequency) - frequency) < abs(Double(point2.frequency) - frequency)
        }
    }
}

// MARK: - Raw Tooltip View

private struct RawTooltipView: View {
    let frequency: Float
    let resistance: Double?
    let reactance: Double?

    init(frequency: Float, resistance: Double) {
        self.frequency = frequency
        self.resistance = resistance
        self.reactance = nil
    }

    init(frequency: Float, reactance: Double) {
        self.frequency = frequency
        self.resistance = nil
        self.reactance = reactance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let reactance = reactance {
                Text("Reactancia")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("\(String(format: "%.1f", reactance)) Ω")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
            } else if let resistance = resistance {
                Text("Resistencia")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("\(String(format: "%.1f", resistance)) Ω")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }

            Text("Frecuencia")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(formatFrequency(Double(frequency)))
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }

    private func formatFrequency(_ freq: Double) -> String {
        if freq >= 1000 {
            return "\(String(format: "%.1f", freq/1000)) kHz"
        } else {
            return "\(Int(freq)) Hz"
        }
    }
}

// MARK: - Export Section


// MARK: - Processing Status Badge

private struct ProcessingStatusBadge: View {
    let state: RawMeasurement.ProcessingState

    var body: some View {
        HStack {
            statusIcon
            Text(state.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(statusColor)
    }

    private var statusIcon: some View {
        Group {
            switch state {
            case .pending:
                Image(systemName: "clock")
            case .processing:
                Image(systemName: "gear")
            case .completed:
                Image(systemName: "checkmark.circle.fill")
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
            case .retrying:
                Image(systemName: "arrow.clockwise")
            }
        }
        .font(.caption)
    }

    private var statusColor: Color {
        switch state {
        case .pending: return .orange
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        case .retrying: return .blue
        }
    }
}

// MARK: - Uses existing ShareSheet and DateFormatter from MeasurementDetailView

// MARK: - Previews

#Preview("Raw Measurement") {
    NavigationStack {
        RawMeasurementDetailView(measurement: SampleRawMeasurements.sampleRawMeasurement)
    }
}

// MARK: - Sample Data for Previews

struct SampleRawMeasurements {
    static let sampleRawMeasurement: RawMeasurement = {
        // Create sample impedance data
        let measurements = (1...20).map { i in
            let freq = Float(1000 + i * 7500) // 1kHz to 150kHz
            let mag = Float(40.0 - Double(i) * 0.9) // Decreasing magnitude
            let phase = Float(-2.0 - Double(i) * 0.3) // Increasingly negative phase
            return ImpedanceData.MeasurementPoint(frequency: freq, magnitude: mag, phase: phase)
        }

        let impedanceData = ImpedanceData(
            measurements: measurements,
            timestamp: Date(),
            deviceInfo: DeviceInfo(name: "BioMess PCB v1.0", serialNumber: "BM001234")
        )

        return RawMeasurement(
            rawData: impedanceData,
            sessionId: UUID(),
            muscleGroup: "quadriceps",
            side: "left",
            perceivedFatigue: 6
        )
    }()
}
