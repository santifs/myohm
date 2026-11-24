import SwiftUI

/// Calibration view for performing bioimpedance system calibration with reference circuits
public struct CalibrationView: View {
    @Environment(MockBioMessCoreBLEManager.self) private var bleManager
    @Environment(BioimpedanceProcessor.self) private var processor
    @State private var calibrationProcessor = CalibrationProcessor()
    
    @State private var calibrationState: CalibrationState = .idle
    @State private var currentCircuit: CalibrationCircuit = .c1
    @State private var currentCalibration: CalibrationConstants?
    @State private var measurements: [CalibrationMeasurement] = []
    @State private var showingInstructions = false
    @State private var measurementProgress: Float = 0
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Header
                    CalibrationHeaderView()
                    
                    // Current Circuit Info
                    if calibrationState == .idle {
                        NextCircuitView(circuit: getNextCircuit())
                    }
                    
                    // Current Calibration Status
                    if let calibration = currentCalibration {
                        CurrentCalibrationStatusView(calibration: calibration)
                    }
                    
                    // Calibration Progress
                    switch calibrationState {
                    case .idle:
                        CalibrationStartView(
                            nextCircuit: getNextCircuit(),
                            onStart: startCalibration,
                            onStartDemo: startDemoCalibration
                        )
                        
                    case .preparing(let circuit):
                        CircuitPreparationView(
                            circuit: circuit,
                            onContinue: { startMeasurement(circuit: circuit) }
                        )
                        
                    case .measuring(let circuit, let progress):
                        MeasurementProgressView(
                            circuit: circuit,
                            progress: progress
                        )
                        
                    case .processing:
                        ProcessingCalibrationView()
                        
                    case .completed(let constants):
                        CalibrationCompletedView(
                            constants: constants,
                            onStartNew: resetCalibration
                        )
                        
                    case .error(let message):
                        CalibrationErrorView(
                            message: message,
                            onRetry: resetCalibration
                        )
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Calibration")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: {
                    #if os(iOS)
                    .topBarTrailing
                    #else
                    .primaryAction
                    #endif
                }()) {
                    Button("Instructions") {
                        showingInstructions = true
                    }
                }
            }
            .sheet(isPresented: $showingInstructions) {
                CalibrationInstructionsView()
            }
        }
    }
    
    // MARK: - Calibration Actions
    
    private func getNextCircuit() -> CalibrationCircuit {
        switch measurements.count {
        case 0: return .c1
        case 1: return .c2
        case 2: return .c3
        default: return .c1
        }
    }
    
    private func startCalibration() {
        measurements.removeAll()
        currentCircuit = .c1
        calibrationState = .preparing(circuit: .c1)
    }
    
    private func startMeasurement(circuit: CalibrationCircuit) {
        calibrationState = .measuring(circuit: circuit, progress: 0)
        measurementProgress = 0
        
        Task {
            do {
                await MainActor.run {
                    calibrationState = .measuring(circuit: circuit, progress: 0.1)
                }
                
                // Perform multiple measurements for averaging
                var rawMeasurements: [ImpedanceData] = []
                let numMeasurements = 5  // Take 5 measurements for averaging
                
                for measurement in 0..<numMeasurements {
                    let data = try await bleManager.performMeasurement()
                    rawMeasurements.append(data)
                    
                    let progress = Float(measurement + 1) / Float(numMeasurements) * 0.8 + 0.1
                    await MainActor.run {
                        calibrationState = .measuring(circuit: circuit, progress: progress)
                    }
                }
                
                await MainActor.run {
                    calibrationState = .measuring(circuit: circuit, progress: 0.95)
                }
                
                // Process measurements into calibration data
                let expectedFrequencies = rawMeasurements[0].frequencies
                let calibrationMeasurement = try calibrationProcessor.processCalibrationMeasurement(
                    circuitName: circuit.displayName,
                    rawMeasurements: rawMeasurements,
                    expectedFrequencies: expectedFrequencies
                )
                
                await MainActor.run {
                    measurements.append(calibrationMeasurement)
                    
                    // Move to next circuit or complete
                    switch circuit {
                    case .c1:
                        currentCircuit = .c2
                        calibrationState = .preparing(circuit: .c2)
                    case .c2:
                        currentCircuit = .c3
                        calibrationState = .preparing(circuit: .c3)
                    case .c3:
                        completeCalibration()
                    }
                }
                
            } catch {
                await MainActor.run {
                    calibrationState = .error(error.localizedDescription)
                }
            }
        }
    }
    
    private func completeCalibration() {
        calibrationState = .processing
        
        Task {
            do {
                guard measurements.count == 3 else {
                    throw CalibrationError.invalidMeasurementCount
                }
                
                let constants = try calibrationProcessor.generateCalibrationConstants(
                    c1Measurement: measurements[0], // C1
                    c2Measurement: measurements[1], // C2
                    c3Measurement: measurements[2]  // C3
                )
                
                await MainActor.run {
                    currentCalibration = constants
                    calibrationState = .completed(constants)
                }
                
            } catch {
                await MainActor.run {
                    calibrationState = .error(error.localizedDescription)
                }
            }
        }
    }
    
    private func resetCalibration() {
        calibrationState = .idle
        measurements.removeAll()
        measurementProgress = 0
    }
    
    private func startDemoCalibration() {
        measurements.removeAll()
        calibrationState = .processing
        
        Task {
            // Simulate processing time
            try await Task.sleep(for: .seconds(2))
            
            // Generate demo calibration data for C1, C2, C3
            let demoMeasurements = generateDemoCalibrationMeasurements()
            
            do {
                let constants = try calibrationProcessor.generateCalibrationConstants(
                    c1Measurement: demoMeasurements[0], // C1
                    c2Measurement: demoMeasurements[1], // C2  
                    c3Measurement: demoMeasurements[2]  // C3
                )
                
                await MainActor.run {
                    measurements = demoMeasurements
                    currentCalibration = constants
                    calibrationState = .completed(constants)
                }
                
            } catch {
                await MainActor.run {
                    calibrationState = .error("Demo calibration failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Generate realistic demo calibration measurements for C1, C2, C3
    private func generateDemoCalibrationMeasurements() -> [CalibrationMeasurement] {
        let circuits: [CalibrationCircuit] = [.c1, .c2, .c3]
        
        // Use the same frequencies as the real system
        let frequencies: [Float] = [
            1000, 2154, 4642, 10000, 21544, 46416, 100000, 
            215443, 464159, 1000000  // 10 frequencies for demo
        ]
        
        var measurements: [CalibrationMeasurement] = []
        
        for circuit in circuits {
            let params = circuit.referenceParameters
            let Re = params[0]
            let Ri = params[1] 
            let Cm = params[2]
            
            // Generate theoretical impedance with some realistic noise
            var complexAverage: [Complex] = []
            var precision: [Float] = []
            var standardDeviation: [Float] = []
            
            for freq in frequencies {
                // Calculate theoretical impedance using body model
                let omega = 2 * Float.pi * freq
                let Zcm_mag = 1.0 / (omega * Cm)
                let Zcm = Complex(real: 0, imaginary: -Zcm_mag)
                
                // Series: Ri + Zcm
                let series = Complex(real: Ri, imaginary: 0) + Zcm
                
                // Parallel: Re || (Ri + Zcm)
                let Re_complex = Complex(real: Re, imaginary: 0)
                let theoretical = (Re_complex * series) / (Re_complex + series)
                
                // Add realistic measurement noise (1-3% CV)
                let noise_magnitude = Float.random(in: 0.01...0.03)
                let noise_phase = Float.random(in: 0.005...0.015)
                
                let noisy_magnitude = theoretical.magnitude * (1 + Float.random(in: -noise_magnitude...noise_magnitude))
                let noisy_phase = theoretical.phase + Float.random(in: -noise_phase...noise_phase)
                
                let noisyImpedance = Complex(magnitude: noisy_magnitude, phase: noisy_phase)
                complexAverage.append(noisyImpedance)
                
                // Realistic precision values (CV%)
                let cv_percent = noise_magnitude * 100 * Float.random(in: 0.8...1.2)
                precision.append(cv_percent)
                
                // Standard deviation
                let std_dev = theoretical.magnitude * noise_magnitude
                standardDeviation.append(std_dev)
            }
            
            let measurement = CalibrationMeasurement(
                circuitName: circuit.displayName,
                frequencies: frequencies,
                complexAverage: complexAverage,
                precision: precision,
                standardDeviation: standardDeviation
            )
            
            measurements.append(measurement)
        }
        
        return measurements
    }
}

// MARK: - Subviews

private struct CalibrationHeaderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tuningfork")
                .font(.system(size: 48))
                .foregroundStyle(.blue.gradient)
            
            Text("System Calibration")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Calibrate using reference circuits with known impedance values for research-grade accuracy")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct NextCircuitView: View {
    let circuit: CalibrationCircuit
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Next Circuit to Measure")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Circuit \(circuit.displayName)")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Text(circuit.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("Step \(circuit.stepNumber)/3")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.2), in: Capsule())
                    .foregroundStyle(.blue)
            }
            .padding()
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CurrentCalibrationStatusView: View {
    let calibration: CalibrationConstants
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current Calibration")
                    .font(.headline)
                Spacer()
                CalibrationQualityBadge(status: calibration.quality.status)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Circuits: C1, C2, C3")
                Text("Date: \(calibration.timestamp, style: .date)")
                Text("Quality: \(String(format: "%.1f%%", calibration.quality.overallScore * 100))")
                
                if calibration.quality.needsRecalibration {
                    Text("⚠️ Recalibration recommended")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CalibrationQualityBadge: View {
    let status: CalibrationStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(status.color).opacity(0.2), in: Capsule())
            .foregroundStyle(Color(status.color))
    }
}

private struct CalibrationStartView: View {
    let nextCircuit: CalibrationCircuit
    let onStart: () -> Void
    let onStartDemo: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Ready to Calibrate")
                .font(.headline)
            
            Text("This will measure 3 reference circuits: C1, C2, C3 in sequence")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                // Demo Calibration Button
                Button(action: onStartDemo) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Quick Demo (2s)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green.gradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Real Calibration Button
                Button(action: onStart) {
                    HStack {
                        Image(systemName: "tuningfork")
                        Text("Real Calibration")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue.gradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            
            Text("Demo uses simulated data with realistic noise for testing the calibration workflow")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CircuitPreparationView: View {
    let circuit: CalibrationCircuit
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                
                Text("Prepare Circuit \(circuit.displayName)")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Step \(circuit.stepNumber) of 3")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Instructions:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    InstructionStep("1", "Disconnect any current circuit")
                    InstructionStep("2", "Connect reference circuit \(circuit.displayName)")
                    InstructionStep("3", "Ensure all connections are secure")
                    InstructionStep("4", "Verify circuit is properly positioned")
                }
            }
            
            Button(action: onContinue) {
                Text("Start Measurement")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green.gradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct InstructionStep: View {
    let number: String
    let text: String
    
    init(_ number: String, _ text: String) {
        self.number = number
        self.text = text
    }
    
    var body: some View {
        HStack {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 20, height: 20)
                .background(.blue, in: Circle())
                .foregroundStyle(.white)
            
            Text(text)
                .font(.caption)
        }
    }
}

private struct MeasurementProgressView: View {
    let circuit: CalibrationCircuit
    let progress: Float
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundStyle(.blue.gradient)
                .symbolEffect(.pulse, value: progress)
            
            Text("Measuring \(circuit.displayName)")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Taking multiple measurements for accuracy")
                .font(.body)
                .foregroundStyle(.secondary)
            
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .frame(maxWidth: 200)
            
            Text("\(Int(progress * 100))% Complete")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ProcessingCalibrationView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.orange.gradient)
                .rotationEffect(.degrees(45))
            
            Text("Processing Calibration")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Calculating weighting functions and validating quality")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
        }
        .padding()
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CalibrationCompletedView: View {
    let constants: CalibrationConstants
    let onStartNew: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                
                Text("Calibration Complete")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                CalibrationQualityBadge(status: constants.quality.status)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Results")
                    .font(.headline)
                
                VStack(spacing: 8) {
                    ResultRow("Circuits", "C1, C2, C3")
                    ResultRow("Quality Score", "\(String(format: "%.1f%%", constants.quality.overallScore * 100))")
                    ResultRow("Max Precision Error", "\(String(format: "%.2f%%", constants.quality.maxPrecisionError))")
                    ResultRow("Mean Residual Error", "\(String(format: "%.3f", constants.quality.meanResidualError))")
                }
            }
            
            Text(constants.quality.status.recommendation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: onStartNew) {
                Text("Start New Calibration")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue.gradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ResultRow: View {
    let label: String
    let value: String
    
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

private struct CalibrationErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            
            Text("Calibration Error")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: onRetry) {
                Text("Try Again")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.red.gradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CalibrationInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    Text("Calibration Instructions")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Overview")
                            .font(.headline)
                        
                        Text("System calibration uses known reference circuits to correct measurement errors and ensure research-grade accuracy. The calibration process measures three reference circuits with precisely known impedance values.")
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Reference Circuits")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Original Set (C1-C3):")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("• C1: High resistance (1270Ω extracellular)")
                            Text("• C2: Medium resistance (422Ω extracellular)")
                            Text("• C3: Low resistance (100Ω extracellular)")
                        }
                        .font(.caption)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Calibration Process")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Select the appropriate calibration set")
                            Text("2. Connect and measure each reference circuit")
                            Text("3. System calculates correction factors")
                            Text("4. Quality validation ensures accuracy")
                            Text("5. Calibration applied to future measurements")
                        }
                        .font(.caption)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quality Requirements")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Precision (CV%) should be < 5%")
                            Text("• Overall quality score should be > 80%")
                            Text("• All reference circuits must be measured")
                            Text("• Connections must be secure and stable")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Instructions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: {
                    #if os(iOS)
                    .topBarTrailing
                    #else
                    .primaryAction
                    #endif
                }()) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    CalibrationView()
        .environment(MockBioMessCoreBLEManager())
        .environment(BioimpedanceProcessor())
}