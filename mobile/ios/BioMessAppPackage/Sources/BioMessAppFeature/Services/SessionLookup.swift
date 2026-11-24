import Foundation
import SwiftData

/// Read-side helpers for `MeasurementSession` queries used by the measurement
/// flow (resume-recent and cleanup-on-exit). Keeps the predicate logic in one
/// place so the ViewModel stays focused on orchestration.
public enum SessionLookup {
    /// Find the most recent `MeasurementSession` matching `(athlete, study, sessionType)`
    /// started after `since`. Returns `nil` if none found. Used to reuse a session
    /// when the operator returns to the same protocol phase within a short window.
    @MainActor
    public static func findRecentSession(
        athleteId: UUID,
        studyId: String,
        sessionType: String,
        since: Date,
        in context: ModelContext
    ) throws -> MeasurementSession? {
        let predicate = #Predicate<MeasurementSession> { session in
            session.athlete?.id == athleteId
                && session.studyId == studyId
                && session.sessionType == sessionType
                && session.startedAt >= since
        }
        var descriptor = FetchDescriptor<MeasurementSession>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.startedAt, order: .reverse)]
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Count measurements in a session. Used by cleanup-on-exit to decide if a
    /// session should be deleted because the operator left without measuring.
    @MainActor
    public static func measurementCount(
        sessionId: UUID,
        in context: ModelContext
    ) throws -> Int {
        let predicate = #Predicate<Measurement> { m in
            m.session?.id == sessionId
        }
        let descriptor = FetchDescriptor<Measurement>(predicate: predicate)
        return try context.fetchCount(descriptor)
    }
}
