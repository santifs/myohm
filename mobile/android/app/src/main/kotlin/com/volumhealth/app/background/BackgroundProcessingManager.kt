package com.volumhealth.app.background

import com.volumhealth.core.database.MeasurementHistoryManager
import com.volumhealth.core.model.ProcessingState
import com.volumhealth.core.processing.BioimpedanceProcessor
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

@Singleton
class BackgroundProcessingManager @Inject constructor(
    private val processor: BioimpedanceProcessor,
    private val historyManager: MeasurementHistoryManager
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun processPendingMeasurements() {
        scope.launch {
            val pending = historyManager.pendingMeasurements
            pending.forEach { measurement ->
                try {
                    historyManager.markMeasurementProcessing(measurement.id)
                    val results = processor.processComplete(measurement.rawData)
                    historyManager.updateMeasurementResults(measurement.id, results)
                } catch (t: Throwable) {
                    historyManager.markMeasurementFailed(measurement.id, t.message ?: "Processing failed")
                }
            }
        }
    }

    fun retryFailedMeasurements() {
        scope.launch {
            val failed = historyManager.rawMeasurements.value
                .filter { it.processingState == ProcessingState.FAILED && it.shouldRetry }
            failed.forEach { measurement ->
                try {
                    historyManager.markMeasurementProcessing(measurement.id)
                    val results = processor.processComplete(measurement.rawData)
                    historyManager.updateMeasurementResults(measurement.id, results)
                } catch (t: Throwable) {
                    historyManager.markMeasurementFailed(measurement.id, t.message ?: "Processing failed")
                }
            }
        }
    }
}
