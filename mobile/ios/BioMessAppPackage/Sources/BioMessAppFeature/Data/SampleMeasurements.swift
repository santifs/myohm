import Foundation

/// Sample measurement data for testing and previews
public struct SampleMeasurements {

    /// Real measurement from Z Board calibration circuit
    /// Date: Sunday, 28 September 2025 at 14:17:24
    /// This measurement shows high fitting error (4911.76%) which is expected for RC circuit analysis
    public static let zBoardCalibration = ColeParameters(
        Re: 3816.4053,           // Extracellular Resistance
        Ri: 4451.4854,           // Intracellular Resistance
        Cm: 1209.4983,           // Membrane Capacitance (nF)
        fc: 0.015915494,         // Characteristic Frequency (kHz)
        alpha: 1.0,              // Dispersion Parameter
        error: 4911.7583,        // Fitting Error (%)
        processingTier: .complete,
        quality: QualityMetrics(
            score: 0.450,
            contactQuality: ContactQuality(
                electrodeImpedance: 5076094.5,
                mismatchPercentage: 202.9513
            ),
            signalQuality: SignalQuality(
                snr: -2.4755182,
                phaseStability: 101.47565,
                frequencyResponse: .poor
            ),
            convergence: ConvergenceMetrics(
                iterations: 0,
                residualError: 0.0,
                parameterErrors: ParameterErrors(
                    reError: 0.0,
                    riError: 0.0,
                    cmError: 0.0,
                    fcError: 0.0,
                    alphaError: 0.0
                ),
                converged: true
            ),
            stabilityMetrics: StabilityMetrics(
                movementDetected: false,
                quaternionStability: 0.0,
                impedanceStability: 1.3297681,
                interferenceLevel: .high
            )
        ),
        patient: PatientSnapshot(
            name: "Z Board",
            exerciseName: "Circuit Test",
            measurementNumber: 1,
            age: 29,
            gender: .male,
            height: 180.0,
            weight: 90.0,
            bmi: 27.8,
            ageGroup: "Adult (29y)",
            bmiCategory: "Overweight"
        ),
        measurementType: .circuit,
        rawData: createZBoardRawData(),
        timestamp: createSampleDate()
    )

    /// Create the actual raw measurement data from the CSV
    private static func createZBoardRawData() -> ImpedanceData {
        let measurements: [ImpedanceData.MeasurementPoint] = [
            // Real data from your CSV file
            ImpedanceData.MeasurementPoint(frequency: 1000.0, magnitude: 17178.164, phase: -88.91589),
            ImpedanceData.MeasurementPoint(frequency: 1430.3262, magnitude: 12026.051, phase: -88.74482),
            ImpedanceData.MeasurementPoint(frequency: 2045.833, magnitude: 8426.613, phase: -88.54816),
            ImpedanceData.MeasurementPoint(frequency: 2926.2085, magnitude: 5901.596, phase: -88.24221),
            ImpedanceData.MeasurementPoint(frequency: 4185.4326, magnitude: 4136.3247, phase: -87.80874),
            ImpedanceData.MeasurementPoint(frequency: 5986.534, magnitude: 2899.0737, phase: -87.21371),
            ImpedanceData.MeasurementPoint(frequency: 8562.696, magnitude: 2034.2324, phase: -86.3524),
            ImpedanceData.MeasurementPoint(frequency: 12247.448, magnitude: 1430.6027, phase: -85.14657),
            ImpedanceData.MeasurementPoint(frequency: 17517.846, magnitude: 1008.72296, phase: -83.45645),
            ImpedanceData.MeasurementPoint(frequency: 25056.234, magnitude: 714.1567, phase: -81.08554),
            ImpedanceData.MeasurementPoint(frequency: 35838.59, magnitude: 508.74527, phase: -77.7406),
            ImpedanceData.MeasurementPoint(frequency: 51260.87, magnitude: 365.8002, phase: -73.22002),
            ImpedanceData.MeasurementPoint(frequency: 73319.766, magnitude: 267.82068, phase: -67.12817),
            ImpedanceData.MeasurementPoint(frequency: 104871.18, magnitude: 202.00119, phase: -59.39737),
            ImpedanceData.MeasurementPoint(frequency: 150000.0, magnitude: 159.2717, phase: -50.12262)  // 309.87738° corrected to -50.12262°
        ]

        return ImpedanceData(
            measurements: measurements,
            timestamp: createSampleDate(),
            deviceInfo: DeviceInfo(
                name: "BioMess Device",
                serialNumber: "\u{0001}",  // Special character from CSV
                batteryLevel: BatteryData(voltageMillivolts: 3000, percentage: 85)
            )
        )
    }

    /// Sample biological tissue measurement
    public static let biologicalTissue = ColeParameters(
        Re: 450.2,              // Typical extracellular resistance
        Ri: 1200.8,             // Typical intracellular resistance
        Cm: 22.5,               // Typical membrane capacitance (nF)
        fc: 45.3,               // Typical characteristic frequency (kHz)
        alpha: 0.85,            // Typical dispersion parameter
        error: 2.3,             // Good fitting error
        processingTier: .complete,
        quality: QualityMetrics(
            score: 0.92,
            contactQuality: ContactQuality(
                electrodeImpedance: 2250.0,
                mismatchPercentage: 3.2
            ),
            signalQuality: SignalQuality(
                snr: 28.5,
                phaseStability: 2.1,
                frequencyResponse: .excellent
            ),
            convergence: ConvergenceMetrics(
                iterations: 12,
                residualError: 0.023,
                parameterErrors: ParameterErrors(
                    reError: 2.1,
                    riError: 8.3,
                    cmError: 0.8,
                    fcError: 1.2,
                    alphaError: 0.05
                ),
                converged: true
            ),
            stabilityMetrics: StabilityMetrics(
                movementDetected: false,
                quaternionStability: 0.98,
                impedanceStability: 0.12,
                interferenceLevel: .low
            )
        ),
        patient: PatientSnapshot(
            name: "Test Patient",
            exerciseName: "Biological Test",
            measurementNumber: 1,
            age: 35,
            gender: .female,
            height: 165.0,
            weight: 65.0,
            bmi: 23.9,
            ageGroup: "Adult (35y)",
            bmiCategory: "Normal weight"
        ),
        measurementType: .body,
        rawData: createBiologicalRawData(),
        timestamp: createSampleDate(daysAgo: 1)
    )

    /// Create synthetic biological tissue measurement data
    private static func createBiologicalRawData() -> ImpedanceData {
        let frequencies: [Float] = [
            1000, 1430, 2046, 2926, 4185, 5987, 8563, 12247,
            17518, 25056, 35839, 51261, 73320, 104871, 150000
        ]

        // Generate realistic biological tissue impedance using Cole model
        let Re: Float = 450.2
        let Ri: Float = 1200.8
        let fc: Float = 45300  // 45.3 kHz in Hz
        let alpha: Float = 0.85

        let measurements = frequencies.map { f in
            let omega = 2.0 * Float.pi * f
            let tau = 1.0 / (2.0 * Float.pi * fc)

            // Simplified Cole calculation for realistic values
            let logArg = 1.0 + pow(omega * tau, alpha)
            let magnitude = Re + (Ri / logArg)
            let phase = -alpha * 90.0 * atan(omega * tau) / (.pi / 2.0)

            return ImpedanceData.MeasurementPoint(
                frequency: f,
                magnitude: magnitude,
                phase: phase
            )
        }

        return ImpedanceData(
            measurements: measurements,
            timestamp: createSampleDate(daysAgo: 1),
            deviceInfo: DeviceInfo(
                name: "BioMess Device",
                serialNumber: "VLM2024001",
                batteryLevel: BatteryData(voltageMillivolts: 3200, percentage: 92)
            )
        )
    }

    private static func createSampleDate(daysAgo: Int = 0) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    }

    /// All sample measurements for testing different scenarios
    public static let allSamples = [zBoardCalibration, biologicalTissue]
}
