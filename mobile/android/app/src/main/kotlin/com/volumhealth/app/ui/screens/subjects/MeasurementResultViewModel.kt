package com.volumhealth.app.ui.screens.subjects

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.volumhealth.core.database.MeasurementHistoryManager
import com.volumhealth.core.model.ImpedanceData
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class MeasurementResultViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    historyManager: MeasurementHistoryManager
) : ViewModel() {

    private val sessionId: String = checkNotNull(savedStateHandle["sessionId"]) {
        "sessionId is required"
    }

    data class UiState(
        val impedance: ImpedanceData? = null,
        val isLoading: Boolean = true
    )

    val uiState: StateFlow<UiState> = historyManager.observeLatestMeasurementForSession(sessionId)
        .map { impedance ->
            UiState(impedance = impedance, isLoading = false)
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = UiState()
        )
}
