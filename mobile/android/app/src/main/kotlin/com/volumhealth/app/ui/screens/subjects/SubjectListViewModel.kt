package com.volumhealth.app.ui.screens.subjects

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.volumhealth.app.auth.LocalProfileService
import com.volumhealth.app.auth.AuthState
import com.volumhealth.app.data.AthleteRepository
import com.volumhealth.core.database.dao.MeasurementSessionDao
import com.volumhealth.core.model.Athlete
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.datetime.Instant
import javax.inject.Inject

/**
 * Landing screen view model for the simplified experiment flow.
 *
 * Scoped to the authenticated user: reads and writes athletes tied to the current
 * userId so Supabase RLS policies (auth.uid() = user_id) return rows correctly.
 */
@HiltViewModel
@OptIn(ExperimentalCoroutinesApi::class)
class SubjectListViewModel @Inject constructor(
    private val athleteRepository: AthleteRepository,
    private val sessionDao: MeasurementSessionDao,
    private val authService: LocalProfileService
) : ViewModel() {

    data class SubjectRow(
        val id: String,
        val name: String,
        val lastMeasurementAt: Instant?,
        val createdAt: Instant?
    )

    data class UiState(
        val subjects: List<SubjectRow> = emptyList(),
        val isLoading: Boolean = true
    )

    private val refreshTrigger = MutableStateFlow(0)

    val uiState: StateFlow<UiState> = combine(
        authService.authState,
        refreshTrigger
    ) { authState, _ -> authState }
        .flatMapLatest { authState ->
            val userId = (authState as? AuthState.Authenticated)?.userId?.toString()
            if (userId == null) {
                flowOf(UiState(isLoading = false))
            } else {
                athleteRepository.getAthletesByUser(userId).map { athletes ->
                    val rows = athletes.map { a ->
                        SubjectRow(
                            id = a.id,
                            name = a.displayName,
                            lastMeasurementAt = sessionDao.getLastSessionForAthlete(a.id)?.startedAt,
                            createdAt = a.createdAt
                        )
                    }.sortedByDescending { it.lastMeasurementAt ?: it.createdAt ?: Instant.DISTANT_PAST }
                    UiState(subjects = rows, isLoading = false)
                }
            }
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = UiState()
        )

    fun createSubject(name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        val userId = (authService.authState.value as? AuthState.Authenticated)?.userId?.toString()
            ?: return
        viewModelScope.launch {
            athleteRepository.saveAthlete(Athlete.minimal(trimmed, userId))
            refreshTrigger.value += 1
        }
    }

    fun renameSubject(athleteId: String, newName: String) {
        val trimmed = newName.trim()
        if (trimmed.isEmpty()) return
        viewModelScope.launch {
            val current = athleteRepository.getAthleteById(athleteId) ?: return@launch
            athleteRepository.updateAthlete(current.copy(fullName = trimmed))
            refreshTrigger.value += 1
        }
    }

    fun deleteSubject(athleteId: String) {
        viewModelScope.launch {
            athleteRepository.deleteAthlete(athleteId)
            refreshTrigger.value += 1
        }
    }
}
