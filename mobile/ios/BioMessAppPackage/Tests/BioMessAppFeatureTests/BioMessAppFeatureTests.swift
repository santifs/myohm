import Testing
@testable import BioMessAppFeature

@Test func quickEstimateUsesReactancePeak() async throws {
    let data = ImpedanceData(measurements: [
        .init(frequency: 5000, magnitude: 100, phase: -5),
        .init(frequency: 50000, magnitude: 80, phase: -15),
        .init(frequency: 100000, magnitude: 40, phase: -20)
    ])
    let result = try await BioimpedanceProcessor().processQuick(data)
    #expect(result.fc == 50)
    #expect(!result.quality.convergence.converged)
    #expect(result.quality.convergence.parameterErrors == nil)
}
