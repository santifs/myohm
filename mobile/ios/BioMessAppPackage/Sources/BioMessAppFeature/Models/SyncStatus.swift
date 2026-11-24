import Foundation

/// Synchronization status for cloud sync with Supabase
/// Used by all syncable models (Athlete, MeasurementSession, Measurement)
public enum SyncStatus: String, Sendable, Codable, CaseIterable {
    /// Created locally, not yet synced to cloud
    case pending = "pending"

    /// Successfully synced to cloud
    case synced = "synced"

    /// Modified locally after sync, needs re-sync
    case modified = "modified"

    /// Sync failed, will retry
    case failed = "failed"

    /// Currently syncing
    case syncing = "syncing"

    // MARK: - Display Properties

    public var displayName: String {
        switch self {
        case .pending: return "Pendiente de sincronizar"
        case .synced: return "Sincronizado"
        case .modified: return "Modificado"
        case .failed: return "Error de sincronización"
        case .syncing: return "Sincronizando…"
        }
    }

    public var iconName: String {
        switch self {
        case .pending: return "arrow.up.circle"
        case .synced: return "checkmark.circle.fill"
        case .modified: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath.circle"
        }
    }

    public var color: String {
        switch self {
        case .pending: return "orange"
        case .synced: return "green"
        case .modified: return "blue"
        case .failed: return "red"
        case .syncing: return "blue"
        }
    }

    /// Whether this status indicates the item needs to be synced
    public var needsSync: Bool {
        switch self {
        case .pending, .modified, .failed:
            return true
        case .synced, .syncing:
            return false
        }
    }
}
