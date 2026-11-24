package com.volumhealth.core.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.volumhealth.core.database.entity.AutoMeasurementSessionEntity
import com.volumhealth.core.model.SessionStatus
import kotlinx.coroutines.flow.Flow

@Dao
interface SessionDao {
    @Query("SELECT * FROM auto_measurement_sessions ORDER BY startTime DESC")
    fun getAllSessions(): Flow<List<AutoMeasurementSessionEntity>>

    @Query("SELECT * FROM auto_measurement_sessions WHERE status IN (:statuses)")
    suspend fun getSessionsByStatus(vararg statuses: SessionStatus): List<AutoMeasurementSessionEntity>

    @Query("SELECT * FROM auto_measurement_sessions WHERE id = :id LIMIT 1")
    suspend fun getSessionById(id: String): AutoMeasurementSessionEntity?

    @Query("SELECT * FROM auto_measurement_sessions WHERE id = :id LIMIT 1")
    fun observeSession(id: String): Flow<AutoMeasurementSessionEntity?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(session: AutoMeasurementSessionEntity)

    @Update
    suspend fun update(session: AutoMeasurementSessionEntity)

    @Delete
    suspend fun delete(session: AutoMeasurementSessionEntity)
}
