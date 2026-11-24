import SwiftUI
import Charts
#if canImport(UIKit)
import UIKit
#endif

// MARK: - View States and Data Models

enum MeasurementViewState: Equatable {
    case disconnected
    case deviceSelection
    case connected
    case measuring
    case processing(ProcessingTier)
    case results
    case error(String)
}

struct MeasurementResults {
    let rawData: ImpedanceData
    let immediateResults: ColeParameters?
    let completeResults: ColeParameters?
    let processingTime: (immediate: TimeInterval, complete: TimeInterval?)
}

/// Main measurement view - handles entire measurement flow
public struct MeasurementView: View {
    @Environment(MockBioMessCoreBLEManager.self) private var bleManager
    @Environment(BioimpedanceProcessor.self) private var processor
    @State private var viewState: MeasurementViewState = .disconnected
    @State private var measurementResults: MeasurementResults?
    @State private var showingDeviceSelection = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            switch viewState {
            case .disconnected:
                DisconnectedView(onStateChange: { newState, results in
                    viewState = newState
                    measurementResults = results
                })
                
            case .deviceSelection:
                DeviceSelectionView()
                
            case .connected:
                ConnectedView()
                
            case .measuring:
                MeasuringView()
                
            case .processing(let tier):
                ProcessingView(tier: tier)
                
            case .results:
                if let results = measurementResults {
                    ResultsView(results: results) {
                        // Reset to disconnected state to return to main menu
                        viewState = .disconnected
                        measurementResults = nil
                    }
                }
                
            case .error(let message):
                ErrorView(message: message)
            }
        }
        .padding()
        .animation(.easeInOut(duration: 0.5), value: viewState)
        .onChange(of: bleManager.connectionState) { oldState, newState in
            updateViewState(from: newState)
        }
        .onAppear {
            updateViewState(from: bleManager.connectionState)
        }
    }
    
    private func updateViewState(from bleState: MockBioMessCoreBLEManager.ConnectionState) {
        switch bleState {
        case .disconnected:
            viewState = .disconnected
        case .scanning:
            viewState = .deviceSelection
        case .connecting:
            viewState = .deviceSelection
        case .connected:
            viewState = .connected
        case .measuring:
            viewState = .measuring
        case .error(let message):
            viewState = .error(message)
        }
    }
}

// MARK: - State Views

private struct DisconnectedView: View {
    @Environment(MockBioMessCoreBLEManager.self) private var bleManager
    @Environment(BioimpedanceProcessor.self) private var processor
    @State private var isRunningDemo = false
    @State private var demoResults: DemoResults?
    
    let onStateChange: (MeasurementViewState, MeasurementResults?) -> Void
    
    struct DemoResults {
        let data: ImpedanceData
        let parameters: ColeParameters
    }
    
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Image(systemName: "cross.vial.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue.gradient)
                
                Text("Ready to Measure")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Connect to your BioMess device to begin bioimpedance analysis")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Quick Demo Button (for development)
            Button(action: runQuickDemo) {
                HStack {
                    if isRunningDemo {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(isRunningDemo ? "Running Demo..." : "Quick Demo (3s)")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.green.gradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isRunningDemo)
            
            Button(action: {
                bleManager.startScanning()
            }) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Scan for Devices")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue.gradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Show demo results
            if let results = demoResults {
                DemoResultsCard(results: results)
            }
        }
        .padding(.horizontal)
    }
    
    private func runQuickDemo() {
        isRunningDemo = true
        demoResults = nil
        
        Task {
            do {
                // Simulate quick measurement
                try await Task.sleep(for: .seconds(2))
                
                // Generate realistic data
                let mockData = generateMockData()
                
                // Create mock parameters directly for demo
                let mockParameters = ColeParameters(
                    Re: 42.9,      // Extracellular resistance 
                    Ri: 25.3,      // Intracellular resistance
                    Cm: 1.24,      // Membrane capacitance (nF)
                    fc: 31.2,      // Characteristic frequency (kHz)
                    alpha: 0.823,   // Dispersion parameter
                    error: 2.1,     // Fit error (%)
                    processingTier: .immediate,
                    quality: QualityMetrics(
                        score: 0.92,
                        contactQuality: ContactQuality(electrodeImpedance: 1250, mismatchPercentage: 3.2),
                        signalQuality: SignalQuality(snr: 45.8, phaseStability: 1.2, frequencyResponse: .excellent),
                        convergence: ConvergenceMetrics(iterations: 12, residualError: 0.021, parameterErrors: ParameterErrors(reError: 0.8, riError: 1.2, cmError: 2.1, fcError: 1.5, alphaError: 0.6), converged: true),
                        stabilityMetrics: StabilityMetrics(movementDetected: false, quaternionStability: 0.002, impedanceStability: 0.015, interferenceLevel: .minimal)
                    )
                )
                
                await MainActor.run {
                    demoResults = DemoResults(data: mockData, parameters: mockParameters)
                    isRunningDemo = false
                    // Navigate to results screen
                    let results = MeasurementResults(
                        rawData: mockData,
                        immediateResults: mockParameters,
                        completeResults: nil,
                        processingTime: (immediate: 2.0, complete: nil)
                    )
                    onStateChange(.results, results)
                }
                
            } catch {
                await MainActor.run {
                    isRunningDemo = false
                }
                print("Demo failed: \(error)")
            }
        }
    }
    
    private func generateMockData() -> ImpedanceData {
        let measurements: [(frequency: Float, magnitude: Float, phase: Float)] = [
            (1000, 68.2, -1.2),
            (2000, 67.8, -2.1),
            (3000, 67.2, -3.0),
            (5000, 66.1, -4.2),
            (7000, 64.8, -5.1),
            (10000, 63.1, -6.2),
            (15000, 60.9, -7.8),
            (20000, 58.5, -8.9),
            (30000, 55.2, -9.8),
            (40000, 52.1, -10.1),
            (50000, 49.8, -9.7),
            (70000, 47.2, -8.9),
            (100000, 45.1, -7.8),
            (120000, 43.8, -6.9),
            (150000, 42.9, -5.8)
        ]
        
        let points = measurements.map { freq, mag, phase in
            ImpedanceData.MeasurementPoint(frequency: freq, magnitude: mag, phase: phase)
        }
        
        return ImpedanceData(measurements: points)
    }
}

private struct DeviceSelectionView: View {
    @Environment(MockBioMessCoreBLEManager.self) private var bleManager
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Text("Devices Available")
                    .font(.headline)
                Text("Select a device to connect")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            
            // Always show devices when in device selection view
            VStack(alignment: .leading, spacing: 12) {
                Text("Available Devices")
                    .font(.headline)
                
                ForEach(bleManager.discoveredDevices) { device in
                    DeviceRow(device: device) {
                        bleManager.connect(to: device)
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            
            Button("Cancel", action: {
                bleManager.stopScanning()
            })
            .foregroundStyle(.secondary)
        }
    }
}

private struct DeviceRow: View {
    let device: MockBioMessCoreBLEManager.MockDevice
    let onConnect: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                Text(device.serialNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("RSSI: \(device.rssi)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button("Connect", action: onConnect)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ConnectedView: View {
    @Environment(MockBioMessCoreBLEManager.self) private var bleManager
    @Environment(BioimpedanceProcessor.self) private var processor
    @State private var isMeasuring = false
    @Environment(\.navigationPath) private var navigationPath
    
    var body: some View {
        VStack(spacing: 30) {
            // Device info
            if let device = bleManager.connectedDevice {
                DeviceInfoCard(device: device)
            }
            
            // Measurement instructions
            InstructionCard()
            
            // Start measurement button
            Button(action: startMeasurement) {
                HStack {
                    if isMeasuring {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(isMeasuring ? "Measuring..." : "Start Measurement")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isMeasuring ? Color.gray.gradient : Color.green.gradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isMeasuring)
            
            // Test connection button
            Button("Test Connection") {
                Task {
                    await bleManager.testConnection()
                }
            }
            .foregroundStyle(.blue)
            
            // Disconnect button
            Button("Disconnect") {
                bleManager.disconnect()
            }
            .foregroundStyle(.red)
        }
    }
    
    private func startMeasurement() {
        isMeasuring = true
        
        Task { @MainActor in
            do {
                // This will trigger the measuring state via state observation
                let _ = try await bleManager.performMeasurement()
                isMeasuring = false
                
                // Navigate to processing/results view
                navigationPath.wrappedValue.append("results")
                
            } catch {
                isMeasuring = false
                // Handle error
                print("Measurement failed: \(error)")
            }
        }
    }
}

private struct DeviceInfoCard: View {
    let device: MockBioMessCoreBLEManager.MockDevice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Connected")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Device: \(device.name)")
                Text("Serial: \(device.serialNumber)")
                Text("Signal: \(device.rssi) dBm")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct InstructionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Measurement Instructions")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                InstructionRow("1", "Place electrodes on calf segment")
                InstructionRow("2", "Ensure good skin contact")
                InstructionRow("3", "Remain still during measurement")
                InstructionRow("4", "Total time: ~3 seconds (mock)")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct InstructionRow: View {
    let number: String
    let text: String
    
    init(_ number: String, _ text: String) {
        self.number = number
        self.text = text
    }
    
    var body: some View {
        HStack {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 20, height: 20)
                .background(.blue, in: Circle())
                .foregroundStyle(.white)
            
            Text(text)
                .font(.caption)
        }
    }
}

private struct MeasuringView: View {
    @State private var progress: Double = 0
    @State private var currentPhase = "Initializing..."
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)
                .symbolEffect(.pulse, value: progress)
            
            VStack(spacing: 12) {
                Text("Measuring Bioimpedance")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(currentPhase)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .frame(maxWidth: 200)
            
            Text("Please remain still")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .onAppear {
            simulateMeasurementProgress()
        }
    }
    
    private func simulateMeasurementProgress() {
        let phases = [
            (1.0, "Starting measurement..."),
            (2.0, "Collecting data..."),
            (0.5, "Finalizing...")
        ]
        
        var totalTime: Double = 0
        
        for (duration, phase) in phases {
            Timer.scheduledTimer(withTimeInterval: totalTime, repeats: false) { _ in
                Task { @MainActor in
                    currentPhase = phase
                }
            }
            totalTime += duration
        }
        
        // Animate progress
        withAnimation(.linear(duration: totalTime)) {
            progress = 1.0
        }
    }
}

private struct ProcessingView: View {
    let tier: ProcessingTier
    @State private var progress: Double = 0
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "cpu")
                .font(.system(size: 64))
                .foregroundStyle(.orange.gradient)
                .rotationEffect(.degrees(progress * 360))
            
            VStack(spacing: 12) {
                Text("Processing Data")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Applying \(tier.description) analysis")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                .frame(maxWidth: 200)
        }
        .onAppear {
            // Simulate processing time based on tier
            let duration = tier == .immediate ? 1.0 : 5.0
            withAnimation(.linear(duration: duration)) {
                progress = 1.0
            }
        }
    }
}

private struct ResultsView: View {
    let results: MeasurementResults
    let onDismiss: () -> Void
    @Environment(MockBioMessCoreBLEManager.self) private var bleManager
    @Environment(MeasurementStorageService.self) private var storageService
    @State private var showingSaveAlert = false
    @State private var saveError: Error?
    
    var body: some View {
        ScrollView {
                VStack(spacing: 24) {
                    // Bode Plot (directly show the plot without success message)
                    BodePlotView(data: results.rawData)
                    
                    // Cole Parameters
                    if let immediate = results.immediateResults {
                        ParameterCard(parameters: immediate, title: "Cole Analysis")
                    }
                    
                    // Processing Info
                    ProcessingInfoCard(results: results)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button("New Measurement") {
                            // Reset to disconnected state for new measurement
                            bleManager.disconnect()
                            onDismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        Button("Export Data") {
                            // TODO: Implement export functionality
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.gray.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 100) // Extra padding for safe scrolling
        }
        .navigationTitle("Results")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: {
                #if os(iOS)
                .topBarTrailing
                #else
                .primaryAction
                #endif
            }()) {
                Button("Done") {
                    saveMeasurementAndDismiss()
                }
            }
        }
        // Support landscape orientation for better chart viewing
        .onAppear {
            #if os(iOS)
            // Allow rotation to landscape for better chart visibility
            UIDevice.current.setValue(UIInterfaceOrientation.unknown.rawValue, forKey: "orientation")
            #endif
        }
        .alert("Save Error", isPresented: $showingSaveAlert) {
            Button("OK") { }
        } message: {
            if let error = saveError {
                Text("Failed to save measurement: \(error.localizedDescription)")
            }
        }
    }
    
    private func saveMeasurementAndDismiss() {
        guard let parameters = results.immediateResults ?? results.completeResults else {
            bleManager.disconnect()
            onDismiss()
            return
        }
        
        Task {
            do {
                // Get device info from BLE manager or use defaults
                let deviceName = bleManager.connectedDevice?.name ?? "Demo Device"
                let deviceSerial = bleManager.connectedDevice?.serialNumber ?? "DEMO-001"
                
                // Save measurement
                try storageService.saveMeasurement(
                    parameters: parameters,
                    deviceName: deviceName,
                    deviceSerialNumber: deviceSerial,
                    processingTime: results.processingTime.immediate,
                    rawData: results.rawData
                )
                
                print("Successfully saved measurement to history")
                
                // Disconnect and return to main menu
                await MainActor.run {
                    bleManager.disconnect()
                    onDismiss()
                }
                
            } catch {
                await MainActor.run {
                    saveError = error
                    showingSaveAlert = true
                    print("Failed to save measurement: \(error)")
                }
            }
        }
    }
}

private struct ParameterCard: View {
    let parameters: ColeParameters
    let title: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                QualityBadge(score: parameters.quality.score)
            }
            
            VStack(spacing: 8) {
                ParameterRow("Re (Extracellular)", String(format: "%.1f Ω", parameters.Re))
                ParameterRow("Ri (Intracellular)", String(format: "%.1f Ω", parameters.Ri)) 
                ParameterRow("Cm (Membrane)", String(format: "%.2f nF", parameters.Cm))
                ParameterRow("fc (Characteristic)", String(format: "%.1f kHz", parameters.fc))
                ParameterRow("α (Dispersion)", String(format: "%.3f", parameters.alpha))
                ParameterRow("Fit Error", String(format: "%.2f%%", parameters.error))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ParameterRow: View {
    let label: String
    let value: String
    
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
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
        if score >= 0.9 { return "Excellent" }
        if score >= 0.8 { return "Good" }
        if score >= 0.6 { return "Fair" }
        return "Poor"
    }
    
    private var qualityColor: Color {
        if score >= 0.9 { return .green }
        if score >= 0.8 { return .blue }
        if score >= 0.6 { return .orange }
        return .red
    }
}

private struct ErrorView: View {
    let message: String
    @Environment(MockBioMessCoreBLEManager.self) private var bleManager
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            
            Text("Error")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                bleManager.disconnect()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private struct DemoResultsCard: View {
    let results: DisconnectedView.DemoResults
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Demo Results")
                    .font(.headline)
                Spacer()
                QualityBadge(score: results.parameters.quality.score)
            }
            
            VStack(spacing: 8) {
                ParameterRow("Re (Extracellular)", String(format: "%.1f Ω", results.parameters.Re))
                ParameterRow("Ri (Intracellular)", String(format: "%.1f Ω", results.parameters.Ri)) 
                ParameterRow("Cm (Membrane)", String(format: "%.2f nF", results.parameters.Cm))
                ParameterRow("fc (Characteristic)", String(format: "%.1f kHz", results.parameters.fc))
                ParameterRow("α (Dispersion)", String(format: "%.3f", results.parameters.alpha))
                ParameterRow("Fit Error", String(format: "%.2f%%", results.parameters.error))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Bode Plot View

public struct BodePlotView: View {
    let data: ImpedanceData
    @State private var selectedTab = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    // Check if we're in landscape orientation
    private var isLandscape: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bode Plot Analysis")
                .font(.headline)
                .padding(.horizontal)
            
            // Tab selector
            Picker("Plot Type", selection: $selectedTab) {
                Text("Resistance").tag(0)
                Text("Reactance").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Enhanced Plot area with landscape support
            VStack {
                if selectedTab == 0 {
                    SwiftChartsResistancePlotView(data: data)
                } else {
                    SwiftChartsReactancePlotView(data: data)
                }
            }
            .frame(height: isLandscape ? 400 : 250)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            
            // Frequency range info
            HStack {
                Text("Frequency Range:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formatFrequency(data.frequencies.first ?? 0)) - \(formatFrequency(data.frequencies.last ?? 0))")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal)
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

// MARK: - Enhanced Swift Charts Implementation

private struct SwiftChartsResistancePlotView: View {
    let data: ImpedanceData
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

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
            Text("Frequency (Hz)")
                .font(isLandscape ? .caption : .caption2)
                .foregroundStyle(.secondary)
        }
        .chartYAxisLabel(position: .leading, alignment: .center) {
            Text("Resistance (Ω)")
                .font(isLandscape ? .caption : .caption2)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(180))
        }
        .padding()
    }
}

private struct SwiftChartsReactancePlotView: View {
    let data: ImpedanceData
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

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
            Text("Frequency (Hz)")
                .font(isLandscape ? .caption : .caption2)
                .foregroundStyle(.secondary)
        }
        .chartYAxisLabel(position: .leading, alignment: .center) {
            Text("Reactance (Ω)")
                .font(isLandscape ? .caption : .caption2)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(180))
        }
        .padding()
    }
}


// MARK: - Processing Info Card

private struct ProcessingInfoCard: View {
    let results: MeasurementResults
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processing Information")
                .font(.headline)
            
            VStack(spacing: 8) {
                HStack {
                    Text("Processing Time:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f seconds", results.processingTime.immediate))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Data Points:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(results.rawData.measurements.count) frequencies")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Algorithm:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Cole Model (Immediate)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                if let quality = results.immediateResults?.quality {
                    HStack {
                        Text("Signal Quality:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("SNR: \(String(format: "%.1f", quality.signalQuality.snr)) dB")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}


#Preview {
    NavigationStack {
        MeasurementView()
            .environment(MockBioMessCoreBLEManager())
            .environment(BioimpedanceProcessor())
    }
}