package com.volumhealth.core.database.util

import com.volumhealth.core.database.entity.AutoMeasurementSessionEntity
import com.volumhealth.core.database.entity.PatientInfoEntity
import com.volumhealth.core.database.entity.RawMeasurementEntity
import com.volumhealth.core.database.util.Serialization
import com.volumhealth.core.model.AutoMeasurementSession
import com.volumhealth.core.model.PatientInfo
import com.volumhealth.core.model.RawMeasurement
import kotlinx.datetime.Clock

internal fun RawMeasurementEntity.toDomain(): RawMeasurement = RawMeasurement(
    id = id,
    rawData = Serialization.decodeImpedance(rawDataJson),
    patientSnapshot = Serialization.decodePatientSnapshot(patientSnapshotJson),
    captureTimestamp = captureTimestamp,
    processingState = processingState,
    results = Serialization.decodeColeParameters(resultsJson),
    processingAttempts = processingAttempts,
    lastProcessingAttempt = lastProcessingAttempt,
    processingError = processingError,
    repetitions = null,
    signalQuality = signalQuality
)

internal fun RawMeasurement.toEntity(): RawMeasurementEntity = RawMeasurementEntity(
    id = id,
    rawDataJson = Serialization.encodeImpedance(rawData),
    patientSnapshotJson = Serialization.encodePatientSnapshot(patientSnapshot),
    captureTimestamp = captureTimestamp,
    processingState = processingState,
    resultsJson = Serialization.encodeColeParameters(results),
    processingAttempts = processingAttempts,
    lastProcessingAttempt = lastProcessingAttempt,
    processingError = processingError,
    signalQuality = signalQuality
)

internal fun AutoMeasurementSessionEntity.toDomain(): AutoMeasurementSession = AutoMeasurementSession(
    id = id,
    name = name,
    intervalMinutes = intervalMinutes,
    sessionType = sessionType,
    startTime = startTime,
    endTime = endTime,
    status = status,
    totalMeasurements = totalMeasurements,
    successfulMeasurements = successfulMeasurements,
    failedMeasurements = failedMeasurements,
    lastMeasurementTime = lastMeasurementTime,
    nextMeasurementTime = nextMeasurementTime,
    patientName = patientName,
    notes = notes
)

internal fun AutoMeasurementSession.toEntity(): AutoMeasurementSessionEntity = AutoMeasurementSessionEntity(
    id = id,
    name = name,
    intervalMinutes = intervalMinutes,
    sessionType = sessionType,
    startTime = startTime,
    endTime = endTime,
    status = status,
    totalMeasurements = totalMeasurements,
    successfulMeasurements = successfulMeasurements,
    failedMeasurements = failedMeasurements,
    lastMeasurementTime = lastMeasurementTime,
    nextMeasurementTime = nextMeasurementTime,
    patientName = patientName,
    notes = notes
)

internal fun PatientInfoEntity.toDomain(): PatientInfo = PatientInfo(
    name = name,
    exerciseName = exerciseName,
    age = age.toString(),
    gender = gender,
    height = height.toString(),
    weight = weight.toString()
)

internal fun PatientInfo.toEntity(id: String, bmiValue: Float): PatientInfoEntity =
    PatientInfoEntity(
        id = id,
        name = name,
        exerciseName = exerciseName,
        age = age.toIntOrNull() ?: 0,
        gender = gender,
        height = height.toFloatOrNull() ?: 0f,
        weight = weight.toFloatOrNull() ?: 0f,
        bmi = bmiValue,
        updatedAt = Clock.System.now()
    )
