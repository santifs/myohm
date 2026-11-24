import Foundation

/// Core bioimpedance measurement data from BioMess device
public struct ImpedanceData: Sendable, Equatable, Codable {
    /// Measurement point for a single frequency
    public struct MeasurementPoint: Sendable, Equatable, Identifiable, Codable {
        public let id: UUID
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

        public init(frequency: Float, magnitude: Float, phase: Float, id: UUID = UUID()) {
            self.id = id
            self.frequency = frequency
            self.magnitude = magnitude
            self.phase = phase
        }
    }

    /// Array of repetitions, where each repetition contains measurement points
    /// For single-repetition measurements, this contains one array
    /// For multi-repetition measurements (e.g., numRepetitions=3), this contains N arrays
    public let repetitions: [[MeasurementPoint]]
    public let timestamp: Date
    public let deviceInfo: DeviceInfo?

    /// Number of repetitions in this measurement
    public var numRepetitions: Int {
        repetitions.count
    }

    /// Primary measurement (first repetition) for backward compatibility
    public var measurements: [MeasurementPoint] {
        repetitions.first ?? []
    }

    /// Frequencies array for convenience (from first repetition)
    public var frequencies: [Float] {
        measurements.map { $0.frequency }
    }

    /// Magnitudes array for convenience (from first repetition)
    public var magnitudes: [Float] {
        measurements.map { $0.magnitude }
    }

    /// Phases array for convenience (from first repetition)
    public var phases: [Float] {
        measurements.map { $0.phase }
    }

    /// Complex impedances for algorithm processing (from first repetition)
    public var complexImpedances: [Complex] {
        measurements.map { $0.complexImpedance }
    }

    /// Initialize with multiple repetitions
    public init(repetitions: [[MeasurementPoint]], timestamp: Date = Date(), deviceInfo: DeviceInfo? = nil) {
        self.repetitions = repetitions
        self.timestamp = timestamp
        self.deviceInfo = deviceInfo
    }

    /// Initialize with single repetition (backward compatibility)
    public init(measurements: [MeasurementPoint], timestamp: Date = Date(), deviceInfo: DeviceInfo? = nil) {
        self.repetitions = [measurements]
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

/// Battery data from BLE characteristic (API_REFERENCE.md 0xC202)
public struct BatteryData: Sendable, Equatable, Codable {
    public let voltageMillivolts: UInt16  // Battery voltage in millivolts (mV)
    public let percentage: UInt16         // Battery percentage (0-100%)

    /// Voltage in volts (V)
    public var voltage: Double {
        Double(voltageMillivolts) / 1000.0
    }

    public init(voltageMillivolts: UInt16, percentage: UInt16) {
        self.voltageMillivolts = voltageMillivolts
        self.percentage = percentage
    }

    // MARK: - Migration Support for Old Format

    private enum CodingKeys: String, CodingKey {
        case voltageMillivolts
        case percentage
        case level  // Old format key
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try new format first
        if let voltageMv = try? container.decode(UInt16.self, forKey: .voltageMillivolts) {
            self.voltageMillivolts = voltageMv
            self.percentage = try container.decode(UInt16.self, forKey: .percentage)
        }
        // Fallback to old format (level was Int16, treat as millivolts)
        else if let oldLevel = try? container.decode(Int16.self, forKey: .level) {
            // Old format used 'level' as voltage in mV (but Int16)
            self.voltageMillivolts = UInt16(max(0, oldLevel))

            // Try to get old percentage, default to estimated value
            if let oldPercentage = try? container.decode(Int16.self, forKey: .percentage) {
                self.percentage = UInt16(max(0, oldPercentage))
            } else {
                // Estimate percentage from voltage (3.0V = 100%, 2.0V = 0%)
                let voltage = Double(oldLevel) / 1000.0
                let estimatedPercentage = min(100, max(0, Int((voltage - 2.0) * 100)))
                self.percentage = UInt16(estimatedPercentage)
            }
        }
        // If nothing works, use default values
        else {
            self.voltageMillivolts = 3000  // Default 3.0V
            self.percentage = 50           // Default 50%
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Always encode in new format
        try container.encode(voltageMillivolts, forKey: .voltageMillivolts)
        try container.encode(percentage, forKey: .percentage)
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