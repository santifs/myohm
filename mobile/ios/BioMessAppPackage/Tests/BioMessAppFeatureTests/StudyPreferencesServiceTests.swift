import Testing
import Foundation
@testable import BioMessAppFeature

@Suite("StudyPreferencesService")
@MainActor
struct StudyPreferencesServiceTests {
    private static let testKey = "active_study_code"

    @Test func initialisesWithStoredValue() {
        UserDefaults.standard.set(Study.bicepsTFG.rawValue, forKey: Self.testKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.testKey) }

        let service = StudyPreferencesService()
        #expect(service.activeStudy == .bicepsTFG)
    }

    @Test func initialisesNilWhenStorageEmpty() {
        UserDefaults.standard.removeObject(forKey: Self.testKey)

        let service = StudyPreferencesService()
        #expect(service.activeStudy == nil)
    }

    @Test func initialisesNilWhenStorageHasUnknownValue() {
        UserDefaults.standard.set("not_a_real_study", forKey: Self.testKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.testKey) }

        let service = StudyPreferencesService()
        #expect(service.activeStudy == nil)
    }

    @Test func setActiveStudyPersistsRawValue() {
        UserDefaults.standard.removeObject(forKey: Self.testKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.testKey) }

        let service = StudyPreferencesService()
        service.setActiveStudy(.sentadillaTFM)

        #expect(service.activeStudy == .sentadillaTFM)
        #expect(UserDefaults.standard.string(forKey: Self.testKey) == "sentadilla_tfm")
    }

    @Test func setActiveStudyNilRemovesStorage() {
        UserDefaults.standard.set(Study.bicepsTFG.rawValue, forKey: Self.testKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.testKey) }

        let service = StudyPreferencesService()
        service.setActiveStudy(nil)

        #expect(service.activeStudy == nil)
        #expect(UserDefaults.standard.string(forKey: Self.testKey) == nil)
    }
}
