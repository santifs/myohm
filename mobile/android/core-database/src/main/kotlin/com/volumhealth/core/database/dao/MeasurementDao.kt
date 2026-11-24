package com.volumhealth.core.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.volumhealth.core.database.entity.RawMeasurementEntity
import com.volumhealth.core.model.ProcessingState
import kotlinx.coroutines.flow.Flow

@Dao
interface MeasurementDao {
    @Query("SELECT * FROM raw_measurements ORDER BY captureTimestamp DESC")
    fun getAllMeasurements(): Flow<List<RawMeasurementEntity>>

    @Query("SELECT * FROM raw_measurements WHERE processingState = :state")
    suspend fun getMeasurementsByState(state: ProcessingState): List<RawMeasurementEntity>

    @Query("SELECT * FROM raw_measurements WHERE id = :id LIMIT 1")
    suspend fun getMeasurementById(id: String): RawMeasurementEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(measurement: RawMeasurementEntity)

    @Update
    suspend fun update(measurement: RawMeasurementEntity)

    @Delete
    suspend fun delete(measurement: RawMeasurementEntity)
}
