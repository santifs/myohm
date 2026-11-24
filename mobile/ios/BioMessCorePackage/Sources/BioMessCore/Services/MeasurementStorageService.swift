import Foundation
import SwiftData
import SwiftUI

/// Service for managing measurement persistence using SwiftData
@Observable
@MainActor
public final class MeasurementStorageService {
    private var modelContext: ModelContext?
    
    public init() {}
    
    /// Configure the service with a model context
    public func configure(with context: ModelContext) {
        self.modelContext = context
    }
    
    /// Save a new measurement to persistent storage
    public func saveMeasurement(
        parameters: ColeParameters,
        deviceName: String,
        deviceSerialNumber: String,
        processingTime: TimeInterval,
        rawData: ImpedanceData
    ) throws {
        guard let context = modelContext else {
            throw StorageError.contextNotConfigured
        }
        
        let storedMeasurement = StoredMeasurement(
            timestamp: parameters.timestamp,
            deviceName: deviceName,
            deviceSerialNumber: deviceSerialNumber,
            parameters: parameters,
            processingTime: processingTime,
            rawData: rawData
        )
        
        context.insert(storedMeasurement)
        
        do {
            try context.save()
            print("Successfully saved measurement with timestamp: \(parameters.timestamp)")
        } catch {
            print("Failed to save measurement: \(error)")
            throw StorageError.saveFailed(error)
        }
    }
    
    /// Load all measurements, sorted by timestamp (most recent first)
    public func loadAllMeasurements() throws -> [StoredMeasurement] {
        guard let context = modelContext else {
            throw StorageError.contextNotConfigured
        }
        
        let descriptor = FetchDescriptor<StoredMeasurement>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Failed to load measurements: \(error)")
            throw StorageError.loadFailed(error)
        }
    }
    
    /// Load measurements within a date range
    public func loadMeasurements(from startDate: Date, to endDate: Date) throws -> [StoredMeasurement] {
        guard let context = modelContext else {
            throw StorageError.contextNotConfigured
        }
        
        let predicate = #Predicate<StoredMeasurement> { measurement in
            measurement.timestamp >= startDate && measurement.timestamp <= endDate
        }
        
        let descriptor = FetchDescriptor<StoredMeasurement>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Failed to load measurements for date range: \(error)")
            throw StorageError.loadFailed(error)
        }
    }
    
    /// Load measurements for a specific device
    public func loadMeasurements(forDevice deviceName: String) throws -> [StoredMeasurement] {
        guard let context = modelContext else {
            throw StorageError.contextNotConfigured
        }
        
        let predicate = #Predicate<StoredMeasurement> { measurement in
            measurement.deviceName == deviceName
        }
        
        let descriptor = FetchDescriptor<StoredMeasurement>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Failed to load measurements for device: \(error)")
            throw StorageError.loadFailed(error)
        }
    }
    
    /// Get measurement count
    public func getMeasurementCount() throws -> Int {
        guard let context = modelContext else {
            throw StorageError.contextNotConfigured
        }
        
        let descriptor = FetchDescriptor<StoredMeasurement>()
        
        do {
            return try context.fetchCount(descriptor)
        } catch {
            print("Failed to get measurement count: \(error)")
            throw StorageError.loadFailed(error)
        }
    }
    
    /// Delete a specific measurement
    public func deleteMeasurement(_ measurement: StoredMeasurement) throws {
        guard let context = modelContext else {
            throw StorageError.contextNotConfigured
        }
        
        context.delete(measurement)
        
        do {
            try context.save()
            print("Successfully deleted measurement")
        } catch {
            print("Failed to delete measurement: \(error)")
            throw StorageError.deleteFailed(error)
        }
    }
    
    /// Delete all measurements (for testing/reset purposes)
    public func deleteAllMeasurements() throws {
        guard let context = modelContext else {
            throw StorageError.contextNotConfigured
        }
        
        let measurements = try loadAllMeasurements()
        
        for measurement in measurements {
            context.delete(measurement)
        }
        
        do {
            try context.save()
            print("Successfully deleted all measurements")
        } catch {
            print("Failed to delete all measurements: \(error)")
            throw StorageError.deleteFailed(error)
        }
    }
    
    /// Export measurements as CSV data
    public func exportMeasurementsAsCSV() throws -> Data {
        let measurements = try loadAllMeasurements()
        
        var csv = "Timestamp,Device Name,Device Serial,Re (Ω),Ri (Ω),Cm (nF),fc (kHz),Alpha,Error (%),Processing Tier,Processing Time (s),Quality Score,Contact Status,SNR (dB),Movement Detected\n"
        
        let dateFormatter = ISO8601DateFormatter()
        
        for measurement in measurements {
            let row = [
                dateFormatter.string(from: measurement.timestamp),
                measurement.deviceName,
                measurement.deviceSerialNumber,
                String(measurement.extracellularResistance),
                String(measurement.intracellularResistance),
                String(measurement.membraneCapacitance),
                String(measurement.characteristicFrequency),
                String(measurement.dispersionParameter),
                String(measurement.fittingError),
                measurement.processingTier,
                String(measurement.processingTime),
                String(measurement.qualityScore),
                measurement.contactQualityStatus,
                String(measurement.signalToNoiseRatio),
                String(measurement.movementDetected)
            ].joined(separator: ",")
            
            csv += row + "\n"
        }
        
        guard let data = csv.data(using: .utf8) else {
            throw StorageError.exportFailed("Failed to encode CSV data")
        }
        
        return data
    }
    
    /// Get statistics for all measurements
    public func getMeasurementStatistics() throws -> MeasurementStatistics {
        let measurements = try loadAllMeasurements()
        
        guard !measurements.isEmpty else {
            return MeasurementStatistics.empty
        }
        
        let reValues = measurements.map(\.extracellularResistance)
        let riValues = measurements.map(\.intracellularResistance)
        let cmValues = measurements.map(\.membraneCapacitance)
        let qualityScores = measurements.map(\.qualityScore)
        
        return MeasurementStatistics(
            totalCount: measurements.count,
            averageRe: reValues.reduce(0, +) / Float(reValues.count),
            averageRi: riValues.reduce(0, +) / Float(riValues.count),
            averageCm: cmValues.reduce(0, +) / Float(cmValues.count),
            averageQuality: qualityScores.reduce(0, +) / Float(qualityScores.count),
            dateRange: (measurements.last?.timestamp, measurements.first?.timestamp),
            qualityDistribution: calculateQualityDistribution(measurements)
        )
    }
    
    private func calculateQualityDistribution(_ measurements: [StoredMeasurement]) -> [MeasurementQuality: Int] {
        var distribution: [MeasurementQuality: Int] = [
            .excellent: 0, .good: 0, .fair: 0, .poor: 0
        ]
        
        for measurement in measurements {
            distribution[measurement.measurementQuality, default: 0] += 1
        }
        
        return distribution
    }
}

// MARK: - Supporting Types

public enum StorageError: LocalizedError {
    case contextNotConfigured
    case saveFailed(Error) 
    case loadFailed(Error)
    case deleteFailed(Error)
    case exportFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .contextNotConfigured:
            return "Storage context not configured"
        case .saveFailed(let error):
            return "Failed to save measurement: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "Failed to load measurements: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete measurement: \(error.localizedDescription)"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        }
    }
}

public struct MeasurementStatistics: Sendable {
    public let totalCount: Int
    public let averageRe: Float
    public let averageRi: Float
    public let averageCm: Float
    public let averageQuality: Float
    public let dateRange: (start: Date?, end: Date?)
    public let qualityDistribution: [MeasurementQuality: Int]
    
    public static let empty = MeasurementStatistics(
        totalCount: 0,
        averageRe: 0,
        averageRi: 0,
        averageCm: 0,
        averageQuality: 0,
        dateRange: (nil, nil),
        qualityDistribution: [:]
    )
}

// MARK: - Environment Key

public struct MeasurementStorageServiceKey: @preconcurrency EnvironmentKey {
    @MainActor
    public static let defaultValue = MeasurementStorageService()
}

public extension EnvironmentValues {
    var measurementStorage: MeasurementStorageService {
        get { self[MeasurementStorageServiceKey.self] }
        set { self[MeasurementStorageServiceKey.self] = newValue }
    }
}