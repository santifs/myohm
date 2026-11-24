package com.volumhealth.core.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.volumhealth.core.database.entity.MeasurementSessionEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.datetime.Instant

@Dao
interface MeasurementSessionDao {

    @Query("SELECT * FROM measurement_sessions WHERE athlete_id = :athleteId ORDER BY started_at DESC")
    fun getSessionsByAthlete(athleteId: String): Flow<List<MeasurementSessionEntity>>

    @Query("SELECT * FROM measurement_sessions ORDER BY started_at DESC")
    fun getAllSessions(): Flow<List<MeasurementSessionEntity>>

    @Query("SELECT * FROM measurement_sessions WHERE id = :id")
    suspend fun getSessionById(id: String): MeasurementSessionEntity?

    @Query("SELECT * FROM measurement_sessions WHERE id = :id")
    fun getSessionByIdFlow(id: String): Flow<MeasurementSessionEntity?>

    @Query("SELECT * FROM measurement_sessions WHERE athlete_id = :athleteId ORDER BY started_at DESC LIMIT 1")
    suspend fun getLastSessionForAthlete(athleteId: String): MeasurementSessionEntity?

    @Query("""
        SELECT * FROM measurement_sessions
        WHERE athlete_id = :athleteId
        AND study_id = :studyId
        AND session_type = :sessionType
        AND started_at >= :since
        ORDER BY started_at DESC
        LIMIT 1
    """)
    suspend fun findRecentSession(
        athleteId: String,
        studyId: String,
        sessionType: String,
        since: Instant
    ): MeasurementSessionEntity?

    @Query("SELECT * FROM measurement_sessions WHERE sync_status IN ('PENDING', 'MODIFIED', 'FAILED')")
    suspend fun getSessionsNeedingSync(): List<MeasurementSessionEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(session: MeasurementSessionEntity)

    @Update
    suspend fun update(session: MeasurementSessionEntity)

    @Delete
    suspend fun delete(session: MeasurementSessionEntity)

    @Query("DELETE FROM measurement_sessions WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("UPDATE measurement_sessions SET sync_status = :status WHERE id = :id")
    suspend fun updateSyncStatus(id: String, status: String)

    @Query("UPDATE measurement_sessions SET sync_status = :status, last_sync_attempt = :timestamp, sync_error = :error WHERE id = :id")
    suspend fun updateSyncResult(id: String, status: String, timestamp: Instant, error: String?)
}
