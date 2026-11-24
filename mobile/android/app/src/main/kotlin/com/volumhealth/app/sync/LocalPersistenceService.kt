// SPDX-License-Identifier: Apache-2.0
package com.volumhealth.app.sync
import kotlinx.coroutines.CompletableJob
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.datetime.Instant
import javax.inject.Inject
import javax.inject.Singleton

/** Existing repositories commit to Room before calling this boundary. No network or cloud queue. */
@Singleton
class LocalPersistenceService @Inject constructor() {
    val isSyncing: StateFlow<Boolean> = MutableStateFlow(false)
    val pendingCount: StateFlow<Int> = MutableStateFlow(0)
    val lastError: StateFlow<String?> = MutableStateFlow(null)
    val lastSyncTime: StateFlow<Instant?> = MutableStateFlow(null)
    fun triggerSync(): Job = Job().also { it.complete() }
    suspend fun syncAll() = Unit
    suspend fun updatePendingCount() = Unit
}
