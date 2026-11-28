package com.volumhealth.core.database.util

import com.volumhealth.core.database.entity.AthleteEntity
import com.volumhealth.core.model.Athlete
import com.volumhealth.core.model.BiologicalSex
import com.volumhealth.core.model.DominantLeg
import com.volumhealth.core.model.SyncStatus
import kotlinx.datetime.Clock
import org.json.JSONArray

fun AthleteEntity.toDomainModel(): Athlete {
    return Athlete(
        id = id,
        userId = userId,
        fullName = fullName,
        dateOfBirth = dateOfBirth,
        dominantLeg = DominantLeg.fromString(dominantLeg),
        biologicalSex = biologicalSex?.let { BiologicalSex.fromString(it) },
        medicalHistory = medicalHistory,
        medications = medications,
        dietType = dietType,
        dailyCalories = dailyCalories,
        allergies = allergiesJson?.let { parseJsonStringList(it) },
        usualActivities = usualActivitiesJson?.let { parseJsonStringList(it) },
        heightCm = heightCm,
        weightKg = weightKg,
        isAthlete = isAthlete,
        rightThighLength = rightThighLength,
        rightThighCircumference = rightThighCircumference,
        leftThighLength = leftThighLength,
        leftThighCircumference = leftThighCircumference,
        hasCurrentInjury = hasCurrentInjury,
        currentInjuryDetails = currentInjuryDetails,
        createdAt = createdAt,
        syncStatus = try { SyncStatus.valueOf(syncStatus) } catch (e: Exception) { SyncStatus.PENDING }
    )
}

fun Athlete.toEntity(): AthleteEntity {
    val now = Clock.System.now()
    return AthleteEntity(
        id = id,
        userId = userId,
        fullName = fullName,
        dateOfBirth = dateOfBirth,
        dominantLeg = dominantLeg.name.lowercase(),
        biologicalSex = biologicalSex?.name?.lowercase(),
        medicalHistory = medicalHistory,
        medications = medications,
        dietType = dietType,
        dailyCalories = dailyCalories,
        allergiesJson = allergies?.let { toJsonStringList(it) },
        usualActivitiesJson = usualActivities?.let { toJsonStringList(it) },
        heightCm = heightCm,
        weightKg = weightKg,
        isAthlete = isAthlete,
        rightThighLength = rightThighLength,
        rightThighCircumference = rightThighCircumference,
        leftThighLength = leftThighLength,
        leftThighCircumference = leftThighCircumference,
        hasCurrentInjury = hasCurrentInjury,
        currentInjuryDetails = currentInjuryDetails,
        createdAt = now,
        updatedAt = now,
        syncStatus = syncStatus.name,
        lastSyncAttempt = null,
        syncError = null
    )
}

private fun parseJsonStringList(json: String): List<String>? {
    return try {
        val array = JSONArray(json)
        (0 until array.length()).map { array.getString(it) }
    } catch (e: Exception) {
        null
    }
}

private fun toJsonStringList(list: List<String>): String {
    val array = JSONArray()
    list.forEach { array.put(it) }
    return array.toString()
}
