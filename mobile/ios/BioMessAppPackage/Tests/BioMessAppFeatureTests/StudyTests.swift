import Testing
@testable import BioMessAppFeature

@Suite("Study")
struct StudyTests {
    @Test func bicepsTFG_usesBicepsBrachii_rightOnly() {
        let s = Study.bicepsTFG
        #expect(s.muscleGroups == [.bicepsBrachii])
        #expect(s.sides == [.right])
        #expect(s.sessionTypeSuggestions.contains("basal"))
        #expect(s.sessionTypeSuggestions.contains("post_serie_5"))
        #expect(s.sessionTypeSuggestions.contains("12h"))
        #expect(s.sessionTypeSuggestions.contains("72h"))
        #expect(s.sessionTypeSuggestions.count == 12)
    }

    @Test func sentadillaTFM_isBilateralAndHasTwoMuscles() {
        let s = Study.sentadillaTFM
        #expect(Set(s.muscleGroups) == Set([.vastusLateralis, .bicepsFemoris]))
        #expect(Set(s.sides) == Set([.right, .left]))
        #expect(s.sessionTypeSuggestions.contains("baseline"))
        #expect(s.sessionTypeSuggestions.contains("post_inc_1"))
        #expect(s.sessionTypeSuggestions.contains("post_30s_1"))
        #expect(s.sessionTypeSuggestions.count == 13)
    }

    @Test func parsesFromRawValue() {
        #expect(Study(rawValue: "biceps_tfg") == .bicepsTFG)
        #expect(Study(rawValue: "sentadilla_tfm") == .sentadillaTFM)
        #expect(Study(rawValue: "unknown") == nil)
    }
}
