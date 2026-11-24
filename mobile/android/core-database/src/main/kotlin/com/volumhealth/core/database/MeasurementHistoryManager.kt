package com.volumhealth.core.database

import com.volumhealth.core.database.dao.MeasurementDao
import com.volumhealth.core.database.dao.NewMeasurementDao
import com.volumhealth.core.database.entity.MeasurementEntity
import com.volumhealth.core.database.entity.RawMeasurementEntity
import com.volumhealth.core.database.util.Serialization
import com.volumhealth.core.database.util.toDomain
import com.volumhealth.core.database.util.toEntity
import com.volumhealth.core.model.ColeParameters
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.PatientSnapshot
import com.volumhealth.core.model.ProcessingState
import com.volumhealth.core.model.RawMeasurement
import com.volumhealth.core.model.SyncStatus
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.datetime.Clock
import java.util.UUID

@Singleton
class MeasurementHistoryManager @Inject constructor(
    private val measurementDao: MeasurementDao,
    private val newMeasurementDao: NewMeasurementDao,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    private val scope = CoroutineScope(SupervisorJob() + ioDispatcher)

    private val _rawMeasurements = MutableStateFlow<List<RawMeasurement>>(emptyList())
    val rawMeasurements: StateFlow<List<RawMeasurement>> = _rawMeasurements.asStateFlow()

    init {
        scope.launch {
            measurementDao.getAllMeasurements().collectLatest { entities ->
                _rawMeasurements.value = entities.map(RawMeasurementEntity::toDomain)
            }
        }
    }

    val pendingMeasurements: List<RawMeasurement>
        get() = _rawMeasurements.value.filter { it.processingState == ProcessingState.PENDING }

    val completedMeasurements: List<RawMeasurement>
        get() = _rawMeasurements.value.filter { it.processingState == ProcessingState.COMPLETED }

    suspend fun addRawMeasurement(
        rawData: ImpedanceData,
        patientSnapshot: PatientSnapshot?,
        results: ColeParameters? = null,
        signalQuality: Float? = null
    ): RawMeasurement = withContext(ioDispatcher) {
        val measurement = RawMeasurement(
            rawData = rawData,
            patientSnapshot = patientSnapshot,
            captureTimestamp = Clock.System.now(),
            processingState = if (results != null) ProcessingState.COMPLETED else ProcessingState.PENDING,
            results = results,
            signalQuality = signalQuality
        )
        measurementDao.insert(measurement.toEntity())
        measurement
    }

    suspend fun insertRawMeasurement(measurement: RawMeasurement) = withContext(ioDispatcher) {
        measurementDao.insert(measurement.toEntity())
    }

    suspend fun markMeasurementProcessing(id: String) = updateMeasurementState(
        id = id,
        newState = ProcessingState.PROCESSING,
        error = null,
        results = null,
        increaseAttempts = false
    )

    suspend fun markMeasurementFailed(id: String, reason: String) = updateMeasurementState(
        id = id,
        newState = ProcessingState.FAILED,
        error = reason,
        results = null,
        increaseAttempts = true
    )

    suspend fun updateMeasurementResults(id: String, results: ColeParameters) = updateMeasurementState(
        id = id,
        newState = ProcessingState.COMPLETED,
        error = null,
        results = results,
        increaseAttempts = false
    )

    suspend fun deleteMeasurement(id: String) = withContext(ioDispatcher) {
        measurementDao.getMeasurementById(id)?.let { measurementDao.delete(it) }
    }

    private suspend fun updateMeasurementState(
        id: String,
        newState: ProcessingState,
        error: String?,
        results: ColeParameters?,
        increaseAttempts: Boolean
    ) = withContext(ioDispatcher) {
        val entity = measurementDao.getMeasurementById(id) ?: return@withContext
        val attempts = if (increaseAttempts) entity.processingAttempts + 1 else entity.processingAttempts
        val updated = entity.copy(
            processingState = newState,
            processingAttempts = attempts,
            lastProcessingAttempt = Clock.System.now(),
            processingError = error,
            resultsJson = results?.let { Serialization.encodeColeParameters(it) } ?: entity.resultsJson
        )
        measurementDao.update(updated)
    }

    /**
     * Save a measurement to the new MeasurementEntity table (for Supabase sync).
     * Returns the generated measurement ID.
     */
    suspend fun saveNewMeasurement(
        sessionId: String,
        muscleGroup: String,
        side: String,
        perceivedFatigue: Int,
        rawData: ImpedanceData,
        id: String = UUID.randomUUID().toString(),
        measuredAt: kotlinx.datetime.Instant = Clock.System.now()
    ): String = withContext(ioDispatcher) {
        val entity = MeasurementEntity(
            id = id,
            sessionId = sessionId,
            muscleGroup = muscleGroup,
            side = side,
            perceivedFatigue = perceivedFatigue,
            rawDataJson = Serialization.encodeImpedance(rawData),
            measuredAt = measuredAt,
            syncStatus = SyncStatus.PENDING.name,
            lastSyncAttempt = null,
            syncError = null
        )
        newMeasurementDao.insert(entity)
        id
    }

    /**
     * Reactive view of the most recent measurement for a session, with the raw impedance
     * payload already decoded. Emits null if no measurement exists yet or if decoding fails.
     */
    fun observeLatestMeasurementForSession(sessionId: String): Flow<ImpedanceData?> =
        newMeasurementDao.getMeasurementsBySession(sessionId).map { entities ->
            val entity = entities.firstOrNull() ?: return@map null
            runCatching { Serialization.decodeImpedance(entity.rawDataJson) }.getOrNull()
        }
}
