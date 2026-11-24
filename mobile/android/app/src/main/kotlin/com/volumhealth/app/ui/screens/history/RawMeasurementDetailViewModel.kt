package com.volumhealth.app.ui.screens.history

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.volumhealth.core.database.MeasurementHistoryManager
import com.volumhealth.core.model.RawMeasurement
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

@HiltViewModel
class RawMeasurementDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    historyManager: MeasurementHistoryManager
) : ViewModel() {
    private val measurementId: String = savedStateHandle.get<String>("measurementId") ?: ""

    val measurement: StateFlow<RawMeasurement?> = historyManager.rawMeasurements
        .map { measurements -> measurements.find { it.id == measurementId } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val selectedRepetition = MutableStateFlow(0)
}
