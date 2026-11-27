import Foundation
import OSLog

/// Manager for configuring AD5940 bioimpedance chip parameters via BLE
/// Handles frequency sweep configuration (start, stop, points, etc.)
@Observable
@MainActor
public final class AD5940ConfigurationManager: Sendable {

    // MARK: - Configuration

    nonisolated static let maxSweepFrequencyHz: Float = 198_000

    public struct Configuration: Sendable, Equatable {
        public var numOfData: Int32           // Derived local total: sweepPoints * numRepetitions
        public var sweepStart: Float          // Start frequency in Hz
        public var sweepStop: Float           // Stop frequency in Hz
        public var sweepPoints: UInt32        // Number of frequency points
        public var sweepEnable: Bool          // Enable frequency sweep
        public var numRepetitions: UInt8      // Number of repetitions (auto-calculates numOfData)

        // Default configuration: 4-198 kHz, 48 points, 5 repetitions (must match firmware defaults)
        public static let `default` = Configuration(
            numOfData: 240,                   // 5 repetitions × 48 points
            sweepStart: 4000.0,               // 4 kHz
            sweepStop: 198000.0,              // 198 kHz
            sweepPoints: 48,                  // 48 frequency points
            sweepEnable: true,
            numRepetitions: 5                 // 5 repetitions (matches firmware DEFAULT_NUM_REPETITIONS)
        )

        public init(
            numOfData: Int32 = 48,
            sweepStart: Float = 4000.0,
            sweepStop: Float = 198000.0,
            sweepPoints: UInt32 = 48,
            sweepEnable: Bool = true,
            numRepetitions: UInt8 = 1
        ) {
            self.numOfData = numOfData
            self.sweepStart = sweepStart
            self.sweepStop = sweepStop
            self.sweepPoints = sweepPoints
            self.sweepEnable = sweepEnable
            self.numRepetitions = min(max(numRepetitions, 1), 10)  // Clamp to 1-10
        }

        /// Calculate expected frequencies for this configuration
        public var calculatedFrequencies: [Float] {
            guard sweepPoints > 1 else { return [sweepStart] }

            let ratio = pow(Double(sweepStop / sweepStart), 1.0 / Double(sweepPoints - 1))
            return (0..<Int(sweepPoints)).map { n in
                Float(Double(sweepStart) * pow(ratio, Double(n)))
            }
        }
    }

    // MARK: - State

    public private(set) var currentConfig: Configuration = .default
    public private(set) var isSyncing: Bool = false
    public private(set) var lastError: String?

    private let logger = Logger(subsystem: "com.biomess.health", category: "AD5940Config")

    // BLE Service/Characteristic UUIDs (0xAF01 configuration service)
    private let configServiceUUID = "0000AF01-0000-1000-8000-00805F9B34FB"
    private let rcalValueCharUUID = "0000C011-0000-1000-8000-00805F9B34FB"      // DO NOT TOUCH
    private let sweepEnableCharUUID = "0000C012-0000-1000-8000-00805F9B34FB"
    private let sweepStartCharUUID = "0000C013-0000-1000-8000-00805F9B34FB"
    private let sweepStopCharUUID = "0000C014-0000-1000-8000-00805F9B34FB"
    private let sweepPointsCharUUID = "0000C015-0000-1000-8000-00805F9B34FB"
    private let numRepetitionsCharUUID = "0000C017-0000-1000-8000-00805F9B34FB"  // Auto-calculates numOfData = N × sweepPoints

    // MARK: - Public Methods

    /// Write configuration to device
    public func writeConfiguration(
        _ config: Configuration,
        to bleManager: BioMessBLEManager
    ) async throws {
        guard !isSyncing else {
            throw ConfigurationError.syncInProgress
        }

        guard config.sweepStart.isFinite, config.sweepStart > 0,
              config.sweepStop > config.sweepStart,
              config.sweepStop <= Self.maxSweepFrequencyHz else {
            throw BLEError.invalidParameter
        }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        logger.info("Writing AD5940 configuration: \(config.sweepStart)Hz-\(config.sweepStop)Hz, \(config.sweepPoints) points")

        do {
            // Write configuration in sequence. Firmware derives NumOfData internally
            // from SweepPoints × NumRepetitions; there is no BLE C010 characteristic.
            try await writeSweepEnable(config.sweepEnable, to: bleManager)
            try await writeSweepStart(config.sweepStart, to: bleManager)
            try await writeSweepStop(config.sweepStop, to: bleManager)
            try await writeSweepPoints(config.sweepPoints, to: bleManager)
            try await writeNumRepetitions(config.numRepetitions, to: bleManager)  // NEW: Auto-calculates numOfData

            currentConfig = config
            logger.info("Configuration written successfully (\(config.numRepetitions) repetitions)")

        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to write configuration: \(error.localizedDescription)")
            throw error
        }
    }

    /// Read current configuration from device
    public func readConfiguration(
        from bleManager: BioMessBLEManager
    ) async throws -> Configuration {
        guard !isSyncing else {
            throw ConfigurationError.syncInProgress
        }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        logger.info("Reading AD5940 configuration from device")

        do {
            let sweepEnable = try await readSweepEnable(from: bleManager)
            let sweepStart = try await readSweepStart(from: bleManager)
            let sweepStop = try await readSweepStop(from: bleManager)
            let sweepPoints = try await readSweepPoints(from: bleManager)
            let numRepetitions = try await readNumRepetitions(from: bleManager)
            let numOfData = Int32(Int(sweepPoints) * Int(numRepetitions))

            let config = Configuration(
                numOfData: numOfData,
                sweepStart: sweepStart,
                sweepStop: sweepStop,
                sweepPoints: sweepPoints,
                sweepEnable: sweepEnable,
                numRepetitions: numRepetitions
            )

            currentConfig = config
            logger.info("Configuration read successfully: \(config.sweepPoints) points, \(config.numRepetitions) repetitions")

            return config

        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to read configuration: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Private Write Methods

    private func writeSweepEnable(_ value: Bool, to bleManager: BioMessBLEManager) async throws {
        let data = Data([value ? 0x01 : 0x00])

        try await bleManager.writeCharacteristic(
            serviceUUID: configServiceUUID,
            charUUID: sweepEnableCharUUID,
            data: data
        )

        try await Task.sleep(for: .milliseconds(50))
    }

    private func writeSweepStart(_ value: Float, to bleManager: BioMessBLEManager) async throws {
        var littleEndian = value.bitPattern.littleEndian
        let data = Data(bytes: &littleEndian, count: 4)

        try await bleManager.writeCharacteristic(
            serviceUUID: configServiceUUID,
            charUUID: sweepStartCharUUID,
            data: data
        )

        try await Task.sleep(for: .milliseconds(50))
    }

    private func writeSweepStop(_ value: Float, to bleManager: BioMessBLEManager) async throws {
        var littleEndian = value.bitPattern.littleEndian
        let data = Data(bytes: &littleEndian, count: 4)

        try await bleManager.writeCharacteristic(
            serviceUUID: configServiceUUID,
            charUUID: sweepStopCharUUID,
            data: data
        )

        try await Task.sleep(for: .milliseconds(50))
    }

    private func writeSweepPoints(_ value: UInt32, to bleManager: BioMessBLEManager) async throws {
        var littleEndian = value.littleEndian
        let data = Data(bytes: &littleEndian, count: 4)

        try await bleManager.writeCharacteristic(
            serviceUUID: configServiceUUID,
            charUUID: sweepPointsCharUUID,
            data: data
        )

        try await Task.sleep(for: .milliseconds(50))
    }

    private func writeNumRepetitions(_ value: UInt8, to bleManager: BioMessBLEManager) async throws {
        let data = Data([value])

        try await bleManager.writeCharacteristic(
            serviceUUID: configServiceUUID,
            charUUID: numRepetitionsCharUUID,
            data: data
        )

        logger.info("📊 NumRepetitions written: \(value) (firmware derives NumOfData = \(value) × SweepPoints)")
        try await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - Private Read Methods

    private func readSweepEnable(from bleManager: BioMessBLEManager) async throws -> Bool {
        let data = try await bleManager.readCharacteristic(
            serviceUUID: configServiceUUID,
            charUUID: sweepEnableCharUUID
        )

        guard data.count == 1 else {
            throw ConfigurationError.invalidDataSize(expected: 1, got: data.count)
        }

        return data[0] != 0x00
    }

    private func readSweepStart(from bleManager: BioMessBLEManager) async throws -> Float {
        let data = try await bleManager.readCharacteristic(
            serviceUUID: configServiceUUID,
            charUUID: sweepStartCharUUID
        )

        guard data.count == 4 else {
            throw ConfigurationError.invalidDataSize(expected: 4, got: data.count)
        }

        let bitPattern = data.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        return Float(bitPattern: bitPattern)
    }

    private func readSweepStop(from bleManager: BioMessBLEManager) async throws -> Float {
        let data = try await bleManager.readCharacteristic(
            serviceUUID: configServiceUUID,
            charUUID: sweepStopCharUUID
        )

        guard data.count == 4 else {
            throw ConfigurationError.invalidDataSize(expected: 4, got: data.count)
        }

        let bitPattern = data.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        return Float(bitPattern: bitPattern)
    }

    private func readSweepPoints(from bleManager: BioMessBLEManager) async throws -> UInt32 {
        let data = try await bleManager.readCharacteristic(
            serviceUUID: configServiceUUID,
            charUUID: sweepPointsCharUUID
        )

        guard data.count == 4 else {
            throw ConfigurationError.invalidDataSize(expected: 4, got: data.count)
        }

        return data.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }

    private func readNumRepetitions(from bleManager: BioMessBLEManager) async throws -> UInt8 {
        let data = try await bleManager.readCharacteristic(
            serviceUUID: configServiceUUID,
            charUUID: numRepetitionsCharUUID
        )

        guard data.count == 1 else {
            throw ConfigurationError.invalidDataSize(expected: 1, got: data.count)
        }

        return data[0]
    }
}

// MARK: - Errors

public enum ConfigurationError: LocalizedError {
    case syncInProgress
    case invalidDataSize(expected: Int, got: Int)
    case bleNotConnected

    public var errorDescription: String? {
        switch self {
        case .syncInProgress:
            return "Configuration sync already in progress"
        case .invalidDataSize(let expected, let got):
            return "Invalid data size: expected \(expected) bytes, got \(got)"
        case .bleNotConnected:
            return "BLE device not connected"
        }
    }
}
