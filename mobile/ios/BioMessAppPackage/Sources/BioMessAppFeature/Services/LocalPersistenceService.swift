// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftData
import Observation

@Observable @MainActor public final class LocalPersistenceService {
    public var isSyncing = false
    public var pendingCount = 0
    public var lastSyncTime: Date?
    public var lastError: String?
    private var context: ModelContext?
    public init() {}
    public func setModelContext(_ context: ModelContext) { self.context = context }
    public var currentUserId: UUID? { nil }
    public func syncAll() async {
        do { try context?.save(); lastError = nil } catch { lastError = error.localizedDescription }
    }
    public func syncAthlete(_ athlete: Athlete) async throws { try context?.save() }
    public func syncSession(_ session: MeasurementSession) async throws { try context?.save() }
    public func syncMeasurement(_ measurement: Measurement) async throws { try context?.save() }
}
