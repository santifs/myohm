package com.volumhealth.core.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.volumhealth.core.database.entity.MeasurementEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.datetime.Instant

@Dao
interface NewMeasurementDao {

    @Query("SELECT * FROM measurements WHERE session_id = :sessionId ORDER BY measured_at DESC")
    fun getMeasurementsBySession(sessionId: String): Flow<List<MeasurementEntity>>

    @Query("SELECT * FROM measurements ORDER BY measured_at DESC")
    fun getAllMeasurements(): Flow<List<MeasurementEntity>>

    @Query("SELECT * FROM measurements WHERE id = :id")
    suspend fun getMeasurementById(id: String): MeasurementEntity?

    @Query("SELECT * FROM measurements WHERE id = :id")
    fun getMeasurementByIdFlow(id: String): Flow<MeasurementEntity?>

    @Query("SELECT * FROM measurements WHERE sync_status IN ('PENDING', 'MODIFIED', 'FAILED')")
    suspend fun getMeasurementsNeedingSync(): List<MeasurementEntity>

    @Query("""
        SELECT * FROM measurements
        WHERE session_id = :sessionId
        AND muscle_group = :muscleGroup
        AND side = :side
        LIMIT 1
    """)
    suspend fun getMeasurementByMuscle(sessionId: String, muscleGroup: String, side: String): MeasurementEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(measurement: MeasurementEntity)

    @Update
    suspend fun update(measurement: MeasurementEntity)

    @Delete
    suspend fun delete(measurement: MeasurementEntity)

    @Query("DELETE FROM measurements WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("UPDATE measurements SET sync_status = :status WHERE id = :id")
    suspend fun updateSyncStatus(id: String, status: String)

    @Query("UPDATE measurements SET sync_status = :status, last_sync_attempt = :timestamp, sync_error = :error WHERE id = :id")
    suspend fun updateSyncResult(id: String, status: String, timestamp: Instant, error: String?)

    @Query("SELECT COUNT(*) FROM measurements WHERE session_id = :sessionId")
    suspend fun getMeasurementCountForSession(sessionId: String): Int
}
