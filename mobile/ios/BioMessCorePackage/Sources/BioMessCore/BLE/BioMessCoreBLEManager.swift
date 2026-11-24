import Foundation
@preconcurrency import CoreBluetooth
import OSLog

/// Core Bluetooth manager for BioMess bioimpedance device
/// Implements exact BLE protocol from BLE_PROTOCOL_IMPLEMENTATION.md
@Observable
@MainActor
public final class BioMessCoreBLEManager: NSObject, Sendable {
    
    // MARK: - State
    
    public enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting
        case connected
        case measuring
        case error(String)
    }
    
    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var discoveredDevices: [CBPeripheral] = []
    public private(set) var connectedDevice: CBPeripheral?
    public private(set) var lastError: String?
    
    // MARK: - Private Properties
    
    private var centralManager: CBCentralManager!
    private var bioMessPeripheral: CBPeripheral?
    private let logger = Logger(subsystem: "com.biomess.health", category: "BLE")
    
    // Data collection
    private var currentMeasurements: [Int: ImpedanceData.MeasurementPoint] = [:]
    private var deviceInfo: DeviceInfo?
    private var measurementContinuation: CheckedContinuation<ImpedanceData, Error>?
    
    // MARK: - BLE UUIDs (Exact from documentation)
    
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
    
    // Environment characteristics
    private let imuQuaternionChar = CBUUID(string: "0000c201-0000-1000-8000-00805f9b34fb")
    private let batteryLevelChar = CBUUID(string: "0000c202-0000-1000-8000-00805f9b34fb")
    private let imuQVarianceChar = CBUUID(string: "0000c203-0000-1000-8000-00805f9b34fb")
    
    // Measurement characteristics (16 channels: 0x0-0xF)
    private let measurementCharacteristics: [CBUUID] = [
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
        CBUUID(string: "0000c11f-0000-1000-8000-00805f9b34fb")  // MEASF
    ]
    
    // MARK: - Commands (Exact from documentation)
    
    private enum BioMessCoreCommands: UInt8 {
        case startMeasurement = 1        // Start bioimpedance + IMU measurement
        case stopReset = 2              // Stop/reset device
        case standby = 4                // Standby/sleep mode
        case measureIMUVariance = 5     // Measure IMU variance specifically
        case ledBlink = 100            // Test connection - blink LED
        case sleep20Seconds = 205       // Sleep 20 seconds
        case sleep5Minutes = 203        // Sleep 5 minutes
        case sleep14Point5Minutes = 202 // Sleep 14.5 minutes
    }
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
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

        // Scan for ALL BLE devices (no service filter)
        // We filter by BioMess-compatible advertising names in didDiscover delegate
        centralManager.scanForPeripherals(
            withServices: nil,  // Scan all devices, filter by name later
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Auto-stop scan after 15 seconds (longer for broader scan)
        Task {
            try? await Task.sleep(for: .seconds(15))
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
        connectionState = .connecting
        bioMessPeripheral = device
        connectedDevice = device
        centralManager.connect(device, options: nil)
    }
    
    public func disconnect() {
        guard let peripheral = bioMessPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
        bioMessPeripheral = nil
        connectedDevice = nil
        connectionState = .disconnected
        logger.info("Disconnected from device")
    }
    
    /// Perform complete bioimpedance measurement following exact protocol timing
    public func performMeasurement() async throws -> ImpedanceData {
        guard bioMessPeripheral != nil, connectionState == .connected else {
            throw BLEError.notConnected
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            measurementContinuation = continuation
            
            Task {
                do {
                    connectionState = .measuring
                    currentMeasurements.removeAll()
                    
                    logger.info("Starting measurement protocol...")
                    
                    // 1. START MEASUREMENT
                    await sendCommand(.startMeasurement)
                    
                    // 2. WAIT OBLIGATORIO - 4 segundos para completar medición
                    logger.info("Waiting 4 seconds for measurement completion...")
                    try await Task.sleep(for: .seconds(4))
                    
                    // 3. STANDBY
                    await sendCommand(.standby)
                    
                    // 4. WAIT DATOS VÁLIDOS - 15 segundos para preparar datos
                    logger.info("Waiting 15 seconds for data preparation...")
                    try await Task.sleep(for: .seconds(15))
                    
                    // 5. LEER TODAS LAS CARACTERÍSTICAS
                    await readAllMeasurements()
                    
                    // 6. SLEEP DISPOSITIVO
                    await sendCommand(.sleep14Point5Minutes)
                    try await Task.sleep(for: .seconds(10))
                    await sendCommand(.stopReset)
                    
                    connectionState = .connected
                    logger.info("Measurement protocol completed")
                    
                } catch {
                    connectionState = .connected
                    continuation.resume(throwing: error)
                    measurementContinuation = nil
                }
            }
        }
    }
    
    /// Test device connection by blinking LED
    public func testConnection() async {
        await sendCommand(.ledBlink)
        logger.info("LED blink command sent")
    }
}

// MARK: - CBCentralManagerDelegate

extension BioMessCoreBLEManager: CBCentralManagerDelegate {
    
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.info("Central manager state: \(central.state.description)")
        
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                break // Ready to scan
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
        
        // Only add BioMess devices
        if let name = peripheral.name, name.contains("BioMess") {
            logger.info("Discovered BioMess device: \(name)")
            
            Task { @MainActor in
                if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                    discoveredDevices.append(peripheral)
                }
            }
        }
    }
    
    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        
        peripheral.delegate = self
        
        Task { @MainActor in
            connectionState = .connected
        }
        
        // Discover all services
        peripheral.discoverServices([
            Self.generalService,
            Self.bioMessControlService,
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
            if let error = error {
                logger.error("Disconnected with error: \(error.localizedDescription)")
                connectionState = .error("Disconnected: \(error.localizedDescription)")
            } else {
                logger.info("Disconnected from peripheral")
                connectionState = .disconnected
            }
            
            bioMessPeripheral = nil
            connectedDevice = nil
            measurementContinuation?.resume(throwing: BLEError.disconnected)
            measurementContinuation = nil
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BioMessCoreBLEManager: CBPeripheralDelegate {
    
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            logger.error("Service discovery failed: \(error!.localizedDescription)")
            return
        }
        
        logger.info("Discovered \(peripheral.services?.count ?? 0) services")
        
        // Discover characteristics for each service
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            logger.error("Characteristic discovery failed: \(error!.localizedDescription)")
            return
        }
        
        logger.info("Discovered \(service.characteristics?.count ?? 0) characteristics for service \(service.uuid)")
    }
    
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else {
            if let error = error {
                logger.error("Characteristic read failed: \(error.localizedDescription)")
            }
            return
        }
        
        Task { @MainActor in
            handleCharacteristicData(characteristic: characteristic, data: data)
        }
    }
    
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("Characteristic write failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Private Methods

private extension BioMessCoreBLEManager {
    
    private func sendCommand(_ command: BioMessCoreCommands) async {
        guard let peripheral = bioMessPeripheral,
              let service = peripheral.services?.first(where: { $0.uuid == Self.bioMessControlService }),
              let characteristic = service.characteristics?.first(where: { $0.uuid == controlCommandChar }) else {
            logger.error("Cannot send command - control characteristic not found")
            return
        }
        
        let commandData = Data([command.rawValue])
        peripheral.writeValue(commandData, for: characteristic, type: .withoutResponse)
        logger.debug("Sent command: \(String(describing: command))")
        
        // Small delay for BLE stack
        try? await Task.sleep(for: .milliseconds(50))
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
        
        // Read all 16 measurement characteristics
        for (index, uuid) in measurementCharacteristics.enumerated() {
            await readCharacteristic(uuid: uuid, service: Self.bioMessDataService)
            logger.debug("Reading measurement \(index)")
            
            // Small delay between reads
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        // After all reads, compile the final measurement data
        try? await Task.sleep(for: .milliseconds(500)) // Wait for all async reads
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
        
        // Handle measurement characteristics
        if let index = measurementCharacteristics.firstIndex(of: uuid) {
            if let measurement = parseMeasurementData(data) {
                currentMeasurements[index] = measurement
                logger.debug("Parsed measurement \(index): \(measurement.frequency)Hz, \(measurement.magnitude)Ω")
            }
            return
        }
        
        // Handle other characteristics
        switch uuid {
        case batteryLevelChar:
            if let battery = parseBatteryData(data) {
                updateDeviceInfo(batteryData: battery)
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
            
        default:
            logger.debug("Unhandled characteristic: \(uuid)")
        }
    }
    
    func compileMeasurementResults() async {
        // Check if we have all 16 measurements
        let measurements = (0..<16).compactMap { currentMeasurements[$0] }
        
        guard measurements.count == 16 else {
            logger.error("Incomplete measurement data: \(measurements.count)/16")
            measurementContinuation?.resume(throwing: BLEError.incompleteData)
            measurementContinuation = nil
            return
        }
        
        let sortedMeasurements = measurements.sorted { $0.frequency < $1.frequency }
        let impedanceData = ImpedanceData(
            measurements: sortedMeasurements,
            timestamp: Date(),
            deviceInfo: deviceInfo
        )
        
        logger.info("Measurement complete: \(measurements.count) points")
        measurementContinuation?.resume(returning: impedanceData)
        measurementContinuation = nil
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

private extension BioMessCoreBLEManager {
    
    func parseMeasurementData(_ data: Data) -> ImpedanceData.MeasurementPoint? {
        guard data.count == 12 else {
            logger.error("Invalid measurement data length: \(data.count), expected 12")
            return nil
        }
        
        // Little Endian format: frequency(4) + magnitude(4) + phase(4)
        let frequency = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Float.self) }
        let magnitude = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Float.self) }
        let phase = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: Float.self) }
        
        return ImpedanceData.MeasurementPoint(
            frequency: frequency,
            magnitude: magnitude,
            phase: phase
        )
    }
    
    func parseBatteryData(_ data: Data) -> BatteryData? {
        guard data.count == 4 else {
            logger.error("Invalid battery data length: \(data.count), expected 4")
            return nil
        }
        
        // Little Endian format: level(2) + percentage(2)
        let level = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int16.self) }
        let percentage = data.withUnsafeBytes { $0.load(fromByteOffset: 2, as: Int16.self) }
        
        return BatteryData(level: level, percentage: percentage)
    }
    
    func parseQuaternionData(_ data: Data) -> QuaternionData? {
        guard data.count == 16 else {
            logger.error("Invalid quaternion data length: \(data.count), expected 16")
            return nil
        }
        
        // Little Endian format: w(4) + x(4) + y(4) + z(4)
        let w = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Float.self) }
        let x = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Float.self) }
        let y = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: Float.self) }
        let z = data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: Float.self) }
        
        return QuaternionData(w: w, x: x, y: y, z: z)
    }
}

// MARK: - Errors

public enum BLEError: LocalizedError, Sendable {
    case notConnected
    case disconnected
    case incompleteData
    case invalidResponse
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Device not connected"
        case .disconnected: return "Device disconnected during operation"
        case .incompleteData: return "Incomplete measurement data received"
        case .invalidResponse: return "Invalid response from device"
        case .timeout: return "Operation timed out"
        }
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
