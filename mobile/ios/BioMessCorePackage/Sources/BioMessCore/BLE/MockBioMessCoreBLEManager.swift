import Foundation
import OSLog

/// Mock BLE manager for development and testing without hardware
/// Simulates exact BioMess device behavior with realistic bioimpedance data
@Observable
@MainActor
public final class MockBioMessCoreBLEManager: Sendable {
    
    // MARK: - State (Same interface as real manager)
    
    public enum ConnectionState: Equatable, Sendable {
        case disconnected
        case scanning
        case connecting
        case connected
        case measuring
        case error(String)
    }
    
    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var discoveredDevices: [MockDevice] = []
    public private(set) var connectedDevice: MockDevice?
    public private(set) var lastError: String?
    
    private let logger = Logger(subsystem: "com.biomess.health.mock", category: "BLE")
    
    // MARK: - Mock Device
    
    public struct MockDevice: Identifiable, Sendable {
        public let id = UUID()
        public let name: String
        public let serialNumber: String
        public let rssi: Int
        
        public init(name: String, serialNumber: String, rssi: Int = -50) {
            self.name = name
            self.serialNumber = serialNumber
            self.rssi = rssi
        }
    }
    
    // MARK: - Mock Data Generation
    
    /// Generate realistic bioimpedance data that passes Cole validation
    private func generateRealisticImpedanceData() -> ImpedanceData {
        // Enhanced bioimpedance data based on real measurements but optimized for algorithm
        // Represents typical human calf bioimpedance with proper Cole characteristics
        let realMeasurements: [(frequency: Float, magnitude: Float, phase: Float)] = [
            (1000, 68.2, -1.2),     // 1 kHz - low freq, higher magnitude
            (2000, 67.8, -2.1),     // 2 kHz  
            (3000, 67.2, -3.0),     // 3 kHz
            (5000, 66.1, -4.2),     // 5 kHz
            (7000, 64.8, -5.1),     // 7 kHz
            (10000, 63.1, -6.2),    // 10 kHz
            (15000, 60.9, -7.8),    // 15 kHz
            (20000, 58.5, -8.9),    // 20 kHz - approaching characteristic frequency
            (30000, 55.2, -9.8),    // 30 kHz
            (40000, 52.1, -10.1),   // 40 kHz - past characteristic frequency
            (50000, 49.8, -9.7),    // 50 kHz
            (70000, 47.2, -8.9),    // 70 kHz
            (100000, 45.1, -7.8),   // 100 kHz
            (120000, 43.8, -6.9),   // 120 kHz
            (150000, 42.9, -5.8)    // 150 kHz - approaching high freq asymptote
        ]
        
        var measurements: [ImpedanceData.MeasurementPoint] = []
        
        for (frequency, baseMagnitude, basePhase) in realMeasurements {
            // Add realistic measurement noise
            let noiseMag = Float.random(in: -0.3...0.3)    // ±0.3Ω variation
            let noisePhase = Float.random(in: -0.15...0.15) // ±0.15° variation
            
            let magnitude = max(baseMagnitude + noiseMag, 30.0) // Ensure minimum magnitude
            let phase = basePhase + noisePhase
            
            measurements.append(ImpedanceData.MeasurementPoint(
                frequency: frequency,
                magnitude: magnitude,
                phase: phase
            ))
        }
        
        // Generate mock device info
        let battery = BatteryData(level: 3600, percentage: 85)
        let quaternion = QuaternionData(w: 0.98, x: 0.02, y: 0.01, z: 0.19) // Slight orientation
        let quaternionVariance = QuaternionData(w: 0.001, x: 0.0005, y: 0.0003, z: 0.0008)
        
        let deviceInfo = DeviceInfo(
            name: connectedDevice?.name ?? "Mock BioMess",
            serialNumber: connectedDevice?.serialNumber ?? "MOCK001",
            batteryLevel: battery,
            quaternion: quaternion,
            quaternionVariance: quaternionVariance
        )
        
        return ImpedanceData(
            measurements: measurements,
            timestamp: Date(),
            deviceInfo: deviceInfo
        )
    }
    
    // MARK: - Public API (Same as real manager)
    
    public init() {
        // Pre-populate some mock devices
        discoveredDevices = [
            MockDevice(name: "BioMess-Dev-001", serialNumber: "VLM001", rssi: -45),
            MockDevice(name: "BioMess-Dev-002", serialNumber: "VLM002", rssi: -60),
            MockDevice(name: "BioMess-Proto", serialNumber: "VLM999", rssi: -55)
        ]
    }
    
    public func startScanning() {
        logger.info("Mock: Starting scan for BioMess devices...")
        connectionState = .scanning
        
        // Do NOT automatically timeout - let user manually cancel or connect
        // This solves the issue of devices disappearing automatically
    }
    
    public func stopScanning() {
        connectionState = .disconnected
        logger.info("Mock: Stopped scanning")
    }
    
    public func connect(to device: MockDevice) {
        logger.info("Mock: Connecting to device: \(device.name)")
        connectionState = .connecting
        
        Task {
            try? await Task.sleep(for: .seconds(1)) // Simulate connection time
            
            connectedDevice = device
            connectionState = .connected
            logger.info("Mock: Connected to \(device.name)")
        }
    }
    
    public func disconnect() {
        connectedDevice = nil
        connectionState = .disconnected
        logger.info("Mock: Disconnected from device")
    }
    
    /// Simulate complete bioimpedance measurement with exact timing
    public func performMeasurement() async throws -> ImpedanceData {
        guard connectedDevice != nil, connectionState == .connected else {
            throw BLEError.notConnected
        }
        
        connectionState = .measuring
        logger.info("Mock: Starting measurement protocol...")
        
        // Fast mock measurement for development (3 seconds total)
        
        // 1. START MEASUREMENT
        logger.info("Mock: Sending START_MEASUREMENT command")
        try? await Task.sleep(for: .milliseconds(100))
        
        // 2. Fast measurement simulation 
        logger.info("Mock: Simulating measurement...")
        try await Task.sleep(for: .seconds(2))
        
        // 3. STANDBY  
        logger.info("Mock: Sending STANDBY command")
        try? await Task.sleep(for: .milliseconds(100))
        
        // 4. Fast data preparation
        logger.info("Mock: Preparing data...")
        try await Task.sleep(for: .milliseconds(500))
        
        // 5. Fast reading of measurements
        logger.info("Mock: Reading all measurements...")
        try? await Task.sleep(for: .milliseconds(300))
        
        // 6. SLEEP DISPOSITIVO
        logger.info("Mock: Sending SLEEP commands")
        try? await Task.sleep(for: .milliseconds(100))
        
        connectionState = .connected
        logger.info("Mock: Measurement protocol completed")
        
        return generateRealisticImpedanceData()
    }
    
    /// Simulate LED blink test
    public func testConnection() async {
        logger.info("Mock: LED blink command sent")
        try? await Task.sleep(for: .milliseconds(500))
    }
}

