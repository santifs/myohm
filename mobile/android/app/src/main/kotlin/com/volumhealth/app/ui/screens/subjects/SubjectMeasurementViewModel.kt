package com.volumhealth.app.ui.screens.subjects

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.volumhealth.app.data.AthleteRepository
import com.volumhealth.app.study.SessionTypeNormalizer
import com.volumhealth.app.study.Study
import com.volumhealth.app.study.StudyPreferencesManager
import com.volumhealth.core.ble.ConnectionState
import com.volumhealth.core.ble.BioMessBleManager
import com.volumhealth.core.database.dao.MeasurementSessionDao
import com.volumhealth.core.database.dao.NewMeasurementDao
import com.volumhealth.core.database.entity.MeasurementSessionEntity
import com.volumhealth.core.model.SyncStatus
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.minus
import java.util.UUID
import javax.inject.Inject

/**
 * Second screen of the simplified flow. Shows the selected subject's name, connection state,
 * and a free-form label input with chips of suggestions from the active Study.
 *
 * On "Measure" tap, looks for a recent matching session (athlete + study + normalized
 * session_type within the last 2 hours) and reuses it; otherwise creates a new
 * [MeasurementSessionEntity].
 */
@HiltViewModel
class SubjectMeasurementViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val athleteRepository: AthleteRepository,
    private val sessionDao: MeasurementSessionDao,
    private val newMeasurementDao: NewMeasurementDao,
    studyPrefs: StudyPreferencesManager,
    private val bleManager: BioMessBleManager
) : ViewModel() {

    fun resetBleForChangeDevice() {
        bleManager.cancelAutoReconnectAndReset()
    }

    private val athleteId: String = checkNotNull(savedStateHandle["athleteId"]) {
        "athleteId is required"
    }

    val activeStudy: StateFlow<Study?> = studyPrefs.activeStudy
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    data class UiState(
        val athleteName: String = "",
        val label: String = "",
        val connectionState: ConnectionState = ConnectionState.Disconnected,
        val isCreatingSession: Boolean = false,
        val sessionTypeSuggestions: List<String> = emptyList(),
        val resumableSessionId: String? = null,
        val resumableMeasurementCount: Int = 0,
        val errorMessage: String? = null
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    private var resumableJob: Job? = null

    init {
        viewModelScope.launch {
            val athlete = athleteRepository.getAthleteById(athleteId)
            _uiState.update { it.copy(athleteName = athlete?.displayName.orEmpty()) }
        }
        viewModelScope.launch {
            bleManager.connectionState.collect { state ->
                _uiState.update { it.copy(connectionState = state) }
            }
        }
        viewModelScope.launch {
            activeStudy.collect { study ->
                _uiState.update {
                    it.copy(sessionTypeSuggestions = study?.sessionTypeSuggestions.orEmpty())
                }
            }
        }
    }

    fun setLabel(newLabel: String) {
        _uiState.update { it.copy(label = newLabel) }
        refreshResumable()
    }

    fun pickSuggestion(suggestion: String) {
        if (_uiState.value.label == suggestion) return
        _uiState.update { it.copy(label = suggestion) }
        refreshResumable()
    }

    fun clearError() {
        _uiState.update { it.copy(errorMessage = null) }
    }

    private fun refreshResumable() {
        val study = activeStudy.value ?: return
        val sessionType = SessionTypeNormalizer.normalize(_uiState.value.label) ?: run {
            _uiState.update { it.copy(resumableSessionId = null, resumableMeasurementCount = 0) }
            return
        }
        resumableJob?.cancel()
        resumableJob = viewModelScope.launch {
            val cutoff = Clock.System.now().minus(2, DateTimeUnit.HOUR)
            val existing = sessionDao.findRecentSession(
                athleteId = athleteId,
                studyId = study.code,
                sessionType = sessionType,
                since = cutoff
            )
            val count = existing?.let { newMeasurementDao.getMeasurementCountForSession(it.id) } ?: 0
            _uiState.update {
                it.copy(
                    resumableSessionId = existing?.id,
                    resumableMeasurementCount = count
                )
            }
        }
    }

    fun startMeasurement(onSessionReady: (sessionId: String) -> Unit) {
        if (_uiState.value.connectionState !is ConnectionState.Connected) return
        if (_uiState.value.isCreatingSession) return
        val study = activeStudy.value ?: run {
            _uiState.update { it.copy(errorMessage = "No active study configured") }
            return
        }
        val sessionType = SessionTypeNormalizer.normalize(_uiState.value.label) ?: run {
            _uiState.update { it.copy(errorMessage = "Especifica el tipo de sesión") }
            return
        }
        _uiState.update { it.copy(isCreatingSession = true, errorMessage = null) }
        viewModelScope.launch {
            try {
                val cutoff = Clock.System.now().minus(2, DateTimeUnit.HOUR)
                val existing = sessionDao.findRecentSession(
                    athleteId = athleteId,
                    studyId = study.code,
                    sessionType = sessionType,
                    since = cutoff
                )
                val sessionId = if (existing != null) {
                    existing.id
                } else {
                    val newId = UUID.randomUUID().toString()
                    val session = MeasurementSessionEntity(
                        id = newId,
                        athleteId = athleteId,
                        startedAt = Clock.System.now(),
                        hoursSinceActivity = null,
                        lastActivityType = null,
                        sleepHours = null,
                        generalFatigue = null,
                        recentPhysio = null,
                        recentPhysioHoursAgo = null,
                        newIssues = null,
                        menstrualCyclePhase = null,
                        involvedLegs = null,
                        legMuscleGroup = null,
                        sessionType = sessionType,
                        studyId = study.code,
                        syncStatus = SyncStatus.PENDING.name,
                        lastSyncAttempt = null,
                        syncError = null
                    )
                    sessionDao.insert(session)
                    newId
                }
                _uiState.update { it.copy(isCreatingSession = false) }
                onSessionReady(sessionId)
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(isCreatingSession = false, errorMessage = e.message ?: "Error")
                }
            }
        }
    }
}
