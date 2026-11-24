package com.volumhealth.app.background

import android.util.Log
import com.volumhealth.core.ble.BioMessBleManager
import com.volumhealth.core.database.MeasurementHistoryManager
import com.volumhealth.core.processing.BioimpedanceProcessor
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class StoredMeasurementSyncManager @Inject constructor(
    private val bleManager: BioMessBleManager,
    private val historyManager: MeasurementHistoryManager,
    private val processor: BioimpedanceProcessor
) {
    suspend fun syncAllMeasurements(): Int {
        val count = bleManager.getStoredMeasurementCount()
        if (count <= 0) return 0

        var imported = 0
        var offset = 0

        while (offset < count) {
            val batchSize = minOf(10, count - offset)
            val batch = bleManager.getStoredMeasurementBatch(offset, batchSize)

            batch.forEach { storedMeasurement ->
                val rawData = storedMeasurement.toImpedanceData()
                val results = runCatching { processor.processImmediate(rawData) }
                    .onFailure { error ->
                        Log.w("StoredSync", "Processing stored measurement failed: ${error.message}")
                    }
                    .getOrNull()

                historyManager.addRawMeasurement(
                    rawData = rawData,
                    patientSnapshot = null,
                    results = results,
                    signalQuality = storedMeasurement.signalQuality
                )
                imported++
            }

            offset += batchSize
        }

        if (imported == count) {
            bleManager.clearStoredMeasurements()
        }

        return imported
    }
}
