package com.volumhealth.app.myohm.data

import android.bluetooth.BluetoothDevice
import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.volumhealth.app.myohm.domain.MeasurementKind
import com.volumhealth.core.ble.BioMessBleManager
import com.volumhealth.core.model.Athlete
import com.volumhealth.core.model.ImpedanceData
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/** Shared state for the redesigned app, scoped to the activity. */
@HiltViewModel
class MyohmViewModel @Inject constructor(
    @ApplicationContext context: Context,
    private val repository: MyohmRepository,
    val ble: BioMessBleManager
) : ViewModel() {

    private val demo = MyohmDemo.isEnabled(context)
    private val prefs = context.getSharedPreferences(if (demo) "myohm-demo" else "myohm", Context.MODE_PRIVATE)

    /** Null until the database has answered, so the first screen does not flash. */
    val people: StateFlow<List<Athlete>?> = repository.people
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    val records: StateFlow<List<MyohmRecord>> = repository.records
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    private val _selectedPersonId = MutableStateFlow(prefs.getString(KEY_PERSON, "") ?: "")
    val selectedPersonId: StateFlow<String> = _selectedPersonId.asStateFlow()

    private val _onboarded = MutableStateFlow(prefs.getBoolean(KEY_ONBOARDED, false))
    val onboarded: StateFlow<Boolean> = _onboarded.asStateFlow()

    val connectionState = ble.connectionState
    val battery = ble.currentBatteryLevel
    val isDeviceReady = ble.isDeviceReady
    val liveProgress = ble.liveSweepProgress
    val livePoints = ble.liveSweepPoints
    val discoveredDevices = ble.discoveredDevices

    init {
        if (demo) viewModelScope.launch {
            if (repository.people.first().isEmpty()) finishOnboarding(MyohmDemo.seed(repository))
        }
    }

    fun selectPerson(id: String) {
        _selectedPersonId.value = id
        prefs.edit().putString(KEY_PERSON, id).apply()
    }

    fun finishOnboarding(personId: String) {
        selectPerson(personId)
        _onboarded.value = true
        prefs.edit().putBoolean(KEY_ONBOARDED, true).apply()
    }

    fun savePerson(person: Athlete, isNew: Boolean, onSaved: (Athlete) -> Unit) {
        viewModelScope.launch {
            repository.savePerson(person, isNew)
            onSaved(person)
        }
    }

    fun deletePerson(person: Athlete) {
        val ids = records.value.filter { it.personId == person.id }.map { it.id }
        viewModelScope.launch {
            repository.deletePerson(person.id, ids)
            if (_selectedPersonId.value == person.id) selectPerson("")
        }
    }

    suspend fun measure(kind: MeasurementKind, personId: String?): String {
        val data: ImpedanceData = ble.performMeasurement(
            numPoints = SWEEP_POINTS,
            startFreq = SWEEP_START_HZ,
            stopFreq = SWEEP_STOP_HZ,
            repetitions = SWEEP_REPETITIONS
        )
        return repository.saveMeasurement(kind, personId, data)
    }

    // BLE helpers
    fun hasPairedDevice(): Boolean = ble.pairedDevice() != null
    fun pairedDeviceName(): String? = ble.pairedDevice()?.name
    fun reconnect() { ble.reconnectLastKnown() }
    fun startScan() { ble.startScan() }
    fun stopScan() { ble.stopScan() }
    fun connect(device: BluetoothDevice) { ble.connect(device) }
    fun disconnect() { ble.disconnect() }
    fun forgetDevice() {
        ble.cancelAutoReconnectAndReset()
        ble.disconnect()
        ble.forgetPairedDevice()
    }

    companion object {
        private const val KEY_PERSON = "personID"
        private const val KEY_ONBOARDED = "onboarded"
        const val SWEEP_POINTS = 48
        const val SWEEP_START_HZ = 4_000f
        const val SWEEP_STOP_HZ = 198_000f
        const val SWEEP_REPETITIONS = 3
    }
}
