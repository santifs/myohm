import Foundation

/// Stored measurement from firmware flash memory (V2.1)
/// Contains 5 repetitions of 48-frequency sweeps for noise robustness
public struct StoredMeasurement: Sendable, Equatable, Codable, Identifiable {

    // MARK: - Size Constants (single source of truth, must match firmware flash_storage.h)

    static let repetitionCount = 5
    static let pointsPerRepetition = 48
    static let bytesPerPoint = 12       // sizeof(BioimpedanceMeasurement) = 3 floats × 4 bytes
    static let metadataSize = 12
    static let quaternionSize = repetitionCount * 4 * 4  // N reps × 4 floats × 4 bytes
    static let expectedSize = metadataSize + (repetitionCount * pointsPerRepetition * bytesPerPoint) + quaternionSize + 2  // +2 for CRC16

    public let id: UUID

    // MARK: - Metadata (12 bytes)

    public let timestamp: UInt32              // Seconds since power-on or epoch
    public let sessionId: UInt16              // Auto-measurement session ID
    public let sequenceNumber: UInt16         // Sequential number within session
    public let intervalSeconds: UInt16        // Configured measurement interval
    public let batteryPercentage: UInt8       // Battery level at measurement time
    public let numRepetitions: UInt8          // Number of repetitions (always 5)

    // MARK: - Bioimpedance Data (5 × 48 × 12 = 2880 bytes)

    /// 5 repetitions of 48 frequency points each
    /// [repetition_index][frequency_point_index]
    public let repetitions: [[ImpedanceData.MeasurementPoint]]

    // MARK: - IMU Data (5 × 16 = 80 bytes)

    /// 5 quaternions (one per repetition)
    /// [repetition_index][w, x, y, z]
    public let quaternions: [[Float]]

    // MARK: - Validation (2 bytes)

    public let crc16: UInt16                  // CRC16 checksum

    // MARK: - Computed Properties

    /// Capture date reconstructed from sync time
    public var captureDate: Date {
        // Timestamp is relative to firmware power-on
        // We reconstruct absolute time based on sync time
        // For now, use current date minus relative time
        Date()
    }

    /// Battery level as percentage
    public var batteryLevel: Int {
        Int(batteryPercentage)
    }

    /// Average measurements across all repetitions (robust to noise)
    public var averagedMeasurements: [ImpedanceData.MeasurementPoint] {
        ProcessingMethod.average(repetitions: repetitions)
    }

    /// Median measurements across all repetitions (more robust to outliers)
    public var medianMeasurements: [ImpedanceData.MeasurementPoint] {
        ProcessingMethod.median(repetitions: repetitions)
    }

    /// Movement-filtered measurements (excludes repetitions with excessive movement)
    public func filteredMeasurements(movementThreshold: Float = 0.1) -> [ImpedanceData.MeasurementPoint]? {
        ProcessingMethod.filterByMovement(
            repetitions: repetitions,
            quaternions: quaternions,
            threshold: movementThreshold
        )
    }

    /// Signal quality metric (0-1, higher is better)
    /// Based on variance between repetitions
    public var signalQuality: Float {
        guard repetitions.count >= 2 else { return 0 }

        // Calculate variance of magnitude at middle frequency (point 24)
        let magnitudes = repetitions.map { $0[24].magnitude }
        let mean = magnitudes.reduce(0, +) / Float(magnitudes.count)
        let variance = magnitudes.map { pow($0 - mean, 2) }.reduce(0, +) / Float(magnitudes.count)
        let stdDev = sqrt(variance)

        // Convert to quality score (lower variance = higher quality)
        // Normalize: assume stdDev < 10 Ohms is excellent, > 50 Ohms is poor
        let normalizedVariance = min(stdDev / 50.0, 1.0)
        return 1.0 - normalizedVariance
    }

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        timestamp: UInt32,
        sessionId: UInt16,
        sequenceNumber: UInt16,
        intervalSeconds: UInt16,
        batteryPercentage: UInt8,
        numRepetitions: UInt8,
        repetitions: [[ImpedanceData.MeasurementPoint]],
        quaternions: [[Float]],
        crc16: UInt16
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.sequenceNumber = sequenceNumber
        self.intervalSeconds = intervalSeconds
        self.batteryPercentage = batteryPercentage
        self.numRepetitions = numRepetitions
        self.repetitions = repetitions
        self.quaternions = quaternions
        self.crc16 = crc16
    }

    // MARK: - Parsing from BLE Data

    /// Parse StoredMeasurement from BLE notification (V2.1)
    /// - Parameter data: Raw data from firmware (expectedSize bytes)
    /// - Returns: Parsed StoredMeasurement or nil if invalid
    public static func parse(from data: Data) -> StoredMeasurement? {
        guard data.count == expectedSize else {
            print("Invalid StoredMeasurement size: \(data.count) bytes (expected \(expectedSize))")
            return nil
        }

        var offset = 0

        // MARK: Metadata (12 bytes)

        let timestamp = uint32LE(data, offset)
        offset += 4

        let sessionId = uint16LE(data, offset)
        offset += 2

        let sequenceNumber = uint16LE(data, offset)
        offset += 2

        let intervalSeconds = uint16LE(data, offset)
        offset += 2

        let batteryPercentage = data[offset]
        offset += 1

        let numRepetitions = data[offset]
        offset += 1

        // MARK: Repetitions (repetitionCount × pointsPerRepetition × bytesPerPoint bytes)

        var repetitions: [[ImpedanceData.MeasurementPoint]] = []

        for _ in 0..<repetitionCount {
            var repData: [ImpedanceData.MeasurementPoint] = []

            for _ in 0..<pointsPerRepetition {
                let frequency = float32LE(data, offset)
                offset += 4

                let magnitude = float32LE(data, offset)
                offset += 4

                let phase = float32LE(data, offset)
                offset += 4

                let point = ImpedanceData.MeasurementPoint(
                    frequency: frequency,
                    magnitude: magnitude,
                    phase: phase
                )
                repData.append(point)
            }

            repetitions.append(repData)
        }

        // MARK: Quaternions (repetitionCount × 4 floats × 4 bytes)

        var quaternions: [[Float]] = []

        for _ in 0..<repetitionCount {
            let w = float32LE(data, offset)
            offset += 4

            let x = float32LE(data, offset)
            offset += 4

            let y = float32LE(data, offset)
            offset += 4

            let z = float32LE(data, offset)
            offset += 4

            quaternions.append([w, x, y, z])
        }

        // MARK: CRC16 (2 bytes)

        let crc16 = uint16LE(data, offset)

        // Validate CRC (calculated over all bytes except last 2)
        let calculatedCRC = CRC16.calculate(data: data.prefix(expectedSize - 2))
        if crc16 != calculatedCRC {
            print("⚠️ CRC mismatch: expected \(crc16), got \(calculatedCRC)")
            // Continue anyway - data might still be useful
        }

        return StoredMeasurement(
            timestamp: timestamp,
            sessionId: sessionId,
            sequenceNumber: sequenceNumber,
            intervalSeconds: intervalSeconds,
            batteryPercentage: batteryPercentage,
            numRepetitions: numRepetitions,
            repetitions: repetitions,
            quaternions: quaternions,
            crc16: crc16
        )
    }

    private static func uint16LE(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func uint32LE(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) |
        (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) |
        (UInt32(data[offset + 3]) << 24)
    }

    private static func float32LE(_ data: Data, _ offset: Int) -> Float {
        Float(bitPattern: uint32LE(data, offset))
    }

    /// Convert to ImpedanceData for processing (uses median of repetitions)
    public func toImpedanceData() -> ImpedanceData {
        ImpedanceData(
            measurements: medianMeasurements,  // Use median for robustness
            timestamp: captureDate,
            deviceInfo: DeviceInfo(
                name: "BioMess",
                serialNumber: nil,
                batteryLevel: BatteryData(
                    voltageMillivolts: 0,  // Not stored in flash
                    percentage: UInt16(batteryPercentage)
                )
            )
        )
    }

    /// Convert each repetition to ImpedanceData
    public func toImpedanceDataArray() -> [ImpedanceData] {
        let deviceInfo = DeviceInfo(
            name: "BioMess",
            serialNumber: nil,
            batteryLevel: BatteryData(
                voltageMillivolts: 0,
                percentage: UInt16(batteryPercentage)
            )
        )

        return repetitions.map { rep in
            ImpedanceData(
                measurements: rep,
                timestamp: captureDate,
                deviceInfo: deviceInfo
            )
        }
    }
}

// MARK: - Processing Methods

public enum ProcessingMethod {

    /// Average all repetitions (simple approach)
    public static func average(repetitions: [[ImpedanceData.MeasurementPoint]]) -> [ImpedanceData.MeasurementPoint] {
        guard !repetitions.isEmpty, repetitions[0].count == StoredMeasurement.pointsPerRepetition else { return [] }

        var averaged: [ImpedanceData.MeasurementPoint] = []

        for point in 0..<StoredMeasurement.pointsPerRepetition {
            var sumMag: Float = 0
            var sumPhase: Float = 0

            for rep in 0..<repetitions.count {
                sumMag += repetitions[rep][point].magnitude
                sumPhase += repetitions[rep][point].phase
            }

            averaged.append(ImpedanceData.MeasurementPoint(
                frequency: repetitions[0][point].frequency,
                magnitude: sumMag / Float(repetitions.count),
                phase: sumPhase / Float(repetitions.count)
            ))
        }

        return averaged
    }

    /// Median of all repetitions (more robust to outliers)
    public static func median(repetitions: [[ImpedanceData.MeasurementPoint]]) -> [ImpedanceData.MeasurementPoint] {
        guard !repetitions.isEmpty, repetitions[0].count == StoredMeasurement.pointsPerRepetition else { return [] }

        var result: [ImpedanceData.MeasurementPoint] = []

        for point in 0..<StoredMeasurement.pointsPerRepetition {
            var mags: [Float] = []
            var phases: [Float] = []

            for rep in 0..<repetitions.count {
                mags.append(repetitions[rep][point].magnitude)
                phases.append(repetitions[rep][point].phase)
            }

            mags.sort()
            phases.sort()

            // Middle element (for 5 repetitions, this is index 2)
            let medianIndex = mags.count / 2

            result.append(ImpedanceData.MeasurementPoint(
                frequency: repetitions[0][point].frequency,
                magnitude: mags[medianIndex],
                phase: phases[medianIndex]
            ))
        }

        return result
    }

    /// Filter by movement (exclude repetitions with excessive quaternion variance)
    public static func filterByMovement(
        repetitions: [[ImpedanceData.MeasurementPoint]],
        quaternions: [[Float]],
        threshold: Float
    ) -> [ImpedanceData.MeasurementPoint]? {
        guard repetitions.count == quaternions.count else { return nil }

        // 1. Detect repetitions with minimal movement
        var validReps: [Int] = []

        for rep in 0..<repetitions.count {
            let movement = calculateMovement(quaternions[rep])
            if movement < threshold {
                validReps.append(rep)
            }
        }

        // 2. Need at least 2 valid repetitions
        guard validReps.count >= 2 else {
            print("⚠️ Excessive movement detected, measurement discarded")
            return nil
        }

        // 3. Average valid repetitions
        var filtered: [ImpedanceData.MeasurementPoint] = []

        for point in 0..<StoredMeasurement.pointsPerRepetition {
            var sumMag: Float = 0
            var sumPhase: Float = 0

            for rep in validReps {
                sumMag += repetitions[rep][point].magnitude
                sumPhase += repetitions[rep][point].phase
            }

            filtered.append(ImpedanceData.MeasurementPoint(
                frequency: repetitions[0][point].frequency,
                magnitude: sumMag / Float(validReps.count),
                phase: sumPhase / Float(validReps.count)
            ))
        }

        return filtered
    }

    /// Calculate movement metric from quaternion
    /// Returns variance of quaternion components (lower = less movement)
    private static func calculateMovement(_ quaternion: [Float]) -> Float {
        guard quaternion.count == 4 else { return Float.infinity }

        // Simple metric: sum of absolute values (should be ~1.0 for unit quaternion)
        let magnitude = sqrt(quaternion.map { $0 * $0 }.reduce(0, +))

        // Deviation from unit quaternion indicates movement
        return abs(magnitude - 1.0)
    }
}

// MARK: - CRC16 Calculator

public struct CRC16 {
    /// Calculate CRC16-CCITT (0xFFFF initial value)
    public static func calculate(data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF

        for byte in data {
            crc ^= UInt16(byte) << 8

            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }

        return crc
    }
}
