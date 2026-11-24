import Foundation
import OSLog

/// Mock BLE manager for development and testing without hardware
/// Simulates exact BioMess device behavior with realistic bioimpedance data
@Observable
@MainActor
public final class MockBioMessBLEManager: Sendable {
    
    // MARK: - State (Same interface as real manager)
    
    public enum ConnectionState: Equatable {
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
    
    /// Generate realistic bioimpedance data based on MATLAB examples
    private func generateRealisticImpedanceData() -> ImpedanceData {
        // 15 frequencies for BioMess device (logarithmically spaced from 1kHz to 150kHz)
        let frequencies: [Float] = [
            1000.0, 1430.3262, 2045.833, 2926.2085, 4185.4326, 5986.534, 8562.696, 12247.448,
            17517.846, 25056.234, 35838.59, 51260.87, 73319.766, 104871.18, 150000.0
        ]

        // Cole parameters (typical human calf values - realistic for body measurements)
        let Re: Float = 15.0     // Extracellular resistance (Ω) - much lower for body
        let Ri: Float = 35.0     // Intracellular resistance (Ω) - realistic range 10-60Ω
        let tau: Float = 0.000008 // Time constant (s) -> fc ≈ 20kHz
        let alpha: Float = 0.85   // Dispersion parameter
        
        var measurements: [ImpedanceData.MeasurementPoint] = []
        
        for frequency in frequencies {
            // Cole model: Z(ω) = Rinf + (R0 - Rinf) / (1 + (jωτ)^α)
            let omega = 2 * Float.pi * frequency
            let jOmegaTau = Complex(real: 0, imaginary: omega * tau)
            let powerTerm = complexPower(jOmegaTau, alpha)
            let denominator = Complex(real: 1, imaginary: 0) + powerTerm
            
            let R0 = Re + Ri  // Total resistance at low frequency
            let Rinf = Re     // Resistance at high frequency
            
            let impedance = Complex(real: Rinf, imaginary: 0) + 
                           Complex(real: R0 - Rinf, imaginary: 0) / denominator
            
            // Add realistic noise (2-3% magnitude, 1-2° phase for body measurements)
            let noiseMag = Float.random(in: -0.03...0.03)
            let noisePhase = Float.random(in: -2.0...2.0)
            
            let magnitude = impedance.magnitude * (1 + noiseMag)
            let phase = impedance.phase + noisePhase
            
            measurements.append(ImpedanceData.MeasurementPoint(
                frequency: frequency,
                magnitude: magnitude,
                phase: phase
            ))
        }
        
        // Generate mock device info
        let battery = BatteryData(voltageMillivolts: 3600, percentage: 85)
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
        
        // Simulate scan duration
        Task {
            try? await Task.sleep(for: .seconds(2))
            stopScanning()
        }
    }
    
    public func stopScanning() {
        if connectionState == .scanning {
            connectionState = .disconnected
        }
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
        
        // Simulate exact protocol timing from documentation
        
        // 1. START MEASUREMENT
        logger.info("Mock: Sending START_MEASUREMENT command")
        try? await Task.sleep(for: .milliseconds(100))
        
        // 2. WAIT 4 segundos obligatorio
        logger.info("Mock: Waiting 4 seconds for measurement completion...")
        try await Task.sleep(for: .seconds(4))
        
        // 3. STANDBY  
        logger.info("Mock: Sending STANDBY command")
        try? await Task.sleep(for: .milliseconds(100))
        
        // 4. WAIT 15 segundos para datos válidos
        logger.info("Mock: Waiting 15 seconds for data preparation...")
        try await Task.sleep(for: .seconds(15))
        
        // 5. LEER TODAS LAS CARACTERÍSTICAS
        logger.info("Mock: Reading all measurements...")
        for i in 0..<16 {
            logger.debug("Mock: Reading measurement \(i)")
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        // 6. SLEEP DISPOSITIVO
        logger.info("Mock: Sending SLEEP commands")
        try? await Task.sleep(for: .seconds(1))
        
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

// MARK: - Complex Math Helpers

private func complexPower(_ base: Complex, _ exponent: Float) -> Complex {
    // (a + bi)^n = r^n * (cos(nθ) + i*sin(nθ))
    let r = base.magnitude
    let theta = base.phase * Float.pi / 180.0
    
    let newR = pow(r, exponent)
    let newTheta = exponent * theta
    
    return Complex(
        real: newR * cos(newTheta),
        imaginary: newR * sin(newTheta)
    )
}

private extension Complex {
    static func +(lhs: Complex, rhs: Complex) -> Complex {
        Complex(real: lhs.real + rhs.real, imaginary: lhs.imaginary + rhs.imaginary)
    }
    
    static func /(lhs: Complex, rhs: Complex) -> Complex {
        let denominator = rhs.real * rhs.real + rhs.imaginary * rhs.imaginary
        return Complex(
            real: (lhs.real * rhs.real + lhs.imaginary * rhs.imaginary) / denominator,
            imaginary: (lhs.imaginary * rhs.real - lhs.real * rhs.imaginary) / denominator
        )
    }
}