package com.volumhealth.app.ui.screens.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.volumhealth.app.data.AthleteRepository
import com.volumhealth.app.history.HistoryExporter
import com.volumhealth.core.database.MeasurementHistoryManager
import com.volumhealth.core.database.dao.MeasurementSessionDao
import com.volumhealth.core.database.dao.NewMeasurementDao
import com.volumhealth.core.database.entity.MeasurementSessionEntity
import com.volumhealth.core.model.ProcessingState
import com.volumhealth.core.model.RawMeasurement
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlin.math.abs
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

@HiltViewModel
@OptIn(ExperimentalCoroutinesApi::class)
class HistoryViewModel @Inject constructor(
    historyManager: MeasurementHistoryManager,
    sessionDao: MeasurementSessionDao,
    newMeasurementDao: NewMeasurementDao,
    athleteRepository: AthleteRepository,
    private val exporter: HistoryExporter
) : ViewModel() {
    private val filter = MutableStateFlow(HistoryFilter.ALL)

    val uiState: StateFlow<HistoryUiState> = combine(
        historyManager.rawMeasurements,
        sessionDao.getAllSessions(),
        newMeasurementDao.getAllMeasurements(),
        athleteRepository.getAllAthletes(),
        filter
    ) { measurements, sessions, newMeasurements, athletes, filter ->
        val annotations = buildAnnotationsMap(measurements, sessions, newMeasurements, athletes)
        val filtered = applyFilter(measurements, filter)
        HistoryUiState(filter, measurements, filtered, annotations)
    }
    .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HistoryUiState())

    fun onFilterSelected(newFilter: HistoryFilter) {
        filter.value = newFilter
    }

    suspend fun exportMeasurements(measurements: List<RawMeasurement>): HistoryExporter.ExportResult {
        return exporter.exportMeasurements(measurements)
    }

    private fun applyFilter(source: List<RawMeasurement>, filter: HistoryFilter): List<RawMeasurement> =
        when (filter) {
            HistoryFilter.ALL -> source
            HistoryFilter.COMPLETED -> source.filter { it.processingState == ProcessingState.COMPLETED }
            HistoryFilter.PENDING -> source.filter { it.processingState == ProcessingState.PENDING || it.processingState == ProcessingState.PROCESSING }
            HistoryFilter.FAILED -> source.filter { it.processingState == ProcessingState.FAILED }
        }

    /**
     * Maps each [RawMeasurement] id to its session label (free-form text in
     * `session_type`) and subject name. Joins legacy raw measurements with the
     * new measurement+session+athlete tables by capture-time proximity.
     */
    private fun buildAnnotationsMap(
        rawMeasurements: List<RawMeasurement>,
        sessions: List<MeasurementSessionEntity>,
        newMeasurements: List<com.volumhealth.core.database.entity.MeasurementEntity>,
        athletes: List<com.volumhealth.core.model.Athlete>
    ): Map<String, MeasurementAnnotation> {
        if (newMeasurements.isEmpty() || sessions.isEmpty()) return emptyMap()
        val sessionsById = sessions.associateBy { it.id }
        val athletesById = athletes.associateBy { it.id }
        val result = mutableMapOf<String, MeasurementAnnotation>()
        for (raw in rawMeasurements) {
            // Only explicit IDs establish ownership; nearby laboratory captures are unrelated.
            val nearest = newMeasurements.firstOrNull { it.id == raw.id && it.sessionId != null }
                ?: continue
            val session = sessionsById[nearest.sessionId] ?: continue
            val label = session.sessionType?.takeIf { it.isNotBlank() }
            val subject = athletesById[session.athleteId]?.displayName
            if (label == null && subject == null && nearest.muscleGroup.isBlank() && nearest.side.isBlank()) continue
            result[raw.id] = MeasurementAnnotation(
                label = label,
                subjectName = subject,
                muscleGroup = nearest.muscleGroup.takeIf { it.isNotBlank() },
                side = nearest.side.takeIf { it.isNotBlank() }
            )
        }
        return result
    }
}

enum class HistoryFilter { ALL, COMPLETED, PENDING, FAILED }

data class MeasurementAnnotation(
    val label: String?,
    val subjectName: String?,
    val muscleGroup: String? = null,
    val side: String? = null
)

data class HistoryUiState(
    val filter: HistoryFilter = HistoryFilter.ALL,
    val measurements: List<RawMeasurement> = emptyList(),
    val filteredMeasurements: List<RawMeasurement> = emptyList(),
    val annotationsByMeasurementId: Map<String, MeasurementAnnotation> = emptyMap()
)
