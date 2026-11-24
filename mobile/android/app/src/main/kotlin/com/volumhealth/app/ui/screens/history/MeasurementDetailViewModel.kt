package com.volumhealth.app.ui.screens.history

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.volumhealth.app.history.HistoryExporter
import com.volumhealth.core.database.MeasurementHistoryManager
import com.volumhealth.core.model.RawMeasurement
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

@HiltViewModel
class MeasurementDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    historyManager: MeasurementHistoryManager,
    private val exporter: HistoryExporter
) : ViewModel() {
    private val measurementId: String = savedStateHandle.get<String>("measurementId") ?: ""

    val measurement: StateFlow<RawMeasurement?> = historyManager.rawMeasurements
        .map { measurements -> measurements.find { it.id == measurementId } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    suspend fun exportMeasurement(measurement: RawMeasurement): HistoryExporter.ExportResult {
        return exporter.exportMeasurements(listOf(measurement), suffix = measurement.id.take(6))
    }
}
