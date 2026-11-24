package com.volumhealth.core.model

/**
 * Synchronization status for cloud sync with Supabase.
 * Used by all syncable models (Athlete, MeasurementSession, Measurement).
 */
enum class SyncStatus {
    /** Created locally, not yet synced to cloud */
    PENDING,

    /** Successfully synced to cloud */
    SYNCED,

    /** Modified locally after sync, needs re-sync */
    MODIFIED,

    /** Sync failed, will retry */
    FAILED,

    /** Currently syncing */
    SYNCING;

    /** Whether this status indicates the item needs to be synced */
    val needsSync: Boolean
        get() = this in listOf(PENDING, MODIFIED, FAILED)

    val displayName: String
        get() = when (this) {
            PENDING -> "Pending sync"
            SYNCED -> "Synced"
            MODIFIED -> "Modified"
            FAILED -> "Sync failed"
            SYNCING -> "Syncing..."
        }
}
