import Foundation

/// Core bioimpedance measurement data from BioMess device
public struct ImpedanceData: Sendable, Equatable, Codable {
    /// Measurement point for a single frequency
    public struct MeasurementPoint: Sendable, Equatable, Identifiable, Codable {
        public let id = UUID()
        public let frequency: Float     // Hz
        public let magnitude: Float     // Ohms (Ω)
        public let phase: Float         // Degrees
        
        /// Complex impedance representation
        public var complexImpedance: Complex {
            let radians = phase * .pi / 180.0
            return Complex(
                real: magnitude * cos(radians),
                imaginary: magnitude * sin(radians)
            )
        }
        
        public init(frequency: Float, magnitude: Float, phase: Float) {
            self.frequency = frequency
            self.magnitude = magnitude
            self.phase = phase
        }
    }
    
    /// 15 measurement points for BioMess device (updated from PCB specs)
    public let measurements: [MeasurementPoint]
    public let timestamp: Date
    public let deviceInfo: DeviceInfo?
    
    /// Frequencies array for convenience
    public var frequencies: [Float] {
        measurements.map { $0.frequency }
    }
    
    /// Magnitudes array for convenience
    public var magnitudes: [Float] {
        measurements.map { $0.magnitude }
    }
    
    /// Phases array for convenience
    public var phases: [Float] {
        measurements.map { $0.phase }
    }
    
    /// Complex impedances for algorithm processing
    public var complexImpedances: [Complex] {
        measurements.map { $0.complexImpedance }
    }
    
    public init(measurements: [MeasurementPoint], timestamp: Date = Date(), deviceInfo: DeviceInfo? = nil) {
        self.measurements = measurements
        self.timestamp = timestamp
        self.deviceInfo = deviceInfo
    }
}

/// Complex number representation for bioimpedance calculations
public struct Complex: Sendable, Equatable, Codable {
    public let real: Float
    public let imaginary: Float
    
    public var magnitude: Float {
        sqrt(real * real + imaginary * imaginary)
    }
    
    public var phase: Float {
        atan2(imaginary, real) * 180.0 / .pi
    }
    
    public init(real: Float, imaginary: Float) {
        self.real = real
        self.imaginary = imaginary
    }
    
    public init(magnitude: Float, phase: Float) {
        let radians = phase * .pi / 180.0
        self.real = magnitude * cos(radians)
        self.imaginary = magnitude * sin(radians)
    }
    
    // MARK: - Mathematical Operations
    
    public static func + (lhs: Complex, rhs: Complex) -> Complex {
        return Complex(real: lhs.real + rhs.real, imaginary: lhs.imaginary + rhs.imaginary)
    }
    
    public static func - (lhs: Complex, rhs: Complex) -> Complex {
        return Complex(real: lhs.real - rhs.real, imaginary: lhs.imaginary - rhs.imaginary)
    }
    
    public static func * (lhs: Complex, rhs: Complex) -> Complex {
        return Complex(
            real: lhs.real * rhs.real - lhs.imaginary * rhs.imaginary,
            imaginary: lhs.real * rhs.imaginary + lhs.imaginary * rhs.real
        )
    }
    
    public static func / (lhs: Complex, rhs: Complex) -> Complex {
        let denominator = rhs.real * rhs.real + rhs.imaginary * rhs.imaginary
        return Complex(
            real: (lhs.real * rhs.real + lhs.imaginary * rhs.imaginary) / denominator,
            imaginary: (lhs.imaginary * rhs.real - lhs.real * rhs.imaginary) / denominator
        )
    }
    
    public func power(_ alpha: Float) -> Complex {
        let magnitude = pow(self.magnitude, alpha)
        let phase = self.phase * alpha * .pi / 180.0  // Convert to radians for calculation
        return Complex(
            real: magnitude * cos(phase),
            imaginary: magnitude * sin(phase)
        )
    }
}

/// Device information from BLE characteristics
public struct DeviceInfo: Sendable, Equatable, Codable {
    public let name: String
    public let serialNumber: String?
    public let batteryLevel: BatteryData?
    public let quaternion: QuaternionData?
    public let quaternionVariance: QuaternionData?
    
    public init(name: String, serialNumber: String? = nil, batteryLevel: BatteryData? = nil, quaternion: QuaternionData? = nil, quaternionVariance: QuaternionData? = nil) {
        self.name = name
        self.serialNumber = serialNumber
        self.batteryLevel = batteryLevel
        self.quaternion = quaternion
        self.quaternionVariance = quaternionVariance
    }
}

/// Battery data from BLE characteristic
public struct BatteryData: Sendable, Equatable, Codable {
    public let level: Int16        // Absolute level
    public let percentage: Int16   // Percentage
    
    public init(level: Int16, percentage: Int16) {
        self.level = level
        self.percentage = percentage
    }
}

/// IMU quaternion data from BLE characteristic
public struct QuaternionData: Sendable, Equatable, Codable {
    public let w: Float
    public let x: Float
    public let y: Float
    public let z: Float
    
    /// Quaternion magnitude (should be close to 1.0 for normalized quaternions)
    public var magnitude: Float {
        sqrt(w*w + x*x + y*y + z*z)
    }
    
    public init(w: Float, x: Float, y: Float, z: Float) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }
}