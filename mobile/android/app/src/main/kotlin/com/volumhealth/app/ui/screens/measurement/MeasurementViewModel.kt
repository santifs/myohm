package com.volumhealth.app.ui.screens.measurement

import android.bluetooth.BluetoothDevice
import androidx.annotation.StringRes
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.volumhealth.app.R
import com.volumhealth.app.background.StoredMeasurementSyncManager
import android.util.Log
import com.volumhealth.core.ble.ConnectionState
import com.volumhealth.core.ble.ScanStartResult
import com.volumhealth.core.ble.BioMessBleManager
import com.volumhealth.core.database.MeasurementHistoryManager
import com.volumhealth.app.study.Study
import com.volumhealth.app.sync.LocalPersistenceService
import com.volumhealth.core.model.BatteryData
import com.volumhealth.core.model.BodySide
import com.volumhealth.core.model.Gender
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.MuscleGroup
import com.volumhealth.core.model.PatientSnapshot
import com.volumhealth.core.processing.BioimpedanceProcessor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import javax.inject.Inject

/**
 * Represents an error message that can be either a dynamic string or a localized resource
 */
sealed interface ErrorMessage {
    data class Text(val message: String) : ErrorMessage
    data class Resource(@StringRes val resId: Int) : ErrorMessage
}

/**
 * UI state for the measurement flow, matching iOS behavior
 */
sealed interface MeasurementViewState {
    data object Disconnected : MeasurementViewState
    data object DeviceSelection : MeasurementViewState
    data class Connected(val deviceName: String) : MeasurementViewState
    data object Measuring : MeasurementViewState
    data object AwaitingFatigueRating : MeasurementViewState
    data class Results(val data: ImpedanceData) : MeasurementViewState
    data class Error(val errorMessage: ErrorMessage) : MeasurementViewState
    data class PermissionsRequired(val permissions: List<String>) : MeasurementViewState
    data object BluetoothDisabled : MeasurementViewState
}

/**
 * Patient form data
 */
data class PatientFormData(
    val name: String = "",
    val exerciseName: String = "",
    val age: String = "",
    val gender: Gender = Gender.MALE,
    val height: String = "",
    val weight: String = ""
) {
    val isValid: Boolean
        get() = name.isNotBlank() &&
                exerciseName.isNotBlank() &&
                age.toIntOrNull()?.let { it in 1..120 } == true &&
                height.toFloatOrNull()?.let { it in 50f..250f } == true &&
                weight.toFloatOrNull()?.let { it in 20f..300f } == true

    val bmi: Float?
        get() {
            val h = height.toFloatOrNull()?.div(100) ?: return null
            val w = weight.toFloatOrNull() ?: return null
            return w / (h * h)
        }

    @get:StringRes
    val bmiCategoryResId: Int
        get() {
            val bmiValue = bmi ?: return 0
            return when {
                bmiValue <= 18.5f -> R.string.bmi_underweight
                bmiValue <= 25f -> R.string.bmi_normal
                bmiValue <= 30f -> R.string.bmi_overweight
                else -> R.string.bmi_obese
            }
        }

    fun toSnapshot(measurementNumber: Int): PatientSnapshot = PatientSnapshot(
        name = name,
        exerciseName = exerciseName,
        measurementNumber = measurementNumber,
        age = age.toIntOrNull() ?: 0,
        gender = gender,
        height = height.toFloatOrNull() ?: 0f,
        weight = weight.toFloatOrNull() ?: 0f,
        bmi = bmi ?: 0f,
        timestamp = Clock.System.now()
    )
}

@HiltViewModel
class MeasurementViewModel @Inject constructor(
    private val bleManager: BioMessBleManager,
    private val historyManager: MeasurementHistoryManager,
    private val syncService: LocalPersistenceService,
    private val processor: BioimpedanceProcessor,
    private val storedMeasurementSyncManager: StoredMeasurementSyncManager,
    private val sessionDao: com.volumhealth.core.database.dao.MeasurementSessionDao,
    private val newMeasurementDao: com.volumhealth.core.database.dao.NewMeasurementDao,
    private val athleteRepository: com.volumhealth.app.data.AthleteRepository,
    private val studyPrefs: com.volumhealth.app.study.StudyPreferencesManager
) : ViewModel() {

    val connectionState = bleManager.connectionState
    val discoveredDevices = bleManager.discoveredDevices
    val battery: StateFlow<BatteryData?> = bleManager.currentBatteryLevel
    val isDeviceReady: StateFlow<Boolean> = bleManager.isDeviceReady
    private val _athleteName = kotlinx.coroutines.flow.MutableStateFlow("")
    val athleteName: StateFlow<String> = _athleteName

    val activeStudy: StateFlow<Study?> = studyPrefs.activeStudy
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    private val _selectedMuscleGroup = MutableStateFlow<MuscleGroup?>(null)
    val selectedMuscleGroup: StateFlow<MuscleGroup?> = _selectedMuscleGroup.asStateFlow()

    private val _selectedSide = MutableStateFlow<BodySide?>(null)
    val selectedSide: StateFlow<BodySide?> = _selectedSide.asStateFlow()

    private val _viewState = MutableStateFlow<MeasurementViewState>(MeasurementViewState.Disconnected)
    val viewState: StateFlow<MeasurementViewState> = _viewState.asStateFlow()

    private val _patientForm = MutableStateFlow(PatientFormData())
    val patientForm: StateFlow<PatientFormData> = _patientForm.asStateFlow()

    private val _measurementNumber = MutableStateFlow(1)
    val measurementNumber: StateFlow<Int> = _measurementNumber.asStateFlow()

    private val _lastMeasurementData = MutableStateFlow<ImpedanceData?>(null)
    val lastMeasurementData: StateFlow<ImpedanceData?> = _lastMeasurementData.asStateFlow()

    private var currentSessionPatient = ""
    private var currentSessionExercise = ""

    private var measurementJob: Job? = null
    private var saveJob: Job? = null

    // Session context — in the simplified flow, only sessionId is carried through the
    // navigation. Muscle group and side are recorded as fixed defaults; perceived fatigue
    // is captured via the Borg CR-10 gate after each measurement completes.
    private var flowSessionId: String = ""

    // Pending payload while the user rates the just-completed measurement.
    private var pendingData: ImpedanceData? = null
    private var pendingRawMeasurementId: String? = null
    private var pendingMeasuredAt: Instant? = null

    init {
        // React to connection state changes
        viewModelScope.launch {
            connectionState.collect { state ->
                updateViewStateFromConnection(state)
            }
        }
        // Default selections track the active study (first muscle / first side declared).
        viewModelScope.launch {
            activeStudy.collect { study ->
                _selectedMuscleGroup.value = study?.muscleGroups?.firstOrNull()
                _selectedSide.value = study?.sides?.firstOrNull()
            }
        }
    }

    fun selectMuscleGroup(mg: MuscleGroup) {
        _selectedMuscleGroup.value = mg
    }

    fun selectSide(side: BodySide) {
        _selectedSide.value = side
    }

    private fun updateViewStateFromConnection(state: ConnectionState) {
        when (state) {
            is ConnectionState.Disconnected -> {
                // Don't override results state
                if (_viewState.value !is MeasurementViewState.Results) {
                    _viewState.value = MeasurementViewState.Disconnected
                }
            }
            is ConnectionState.Scanning, is ConnectionState.Connecting -> {
                _viewState.value = MeasurementViewState.DeviceSelection
            }
            is ConnectionState.Connected -> {
                // Don't override results state
                if (_viewState.value !is MeasurementViewState.Results) {
                    val deviceName = "" // Could get from bleManager if exposed
                    _viewState.value = MeasurementViewState.Connected(deviceName)
                }
            }
            is ConnectionState.Measuring -> {
                _viewState.value = MeasurementViewState.Measuring
            }
            is ConnectionState.Error -> {
                _viewState.value = MeasurementViewState.Error(ErrorMessage.Text(state.message))
            }
        }
    }

    fun startScan() {
        when (val result = bleManager.startScan()) {
            is ScanStartResult.Success -> {
                _viewState.value = MeasurementViewState.DeviceSelection
            }
            is ScanStartResult.MissingPermissions -> {
                _viewState.value = MeasurementViewState.PermissionsRequired(result.permissions)
            }
            is ScanStartResult.BluetoothDisabled -> {
                _viewState.value = MeasurementViewState.BluetoothDisabled
            }
            is ScanStartResult.BluetoothNotAvailable -> {
                _viewState.value = MeasurementViewState.Error(ErrorMessage.Resource(R.string.error_bluetooth_not_available))
            }
        }
    }

    fun stopScan() {
        bleManager.stopScan()
    }

    fun connectToDevice(device: BluetoothDevice) {
        bleManager.connect(device)
    }

    fun disconnect() {
        bleManager.disconnect()
        _viewState.value = MeasurementViewState.Disconnected
    }

    /**
     * Force a fresh device-selection state: cancels any in-flight auto-reconnect
     * (which would otherwise hold connectionState in Connecting) and starts a new
     * scan. Use when the user explicitly wants to find a different device.
     */
    fun forceRescan() {
        bleManager.cancelAutoReconnectAndReset()
        startScan()
    }

    fun updatePatientForm(form: PatientFormData) {
        _patientForm.value = form
    }

    fun startMeasurement() {
        if (_viewState.value is MeasurementViewState.Measuring) return

        measurementJob = viewModelScope.launch {
            // Check if this is a new session
            val form = _patientForm.value
            val isNewSession = currentSessionPatient != form.name ||
                    currentSessionExercise != form.exerciseName

            if (isNewSession || currentSessionPatient.isEmpty()) {
                currentSessionPatient = form.name
                currentSessionExercise = form.exerciseName
                _measurementNumber.value = 1
            }

            _viewState.value = MeasurementViewState.Measuring

            try {
                val data = bleManager.performMeasurement()
                _lastMeasurementData.value = data

                val processedResults = runCatching { processor.processImmediate(data) }
                    .onFailure { error ->
                        Log.w("MeasurementVM", "Immediate processing failed: ${error.message}")
                    }
                    .getOrNull()

                // Save to legacy history
                val patientSnapshot = if (form.isValid) {
                    form.toSnapshot(_measurementNumber.value)
                } else null
                val rawMeasurement = historyManager.addRawMeasurement(
                    rawData = data,
                    patientSnapshot = patientSnapshot,
                    results = processedResults,
                    signalQuality = processedResults?.quality?.score
                )

                // Persist new MeasurementEntity (Supabase) only after the user rates
                // perceived fatigue via the Borg CR-10 gate.
                if (flowSessionId.isNotEmpty()) {
                    pendingData = data
                    pendingRawMeasurementId = rawMeasurement.id
                    pendingMeasuredAt = rawMeasurement.captureTimestamp
                    _viewState.value = MeasurementViewState.AwaitingFatigueRating
                } else {
                    _viewState.value = MeasurementViewState.Results(data)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (t: Throwable) {
                val errorMessage = t.message?.let { ErrorMessage.Text(it) }
                    ?: ErrorMessage.Resource(R.string.error_measurement_failed)
                _viewState.value = MeasurementViewState.Error(errorMessage)
            }
        }
    }

    fun syncStoredMeasurements() {
        viewModelScope.launch {
            runCatching { storedMeasurementSyncManager.syncAllMeasurements() }
                .onSuccess { imported ->
                    Log.i("MeasurementVM", "Stored measurements imported: $imported")
                }
                .onFailure { error ->
                    Log.w("MeasurementVM", "Stored measurement sync failed: ${error.message}")
                }
        }
    }

    fun cancelMeasurementIfCapturing() {
        if (_viewState.value is MeasurementViewState.Measuring) cancelMeasurement()
    }

    fun cancelMeasurement() {
        measurementJob?.cancel()
        measurementJob = null
        clearPendingMeasurement()
        updateViewStateFromConnection(connectionState.value)
    }

    fun confirmFatigue(rating: Int) {
        require(rating in 0..10) { "Borg CR-10 rating out of range: $rating" }
        val data = pendingData ?: run {
            Log.w("MeasurementVM", "confirmFatigue called without pending data")
            return
        }
        saveJob = viewModelScope.launch {
            val rawMeasurementId = pendingRawMeasurementId
            val measuredAt = pendingMeasuredAt
            val mg = _selectedMuscleGroup.value
            val sd = _selectedSide.value
            if (mg == null || sd == null) {
                Log.e("MeasurementVM", "Cannot save: muscleGroup=$mg side=$sd (study not initialized)")
                clearPendingMeasurement()
                _viewState.value = MeasurementViewState.Error(ErrorMessage.Text("Estudio no configurado"))
                return@launch
            }
            if (rawMeasurementId == null || measuredAt == null) {
                Log.e("MeasurementVM", "Cannot save: missing raw measurement link")
                clearPendingMeasurement()
                _viewState.value = MeasurementViewState.Error(ErrorMessage.Text("No se pudo enlazar la medida raw"))
                return@launch
            }
            try {
                val measurementId = historyManager.saveNewMeasurement(
                    sessionId = flowSessionId,
                    muscleGroup = mg.value,
                    side = sd.value,
                    perceivedFatigue = rating,
                    rawData = data,
                    id = rawMeasurementId,
                    measuredAt = measuredAt
                )
                Log.i("MeasurementVM", "Measurement saved: $measurementId (session=$flowSessionId, fatigue=$rating)")
                syncService.triggerSync()
            } catch (e: Exception) {
                Log.e("MeasurementVM", "Failed to save new measurement: ${e.message}")
            }
            clearPendingMeasurement()
            _viewState.value = MeasurementViewState.Results(data)
        }
    }

    private fun clearPendingMeasurement() {
        pendingData = null
        pendingRawMeasurementId = null
        pendingMeasuredAt = null
    }

    fun resetToConnected() {
        _measurementNumber.value += 1
        _lastMeasurementData.value = null
        _viewState.value = MeasurementViewState.Connected("")
    }

    fun hasRequiredPermissions(): Boolean = bleManager.hasRequiredPermissions()

    fun isBluetoothEnabled(): Boolean = bleManager.isBluetoothEnabled()

    fun getMissingPermissions(): List<String> = bleManager.getMissingPermissions()

    fun retryAfterPermissions() {
        if (hasRequiredPermissions() && isBluetoothEnabled()) {
            _viewState.value = MeasurementViewState.Disconnected
        }
    }

    fun setSessionContext(sessionId: String) {
        flowSessionId = sessionId
        viewModelScope.launch {
            val session = sessionDao.getSessionById(sessionId) ?: return@launch
            val athlete = athleteRepository.getAthleteById(session.athleteId)
            _athleteName.value = athlete?.displayName.orEmpty()
        }
    }

    fun cleanupIfEmpty(sessionId: String) {
        if (sessionId.isEmpty()) return
        viewModelScope.launch {
            runCatching {
                saveJob?.join()  // Wait for any in-flight save before checking count.
                val count = newMeasurementDao.getMeasurementCountForSession(sessionId)
                if (count == 0) {
                    sessionDao.deleteById(sessionId)
                    Log.i("MeasurementVM", "Deleted empty session $sessionId")
                }
            }.onFailure { Log.w("MeasurementVM", "cleanupIfEmpty failed: ${it.message}") }
        }
    }
}
