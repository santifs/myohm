import XCTest
import SwiftData
@testable import BioMessCore

@MainActor
final class MeasurementStorageTests: XCTestCase {
    var storageService: MeasurementStorageService!
    var modelContainer: ModelContainer!
    
    override func setUp() async throws {
        // Create in-memory model container for testing
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: StoredMeasurement.self, configurations: config)
        
        storageService = MeasurementStorageService()
        storageService.configure(with: modelContainer.mainContext)
    }
    
    override func tearDown() async throws {
        storageService = nil
        modelContainer = nil
    }
    
    func testSaveMeasurement() async throws {
        // Create test measurement data
        let testParameters = ColeParameters(
            Re: 45.2,
            Ri: 28.1,
            Cm: 1.35,
            fc: 28.5,
            alpha: 0.815,
            error: 1.8,
            processingTier: .immediate,
            quality: createTestQualityMetrics()
        )
        
        let testData = createTestImpedanceData()
        
        // Save measurement
        try storageService.saveMeasurement(
            parameters: testParameters,
            deviceName: "Test Device",
            deviceSerialNumber: "TEST-001",
            processingTime: 2.5,
            rawData: testData
        )
        
        // Verify measurement was saved
        let measurements = try storageService.loadAllMeasurements()
        XCTAssertEqual(measurements.count, 1)
        
        let savedMeasurement = measurements.first!
        XCTAssertEqual(savedMeasurement.deviceName, "Test Device")
        XCTAssertEqual(savedMeasurement.deviceSerialNumber, "TEST-001")
        XCTAssertEqual(savedMeasurement.extracellularResistance, 45.2, accuracy: 0.1)
        XCTAssertEqual(savedMeasurement.intracellularResistance, 28.1, accuracy: 0.1)
        XCTAssertEqual(savedMeasurement.processingTime, 2.5, accuracy: 0.1)
    }
    
    func testLoadMeasurements() async throws {
        // Save multiple measurements
        for i in 0..<3 {
            let parameters = ColeParameters(
                Re: Float(40 + i),
                Ri: Float(25 + i),
                Cm: Float(1.2 + Double(i) * 0.1),
                fc: Float(30 + i),
                alpha: 0.8,
                error: 2.0,
                processingTier: .immediate,
                quality: createTestQualityMetrics()
            )
            
            try storageService.saveMeasurement(
                parameters: parameters,
                deviceName: "Device \(i)",
                deviceSerialNumber: "TEST-00\(i)",
                processingTime: 2.0,
                rawData: createTestImpedanceData()
            )
        }
        
        // Load all measurements
        let measurements = try storageService.loadAllMeasurements()
        XCTAssertEqual(measurements.count, 3)
        
        // Verify they're sorted by timestamp (most recent first)
        for i in 0..<2 {
            XCTAssertGreaterThanOrEqual(measurements[i].timestamp, measurements[i+1].timestamp)
        }
    }
    
    func testMeasurementStatistics() async throws {
        // Save test measurements
        let qualityScores: [Float] = [0.95, 0.85, 0.75, 0.65]
        for (index, score) in qualityScores.enumerated() {
            let parameters = ColeParameters(
                Re: Float(40 + index),
                Ri: Float(25 + index),
                Cm: 1.3,
                fc: 30.0,
                alpha: 0.8,
                error: 2.0,
                processingTier: .immediate,
                quality: QualityMetrics(
                    score: score,
                    contactQuality: ContactQuality(electrodeImpedance: 2000, mismatchPercentage: 3.0),
                    signalQuality: SignalQuality(snr: 40.0, phaseStability: 1.0, frequencyResponse: .excellent),
                    convergence: ConvergenceMetrics(iterations: 10, residualError: 0.02, parameterErrors: ParameterErrors(reError: 0.5, riError: 0.8, cmError: 1.2, fcError: 1.0, alphaError: 0.3), converged: true),
                    stabilityMetrics: StabilityMetrics(movementDetected: false, quaternionStability: 0.001, impedanceStability: 0.01, interferenceLevel: .minimal)
                )
            )
            
            try storageService.saveMeasurement(
                parameters: parameters,
                deviceName: "Test Device",
                deviceSerialNumber: "TEST-001",
                processingTime: 2.0,
                rawData: createTestImpedanceData()
            )
        }
        
        // Get statistics
        let stats = try storageService.getMeasurementStatistics()
        XCTAssertEqual(stats.totalCount, 4)
        XCTAssertEqual(stats.averageRe, 41.5, accuracy: 0.1) // (40+41+42+43)/4
        XCTAssertEqual(stats.averageQuality, 0.8, accuracy: 0.1) // (0.95+0.85+0.75+0.65)/4
    }
    
    func testCSVExport() async throws {
        // Save a test measurement
        let parameters = ColeParameters(
            Re: 45.0,
            Ri: 28.0,
            Cm: 1.3,
            fc: 30.0,
            alpha: 0.8,
            error: 2.0,
            processingTier: .immediate,
            quality: createTestQualityMetrics()
        )
        
        try storageService.saveMeasurement(
            parameters: parameters,
            deviceName: "Test Device",
            deviceSerialNumber: "TEST-001",
            processingTime: 2.0,
            rawData: createTestImpedanceData()
        )
        
        // Export as CSV
        let csvData = try storageService.exportMeasurementsAsCSV()
        let csvString = String(data: csvData, encoding: .utf8)!
        
        // Verify CSV contains expected data
        XCTAssertTrue(csvString.contains("Timestamp,Device Name"))
        XCTAssertTrue(csvString.contains("Test Device"))
        XCTAssertTrue(csvString.contains("TEST-001"))
        XCTAssertTrue(csvString.contains("45.0"))
        XCTAssertTrue(csvString.contains("28.0"))
    }
    
    // MARK: - Helper Methods
    
    private func createTestQualityMetrics() -> QualityMetrics {
        let contactQuality = ContactQuality(
            electrodeImpedance: 2500,
            mismatchPercentage: 4.2
        )
        
        let signalQuality = SignalQuality(
            snr: 42.5,
            phaseStability: 1.1,
            frequencyResponse: .excellent
        )
        
        let parameterErrors = ParameterErrors(
            reError: 0.5, riError: 0.8, cmError: 1.2, fcError: 1.0, alphaError: 0.3
        )
        
        let convergenceMetrics = ConvergenceMetrics(
            iterations: 12,
            residualError: 0.018,
            parameterErrors: parameterErrors,
            converged: true
        )
        
        let stabilityMetrics = StabilityMetrics(
            movementDetected: false,
            quaternionStability: 0.002,
            impedanceStability: 0.012,
            interferenceLevel: .minimal
        )
        
        return QualityMetrics(
            score: 0.92,
            contactQuality: contactQuality,
            signalQuality: signalQuality,
            convergence: convergenceMetrics,
            stabilityMetrics: stabilityMetrics
        )
    }
    
    private func createTestImpedanceData() -> ImpedanceData {
        let measurements: [(frequency: Float, magnitude: Float, phase: Float)] = [
            (1000, 68.2, -1.2),
            (2000, 67.8, -2.1),
            (5000, 66.1, -4.2),
            (10000, 63.1, -6.2),
            (20000, 58.5, -8.9),
            (50000, 49.8, -9.7),
            (100000, 45.1, -7.8)
        ]
        
        let points = measurements.map { freq, mag, phase in
            ImpedanceData.MeasurementPoint(frequency: freq, magnitude: mag, phase: phase)
        }
        
        return ImpedanceData(measurements: points)
    }
}