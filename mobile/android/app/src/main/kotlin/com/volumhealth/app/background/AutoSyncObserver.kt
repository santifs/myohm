package com.volumhealth.app.background

import com.volumhealth.core.ble.ConnectionState
import com.volumhealth.core.ble.BioMessBleManager
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * Observes BLE connection state and syncs stored measurements when reconnected.
 *
 */
@Singleton
class AutoSyncObserver @Inject constructor(
    private val bleManager: BioMessBleManager,
    private val storedMeasurementSyncManager: StoredMeasurementSyncManager
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    init {
        scope.launch {
            var lastState: ConnectionState = ConnectionState.Disconnected
            bleManager.connectionState.collectLatest { state ->
                if (state == ConnectionState.Connected && lastState != ConnectionState.Connected) {
                    runCatching {
                        val imported = storedMeasurementSyncManager.syncAllMeasurements()
                        if (imported > 0) {
                            android.util.Log.i("AutoSyncObserver", "Imported $imported stored measurements after reconnect")
                        }
                    }
                }
                lastState = state
            }
        }
    }
}
