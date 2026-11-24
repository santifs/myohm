import Testing
@testable import BioMessAppFeature

@Suite("MuscleGroup")
struct MuscleGroupTests {
    @Test func parsesNewMuscles() {
        #expect(MuscleGroup(rawValue: "biceps_brachii") == .bicepsBrachii)
        #expect(MuscleGroup(rawValue: "vastus_lateralis") == .vastusLateralis)
        #expect(MuscleGroup(rawValue: "biceps_femoris") == .bicepsFemoris)
    }

    @Test func legacyValuesStillParse() {
        #expect(MuscleGroup(rawValue: "quadriceps") == .quadriceps)
        #expect(MuscleGroup(rawValue: "hamstring") == .hamstring)
    }

    @Test func newMusclesHaveSpanishDisplayNames() {
        #expect(MuscleGroup.bicepsBrachii.displayName == "Bíceps braquial")
        #expect(MuscleGroup.vastusLateralis.displayName == "Vasto lateral")
        #expect(MuscleGroup.bicepsFemoris.displayName == "Bíceps femoral")
    }

    @Test func allCasesPresent() {
        #expect(MuscleGroup.allCases.count == 5)
    }
}
