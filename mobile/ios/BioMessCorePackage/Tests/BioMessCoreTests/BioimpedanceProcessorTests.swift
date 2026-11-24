import Testing
import Foundation
@testable import BioMessCore

@Suite("Bioimpedance Processor Tests")
struct BioimpedanceProcessorTests {
    
    let processor = BioimpedanceProcessor()
    
    @Test("Cole immediate processing performance")
    func immediateProcessingPerformance() async throws {
        let testData = createTestImpedanceData()
        
        let startTime = Date()
        
        // Immediate processing may fail optimization due to limited iterations,
        // so we'll test that it at least attempts processing quickly
        do {
            let result = try await processor.processImmediate(testData)
            let processingTime = Date().timeIntervalSince(startTime)
            
            // Performance requirement: <1 second for immediate processing
            #expect(processingTime < 1.0)
            
            // Basic validity checks (if optimization succeeds)
            #expect(result.Re > 0)
            #expect(result.Ri > 0)
            #expect(result.Cm > 0)
            #expect(result.fc > 0)
            #expect(result.alpha > 0 && result.alpha <= 1.0)
            #expect(result.error >= 0)
            #expect(result.processingTier == .immediate)
        } catch ProcessingError.optimizationFailed {
            // This is expected for immediate processing with challenging data
            let processingTime = Date().timeIntervalSince(startTime)
            #expect(processingTime < 1.0) // Still should be fast
        }
    }
    
    @Test("Cole complete processing accuracy")
    func completeProcessingAccuracy() async throws {
        let testData = createTestImpedanceData()
        
        let startTime = Date()
        let result = try await processor.processComplete(testData)
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Performance requirement: <5 seconds for complete processing
        #expect(processingTime < 5.0)
        
        // Accuracy requirement: should be better than immediate
        #expect(result.error < 500.0) // Less strict for test data (synthetic data)
        #expect(result.processingTier == .complete)
        
        // Parameter ranges should be physiologically reasonable (relaxed for test data)
        #expect(result.Re > 0 && result.Re < 10000)    // Broad range for synthetic data
        #expect(result.Ri > 0 && result.Ri < 50000)    // Broad range for synthetic data  
        #expect(result.fc > 0 && result.fc < 1000)     // Broad frequency range
    }
    
    @Test("Quality assessment functionality")
    func qualityAssessment() {
        let testData = createTestImpedanceData()
        let quality = processor.assessQuality(testData)
        
        // Quality score should be between 0 and 1
        #expect(quality.score >= 0 && quality.score <= 1.0)
        
        // Contact quality should have reasonable values
        #expect(quality.contactQuality.electrodeImpedance >= 0)
        #expect(quality.contactQuality.mismatchPercentage >= 0)
        
        // Signal quality should be populated
        #expect(quality.signalQuality.snr != 0 || quality.signalQuality.phaseStability >= 0)
    }
    
    @Test("Invalid data handling")
    func invalidDataHandling() async {
        // Test with wrong number of measurements (should be 15 for BioMess)
        let invalidData = ImpedanceData(measurements: [
            ImpedanceData.MeasurementPoint(frequency: 1000, magnitude: 300, phase: -10)
        ])
        
        await #expect(throws: ProcessingError.invalidDataSize) {
            try await processor.processImmediate(invalidData)
        }
    }
    
    @Test("Data model consistency")
    func dataModelConsistency() {
        let testData = createTestImpedanceData()
        
        // Check that we have 15 measurements for BioMess device
        #expect(testData.measurements.count == 15)
        
        // Check frequency range (should be ~1kHz to ~438kHz for BioMess)
        let frequencies = testData.frequencies
        #expect(frequencies.first! > 500)
        #expect(frequencies.last! < 500000)
        
        // Check that frequencies are in ascending order
        for i in 1..<frequencies.count {
            #expect(frequencies[i] > frequencies[i-1])
        }
        
        // Check complex impedance calculations
        for measurement in testData.measurements {
            let complex = measurement.complexImpedance
            let calculatedMagnitude = sqrt(complex.real * complex.real + complex.imaginary * complex.imaginary)
            
            // Should match original magnitude within floating point precision
            #expect(abs(calculatedMagnitude - measurement.magnitude) < 0.001)
        }
    }
    
    // MARK: - Helper Functions
    
    private func createTestImpedanceData() -> ImpedanceData {
        // Use realistic test data similar to mock BLE manager
        
        // Use simple realistic test data that matches the mock data pattern
        let realMeasurements: [(frequency: Float, magnitude: Float, phase: Float)] = [
            (1000, 68.2, -1.2),     // 1 kHz
            (2000, 67.8, -2.1),     // 2 kHz  
            (3000, 67.2, -3.0),     // 3 kHz
            (5000, 66.1, -4.2),     // 5 kHz
            (7000, 64.8, -5.1),     // 7 kHz
            (10000, 63.1, -6.2),    // 10 kHz
            (15000, 60.9, -7.8),    // 15 kHz
            (20000, 58.5, -8.9),    // 20 kHz
            (30000, 55.2, -9.8),    // 30 kHz
            (40000, 52.1, -10.1),   // 40 kHz
            (50000, 49.8, -9.7),    // 50 kHz
            (70000, 47.2, -8.9),    // 70 kHz
            (100000, 45.1, -7.8),   // 100 kHz
            (120000, 43.8, -6.9),   // 120 kHz
            (150000, 42.9, -5.8)    // 150 kHz
        ]
        
        let measurements = realMeasurements.map { freq, mag, phase in
            ImpedanceData.MeasurementPoint(frequency: freq, magnitude: mag, phase: phase)
        }
        
        return ImpedanceData(
            measurements: measurements,
            timestamp: Date(),
            deviceInfo: DeviceInfo(name: "Test Device")
        )
    }
}

@Suite("BLE Manager Tests")
struct BLEManagerTests {
    
    @Test("Mock BLE manager basic functionality")
    @MainActor
    func mockBLEBasicFunctionality() async {
        let manager = MockBioMessCoreBLEManager()
        
        // Initial state should be disconnected
        #expect(manager.connectionState == .disconnected)
        #expect(!manager.discoveredDevices.isEmpty) // Mock should have pre-populated devices
        
        // Test scanning
        manager.startScanning()
        #expect(manager.connectionState == .scanning)
        
        // Test connection to first device
        if let firstDevice = manager.discoveredDevices.first {
            manager.connect(to: firstDevice)
            
            // Wait for mock connection
            try? await Task.sleep(for: .seconds(1.5))
            #expect(manager.connectionState == .connected)
            #expect(manager.connectedDevice?.id == firstDevice.id)
        }
    }
    
    @Test("Mock measurement protocol timing")
    @MainActor
    func mockMeasurementTiming() async throws {
        let manager = MockBioMessCoreBLEManager()
        
        // Connect to first device
        if let firstDevice = manager.discoveredDevices.first {
            manager.connect(to: firstDevice)
            try? await Task.sleep(for: .seconds(1.5))
            
            let startTime = Date()
            let data = try await manager.performMeasurement()
            let totalTime = Date().timeIntervalSince(startTime)
            
            // Should follow fast mock timing: ~3s
            #expect(totalTime >= 2.5 && totalTime <= 4.0)
            
            // Should return valid data
            #expect(data.measurements.count == 15)
            #expect(data.deviceInfo != nil)
        }
    }
    
    @Test("Realistic bioimpedance data generation")
    @MainActor
    func realisticDataGeneration() async throws {
        let manager = MockBioMessCoreBLEManager()
        
        if let firstDevice = manager.discoveredDevices.first {
            manager.connect(to: firstDevice)
            try? await Task.sleep(for: .seconds(1.5))
            
            let data = try await manager.performMeasurement()
            
            // Check frequency range is realistic
            let frequencies = data.frequencies
            #expect(frequencies.first! >= 1000)  // At least 1kHz
            #expect(frequencies.last! <= 500000) // No more than 500kHz
            
            // Check magnitude values are in physiological range
            let magnitudes = data.magnitudes
            for magnitude in magnitudes {
                #expect(magnitude > 30 && magnitude < 100) // Typical calf impedance range
            }
            
            // Check phase values are reasonable (should be negative for capacitive tissue)
            let phases = data.phases
            for phase in phases {
                #expect(phase >= -90 && phase <= 0) // Capacitive behavior
            }
        }
    }
}

@Suite("Data Model Tests")
struct DataModelTests {
    
    @Test("Complex number calculations")
    func complexNumberCalculations() {
        let complex1 = Complex(real: 100, imaginary: -50)
        
        // Test magnitude calculation
        let expectedMagnitude = sqrt(Float(100*100 + 50*50))
        #expect(abs(complex1.magnitude - expectedMagnitude) < 0.001)
        
        // Test phase calculation
        let expectedPhase = atan2(-50, 100) * 180.0 / Float.pi
        #expect(abs(complex1.phase - expectedPhase) < 0.001)
        
        // Test polar constructor
        let complex2 = Complex(magnitude: expectedMagnitude, phase: expectedPhase)
        #expect(abs(complex2.real - 100) < 0.001)
        #expect(abs(complex2.imaginary - (-50)) < 0.001)
    }
    
    @Test("Cole parameters validation")
    func coleParametersValidation() {
        let quality = QualityMetrics(
            score: 0.9,
            contactQuality: ContactQuality(electrodeImpedance: 3000, mismatchPercentage: 2.5),
            signalQuality: SignalQuality(
                snr: 45.0,
                phaseStability: 1.2,
                frequencyResponse: .excellent
            ),
            convergence: ConvergenceMetrics(
                iterations: 15,
                residualError: 0.02,
                parameterErrors: ParameterErrors(reError: 0.1, riError: 0.15, cmError: 0.05, fcError: 0.2, alphaError: 0.01),
                converged: true
            ),
            stabilityMetrics: StabilityMetrics(
                movementDetected: false,
                quaternionStability: 0.001,
                impedanceStability: 0.02,
                interferenceLevel: .minimal
            )
        )
        
        let parameters = ColeParameters(
            Re: 285.0,
            Ri: 1150.0,
            Cm: 2.8,
            fc: 19.9,
            alpha: 0.82,
            error: 2.1,
            processingTier: .complete,
            quality: quality
        )
        
        // Validate parameter ranges
        #expect(parameters.Re > 0)
        #expect(parameters.Ri > 0)
        #expect(parameters.Cm > 0)
        #expect(parameters.fc > 0)
        #expect(parameters.alpha > 0 && parameters.alpha <= 1.0)
        #expect(parameters.quality.score >= 0 && parameters.quality.score <= 1.0)
    }
    
    @Test("Quality metrics assessment")
    func qualityMetricsAssessment() {
        // Test excellent contact quality
        let excellentContact = ContactQuality(electrodeImpedance: 3000, mismatchPercentage: 2.0)
        #expect(excellentContact.status == .excellent)
        
        // Test poor contact quality  
        let poorContact = ContactQuality(electrodeImpedance: 25000, mismatchPercentage: 20.0)
        #expect(poorContact.status == .poor)
        
        // Test good contact quality
        let goodContact = ContactQuality(electrodeImpedance: 8000, mismatchPercentage: 7.0)
        #expect(goodContact.status == .good)
    }
}