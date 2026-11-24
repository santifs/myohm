package com.volumhealth.app.data

import com.volumhealth.core.database.dao.AthleteDao
import com.volumhealth.core.database.util.toDomainModel
import com.volumhealth.core.database.util.toEntity
import com.volumhealth.core.model.Athlete
import com.volumhealth.core.model.SyncStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.datetime.Clock
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AthleteRepository @Inject constructor(
    private val athleteDao: AthleteDao
) {
    fun getAthletesByUser(userId: String): Flow<List<Athlete>> {
        return athleteDao.getAthletesByUser(userId).map { entities ->
            entities.map { it.toDomainModel() }
        }
    }

    fun getAllAthletes(): Flow<List<Athlete>> {
        return athleteDao.getAllAthletes().map { entities ->
            entities.map { it.toDomainModel() }
        }
    }

    fun getAthleteByIdFlow(id: String): Flow<Athlete?> {
        return athleteDao.getAthleteByIdFlow(id).map { it?.toDomainModel() }
    }

    suspend fun getAthleteById(id: String): Athlete? {
        return athleteDao.getAthleteById(id)?.toDomainModel()
    }

    suspend fun saveAthlete(athlete: Athlete) {
        athleteDao.insert(athlete.toEntity())
    }

    suspend fun updateAthlete(athlete: Athlete) {
        val existing = athleteDao.getAthleteById(athlete.id)
        if (existing != null) {
            val updated = athlete.toEntity().copy(
                createdAt = existing.createdAt,
                updatedAt = Clock.System.now(),
                syncStatus = if (existing.syncStatus == SyncStatus.SYNCED.name) {
                    SyncStatus.MODIFIED.name
                } else {
                    existing.syncStatus
                }
            )
            athleteDao.update(updated)
        }
    }

    suspend fun deleteAthlete(id: String) {
        athleteDao.deleteById(id)
    }

    suspend fun getAthletesNeedingSync(): List<Athlete> {
        return athleteDao.getAthletesNeedingSync().map { it.toDomainModel() }
    }
}
