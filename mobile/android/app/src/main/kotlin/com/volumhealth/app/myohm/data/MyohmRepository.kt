package com.volumhealth.app.myohm.data

import com.volumhealth.app.myohm.domain.LimbSide
import com.volumhealth.app.myohm.domain.MeasurementKind
import com.volumhealth.app.myohm.domain.MyohmMuscle
import com.volumhealth.app.myohm.domain.SweepAnalysis
import com.volumhealth.core.database.dao.AthleteDao
import com.volumhealth.core.database.dao.NewMeasurementDao
import com.volumhealth.core.database.entity.MeasurementEntity
import com.volumhealth.core.database.util.ImpedanceJson
import com.volumhealth.core.database.util.toDomainModel
import com.volumhealth.core.database.util.toEntity
import com.volumhealth.core.model.Athlete
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.SyncStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** A saved measurement with its sweep already combined. */
data class MyohmRecord(
    val id: String,
    val muscleGroup: String,
    val side: String,
    val measuredAt: Instant,
    val personId: String?,
    val bandMillimeters: Int?,
    val bodyWeightKg: Double?,
    val restCompleted: Boolean?,
    val sweep: SweepAnalysis?
) {
    val isWholeBody: Boolean get() = muscleGroup == MyohmMuscle.WHOLE_BODY_KEY
    val muscle: MyohmMuscle? get() = MyohmMuscle.fromKey(muscleGroup)
    val bodySide: LimbSide? get() = LimbSide.fromKey(side)
}

@Singleton
class MyohmRepository @Inject constructor(
    private val athleteDao: AthleteDao,
    private val measurementDao: NewMeasurementDao
) {
    val people: Flow<List<Athlete>> = athleteDao.getAllAthletes()
        .map { list -> list.sortedBy { it.createdAt }.map { it.toDomainModel() } }

    /** Newest first. */
    val records: Flow<List<MyohmRecord>> = measurementDao.getAllMeasurements()
        .map { list -> list.map { it.toRecord() } }
        .flowOn(Dispatchers.Default)

    suspend fun savePerson(person: Athlete, isNew: Boolean) {
        if (isNew) {
            athleteDao.insert(person.toEntity())
        } else {
            val existing = athleteDao.getAthleteById(person.id)
            val entity = person.toEntity()
            athleteDao.insert(
                if (existing != null) entity.copy(createdAt = existing.createdAt, updatedAt = Clock.System.now()) else entity
            )
        }
    }

    suspend fun updateWeight(personId: String, weightKg: Double) {
        val existing = athleteDao.getAthleteById(personId) ?: return
        athleteDao.update(existing.copy(weightKg = weightKg, updatedAt = Clock.System.now()))
    }

    suspend fun deletePerson(personId: String, recordIds: List<String>) {
        recordIds.forEach { measurementDao.deleteById(it) }
        athleteDao.deleteById(personId)
    }

    suspend fun saveMeasurement(
        kind: MeasurementKind,
        personId: String?,
        data: ImpedanceData,
        measuredAt: Instant = Clock.System.now()
    ): String {
        val id = UUID.randomUUID().toString()
        val base = MeasurementEntity(
            id = id,
            sessionId = null,
            muscleGroup = MyohmMuscle.WHOLE_BODY_KEY,
            side = LimbSide.RIGHT.key,
            perceivedFatigue = 0,
            rawDataJson = ImpedanceJson.encode(data),
            measuredAt = measuredAt,
            syncStatus = SyncStatus.PENDING.name,
            lastSyncAttempt = null,
            syncError = null,
            personId = personId
        )
        val entity = when (kind) {
            is MeasurementKind.Muscle -> base.copy(
                muscleGroup = kind.muscle.key, side = kind.side.key, bandMillimeters = kind.band
            )
            is MeasurementKind.WholeBody -> base.copy(
                bodyWeightKg = kind.weightKg, restCompleted = kind.restCompleted
            )
        }
        measurementDao.insert(entity)
        if (kind is MeasurementKind.WholeBody && personId != null) updateWeight(personId, kind.weightKg)
        return id
    }

    private fun MeasurementEntity.toRecord() = MyohmRecord(
        id = id,
        muscleGroup = muscleGroup,
        side = side,
        measuredAt = measuredAt,
        personId = personId,
        bandMillimeters = bandMillimeters,
        bodyWeightKg = bodyWeightKg,
        restCompleted = restCompleted,
        sweep = ImpedanceJson.decode(rawDataJson)?.let { SweepAnalysis.from(it) }
    )
}
