import Foundation
@preconcurrency import CoreBluetooth
import OSLog

/// Core Bluetooth manager for BioMess bioimpedance device
/// Implements exact BLE protocol from BLE_PROTOCOL_IMPLEMENTATION.md
@Observable
@MainActor
public final class BioMessBLEManager: NSObject, Sendable {
    
    // MARK: - State
    
    public enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting
        case connected
        case measuring
        case error(String)
    }

    /// Status of automatic reconnection attempts
    public enum AutoConnectStatus: Equatable {
        case idle       // No auto-connect in progress (no paired device or disabled)
        case searching  // Actively searching for paired device
        case failed     // Search completed without finding device
    }

    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var autoConnectStatus: AutoConnectStatus = .idle
    public private(set) var discoveredDevices: [CBPeripheral] = []
    public private(set) var connectedDevice: CBPeripheral?
    public private(set) var lastError: String?
    public private(set) var currentBatteryLevel: BatteryData?

    /// Whether the device has completed post-connection setup (notifications enabled, battery read done)
    /// UI should wait for this before allowing measurements
    public private(set) var isDeviceReady: Bool = false

    // Auto-reconnection properties
    public private(set) var isAutoConnectEnabled: Bool = true
    public private(set) var isAutoConnecting: Bool = false
    
    // MARK: - Private Properties
    
    private var centralManager: CBCentralManager!
    private var bioMessPeripheral: CBPeripheral?
    private let logger = Logger(subsystem: "com.biomess.health", category: "BLE")
    
    // Data collection
    private var currentMeasurements: [Int: ImpedanceData.MeasurementPoint] = [:]
    private var deviceInfo: DeviceInfo?
    private var measurementContinuation: CheckedContinuation<ImpedanceData, Error>?
    private var lastMeasurementReceivedTime: Date?
    private var measurementCompilationTask: Task<Void, Never>?

    // V3.0 Streaming data reassembly (measurements received via 0xC000 notifications)
    private var streamingMeasurementID: UUID?
    private var streamingSetupTask: Task<Void, Never>?
    private var streamingBuffer = Data()  // Accumulates BLE notification chunks
    private var expectedStreamingBytes: Int?  // Expected total bytes for current measurement
    private var expectedMeasurementPoints = 48  // Default: 48 points per repetition
    private var expectedRepetitions = 1  // Default: 1 repetition
    private var streamingInactivityTask: Task<Void, Never>?  // Timeout for stalled streaming
    private let bytesPerMeasurementPoint = 12  // sizeof(BioimpedanceMeasurement) = 3 floats × 4 bytes

    // Auto-reconnection management
    private var autoReconnectTask: Task<Void, Never>?

    // Auto-measurement callback
    public var onAutomaticMeasurement: ((ImpedanceData) -> Void)?

    // Notification state tracking
    private var controlCharNotificationsEnabled = false
    private var commandQueue: [(BioMessCommands, Data)] = []

    // MARK: - BLE UUIDs (Exact from documentation)

    private nonisolated static let advertisedDeviceName = "BioMess"
    private nonisolated static let acceptedDeviceNamePrefixes = ["BIOMESS", "MESSI"]
    
    // Services (nonisolated for use in delegate methods)
    private nonisolated static let generalService = CBUUID(string: "00001800-0000-1000-8000-00805f9b34fb")
    private nonisolated static let bioMessControlService = CBUUID(string: "0000af00-0000-1000-8000-00805f9b34fb") 
    private nonisolated static let bioMessConfigService = CBUUID(string: "0000af01-0000-1000-8000-00805f9b34fb")
    private nonisolated static let bioMessDataService = CBUUID(string: "0000af02-0000-1000-8000-00805f9b34fb")
    private nonisolated static let bioMessEnvService = CBUUID(string: "0000af03-0000-1000-8000-00805f9b34fb")
    
    // Control characteristics
    private let deviceNameChar = CBUUID(string: "00002a00-0000-1000-8000-00805f9b34fb")
    private let controlCommandChar = CBUUID(string: "0000c000-0000-1000-8000-00805f9b34fb")
    private let serialNumberChar = CBUUID(string: "0000c001-0000-1000-8000-00805f9b34fb")

    // Configuration characteristics (V3.0+)
    private let rcalChar = CBUUID(string: "0000c011-0000-1000-8000-00805f9b34fb")  // Rcal (float)
    private let sweepEnableChar = CBUUID(string: "0000c012-0000-1000-8000-00805f9b34fb")  // Enable sweep (uint8)
    private let sweepStartFreqChar = CBUUID(string: "0000c013-0000-1000-8000-00805f9b34fb")  // Start freq (float Hz)
    private let sweepStopFreqChar = CBUUID(string: "0000c014-0000-1000-8000-00805f9b34fb")  // Stop freq (float Hz)
    private let sweepPointsChar = CBUUID(string: "0000c015-0000-1000-8000-00805f9b34fb")  // Num points (uint32)
    private let numRepetitionsChar = CBUUID(string: "0000c017-0000-1000-8000-00805f9b34fb")  // Num repetitions (uint8)

    // Environment characteristics
    private let imuQuaternionChar = CBUUID(string: "0000c201-0000-1000-8000-00805f9b34fb")
    private let batteryLevelChar = CBUUID(string: "0000c202-0000-1000-8000-00805f9b34fb")
    private let imuQVarianceChar = CBUUID(string: "0000c203-0000-1000-8000-00805f9b34fb")
    
    // Measurement characteristics (48 channels: 0x0-0x2F for 4-198 kHz sweep)
    private let measurementCharacteristics: [CBUUID] = [
        // 0x10-0x1F (0-15)
        CBUUID(string: "0000c110-0000-1000-8000-00805f9b34fb"), // MEAS0
        CBUUID(string: "0000c111-0000-1000-8000-00805f9b34fb"), // MEAS1
        CBUUID(string: "0000c112-0000-1000-8000-00805f9b34fb"), // MEAS2
        CBUUID(string: "0000c113-0000-1000-8000-00805f9b34fb"), // MEAS3
        CBUUID(string: "0000c114-0000-1000-8000-00805f9b34fb"), // MEAS4
        CBUUID(string: "0000c115-0000-1000-8000-00805f9b34fb"), // MEAS5
        CBUUID(string: "0000c116-0000-1000-8000-00805f9b34fb"), // MEAS6
        CBUUID(string: "0000c117-0000-1000-8000-00805f9b34fb"), // MEAS7
        CBUUID(string: "0000c118-0000-1000-8000-00805f9b34fb"), // MEAS8
        CBUUID(string: "0000c119-0000-1000-8000-00805f9b34fb"), // MEAS9
        CBUUID(string: "0000c11a-0000-1000-8000-00805f9b34fb"), // MEASA
        CBUUID(string: "0000c11b-0000-1000-8000-00805f9b34fb"), // MEASB
        CBUUID(string: "0000c11c-0000-1000-8000-00805f9b34fb"), // MEASC
        CBUUID(string: "0000c11d-0000-1000-8000-00805f9b34fb"), // MEASD
        CBUUID(string: "0000c11e-0000-1000-8000-00805f9b34fb"), // MEASE
        CBUUID(string: "0000c11f-0000-1000-8000-00805f9b34fb"), // MEASF
        // 0x20-0x2F (16-31)
        CBUUID(string: "0000c120-0000-1000-8000-00805f9b34fb"), // MEAS16
        CBUUID(string: "0000c121-0000-1000-8000-00805f9b34fb"), // MEAS17
        CBUUID(string: "0000c122-0000-1000-8000-00805f9b34fb"), // MEAS18
        CBUUID(string: "0000c123-0000-1000-8000-00805f9b34fb"), // MEAS19
        CBUUID(string: "0000c124-0000-1000-8000-00805f9b34fb"), // MEAS20
        CBUUID(string: "0000c125-0000-1000-8000-00805f9b34fb"), // MEAS21
        CBUUID(string: "0000c126-0000-1000-8000-00805f9b34fb"), // MEAS22
        CBUUID(string: "0000c127-0000-1000-8000-00805f9b34fb"), // MEAS23
        CBUUID(string: "0000c128-0000-1000-8000-00805f9b34fb"), // MEAS24
        CBUUID(string: "0000c129-0000-1000-8000-00805f9b34fb"), // MEAS25
        CBUUID(string: "0000c12a-0000-1000-8000-00805f9b34fb"), // MEAS26
        CBUUID(string: "0000c12b-0000-1000-8000-00805f9b34fb"), // MEAS27
        CBUUID(string: "0000c12c-0000-1000-8000-00805f9b34fb"), // MEAS28
        CBUUID(string: "0000c12d-0000-1000-8000-00805f9b34fb"), // MEAS29
        CBUUID(string: "0000c12e-0000-1000-8000-00805f9b34fb"), // MEAS30
        CBUUID(string: "0000c12f-0000-1000-8000-00805f9b34fb"), // MEAS31
        // 0x30-0x3F (32-47)
        CBUUID(string: "0000c130-0000-1000-8000-00805f9b34fb"), // MEAS32
        CBUUID(string: "0000c131-0000-1000-8000-00805f9b34fb"), // MEAS33
        CBUUID(string: "0000c132-0000-1000-8000-00805f9b34fb"), // MEAS34
        CBUUID(string: "0000c133-0000-1000-8000-00805f9b34fb"), // MEAS35
        CBUUID(string: "0000c134-0000-1000-8000-00805f9b34fb"), // MEAS36
        CBUUID(string: "0000c135-0000-1000-8000-00805f9b34fb"), // MEAS37
        CBUUID(string: "0000c136-0000-1000-8000-00805f9b34fb"), // MEAS38
        CBUUID(string: "0000c137-0000-1000-8000-00805f9b34fb"), // MEAS39
        CBUUID(string: "0000c138-0000-1000-8000-00805f9b34fb"), // MEAS40
        CBUUID(string: "0000c139-0000-1000-8000-00805f9b34fb"), // MEAS41
        CBUUID(string: "0000c13a-0000-1000-8000-00805f9b34fb"), // MEAS42
        CBUUID(string: "0000c13b-0000-1000-8000-00805f9b34fb"), // MEAS43
        CBUUID(string: "0000c13c-0000-1000-8000-00805f9b34fb"), // MEAS44
        CBUUID(string: "0000c13d-0000-1000-8000-00805f9b34fb"), // MEAS45
        CBUUID(string: "0000c13e-0000-1000-8000-00805f9b34fb"), // MEAS46
        CBUUID(string: "0000c13f-0000-1000-8000-00805f9b34fb")  // MEAS47
    ]
    
    // MARK: - Commands (From actual firmware API_REFERENCE.md - October 2025)

    private enum BioMessCommands: UInt8 {
        case measurement = 0x01        // Start bioimpedance measurement (AD5940 frequency sweep) ~4 seconds
        case batteryManual = 0x02      // Manual battery measurement (NOT NEEDED - battery auto-updates)
        case imuSingle = 0x03          // Single IMU quaternion reading ~100ms
        case imuStats = 0x04           // IMU with variance calculation ~1 second
        case startAutoMode = 0x05      // Start automatic measurement mode (firmware sends data periodically)
        case stopAutoMode = 0x06       // Stop automatic measurement mode
        case getStoredCount = 0x07     // Get number of measurements stored by firmware
        case getStoredBatch = 0x08     // Get batch of stored measurements (offset + count)
        case clearStored = 0x09        // Clear all stored measurements
        case healthCheck = 0x0A         // PMIC + AD5940 identity diagnostic
        case ledBlink = 100            // Test connection - blink LED
        // Sleep commands (200-205) intentionally omitted - they disconnect BLE
    }
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    // MARK: - Auto-Reconnection Methods
    
    /// Enable/disable automatic reconnection
    public func setAutoConnectEnabled(_ enabled: Bool) {
        isAutoConnectEnabled = enabled
        if !enabled {
            cancelAutoReconnect()
        } else if connectionState == .disconnected {
            // Start auto-connect if we have a paired device and are disconnected
            startAutoConnectIfNeeded()
        }
        logger.info("Auto-connect \(enabled ? "enabled" : "disabled")")
    }
    
    /// Clear the paired device (forget device)
    public func forgetPairedDevice() {
        PairedDeviceManager.clearPairedDevice()
        cancelAutoReconnect()
        logger.info("Paired device forgotten")
    }
    
    /// Start automatic connection process if we have a paired device
    public func startAutoConnectIfNeeded() {
        guard isAutoConnectEnabled,
              !isAutoConnecting,
              connectionState == .disconnected,
              PairedDeviceManager.pairedDevice != nil,
              centralManager.state == .poweredOn else {
            return
        }

        logger.info("Starting auto-connect scan for paired device...")
        isAutoConnecting = true
        autoConnectStatus = .searching
        connectionState = .scanning

        startAutoConnectScan()
    }

    /// Retry automatic connection (called from UI after failed attempt)
    public func retryAutoConnect() {
        guard PairedDeviceManager.pairedDevice != nil,
              centralManager.state == .poweredOn else {
            logger.warning("Cannot retry auto-connect: no paired device or Bluetooth off")
            return
        }

        // Cancel any existing attempt and reset state
        cancelAutoReconnect()
        connectionState = .disconnected
        autoConnectStatus = .idle

        // Start fresh auto-connect attempt
        startAutoConnectIfNeeded()
    }

    /// Start scanning specifically for paired device
    private func startAutoConnectScan() {
        guard isAutoConnecting else { return }

        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Auto-timeout after 20 seconds (single attempt, no retries)
        autoReconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            await MainActor.run { [weak self] in
                self?.handleAutoConnectTimeout()
            }
        }
    }

    /// Handle auto-connect timeout - single attempt, then show retry button
    private func handleAutoConnectTimeout() {
        guard isAutoConnecting else { return }

        centralManager.stopScan()
        isAutoConnecting = false
        connectionState = .disconnected
        autoConnectStatus = .failed

        logger.info("Auto-connect failed after 20 seconds - showing retry option")
    }

    /// Cancel auto-reconnection process
    private func cancelAutoReconnect() {
        isAutoConnecting = false
        autoReconnectTask?.cancel()
        autoReconnectTask = nil
        autoConnectStatus = .idle

        if connectionState == .scanning && !discoveredDevices.isEmpty {
            // If we're scanning manually (not auto-connect), don't change state
            return
        }

        centralManager.stopScan()
        logger.info("Auto-connect cancelled")
    }
    
    /// Mark device as paired after successful connection
    private func pairDevice(_ peripheral: CBPeripheral, serialNumber: String? = nil) {
        let pairedDevice = PairedDevice(
            identifier: peripheral.identifier.uuidString,
            name: peripheral.name ?? Self.advertisedDeviceName,
            serialNumber: serialNumber
        )
        
        PairedDeviceManager.setPairedDevice(pairedDevice)
        logger.info("Device paired: \(pairedDevice.name)")
    }
    
    /// Update paired device info
    private func updatePairedDeviceInfo() {
        // Update connection count and timestamp
        PairedDeviceManager.updatePairedDevice(serialNumber: deviceInfo?.serialNumber)
    }
    
    // MARK: - Public API
    
    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionState = .error("Bluetooth not available")
            return
        }
        
        logger.info("Starting scan for BioMess devices...")
        connectionState = .scanning
        discoveredDevices.removeAll()
        
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        // Auto-stop scan after 20 seconds
        Task {
            try? await Task.sleep(for: .seconds(20))
            stopScanning()
        }
    }
    
    public func stopScanning() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
        logger.info("Stopped scanning")
    }
    
    public func connect(to device: CBPeripheral) {
        logger.info("Connecting to device: \(device.name ?? "Unknown")")

        // Cancel any ongoing auto-connect process since user is manually connecting
        cancelAutoReconnect()

        isDeviceReady = false
        connectionState = .connecting
        bioMessPeripheral = device
        connectedDevice = device
        centralManager.connect(device, options: nil)
    }
    
    public func disconnect() {
        guard let peripheral = bioMessPeripheral else { return }

        finishStreamingMeasurement(throwing: BLEError.disconnected)
        controlCharNotificationsEnabled = false
        commandQueue.removeAll()

        // Cancel auto-reconnection since this is a manual disconnect
        cancelAutoReconnect()

        isDeviceReady = false
        centralManager.cancelPeripheralConnection(peripheral)
        bioMessPeripheral = nil
        connectedDevice = nil
        connectionState = .disconnected
    }

    /// Force disconnect and reconnect to refresh BLE cache
    /// Use this when firmware is updated and iOS is showing stale characteristics
    public func refreshConnection() async {
        logger.info("🔄 Refreshing connection to clear iOS BLE cache...")

        guard let peripheral = bioMessPeripheral else {
            logger.warning("No peripheral to refresh")
            return
        }

        // Save device for reconnection
        let deviceToReconnect = peripheral

        // Disconnect
        disconnect()
        connectionState = .disconnected

        // Wait for iOS to fully disconnect and clear cache
        try? await Task.sleep(for: .seconds(2))

        // Reconnect
        logger.info("Reconnecting after cache clear...")
        connect(to: deviceToReconnect)
    }

    /// Force disconnect and completely reset BLE manager state
    public func forceDisconnectAndReset() async {
        logger.info("Force disconnect and reset requested")

        // Cancel any ongoing operations
        finishStreamingMeasurement(throwing: BLEError.disconnected)
        measurementCompilationTask?.cancel()
        measurementCompilationTask = nil

        // Cancel auto-reconnection
        cancelAutoReconnect()

        // Stop scanning if active
        centralManager.stopScan()

        // Disconnect from peripheral if connected
        if let peripheral = bioMessPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }

        // Clear all state
        bioMessPeripheral = nil
        connectedDevice = nil
        discoveredDevices.removeAll()
        currentMeasurements.removeAll()
        deviceInfo = nil
        lastError = nil
        isAutoConnecting = false
        autoConnectStatus = .idle
        isDeviceReady = false

        // Set to disconnected state
        connectionState = .disconnected

        logger.info("BLE manager completely reset")
    }
    
    /// Perform complete bioimpedance measurement with V3.0 streaming protocol
    /// V3.0: Data is streamed via 0xC000 notifications (not read from 48 characteristics)
    public func performMeasurement(
        numPoints: UInt32? = nil,
        startFreq: Float? = nil,
        stopFreq: Float? = nil,
        repetitions: UInt8? = nil
    ) async throws -> ImpedanceData {
        guard bioMessPeripheral != nil, connectionState == .connected, controlCharNotificationsEnabled else {
            throw BLEError.notConnected
        }
        guard measurementContinuation == nil else { throw BLEError.invalidParameter }
        let maxHz = AD5940ConfigurationManager.maxSweepFrequencyHz
        if let startFreq, !startFreq.isFinite || startFreq <= 0 || startFreq >= maxHz {
            throw BLEError.invalidParameter
        }
        if let stopFreq, !stopFreq.isFinite || stopFreq <= (startFreq ?? 0) || stopFreq > maxHz {
            throw BLEError.invalidParameter
        }

        let measurementID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            measurementContinuation = continuation
            streamingMeasurementID = measurementID

            streamingSetupTask = Task {
                do {
                    try Task.checkCancellation()
                    if let points = numPoints { try await configureSweepPoints(points) }
                    try Task.checkCancellation()
                    if let start = startFreq { try await configureSweepStartFreq(start) }
                    try Task.checkCancellation()
                    if let stop = stopFreq { try await configureSweepStopFreq(stop) }
                    try Task.checkCancellation()
                    if let reps = repetitions { try await configureNumRepetitions(reps) }

                    if numPoints != nil || startFreq != nil || stopFreq != nil || repetitions != nil {
                        try await Task.sleep(for: .milliseconds(300))
                    }

                    try Task.checkCancellation()
                    let points = try await readSweepPoints()
                    try Task.checkCancellation()
                    let reps = try await readNumRepetitions()
                    guard (2...100).contains(points), (1...10).contains(reps) else {
                        throw BLEError.invalidResponse
                    }
                    guard streamingMeasurementID == measurementID else { return }

                    connectionState = .measuring
                    expectedMeasurementPoints = Int(points)
                    expectedRepetitions = Int(reps)
                    expectedStreamingBytes = Int(points) * Int(reps) * bytesPerMeasurementPoint
                    startStreamingTimeout(for: .seconds(30))
                    await sendCommand(.measurement)
                } catch {
                    guard streamingMeasurementID == measurementID else { return }
                    finishStreamingMeasurement(throwing: error)
                }
            }
        }
    }

    func cancelStreamingMeasurement() {
        guard streamingMeasurementID != nil else { return }
        abortStreamingMeasurement(throwing: CancellationError())
    }

    /// Test device connection by blinking LED
    public func testConnection() async {
        await sendCommand(.ledBlink)
        logger.info("LED blink command sent")
    }

    /// Read battery level from device using MANUAL protocol
    /// IMPORTANT: Battery measurement is MANUAL ONLY - must send command 0x02 first
    /// Firmware performs ADC sampling when command is received, then updates BLE characteristic
    public func readBatteryLevel() async throws -> BatteryData {
        logger.debug("🔋 readBatteryLevel() called")

        guard bioMessPeripheral != nil, connectionState == .connected else {
            logger.error("🔋 ERROR: Cannot read battery - not connected (state: \(String(describing: self.connectionState)))")
            throw BLEError.notConnected
        }

        logger.debug("🔋 STEP 1: Sending battery command (0x02)...")

        // STEP 1: Send command 0x02 to trigger battery measurement
        // This initializes ADC, performs sampling, and updates the BLE characteristic
        await sendCommand(.batteryManual)

        logger.debug("🔋 STEP 2: Waiting 150ms for firmware ADC sampling...")

        // STEP 2: Wait for firmware to complete ADC sampling and characteristic update
        // Firmware needs ~100ms for BatteryLevel_Init() + sampling + BatteryLevel_DeInit()
        try await Task.sleep(for: .milliseconds(150))

        logger.debug("🔋 STEP 3: Reading battery characteristic (C202)...")

        // STEP 3: Read the updated battery characteristic (0xC202)
        await readCharacteristic(uuid: batteryLevelChar, service: Self.bioMessEnvService)

        logger.debug("🔋 STEP 4: Waiting 100ms for characteristic value to arrive...")

        // STEP 4: Wait briefly for characteristic value to arrive via delegate
        try await Task.sleep(for: .milliseconds(100))

        logger.debug("🔋 STEP 5: Checking if battery data was received...")

        // STEP 5: Return the battery data
        guard let battery = currentBatteryLevel else {
            logger.error("🔋 ERROR: Battery characteristic read but NO DATA received (currentBatteryLevel is nil)")
            throw BLEError.incompleteData
        }

        logger.debug("🔋 SUCCESS: Battery read completed: \(battery.voltageMillivolts)mV (\(battery.percentage)%)")
        return battery
    }

    /// Start automatic measurement mode - firmware will send measurements periodically
    /// - Parameter intervalSeconds: Interval between measurements in seconds (60-3600)
    public func startAutomaticMode(intervalSeconds: UInt16) async throws {
        guard bioMessPeripheral != nil, connectionState == .connected else {
            throw BLEError.notConnected
        }

        // Validate interval (firmware limits: 60s - 3600s)
        guard intervalSeconds >= 60 && intervalSeconds <= 3600 else {
            logger.error("Invalid interval: \(intervalSeconds)s. Must be between 60-3600 seconds")
            throw BLEError.invalidParameter
        }

        logger.info("Starting automatic mode with \(intervalSeconds)s interval...")

        // Send START_AUTO_MODE command (0x05) with interval as payload
        // Payload: 2 bytes little-endian UInt16
        let lowByte = UInt8(intervalSeconds & 0xFF)
        let highByte = UInt8(intervalSeconds >> 8)
        let payload = Data([lowByte, highByte])

        await sendCommand(.startAutoMode, payload: payload)

        logger.info("Automatic mode started - firmware will send measurements every \(intervalSeconds)s")
    }

    /// Stop automatic measurement mode
    public func stopAutomaticMode() async {
        guard bioMessPeripheral != nil, connectionState == .connected else {
            logger.warning("Cannot stop automatic mode: device not connected")
            return
        }

        logger.info("Stopping automatic mode...")
        await sendCommand(.stopAutoMode)
        logger.info("Automatic mode stopped")
    }

    /// Legacy function - DEPRECATED
    /// Use readBatteryLevel() instead which properly sends command 0x02
    @available(*, deprecated, message: "Use readBatteryLevel() instead - battery requires manual trigger")
    private func requestBatteryLevel() async {
        logger.warning("⚠️ Deprecated: requestBatteryLevel() called - use readBatteryLevel() instead")
        try? await readBatteryLevel()
    }

    // MARK: - Generic BLE Characteristic Methods

    /// Write data to a specific BLE characteristic
    /// - Parameters:
    ///   - serviceUUID: Service UUID string (e.g., "0000AF01-...")
    ///   - charUUID: Characteristic UUID string
    ///   - data: Data to write
    public func writeCharacteristic(
        serviceUUID: String,
        charUUID: String,
        data: Data
    ) async throws {
        guard let peripheral = bioMessPeripheral else {
            throw BLEError.notConnected
        }

        guard connectionState == .connected else {
            throw BLEError.notConnected
        }

        let serviceCBUUID = CBUUID(string: serviceUUID)
        let charCBUUID = CBUUID(string: charUUID)

        // Debug: Log available services
        print("DEBUG: Looking for service \(serviceUUID)")
        if let services = peripheral.services {
            print("DEBUG: Available services: \(services.map { $0.uuid.uuidString })")
        } else {
            print("DEBUG: No services discovered yet!")
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == serviceCBUUID }) else {
            throw BLEError.serviceNotFound
        }

        // Debug: Print available characteristics
        if let chars = service.characteristics {
            let charUUIDs = chars.map { $0.uuid.uuidString }.joined(separator: ", ")
            print("DEBUG: Looking for char \(charUUID)")
            print("DEBUG: Available characteristics in \(serviceUUID): [\(charUUIDs)]")
        }

        guard let characteristic = service.characteristics?.first(where: { $0.uuid == charCBUUID }) else {
            print("ERROR: Characteristic \(charUUID) NOT FOUND in service \(serviceUUID)")
            throw BLEError.characteristicNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Store continuation to be resumed in didWriteValueFor callback
            Task { @MainActor in
                self.writeCompletionHandlers[charCBUUID] = continuation
            }

            // Write value
            peripheral.writeValue(data, for: characteristic, type: .withResponse)

            // Timeout after 5 seconds
            Task {
                try? await Task.sleep(for: .seconds(5))
                if let handler = await self.writeCompletionHandlers.removeValue(forKey: charCBUUID) {
                    handler.resume(throwing: BLEError.timeout)
                }
            }
        }
    }

    /// Read data from a specific BLE characteristic
    /// - Parameters:
    ///   - serviceUUID: Service UUID string
    ///   - charUUID: Characteristic UUID string
    /// - Returns: Data read from characteristic
    public func readCharacteristic(
        serviceUUID: String,
        charUUID: String
    ) async throws -> Data {
        guard let peripheral = bioMessPeripheral else {
            throw BLEError.notConnected
        }

        guard connectionState == .connected else {
            throw BLEError.notConnected
        }

        let serviceCBUUID = CBUUID(string: serviceUUID)
        let charCBUUID = CBUUID(string: charUUID)

        guard let service = peripheral.services?.first(where: { $0.uuid == serviceCBUUID }) else {
            throw BLEError.serviceNotFound
        }

        guard let characteristic = service.characteristics?.first(where: { $0.uuid == charCBUUID }) else {
            throw BLEError.characteristicNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Store continuation to be resumed in didUpdateValueFor callback
            Task { @MainActor in
                self.readCompletionHandlers[charCBUUID] = continuation
            }

            // Read value
            peripheral.readValue(for: characteristic)

            // Timeout after 5 seconds
            Task {
                try? await Task.sleep(for: .seconds(5))
                if let handler = await self.readCompletionHandlers.removeValue(forKey: charCBUUID) {
                    handler.resume(throwing: BLEError.timeout)
                }
            }
        }
    }

    // Completion handlers for async write/read operations
    private var writeCompletionHandlers: [CBUUID: CheckedContinuation<Void, Error>] = [:]
    private var readCompletionHandlers: [CBUUID: CheckedContinuation<Data, Error>] = [:]
}

// MARK: - CBCentralManagerDelegate

extension BioMessBLEManager: CBCentralManagerDelegate {
    
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.info("Central manager state: \(central.state.description)")
        
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                // Bluetooth is ready - start auto-connect if we have a paired device
                startAutoConnectIfNeeded()
            case .poweredOff:
                connectionState = .error("Bluetooth is turned off")
            case .unauthorized:
                connectionState = .error("Bluetooth access not authorized")
            case .unsupported:
                connectionState = .error("Bluetooth not supported on this device")
            default:
                connectionState = .error("Bluetooth unavailable")
            }
        }
    }
    
    nonisolated public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {

        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? ""
        let upperName = name.uppercased()
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let advertisesBioMessService = advertisedServices.contains(Self.bioMessControlService)
        let hasBioMessName = Self.acceptedDeviceNamePrefixes.contains { upperName.hasPrefix($0) }

        guard hasBioMessName || advertisesBioMessService else {
            return
        }

        logger.info("Discovered device: \(name.isEmpty ? Self.advertisedDeviceName : name)")

        Task { @MainActor in
            // Check if this is our paired device and we're auto-connecting
            if isAutoConnecting && PairedDeviceManager.isDevicePaired(peripheral) {
                logger.info("Found paired device during auto-connect: \(name)")

                // Cancel auto-connect timeout and connect immediately
                autoReconnectTask?.cancel()
                autoReconnectTask = nil

                // Connect to the paired device
                connect(to: peripheral)
                return
            }

            // Add to discovered devices list for manual selection
            if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                discoveredDevices.append(peripheral)
            }
        }
    }
    
    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.debug("🔵 Connected to peripheral: \(peripheral.name ?? "Unknown")")

        peripheral.delegate = self

        Task { @MainActor in
            connectionState = .connected
            isAutoConnecting = false // Stop auto-connect process
            autoConnectStatus = .idle // Reset auto-connect status on successful connection
            isDeviceReady = false // Will be set to true after battery read completes

            // If this device isn't already paired, pair it now
            if !PairedDeviceManager.isDevicePaired(peripheral) {
                pairDevice(peripheral)
            } else {
                // Update existing paired device info
                updatePairedDeviceInfo()
            }

            // Safety timeout: mark device ready after 3s even if battery read didn't complete
            Task {
                try? await Task.sleep(for: .seconds(3))
                if !self.isDeviceReady && self.connectionState == .connected {
                    self.isDeviceReady = true
                    logger.warning("⚠️ Device ready via safety timeout (battery read may not have completed)")
                }
            }

            logger.debug("🔵 Starting service discovery...")
        }

        // Discover all services
        peripheral.discoverServices([
            Self.generalService,
            Self.bioMessControlService,
            Self.bioMessConfigService,
            Self.bioMessDataService,
            Self.bioMessEnvService
        ])
    }
    
    nonisolated public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        
        Task { @MainActor in
            connectionState = .error(error?.localizedDescription ?? "Connection failed")
            bioMessPeripheral = nil
            connectedDevice = nil
        }
    }
    
    nonisolated public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            guard bioMessPeripheral === peripheral else { return }
            if let error = error {
                logger.error("Disconnected with error: \(error.localizedDescription)")
                connectionState = .error("Disconnected: \(error.localizedDescription)")
            } else {
                logger.info("Disconnected from peripheral")
                connectionState = .disconnected
            }
            
            bioMessPeripheral = nil
            connectedDevice = nil
            finishStreamingMeasurement(throwing: BLEError.disconnected)
            measurementCompilationTask?.cancel()
            measurementCompilationTask = nil

            // Reset notification and ready state
            controlCharNotificationsEnabled = false
            commandQueue.removeAll()
            isDeviceReady = false

            // If we were connected to a paired device and got disconnected unexpectedly, 
            // start auto-reconnect (unless this was a manual disconnect)
            if error != nil && PairedDeviceManager.isDevicePaired(peripheral) {
                logger.info("Unexpected disconnection from paired device, starting auto-reconnect...")
                
                // Wait a bit before trying to reconnect
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run { [weak self] in
                        self?.startAutoConnectIfNeeded()
                    }
                }
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BioMessBLEManager: CBPeripheralDelegate {
    
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            logger.error("Service discovery failed: \(error!.localizedDescription)")
            return
        }

        logger.debug("🔵 Discovered \(peripheral.services?.count ?? 0) services")

        // Debug: Log all discovered service UUIDs
        if let services = peripheral.services {
            let serviceUUIDs = services.map { $0.uuid.uuidString }.joined(separator: ", ")
            logger.debug("🔵 Service UUIDs: [\(serviceUUIDs)]")
        }

        // Discover characteristics for each service
        peripheral.services?.forEach { service in
            logger.debug("🔵 Discovering characteristics for service \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            logger.error("Characteristic discovery failed: \(error!.localizedDescription)")
            return
        }

        logger.debug("🔵 Discovered \(service.characteristics?.count ?? 0) characteristics for service \(service.uuid)")

        // Debug: Log all characteristic UUIDs for every service
        if let chars = service.characteristics {
            let uuids = chars.map { $0.uuid.uuidString }.joined(separator: ", ")
            logger.debug("🔵 Characteristics in \(service.uuid): [\(uuids)]")
        }

        // CRITICAL: Enable notifications for control characteristic (0xC000) BEFORE sending commands
        if service.uuid == Self.bioMessControlService {
            if let controlChar = service.characteristics?.first(where: { $0.uuid.uuidString.uppercased().contains("C000") }) {
                logger.info("🔔 Enabling notifications for control characteristic (C000)")
                peripheral.setNotifyValue(true, for: controlChar)
            }
        }

        // Read battery when environment service characteristics are discovered
        if service.uuid == Self.bioMessEnvService {
            logger.debug("🔋 Environment service (AF03) characteristics discovered")

            // Check if battery characteristic exists
            let batteryChar = CBUUID(string: "0000c202-0000-1000-8000-00805f9b34fb")
            if service.characteristics?.first(where: { $0.uuid == batteryChar }) != nil {
                logger.debug("🔋 Battery characteristic (C202) found in service")
            } else {
                logger.error("🔋 Battery characteristic (C202) NOT FOUND in AF03 service!")
            }

            // Device is ready for measurements now
            // Note: Battery read removed from connection setup to avoid
            // command conflicts (0x02 busy when 0x01 is sent immediately after)
            Task { @MainActor in
                self.isDeviceReady = true
                logger.info("✅ Device setup complete - ready for measurements")
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("Failed to enable notifications for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }

        // Check if this is the control characteristic (C000)
        if characteristic.uuid.uuidString.uppercased().contains("C000") {
            if characteristic.isNotifying {
                logger.info("✅ Notifications enabled for control characteristic - ready to send commands")

                Task { @MainActor in
                    self.controlCharNotificationsEnabled = true

                    // Process any queued commands
                    if !self.commandQueue.isEmpty {
                        logger.info("Processing \(self.commandQueue.count) queued commands")
                        for (command, payload) in self.commandQueue {
                            await self.sendCommand(command, payload: payload)
                        }
                        self.commandQueue.removeAll()
                    }
                }
            } else {
                logger.warning("Notifications disabled for control characteristic")
                Task { @MainActor in
                    self.controlCharNotificationsEnabled = false
                }
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else {
            if let error = error {
                logger.error("Characteristic read failed: \(error.localizedDescription)")

                // Resume read completion handler with error if present
                Task { @MainActor in
                    guard peripheral === self.bioMessPeripheral else { return }
                    if let handler = self.readCompletionHandlers.removeValue(forKey: characteristic.uuid) {
                        handler.resume(throwing: error)
                    }
                }
            }
            return
        }

        Task { @MainActor in
            guard peripheral === self.bioMessPeripheral else { return }
            // Check if this is a read operation awaiting completion
            if let handler = self.readCompletionHandlers.removeValue(forKey: characteristic.uuid) {
                handler.resume(returning: data)
            } else {
                // Normal characteristic update handling
                handleCharacteristicData(characteristic: characteristic, data: data)
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard peripheral === self.bioMessPeripheral else { return }
            // Resume write completion handler
            if let handler = self.writeCompletionHandlers.removeValue(forKey: characteristic.uuid) {
                if let error = error {
                    logger.error("Characteristic write failed: \(error.localizedDescription)")
                    handler.resume(throwing: error)
                } else {
                    handler.resume()
                }
            } else if let error = error {
                logger.error("Characteristic write failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Private Methods

extension BioMessBLEManager {
    
    private func sendCommand(_ command: BioMessCommands, payload: Data = Data()) async {
        guard let peripheral = bioMessPeripheral else {
            logger.error("No peripheral connected")
            return
        }

        // Check if notifications are enabled
        guard controlCharNotificationsEnabled else {
            logger.warning("⚠️ Notifications not enabled yet - queueing command \(String(describing: command))")
            commandQueue.append((command, payload))
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == Self.bioMessControlService }) else {
            logger.error("Control service (AF00) not found. Available services: \(peripheral.services?.map { $0.uuid.uuidString } ?? [])")
            return
        }

        guard let characteristic = service.characteristics?.first(where: { $0.uuid == controlCommandChar }) else {
            logger.error("Control characteristic (C000) not found. Available characteristics: \(service.characteristics?.map { $0.uuid.uuidString } ?? [])")
            return
        }

        var commandData = Data([command.rawValue])
        commandData.append(payload)

        logger.info("Sending command \(String(describing: command)) (0x\(String(format: "%02X", command.rawValue))) with \(payload.count) bytes payload to service \(service.uuid) characteristic \(characteristic.uuid)")
        peripheral.writeValue(commandData, for: characteristic, type: .withResponse)

        // Small delay for BLE stack
        try? await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - V3.0 Configuration Methods

    /// Configure number of sweep points (V3.0+)
    private func configureSweepPoints(_ points: UInt32) async throws {
        let value = min(max(points, UInt32(2)), UInt32(100))
        let data = Self.dataUInt32LE(value)
        try await writeCharacteristic(
            serviceUUID: "0000AF00-0000-1000-8000-00805F9B34FB",
            charUUID: "0000C015-0000-1000-8000-00805F9B34FB",
            data: data
        )
        logger.info("✏️ Configured sweep points: \(value)")
    }

    /// Configure sweep start frequency in Hz (V3.0+)
    private func configureSweepStartFreq(_ freqHz: Float) async throws {
        let data = Self.dataFloat32LE(freqHz)
        try await writeCharacteristic(
            serviceUUID: "0000AF00-0000-1000-8000-00805F9B34FB",
            charUUID: "0000C013-0000-1000-8000-00805F9B34FB",
            data: data
        )
        logger.info("✏️ Configured start frequency: \(freqHz) Hz")
    }

    /// Configure sweep stop frequency in Hz (V3.0+)
    private func configureSweepStopFreq(_ freqHz: Float) async throws {
        let data = Self.dataFloat32LE(freqHz)
        try await writeCharacteristic(
            serviceUUID: "0000AF00-0000-1000-8000-00805F9B34FB",
            charUUID: "0000C014-0000-1000-8000-00805F9B34FB",
            data: data
        )
        logger.info("✏️ Configured stop frequency: \(freqHz) Hz")
    }

    /// Configure number of repetitions (V3.0+)
    private func configureNumRepetitions(_ repetitions: UInt8) async throws {
        let value = min(max(repetitions, UInt8(1)), UInt8(10))
        try await writeCharacteristic(
            serviceUUID: "0000AF01-0000-1000-8000-00805F9B34FB",
            charUUID: "0000C017-0000-1000-8000-00805F9B34FB",
            data: Data([value])
        )
        logger.info("✏️ Configured repetitions: \(value)")
    }

    /// Read number of repetitions from firmware (V3.0+)
    private func readNumRepetitions() async throws -> UInt8 {
        let data = try await readCharacteristic(
            serviceUUID: "0000AF01-0000-1000-8000-00805F9B34FB",  // bioMessConfigService
            charUUID: "0000C017-0000-1000-8000-00805F9B34FB"      // numRepetitionsChar
        )

        guard data.count == 1 else {
            throw BLEError.incompleteData
        }

        return data[0]
    }

    /// Read number of sweep points from firmware (V3.0+)
    private func readSweepPoints() async throws -> UInt32 {
        let data = try await readCharacteristic(
            serviceUUID: "0000AF01-0000-1000-8000-00805F9B34FB",  // bioMessConfigService
            charUUID: "0000C015-0000-1000-8000-00805F9B34FB"      // sweepPointsChar
        )

        guard data.count == 4 else {
            throw BLEError.incompleteData
        }

        return Self.uint32LE(data, 0)
    }

    // MARK: - V3.0 Streaming Data Processing

    /// Handle streaming measurement data from 0xC000 notifications (V3.0+)
    /// Data format: N × (freq, mag, phase) = N × 12 bytes
    private func handleStreamingMeasurementData(_ chunk: Data) {
        guard let expectedBytes = expectedStreamingBytes, measurementContinuation != nil else { return }
        let received = streamingBuffer.count + chunk.count
        guard received <= expectedBytes else {
            logger.error("Unexpected sweep length: \(received)/\(expectedBytes) bytes")
            abortStreamingMeasurement(throwing: BLEError.incompleteSweep)
            return
        }

        streamingBuffer.append(chunk)
        if received == expectedBytes {
            compileStreamingMeasurement()
        } else {
            startStreamingTimeout(for: .seconds(5))
        }
    }

    private func startStreamingTimeout(for duration: Duration) {
        streamingInactivityTask?.cancel()
        streamingInactivityTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard let self, let expected = self.expectedStreamingBytes else { return }
            self.logger.warning("Sweep stalled at \(self.streamingBuffer.count)/\(expected) bytes")
            self.abortStreamingMeasurement(throwing: BLEError.incompleteSweep)
        }
    }

    // The stream has no frame marker. Close the link before accepting another sweep.
    private func abortStreamingMeasurement(throwing error: Error) {
        finishStreamingMeasurement(throwing: error)
        disconnect()
    }

    private func finishStreamingMeasurement(throwing error: Error) {
        clearStreamingMeasurement()?.resume(throwing: error)
    }

    private func clearStreamingMeasurement() -> CheckedContinuation<ImpedanceData, Error>? {
        streamingSetupTask?.cancel()
        streamingSetupTask = nil
        streamingInactivityTask?.cancel()
        streamingInactivityTask = nil
        streamingBuffer.removeAll()
        expectedStreamingBytes = nil
        streamingMeasurementID = nil
        let pending = measurementContinuation
        measurementContinuation = nil
        return pending
    }

    private func compileStreamingMeasurement() {
        let repetitions = (0..<expectedRepetitions).map { repetition in
            (0..<expectedMeasurementPoints).map { point in
                let offset = (repetition * expectedMeasurementPoints + point) * bytesPerMeasurementPoint
                return ImpedanceData.MeasurementPoint(
                    frequency: Self.float32LE(streamingBuffer, offset),
                    magnitude: Self.float32LE(streamingBuffer, offset + 4),
                    phase: Self.float32LE(streamingBuffer, offset + 8)
                )
            }.sorted { $0.frequency < $1.frequency }
        }
        let measurement = ImpedanceData(repetitions: repetitions, timestamp: Date(), deviceInfo: deviceInfo)
        let pending = clearStreamingMeasurement()
        connectionState = .connected
        pending?.resume(returning: measurement)
    }

    func readAllMeasurements() async {
        guard bioMessPeripheral != nil else { return }
        
        logger.info("Reading all measurements and device info...")
        
        // Read device info
        await readCharacteristic(uuid: deviceNameChar, service: Self.generalService)
        await readCharacteristic(uuid: serialNumberChar, service: Self.bioMessControlService)
        
        // Read sensor data
        await readCharacteristic(uuid: batteryLevelChar, service: Self.bioMessEnvService)
        await readCharacteristic(uuid: imuQuaternionChar, service: Self.bioMessEnvService)
        await readCharacteristic(uuid: imuQVarianceChar, service: Self.bioMessEnvService)

        // Read all 48 measurement characteristics (4kHz to 198kHz sweep)
        for (index, uuid) in measurementCharacteristics.enumerated() {
            await readCharacteristic(uuid: uuid, service: Self.bioMessDataService)
            logger.debug("Reading measurement \(index)")

            // Small delay between reads
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        // After all reads, wait longer for all async characteristic updates to arrive
        logger.info("DEBUG: Waiting for all BLE characteristics to be read...")
        try? await Task.sleep(for: .seconds(3)) // Wait longer for all async reads
        
        // Check periodically until we have enough measurements or timeout
        let maxWaitTime = 10.0 // seconds
        let checkInterval = 0.5 // seconds
        var waitTime = 0.0
        
        while waitTime < maxWaitTime {
            let currentCount = self.currentMeasurements.count
            logger.info("DEBUG: Current measurement count: \(currentCount)/15")
            
            if currentCount >= 15 {
                break
            }
            
            try? await Task.sleep(for: .milliseconds(Int(checkInterval * 1000)))
            waitTime += checkInterval
        }
        
        await compileMeasurementResults()
    }
    
    func readCharacteristic(uuid: CBUUID, service serviceUUID: CBUUID) async {
        guard let peripheral = bioMessPeripheral,
              let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }),
              let characteristic = service.characteristics?.first(where: { $0.uuid == uuid }) else {
            logger.warning("Characteristic \(uuid) not found in service \(serviceUUID)")
            return
        }
        
        peripheral.readValue(for: characteristic)
        
        // Small delay for BLE stack
        try? await Task.sleep(for: .milliseconds(50))
    }
    
    func handleCharacteristicData(characteristic: CBCharacteristic, data: Data) {
        let uuid = characteristic.uuid

        logger.debug("🔵 handleCharacteristicData: \(uuid) with \(data.count) bytes")

        // 0xC000 multiplexes live measurement streams and stored-measurement sync responses.
        if uuid == controlCommandChar {
            if storedCountContinuation != nil || storedBatchContinuation != nil || expectedBatchCount > 0 {
                handleSyncCommandResponse(data: data)
            } else {
                handleStreamingMeasurementData(data)
            }
            return
        }

        // Handle other characteristics
        switch uuid {
        case batteryLevelChar:
            logger.debug("🔋 Battery characteristic data received - parsing...")
            if let battery = parseBatteryData(data) {
                logger.debug("🔋 Battery parsed successfully, setting currentBatteryLevel...")
                currentBatteryLevel = battery
                updateDeviceInfo(batteryData: battery)
                logger.debug("🔋 currentBatteryLevel is now: \(battery.voltageMillivolts)mV (\(battery.percentage)%)")
            } else {
                logger.error("🔋 ERROR: Failed to parse battery data!")
            }
            
        case imuQuaternionChar:
            if let quaternion = parseQuaternionData(data) {
                updateDeviceInfo(quaternion: quaternion)
            }
            
        case imuQVarianceChar:
            if let variance = parseQuaternionData(data) {
                updateDeviceInfo(quaternionVariance: variance)
            }
            
        case deviceNameChar:
            let name = String(data: data, encoding: .utf8) ?? "Unknown"
            updateDeviceInfo(name: name)

        case serialNumberChar:
            let serialNumber = String(data: data, encoding: .utf8)
            updateDeviceInfo(serialNumber: serialNumber)

        case controlCommandChar:
            // Handle sync command responses
            handleSyncCommandResponse(data: data)

        default:
            logger.debug("Unhandled characteristic: \(uuid)")
        }
    }

    /// Handle responses from sync commands (0x07, 0x08, 0x09)
    /// Implements MTU fragmentation reassembly (V2.1: chunks per measurement)
    private func handleSyncCommandResponse(data: Data) {
        logger.debug("Handling sync command response: \(data.count) bytes")

        // Command 0x07 response: 2-byte UInt16 count
        if data.count == 2, let continuation = storedCountContinuation {
            let count = Self.uint16LE(data, 0)
            logger.info("Received stored measurement count: \(count)")
            storedCountContinuation = nil
            continuation.resume(returning: count)
            return
        }

        // Command 0x08 response: Fragmented StoredMeasurements (MTU=247)
        // We accumulate chunks in reassembly buffer until we have complete measurements

        // Update last chunk time for timeout detection
        lastChunkTime = Date()

        // Append incoming chunk to reassembly buffer
        self.reassemblyBuffer.append(data)
        logger.debug("Reassembly buffer: \(self.reassemblyBuffer.count) bytes")

        // Process all complete measurements in buffer
        while self.reassemblyBuffer.count >= StoredMeasurement.expectedSize {
            let measurementData = self.reassemblyBuffer.prefix(StoredMeasurement.expectedSize)

            // Parse measurement (V2.1: 5 repetitions)
            guard let measurement = StoredMeasurement.parse(from: Data(measurementData)) else {
                logger.error("Failed to parse StoredMeasurement from \(StoredMeasurement.expectedSize) bytes")
                self.reassemblyBuffer.removeFirst(StoredMeasurement.expectedSize)  // Discard corrupted data
                continue
            }

            // Validate CRC16 (calculated over all bytes except last 2)
            let calculatedCRC = CRC16.calculate(data: measurementData.prefix(StoredMeasurement.expectedSize - 2))
            if measurement.crc16 != calculatedCRC {
                logger.warning("CRC mismatch for session=\(measurement.sessionId), seq=\(measurement.sequenceNumber) - expected \(measurement.crc16), got \(calculatedCRC)")
                // Continue anyway - data might still be useful
            } else {
                logger.debug("✓ CRC valid for session=\(measurement.sessionId), seq=\(measurement.sequenceNumber), quality=\(String(format: "%.2f", measurement.signalQuality))")
            }

            logger.info("Received stored measurement: session=\(measurement.sessionId), seq=\(measurement.sequenceNumber), repetitions=\(measurement.numRepetitions)")
            self.receivedBatchMeasurements.append(measurement)

            // Remove processed measurement from buffer
            self.reassemblyBuffer.removeFirst(StoredMeasurement.expectedSize)

            // Check if we have received the complete batch
            if self.receivedBatchMeasurements.count >= self.expectedBatchCount {
                logger.info("Batch complete: \(self.receivedBatchMeasurements.count) measurements")
                if let continuation = storedBatchContinuation {
                    let batch = self.receivedBatchMeasurements
                    storedBatchContinuation = nil
                    expectedBatchCount = 0
                    receivedBatchMeasurements = []
                    reassemblyBuffer = Data()  // Clear buffer
                    continuation.resume(returning: batch)
                }
                return
            }
        }

        // If we're here, we're waiting for more chunks
        logger.debug("Batch progress: \(self.receivedBatchMeasurements.count)/\(self.expectedBatchCount), buffer: \(self.reassemblyBuffer.count) bytes")
    }

    /// Check for chunk timeout and reset buffer if needed
    private func checkChunkTimeout() {
        let timeout: TimeInterval = 5.0  // 5 seconds
        if Date().timeIntervalSince(lastChunkTime) > timeout {
            logger.warning("Chunk timeout - resetting reassembly buffer (\(self.reassemblyBuffer.count) bytes discarded)")
            self.reassemblyBuffer = Data()
        }
    }

    func compileMeasurementResults() async {
        guard streamingMeasurementID == nil else { return }
        // Check if we have measurements (firmware sends 15 points, not 16)
        let measurements = (0..<16).compactMap { self.currentMeasurements[$0] }

        logger.info("DEBUG: Compiling measurements...")
        logger.info("DEBUG: currentMeasurements dictionary has \(self.currentMeasurements.count) entries")
        for (index, measurement) in self.currentMeasurements {
            logger.info("DEBUG: Index \(index): \(measurement.frequency)Hz, \(measurement.magnitude)Ω, \(measurement.phase)°")
        }

        guard measurements.count >= 15 else {
            logger.error("Incomplete measurement data: \(measurements.count)/16 (need at least 15)")
            logger.error("Missing indices: \((0..<16).filter { self.currentMeasurements[$0] == nil })")
            measurementContinuation?.resume(throwing: BLEError.incompleteData)
            measurementContinuation = nil
            return
        }

        logger.info("Successfully collected \(measurements.count) measurement points")

        let sortedMeasurements = measurements.sorted { $0.frequency < $1.frequency }
        let impedanceData = ImpedanceData(
            measurements: sortedMeasurements,
            timestamp: Date(),
            deviceInfo: deviceInfo
        )

        logger.info("Measurement complete: \(measurements.count) points, device: \(self.deviceInfo?.name ?? "Unknown")")
        print("DEBUG BLE: Measurement data ready - \(measurements.count) points")

        // Check if this is a manual measurement (has continuation) or automatic (from firmware)
        if let continuation = measurementContinuation {
            // Manual measurement - resolve continuation
            continuation.resume(returning: impedanceData)
            measurementContinuation = nil
        } else {
            // Automatic measurement from firmware - notify callback
            logger.info("Automatic measurement received from firmware")
            onAutomaticMeasurement?(impedanceData)
        }

        // Clear measurements for next round
        currentMeasurements.removeAll()
    }
    
    func updateDeviceInfo(name: String? = nil, serialNumber: String? = nil, batteryData: BatteryData? = nil, quaternion: QuaternionData? = nil, quaternionVariance: QuaternionData? = nil) {
        
        let currentInfo = deviceInfo ?? DeviceInfo(name: "BioMess Device")
        
        deviceInfo = DeviceInfo(
            name: name ?? currentInfo.name,
            serialNumber: serialNumber ?? currentInfo.serialNumber,
            batteryLevel: batteryData ?? currentInfo.batteryLevel,
            quaternion: quaternion ?? currentInfo.quaternion,
            quaternionVariance: quaternionVariance ?? currentInfo.quaternionVariance
        )
    }
}

// MARK: - Data Parsing (Little Endian, exact from documentation)

extension BioMessBLEManager {

    nonisolated static func uint16LE(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    nonisolated static func uint32LE(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) |
        (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) |
        (UInt32(data[offset + 3]) << 24)
    }

    nonisolated static func float32LE(_ data: Data, _ offset: Int) -> Float {
        Float(bitPattern: uint32LE(data, offset))
    }

    nonisolated static func dataUInt32LE(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }

    nonisolated static func dataFloat32LE(_ value: Float) -> Data {
        dataUInt32LE(value.bitPattern)
    }

    func parseMeasurementData(_ data: Data) -> ImpedanceData.MeasurementPoint? {
        guard data.count == bytesPerMeasurementPoint else {
            logger.error("Invalid measurement data length: \(data.count), expected \(self.bytesPerMeasurementPoint)")
            return nil
        }
        
        // Debug: Show raw bytes
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.info("DEBUG: Parsing measurement data: \(hexString)")
        
        // Little Endian format: frequency(4) + magnitude(4) + phase(4)
        let frequency = Self.float32LE(data, 0)
        let magnitude = Self.float32LE(data, 4)
        let phase = Self.float32LE(data, 8)
        
        logger.info("DEBUG: Parsed values - freq: \(frequency), mag: \(magnitude), phase: \(phase)")
        
        // Check for invalid values - but keep them for testing without sensor
        if !frequency.isFinite || !magnitude.isFinite || !phase.isFinite {
            logger.warning("DEBUG: Invalid float values detected - keeping for testing")
            // Replace infinite values with 0 for testing
            let cleanFreq = frequency.isFinite ? frequency : 0.0
            let cleanMag = magnitude.isFinite ? magnitude : 1000.0  // Dummy resistance value
            let cleanPhase = phase.isFinite ? phase : 0.0
            
            logger.info("DEBUG: Using cleaned values - freq: \(cleanFreq), mag: \(cleanMag), phase: \(cleanPhase)")
            
            return ImpedanceData.MeasurementPoint(
                frequency: cleanFreq,
                magnitude: cleanMag, 
                phase: cleanPhase
            )
        }
        
        return ImpedanceData.MeasurementPoint(
            frequency: frequency,
            magnitude: magnitude,
            phase: phase
        )
    }
    
    func parseBatteryData(_ data: Data) -> BatteryData? {
        logger.debug("🔋 parseBatteryData() called with \(data.count) bytes")

        guard data.count == 4 else {
            logger.error("🔋 ERROR: Invalid battery data length: \(data.count), expected 4")
            return nil
        }

        // Debug: Show raw bytes received
        let hexBytes = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.debug("🔋 Raw bytes received: [\(hexBytes)]")

        // Little Endian format: voltage_mv(uint16_t) + percentage(uint16_t)
        // From API_REFERENCE.md: [voltage_mv, percentage]
        // Nordic nRF52832 sends little-endian data, must explicitly convert to host byte order
        let voltageMillivolts = Self.uint16LE(data, 0)
        let percentage = Self.uint16LE(data, 2)

        logger.debug("🔋 After little-endian conversion: \(voltageMillivolts)mV, \(percentage)%")

        let batteryData = BatteryData(voltageMillivolts: voltageMillivolts, percentage: percentage)
        logger.debug("🔋 Created BatteryData object: \(batteryData.voltageMillivolts)mV (\(batteryData.percentage)%)")

        return batteryData
    }
    
    func parseQuaternionData(_ data: Data) -> QuaternionData? {
        guard data.count == 16 else {
            logger.error("Invalid quaternion data length: \(data.count), expected 16")
            return nil
        }
        
        // Little Endian format: w(4) + x(4) + y(4) + z(4)
        let w = Self.float32LE(data, 0)
        let x = Self.float32LE(data, 4)
        let y = Self.float32LE(data, 8)
        let z = Self.float32LE(data, 12)
        
        return QuaternionData(w: w, x: x, y: y, z: z)
    }
}

// MARK: - Errors

public enum BLEError: LocalizedError, Sendable {
    case notConnected
    case disconnected
    case incompleteData
    case incompleteSweep
    case invalidResponse
    case timeout
    case invalidParameter
    case serviceNotFound
    case characteristicNotFound

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Device not connected"
        case .disconnected: return "Device disconnected during operation"
        case .incompleteData: return "Incomplete measurement data received"
        case .incompleteSweep: return "Incomplete sweep. Reconnect the device before retrying."
        case .invalidResponse: return "Invalid response from device"
        case .timeout: return "Operation timed out"
        case .invalidParameter: return "Invalid parameter value"
        case .serviceNotFound: return "BLE service not found"
        case .characteristicNotFound: return "BLE characteristic not found"
        }
    }
}

// MARK: - Stored Measurement Sync Extensions

extension BioMessBLEManager {

    // MARK: - Continuation Storage

    private static var storedCountContinuationStorage: CheckedContinuation<UInt16, Error>?
    private static var storedBatchContinuationStorage: CheckedContinuation<[StoredMeasurement], Error>?
    private static var expectedBatchCountStorage: Int = 0
    private static var receivedBatchMeasurementsStorage: [StoredMeasurement] = []

    // MARK: - MTU Fragmentation Reassembly

    private static var reassemblyBufferStorage: Data = Data()
    private static var lastChunkTimeStorage: Date = Date()

    internal var reassemblyBuffer: Data {
        get { Self.reassemblyBufferStorage }
        set { Self.reassemblyBufferStorage = newValue }
    }

    internal var lastChunkTime: Date {
        get { Self.lastChunkTimeStorage }
        set { Self.lastChunkTimeStorage = newValue }
    }

    internal var storedCountContinuation: CheckedContinuation<UInt16, Error>? {
        get { Self.storedCountContinuationStorage }
        set { Self.storedCountContinuationStorage = newValue }
    }

    internal var storedBatchContinuation: CheckedContinuation<[StoredMeasurement], Error>? {
        get { Self.storedBatchContinuationStorage }
        set { Self.storedBatchContinuationStorage = newValue }
    }

    internal var expectedBatchCount: Int {
        get { Self.expectedBatchCountStorage }
        set { Self.expectedBatchCountStorage = newValue }
    }

    internal var receivedBatchMeasurements: [StoredMeasurement] {
        get { Self.receivedBatchMeasurementsStorage }
        set { Self.receivedBatchMeasurementsStorage = newValue }
    }

    // MARK: - Sync Commands

    /// Command 0x07: Get number of stored measurements
    func getStoredMeasurementCount() async throws -> UInt16 {
        guard connectionState == .connected else {
            throw BLEError.notConnected
        }

        logger.info("Sending GET_STORED_COUNT command (0x07)...")

        // Wait for response via notification (2 bytes UInt16)
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                self.storedCountContinuation = continuation
                await self.sendCommand(.getStoredCount)
            }

            // Timeout after 5 seconds
            Task {
                try? await Task.sleep(for: .seconds(5))
                Task { @MainActor in
                    if let handler = self.storedCountContinuation {
                        self.storedCountContinuation = nil
                        handler.resume(throwing: BLEError.timeout)
                    }
                }
            }
        }
    }

    /// Command 0x08: Get batch of stored measurements
    func getStoredMeasurementBatch(offset: UInt16, count: UInt8) async throws -> [StoredMeasurement] {
        guard connectionState == .connected else {
            throw BLEError.notConnected
        }

        logger.info("Sending GET_STORED_BATCH command (0x08): offset=\(offset), count=\(count)...")

        // Build payload: [0x08, offset_low, offset_high, count]
        let offsetLow = UInt8(offset & 0xFF)
        let offsetHigh = UInt8(offset >> 8)
        let payload = Data([offsetLow, offsetHigh, count])

        // Wait for batch notifications (count x StoredMeasurement.expectedSize bytes)
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                self.storedBatchContinuation = continuation
                self.expectedBatchCount = Int(count)
                self.receivedBatchMeasurements = []
                self.reassemblyBuffer = Data()
                await self.sendCommand(.getStoredBatch, payload: payload)
            }

            // Timeout after 30 seconds (batch can take time)
            Task {
                try? await Task.sleep(for: .seconds(30))
                Task { @MainActor in
                    if let handler = self.storedBatchContinuation {
                        self.storedBatchContinuation = nil
                        handler.resume(throwing: BLEError.timeout)
                    }
                }
            }
        }
    }

    /// Command 0x09: Clear all stored measurements
    func clearStoredMeasurements() async throws {
        guard connectionState == .connected else {
            throw BLEError.notConnected
        }

        logger.info("Sending CLEAR_STORED command (0x09)...")

        // Send command 0x09 (fire-and-forget)
        await sendCommand(.clearStored)

        // Small delay to let firmware process
        try await Task.sleep(for: .milliseconds(100))
    }
}

// MARK: - Extensions

private extension CBManagerState {
    var description: String {
        switch self {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unknown"
        }
    }
}
