import SwiftUI
import BioMessCore
@preconcurrency import CoreBluetooth
#if os(iOS)
import UIKit
#endif

/// Custom error for handling processing failures with data recovery
enum ProcessingRecoveryError: LocalizedError {
    case allProcessingFailed(rawDataAvailable: Bool, underlyingError: String)
    case partialProcessingFailure(availableResults: String, underlyingError: String)

    var errorDescription: String? {
        switch self {
        case .allProcessingFailed(let rawDataAvailable, _):
            return rawDataAvailable
                ? "El procesamiento falló pero los datos crudos fueron preservados"
                : "Fallo completo de medición"
        case .partialProcessingFailure(_, let underlyingError):
            return "Fallo parcial de procesamiento" + ": \(underlyingError)"
        }
    }

    var userMessage: String {
        switch self {
        case .allProcessingFailed(let rawDataAvailable, let underlyingError):
            if rawDataAvailable {
                return "Medición completada pero el análisis falló" + "\n\n" + "Error" + ": \(underlyingError)"
            } else {
                return "La medición falló completamente" + "\n\n" + "Error" + ": \(underlyingError)"
            }
        case .partialProcessingFailure(let availableResults, let underlyingError):
            return "Medición parcialmente exitosa" + " \(availableResults) " + "disponible" + "\n\n" + "Problema" + ": \(underlyingError)"
        }
    }
}

/// Main measurement view - handles entire measurement flow
struct MeasurementView: View {
    @Environment(BioMessBLEManager.self) private var bleManager
    @Environment(BioimpedanceProcessor.self) private var processor
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var viewState: ViewState = .disconnected
    @State private var measurementResults: MeasurementResults?
    @State private var showingDeviceSelection = false
    @State private var currentMeasurementNumber: Int = 1
    @State private var currentSessionPatient: String = ""
    @State private var currentSessionExercise: String = ""
    @Binding private var selectedTab: Int

    /// When true, hides PatientFormCard and enables session-based measurement saving
    private let laboratoryMode: Bool
    private let embeddedMode: Bool

    // MARK: - Session Context (passed from MeasurementFlowViewModel when embedded)

    /// Session to link measurement to
    private let session: MeasurementSession?

    /// Muscle group being measured
    private let muscleGroup: String?

    /// Side (left/right)
    private let side: String?

    /// Perceived fatigue for this muscle
    private let perceivedFatigue: Int?

    /// Callback when measurement completes (passes the saved measurement ID)
    var onMeasurementComplete: ((UUID?) -> Void)?

    /// Optional flow VM used to register the save Task so `cleanupIfEmpty`
    /// waits for the save before counting (race-safe). Legacy basal/match
    /// callers that don't run inside `MeasurementFlowView` pass `nil`.
    private let flowViewModel: MeasurementFlowViewModel?

    init(
        selectedTab: Binding<Int> = .constant(0),
        laboratoryMode: Bool = false,
        embeddedMode: Bool = true,  // Always use embedded mode (via MeasurementFlowView) for athlete/session context
        session: MeasurementSession? = nil,
        muscleGroup: String? = nil,
        side: String? = nil,
        perceivedFatigue: Int? = nil,
        flowViewModel: MeasurementFlowViewModel? = nil,
        onMeasurementComplete: ((UUID?) -> Void)? = nil
    ) {
        self._selectedTab = selectedTab
        self.laboratoryMode = laboratoryMode
        self.embeddedMode = embeddedMode
        self.session = session
        self.muscleGroup = muscleGroup
        self.side = side
        self.perceivedFatigue = perceivedFatigue
        self.flowViewModel = flowViewModel
        self.onMeasurementComplete = onMeasurementComplete
    }
    
    enum ViewState: Equatable {
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
    
    var body: some View {
        ZStack {
            Color.systemGroupedBackground
                .ignoresSafeArea()

            switch viewState {
            case .disconnected:
                DisconnectedView()

            case .deviceSelection:
                DeviceSelectionView()

            case .connected:
                ConnectedView(
                    currentMeasurementNumber: $currentMeasurementNumber,
                    currentSessionPatient: $currentSessionPatient,
                    currentSessionExercise: $currentSessionExercise,
                    laboratoryMode: laboratoryMode,
                    embeddedMode: embeddedMode,
                    autoStart: embeddedMode,
                    session: session,
                    muscleGroup: muscleGroup,
                    side: side,
                    perceivedFatigue: perceivedFatigue,
                    flowViewModel: flowViewModel,
                    onMeasurementComplete: { results in
                        measurementResults = results
                        viewState = .results
                    },
                    onMeasurementSaved: onMeasurementComplete
                )

            case .measuring:
                MeasuringView(onCancel: {
                    Task { await bleManager.forceDisconnectAndReset() }
                })

            case .processing(let tier):
                ProcessingView(tier: tier)

            case .results:
                if let results = measurementResults {
                    ResultsView(
                        results: results,
                        onReset: resetToConnected,
                        onViewHistory: {
                            if laboratoryMode { dismiss() } else { selectedTab = 3 }
                        }
                    )
                }

            case .error(let message):
                ErrorView(message: message)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: viewState)
        .onChange(of: bleManager.connectionState) { oldState, newState in
            updateViewState(from: newState)
        }
        .onAppear {
            updateViewState(from: bleManager.connectionState)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                bleManager.cancelStreamingMeasurement()
            }
            // When app returns to foreground, try to auto-connect if disconnected
            if newPhase == .active && oldPhase != .active {
                if bleManager.connectionState == .disconnected {
                    bleManager.startAutoConnectIfNeeded()
                }
            }
        }
    }
    
    private func updateViewState(from bleState: BioMessBLEManager.ConnectionState) {
        switch bleState {
        case .disconnected:
            viewState = .disconnected
        case .scanning:
            viewState = .deviceSelection
        case .connecting:
            viewState = .deviceSelection
        case .connected:
            // Don't override results or measuring state.
            // When a measurement completes, BLE state transitions to .connected
            // BEFORE the measurement processing Task finishes setting measurementResults.
            // If we switch to .connected here, ConnectedView is recreated with autoStart,
            // triggering a second measurement.
            if measurementResults == nil && viewState != .measuring {
                viewState = .connected
            }
        case .measuring:
            viewState = .measuring
        case .error(let message):
            viewState = .error(message)
        }
    }

    private func resetToConnected() {
        measurementResults = nil
        // Increment measurement number for the next measurement in the same session
        currentMeasurementNumber += 1
        viewState = .connected
    }

    private var bleConnectionState: BLEConnectionState {
        switch bleManager.connectionState {
        case .disconnected:
            return .disconnected
        case .scanning, .connecting:
            return .connecting
        case .connected, .measuring:
            return .connected
        case .error:
            return .disconnected
        }
    }
}

// MARK: - State Views

private struct DisconnectedView: View {
    @Environment(BioMessBLEManager.self) private var bleManager
    @Environment(BioimpedanceProcessor.self) private var processor
    @State private var isRunningDemo = false
    @State private var demoResults: DemoResults?
    
    struct DemoResults {
        let data: ImpedanceData
        let parameters: ColeParameters
    }
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Icon - matches NeedsAthleteView / NeedsSessionView pattern
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "cross.vial.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.brandPrimary)
            }

            // Text
            VStack(spacing: 12) {
                Text("Listo para Medir")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Conecta tu dispositivo para comenzar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Auto-connection status
            autoConnectStatusView

            // Main Action Button
            Button(action: {
                bleManager.startScanning()
            }) {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Buscar Dispositivos")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.brandPrimary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 48)

            // Quick Demo Button (subtle link style)
            Button(action: runQuickDemo) {
                HStack(spacing: 6) {
                    if isRunningDemo {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "play.circle")
                    }
                    Text(isRunningDemo ? "Ejecutando demo..." : "Demo Rápida")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .disabled(isRunningDemo)

            // Show demo results
            if let results = demoResults {
                DemoResultsCard(results: results)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
    }
    /// Auto-connect status indicator view
    @ViewBuilder
    private var autoConnectStatusView: some View {
        switch bleManager.autoConnectStatus {
        case .searching:
            // Actively searching for device
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                if let pairedDevice = PairedDeviceManager.pairedDevice {
                    Text(String(format: "Buscando %@...", pairedDevice.name))
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else {
                    Text("Buscando dispositivo emparejado...")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

        case .failed:
            // Search failed - show retry option
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("No se encontró el dispositivo")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }

                Text("Asegúrate de que la pila está puesta e inténtalo de nuevo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: {
                    bleManager.retryAutoConnect()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Reintentar")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
            .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))

        case .idle:
            // Idle state - show paired device info if available
            if let pairedDevice = PairedDeviceManager.pairedDevice, bleManager.isAutoConnectEnabled {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text(String(format: "Dispositivo guardado: %@", pairedDevice.name))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // If no paired device, show nothing (just the scan button)
        }
    }

    private func runQuickDemo() {
        isRunningDemo = true
        demoResults = nil
        
        Task {
            do {
                // Simulate quick measurement
                try await Task.sleep(for: .seconds(3))
                
                // Generate realistic data
                let mockData = generateMockData()
                
                // Process with algorithm
                let parameters = try await processor.processImmediate(mockData)
                
                await MainActor.run {
                    demoResults = DemoResults(data: mockData, parameters: parameters)
                    isRunningDemo = false
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

private struct DemoResultsCard: View {
    let results: DisconnectedView.DemoResults
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Resultados Demo")
                    .font(.headline)
                Spacer()
                QualityIndicator(score: results.parameters.quality.score)
            }

            VStack(spacing: 8) {
                ParameterRow("Re (Extracelular)", String(format: "%.1f Ω", results.parameters.Re))
                ParameterRow("Ri (Intracelular)", String(format: "%.1f Ω", results.parameters.Ri))
                ParameterRow("Cm (Membrana)", String(format: "%.2f nF", results.parameters.Cm))
                ParameterRow("fc (Característica)", String(format: "%.1f kHz", results.parameters.fc))
                ParameterRow("α (Dispersión)", String(format: "%.3f", results.parameters.alpha))
                ParameterRow("Error de Ajuste", String(format: "%.2f%%", results.parameters.error))
            }
        }
        .padding()
        .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DeviceSelectionView: View {
    @Environment(BioMessBLEManager.self) private var bleManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Scanning indicator
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.brandPrimary)
                    .symbolEffect(.pulse)
            }

            VStack(spacing: 8) {
                Text("Buscando Dispositivos")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Selecciona un dispositivo para conectar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Device list
            if bleManager.discoveredDevices.isEmpty {
                ProgressView()
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(bleManager.discoveredDevices, id: \.identifier) { device in
                        DeviceRow(device: device) {
                            bleManager.connect(to: device)
                        }
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            // Cancel button
            Button {
                bleManager.stopScanning()
            } label: {
                Text("Cancelar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom)
        }
        .padding()
    }
}

private struct DeviceRow: View {
    let device: CBPeripheral
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.brandPrimary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name ?? "Desconocido")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(device.identifier.uuidString.prefix(8).uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct ConnectedView: View {
    @Environment(BioMessBLEManager.self) private var bleManager
    @Environment(\.modelContext) private var modelContext
    @Environment(PatientInfo.self) private var patientInfo
    @Environment(AD5940ConfigurationManager.self) private var configManager
    @Environment(LocalPersistenceService.self) private var syncService: LocalPersistenceService?
    @State private var isMeasuring = false
    @State private var measurementError: String?
    @State private var sweepStart: Double = 4000
    @State private var sweepStop: Double = 198000
    @State private var sweepPoints: Int = 48
    @State private var numRepetitions: Int = 5  // Default to firmware standard
    @Environment(\.navigationPath) private var navigationPath

    @Binding var currentMeasurementNumber: Int
    @Binding var currentSessionPatient: String
    @Binding var currentSessionExercise: String
    /// When true, hides PatientFormCard and MeasurementConfigCard (patient info already collected in flow)
    let laboratoryMode: Bool
    let embeddedMode: Bool
    /// When true, auto-starts measurement on appear (skips instruction screen)
    let autoStart: Bool

    // MARK: - Session Context (passed from MeasurementView when embedded)
    let session: MeasurementSession?
    let muscleGroup: String?
    let side: String?
    let perceivedFatigue: Int?

    /// Optional flow VM for registering the save Task (race-safe cleanup).
    let flowViewModel: MeasurementFlowViewModel?

    /// Callback when measurement completes with results for display
    let onMeasurementComplete: (MeasurementView.MeasurementResults) -> Void
    /// Callback when measurement is saved (passes saved measurement ID for flow tracking)
    var onMeasurementSaved: ((UUID?) -> Void)?

    @State private var hasAutoStarted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Device info
                if let device = bleManager.connectedDevice {
                    DeviceInfoCard(device: device)
                }

                // Patient information form (hidden in embedded mode - already collected in flow)
                if !embeddedMode && !laboratoryMode {
                    PatientFormCard()
                }

                // Measurement Configuration - debug/advanced (hidden in embedded mode)
                if !embeddedMode {
                    MeasurementConfigCard(
                        sweepStart: $sweepStart,
                        sweepStop: $sweepStop,
                        sweepPoints: $sweepPoints,
                        numRepetitions: $numRepetitions,
                        mode: .manual,
                        onApply: {
                            await applyConfiguration()
                        }
                    )
                }

                // Device preparing banner
                if !bleManager.isDeviceReady {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Preparando dispositivo...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.orange.opacity(0.3), lineWidth: 1)
                    )
                }

                // Show measurement error if present
                if let error = measurementError {
                    MeasurementErrorCard(message: error) {
                        measurementError = nil
                    }
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
                        Text(isMeasuring ? "Midiendo..." : (bleManager.isDeviceReady ? "Iniciar Medición" : "Esperando dispositivo..."))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        (isMeasuring || !bleManager.isDeviceReady) ? Color.gray :
                        (laboratoryMode || embeddedMode || patientInfo.isValid) ? Color.brandPrimary : Color.gray.opacity(0.5)
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isMeasuring || !bleManager.isDeviceReady || (!laboratoryMode && !embeddedMode && !patientInfo.isValid))

                // Secondary actions grouped in a card
                VStack(spacing: 0) {
                    secondaryActionRow(
                        icon: "antenna.radiowaves.left.and.right",
                        label: "Probar Conexión",
                        color: Color.brandPrimary
                    ) {
                        Task { await bleManager.testConnection() }
                    }

                    Divider().padding(.leading, 44)

                    secondaryActionRow(
                        icon: "arrow.clockwise",
                        label: "Actualizar Conexión",
                        color: .orange
                    ) {
                        Task { await bleManager.refreshConnection() }
                    }

                    Divider().padding(.leading, 44)

                    secondaryActionRow(
                        icon: "wifi.slash",
                        label: "Desconectar",
                        color: .red
                    ) {
                        Task { await bleManager.forceDisconnectAndReset() }
                    }
                }
                .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .dismissKeyboardOnTap()
        .onChange(of: bleManager.isDeviceReady) { _, ready in
            if ready && autoStart && !hasAutoStarted && !isMeasuring {
                hasAutoStarted = true
                startMeasurement()
            }
        }
        .onAppear {
            // Only auto-start if device is already ready (e.g., second measurement in same session)
            if autoStart && !hasAutoStarted && !isMeasuring && bleManager.isDeviceReady {
                hasAutoStarted = true
                startMeasurement()
            }
        }
    }
    
    private func secondaryActionRow(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
                    .frame(width: 24)
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }

    private func applyConfiguration() async {
        let config = AD5940ConfigurationManager.Configuration(
            numOfData: Int32(numRepetitions * sweepPoints),
            sweepStart: Float(sweepStart),
            sweepStop: Float(sweepStop),
            sweepPoints: UInt32(sweepPoints),
            sweepEnable: true,
            numRepetitions: UInt8(numRepetitions)
        )

        do {
            try await configManager.writeConfiguration(config, to: bleManager)
            print("✓ Configuration applied: \(numRepetitions) reps × \(sweepPoints) pts = \(numRepetitions * sweepPoints) total")
        } catch {
            measurementError = "Error al aplicar configuración" + ": \(error.localizedDescription)"
        }
    }

    private func startMeasurement() {
        isMeasuring = true

        Task { @MainActor in
            do {
                // Step 1: Capture RAW measurement data
                let contextInfo = embeddedMode
                    ? "session \(session?.id.uuidString.prefix(8) ?? "none"), muscle: \(muscleGroup ?? "unknown")"
                    : "standalone mode"
                print("DEBUG: Starting measurement (\(contextInfo))...")

                let measurementData = try await bleManager.performMeasurement(
                    numPoints: UInt32(sweepPoints),
                    startFreq: Float(sweepStart),
                    stopFreq: Float(sweepStop),
                    repetitions: UInt8(numRepetitions)
                )
                print("DEBUG: Measurement completed with \(measurementData.measurements.count) points")
                print("DEBUG: Number of repetitions: \(measurementData.numRepetitions)")
                print("DEBUG: Device info: \(measurementData.deviceInfo?.name ?? "Unknown")")

                // Step 2: Save directly to SwiftData
                let measurementId = UUID()

                // Encode raw data to JSON
                let encoder = JSONEncoder()
                encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
                let rawDataJSON = try encoder.encode(measurementData)

                // Create and save SwiftData Measurement
                let measurement = Measurement(
                    id: measurementId,
                    session: session,
                    muscleGroup: muscleGroup ?? "unknown",
                    side: side ?? "unknown",
                    perceivedFatigue: perceivedFatigue ?? 5,
                    rawDataJSON: rawDataJSON
                )

                // Wrap save + sync in a tracked Task and register it on the
                // flow VM so `cleanupIfEmpty` waits for it before counting.
                // Fixes the cleanup race we hit on Android (commit da38ed4):
                // user backs out before save completes, cleanup sees count=0,
                // session gets deleted, save then fails / leaves orphans.
                let syncService = self.syncService
                let saveTask = Task<Void, Error> { @MainActor in
                    modelContext.insert(measurement)
                    try modelContext.save()

                    print("DEBUG: Measurement saved to SwiftData. Session: \(session?.id.uuidString.prefix(8) ?? "none"), Muscle: \(muscleGroup ?? "none")")

                    if let syncService = syncService {
                        try? await syncService.syncMeasurement(measurement)
                    }
                }
                flowViewModel?.registerSaveTask(saveTask)
                try await saveTask.value  // mantener el flow secuencial para la UI

                // Step 3: Return to UI immediately - measurement is "complete" from user perspective
                isMeasuring = false
                let measurementResults = MeasurementView.MeasurementResults(
                    rawData: measurementData,
                    immediateResults: nil,  // Will be filled by background processing
                    completeResults: nil,   // Will be filled by background processing
                    processingTime: (immediate: 0.0, complete: 0.0)
                )
                onMeasurementComplete(measurementResults)

                // Step 4: Notify the flow that measurement was saved (for session tracking)
                if embeddedMode {
                    onMeasurementSaved?(measurementId)
                }

            } catch {
                // Handle measurement capture failures
                isMeasuring = false
                measurementError = "La captura falló" + ": \(error.localizedDescription)"
                print("CAPTURE ERROR: \(error)")
            }
        }
    }

}

private struct DeviceInfoCard: View {
    let device: CBPeripheral
    @Environment(BioMessBLEManager.self) private var bleManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name ?? "Desconocido")
                    .font(.body)
                    .fontWeight(.medium)

                if let battery = bleManager.currentBatteryLevel {
                    HStack(spacing: 4) {
                        Text("Batería: \(battery.percentage)%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Leyendo batería...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let battery = bleManager.currentBatteryLevel {
                BatteryIndicator(battery: battery)
            }
        }
        .padding()
        .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func batteryColor(for percentage: UInt16) -> Color {
        switch percentage {
        case 50...100: return .green
        case 20..<50: return .orange
        default: return .red
        }
    }
}

private struct BatteryIndicator: View {
    let battery: BatteryData

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIconName)
                .foregroundStyle(batteryColor)
            Text("\(battery.percentage)%")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(batteryColor)
        }
    }

    private var batteryIconName: String {
        let percentage = Int(battery.percentage)
        switch percentage {
        case 90...100: return "battery.100"
        case 60..<90: return "battery.75"
        case 30..<60: return "battery.50"
        case 10..<30: return "battery.25"
        default: return "battery.0"
        }
    }

    private var batteryColor: Color {
        switch battery.percentage {
        case 50...100: return .green
        case 20..<50: return .orange
        default: return .red
        }
    }
}

private struct InstructionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instrucciones de Medición")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                InstructionRow("1", "Coloca los electrodos en la pantorrilla")
                InstructionRow("2", "Asegura buen contacto con la piel")
                InstructionRow("3", "Permanece quieto durante la medición")
                InstructionRow("4", "Tiempo total: ~4 segundos")
            }
        }
        .padding()
        .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
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
        HStack(spacing: 10) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 22, height: 22)
                .background(Color.brandPrimary, in: Circle())
                .foregroundStyle(.white)

            Text(text)
                .font(.subheadline)
        }
    }
}

private struct MeasuringView: View {
    let onCancel: () -> Void
    @State private var progress: Double = 0
    @State private var currentPhase = "Inicializando..."
    @State private var phasesComplete = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.brandPrimary)
                    .symbolEffect(.pulse, value: progress)
            }

            VStack(spacing: 12) {
                Text("Midiendo Bioimpedancia")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(phasesComplete ? "Esperando datos..." : currentPhase)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if phasesComplete {
                ProgressView()
                    .tint(Color.brandPrimary)
                    .frame(maxWidth: 200)
            } else {
                ProgressView(value: progress, total: 1.0)
                    .tint(Color.brandPrimary)
                    .frame(maxWidth: 200)
            }

            Text("Permanece quieto")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.1), in: Capsule())

            Button(action: onCancel) {
                Text("Cancelar")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            simulateMeasurementProgress()
        }
    }

    private func simulateMeasurementProgress() {
        let phases = [
            (1.0, "Iniciando medición..."),
            (2.0, "Recolectando datos...")
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

        // Animate progress bar to full
        withAnimation(.linear(duration: totalTime)) {
            progress = 1.0
        }

        // After animation completes, switch to indeterminate
        Timer.scheduledTimer(withTimeInterval: totalTime, repeats: false) { _ in
            Task { @MainActor in
                phasesComplete = true
            }
        }
    }
}

private struct ProcessingView: View {
    let tier: ProcessingTier
    @State private var progress: Double = 0

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "cpu")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                    .rotationEffect(.degrees(progress * 360))
            }

            VStack(spacing: 12) {
                Text("Procesando Datos")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Aplicando análisis \(tier.description)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress, total: 1.0)
                .tint(.orange)
                .frame(maxWidth: 200)

            Spacer()
        }
        .padding()
        .onAppear {
            let duration = tier == .immediate ? 1.0 : 5.0
            withAnimation(.linear(duration: duration)) {
                progress = 1.0
            }
        }
    }
}

private struct ResultsView: View {
    let results: MeasurementView.MeasurementResults
    let onReset: () -> Void
    let onViewHistory: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Success header
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)

                    Text("Medición Capturada")
                        .font(.title)
                        .fontWeight(.bold)
                }

                // Raw data captured confirmation
                RawDataCard(rawData: results.rawData)

                // Show results if available
                if let immediate = results.immediateResults {
                    ResultsCard(parameters: immediate, title: "Análisis Rápido")
                }

                if let complete = results.completeResults {
                    ResultsCard(parameters: complete, title: "Análisis Completo")
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        onReset()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Tomar Otra Medición")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        onViewHistory()
                    } label: {
                        Text("Ver Historial")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top)
            }
            .padding()
        }
    }
}

private struct RawDataCard: View {
    let rawData: ImpedanceData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Datos Crudos Capturados")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            VStack(spacing: 8) {
                HStack {
                    Text("Puntos de Datos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(rawData.measurements.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Rango de Frecuencia")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: "%.0f", rawData.frequencies.min() ?? 0)) - \(String(format: "%.0f", rawData.frequencies.max() ?? 0)) Hz")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Rango de Impedancia")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: "%.1f", rawData.magnitudes.min() ?? 0)) - \(String(format: "%.1f", rawData.magnitudes.max() ?? 0)) Ω")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Hora")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(rawData.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.green.opacity(0.3), lineWidth: 1)
        )
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


private struct ErrorView: View {
    let message: String
    @Environment(BioMessBLEManager.self) private var bleManager
    @Environment(\.navigationPath) private var navigationPath
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)
            }

            VStack(spacing: 12) {
                Text("Error de Conexión")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button(action: tryAgain) {
                HStack {
                    if isRetrying {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isRetrying ? "Reconectando..." : "Reintentar")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.brandPrimary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isRetrying)
            .padding(.horizontal, 48)

            Button("Volver al Menú Principal") {
                backToMainMenu()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    private func tryAgain() {
        isRetrying = true

        Task {
            // First, completely disconnect and reset
            await bleManager.forceDisconnectAndReset()

            // Wait a moment for cleanup
            try? await Task.sleep(for: .seconds(1))

            // Try to reconnect to paired device if available, otherwise scan
            await MainActor.run {
                isRetrying = false
                if PairedDeviceManager.pairedDevice != nil {
                    bleManager.startAutoConnectIfNeeded()
                } else {
                    bleManager.startScanning()
                }
            }
        }
    }

    private func backToMainMenu() {
        // Force disconnect and clear state
        Task {
            await bleManager.forceDisconnectAndReset()
        }

        // Reset navigation path to go back to main menu
        navigationPath.wrappedValue.removeLast(navigationPath.wrappedValue.count)
    }
}

private struct PatientFormCard: View {
    @Environment(PatientInfo.self) private var patientInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Información del Paciente")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                // Name field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nombre del Paciente")
                        .font(.caption)
                        .fontWeight(.medium)
                    TextField("Nombre completo", text: Bindable(patientInfo).name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: patientInfo.name) {
                            patientInfo.saveToStorage()
                        }
                    if let error = patientInfo.validateName() {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // Exercise name field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nombre del Ejercicio")
                        .font(.caption)
                        .fontWeight(.medium)
                    TextField("Nombre del ejercicio", text: Bindable(patientInfo).exerciseName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: patientInfo.exerciseName) {
                            patientInfo.saveToStorage()
                        }
                    if let error = patientInfo.validateExerciseName() {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // Age and Gender row
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Edad")
                            .font(.caption)
                            .fontWeight(.medium)
                        TextField("Edad", text: Bindable(patientInfo).age)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .onChange(of: patientInfo.age) {
                                patientInfo.saveToStorage()
                            }
                        if let error = patientInfo.validateAge() {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Género")
                            .font(.caption)
                            .fontWeight(.medium)
                        Picker("Género", selection: Bindable(patientInfo).gender) {
                            ForEach(Gender.allCases, id: \.self) { gender in
                                Text(gender.displayName).tag(gender)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: patientInfo.gender) {
                            patientInfo.saveToStorage()
                        }
                    }
                }

                // Height and Weight row
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Altura (cm)")
                            .font(.caption)
                            .fontWeight(.medium)
                        TextField("cm", text: Bindable(patientInfo).height)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .onChange(of: patientInfo.height) {
                                patientInfo.saveToStorage()
                            }
                        if let error = patientInfo.validateHeight() {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Peso (kg)")
                            .font(.caption)
                            .fontWeight(.medium)
                        TextField("kg", text: Bindable(patientInfo).weight)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .onChange(of: patientInfo.weight) {
                                patientInfo.saveToStorage()
                            }
                        if let error = patientInfo.validateWeight() {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                // BMI display (if available)
                if let bmi = patientInfo.bmi {
                    HStack {
                        Text("IMC" + ": \(String(format: "%.1f", bmi)) (\(patientInfo.bmiCategory))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 4)
                }

                // Validation status
                HStack {
                    Image(systemName: patientInfo.isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(patientInfo.isValid ? .green : .orange)
                    Text(patientInfo.isValid ? "Datos del paciente completos" : "Completa los campos requeridos")
                        .font(.caption)
                        .foregroundStyle(patientInfo.isValid ? .green : .orange)
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hecho") {
                    #if os(iOS)
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                    #endif
                }
            }
        }
    }
}

private struct MeasurementErrorCard: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Problema con la Medición")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cerrar", action: onDismiss)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            HStack(spacing: 12) {
                Button("Exportar Datos Crudos") {
                    // TODO: Implement raw data export
                    print("TODO: Export raw data functionality")
                }
                .font(.caption)
                .buttonStyle(.bordered)

                Spacer()

                Button("Reintentar") {
                    onDismiss()
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        MeasurementView()
            .environment(BioMessBLEManager())
            .environment(BioimpedanceProcessor())
    }
}

// MARK: - Results Card

private struct ResultsCard: View {
    let parameters: ColeParameters
    let title: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                QualityIndicator(score: parameters.quality.score)
            }
            
            VStack(spacing: 8) {
                ParameterRow("Re", String(format: "%.1f Ω", parameters.Re))
                ParameterRow("Ri", String(format: "%.1f Ω", parameters.Ri))
                ParameterRow("Cm", String(format: "%.2f nF", parameters.Cm))
                ParameterRow("fc", String(format: "%.1f kHz", parameters.fc))
            }
        }
        .padding()
        .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}
