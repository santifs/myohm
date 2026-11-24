package com.volumhealth.core.database.entity

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.volumhealth.core.model.Gender
import kotlinx.datetime.Instant

@Entity(tableName = "patient_info")
data class PatientInfoEntity(
    @PrimaryKey val id: String,
    val name: String,
    val exerciseName: String,
    val age: Int,
    val gender: Gender,
    val height: Float,
    val weight: Float,
    val bmi: Float,
    val updatedAt: Instant
)
