import Foundation
import Observation

/// App-wide source of truth for the active `Study`.
///
/// Persists the active study's rawValue in `UserDefaults` under
/// `active_study_code`. UI reads `activeStudy` via `@Environment` and
/// reacts to changes thanks to `@Observable`.
@Observable
@MainActor
public final class StudyPreferencesService {
    private static let key = "active_study_code"

    public private(set) var activeStudy: Study?

    public init() {
        let stored = UserDefaults.standard.string(forKey: Self.key) ?? ""
        self.activeStudy = Study(rawValue: stored)
    }

    public func setActiveStudy(_ study: Study?) {
        activeStudy = study
        if let study {
            UserDefaults.standard.set(study.rawValue, forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }
}
