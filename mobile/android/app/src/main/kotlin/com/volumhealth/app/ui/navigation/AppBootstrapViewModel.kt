package com.volumhealth.app.ui.navigation

import androidx.lifecycle.ViewModel
import com.volumhealth.core.ble.BioMessBleManager
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

/**
 * Fires once when the app composes. Triggers auto-reconnect to the last paired
 * BLE device so the user can measure immediately without a manual scan.
 */
@HiltViewModel
class AppBootstrapViewModel @Inject constructor(
    private val bleManager: BioMessBleManager
) : ViewModel() {

    fun tryAutoReconnect() {
        bleManager.reconnectLastKnown()
    }
}
