package com.volumhealth.core.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.volumhealth.core.database.entity.PatientInfoEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface PatientDao {
    @Query("SELECT * FROM patient_info ORDER BY updatedAt DESC")
    fun observePatients(): Flow<List<PatientInfoEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(patient: PatientInfoEntity)

    @Delete
    suspend fun delete(patient: PatientInfoEntity)
}
