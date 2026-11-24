package com.volumhealth.app.ui.screens.settings

import android.bluetooth.BluetoothDevice
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.volumhealth.app.auth.LocalProfileService
import com.volumhealth.app.auth.AuthState
import com.volumhealth.app.locale.AppLanguage
import com.volumhealth.app.locale.LanguageManager
import com.volumhealth.app.study.Study
import com.volumhealth.app.study.StudyPreferencesManager
import com.volumhealth.app.sync.LocalPersistenceService
import com.volumhealth.core.ble.BioMessBleManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val bleManager: BioMessBleManager,
    private val languageManager: LanguageManager,
    private val authService: LocalProfileService,
    private val syncService: LocalPersistenceService,
    private val studyPrefs: StudyPreferencesManager
) : ViewModel() {
    val connectionState = bleManager.connectionState
    val battery = bleManager.currentBatteryLevel
    val devices: StateFlow<List<BluetoothDevice>> = bleManager.discoveredDevices

    val currentLanguage: StateFlow<AppLanguage> = languageManager.currentLanguage
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AppLanguage.ENGLISH)

    val activeStudy: StateFlow<Study?> = studyPrefs.activeStudy
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    // Auth state
    val currentUserEmail: String?
        get() = (authService.authState.value as? AuthState.Authenticated)?.email

    // Sync state
    val isSyncing = syncService.isSyncing
    val pendingCount = syncService.pendingCount
    val lastSyncError = syncService.lastError

    init {
        viewModelScope.launch {
            syncService.updatePendingCount()
        }
    }

    fun startScan() = bleManager.startScan()
    fun stopScan() = bleManager.stopScan()
    fun connect(device: BluetoothDevice) = bleManager.connect(device)
    fun disconnect() = bleManager.disconnect()

    fun setLanguage(language: AppLanguage) {
        viewModelScope.launch {
            languageManager.setLanguage(language)
        }
    }

    fun selectStudy(study: Study) {
        viewModelScope.launch {
            studyPrefs.setActiveStudy(study)
        }
    }

    fun signOut() {
        viewModelScope.launch {
            authService.signOut()
        }
    }

    fun syncNow() {
        syncService.triggerSync()
    }
}
