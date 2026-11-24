package com.volumhealth.core.database

import androidx.room.TypeConverter
import com.volumhealth.core.model.Gender
import com.volumhealth.core.model.ProcessingState
import com.volumhealth.core.model.SessionStatus
import com.volumhealth.core.model.SessionType
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate

class Converters {
    @TypeConverter
    fun instantToEpoch(value: Instant?): Long? = value?.toEpochMilliseconds()

    @TypeConverter
    fun epochToInstant(value: Long?): Instant? = value?.let { Instant.fromEpochMilliseconds(it) }

    @TypeConverter
    fun processingStateToString(state: ProcessingState?): String? = state?.name

    @TypeConverter
    fun stringToProcessingState(name: String?): ProcessingState? = name?.let { ProcessingState.valueOf(it) }

    @TypeConverter
    fun sessionStatusToString(status: SessionStatus?): String? = status?.name

    @TypeConverter
    fun stringToSessionStatus(name: String?): SessionStatus? = name?.let { SessionStatus.valueOf(it) }

    @TypeConverter
    fun sessionTypeToString(type: SessionType?): String? = type?.name

    @TypeConverter
    fun stringToSessionType(name: String?): SessionType? = name?.let { SessionType.valueOf(it) }

    @TypeConverter
    fun genderToString(gender: Gender?): String? = gender?.name

    @TypeConverter
    fun stringToGender(name: String?): Gender? = name?.let { Gender.valueOf(it) }

    @TypeConverter
    fun fromLocalDate(date: LocalDate?): String? {
        return date?.toString()
    }

    @TypeConverter
    fun toLocalDate(dateString: String?): LocalDate? {
        return dateString?.let { LocalDate.parse(it) }
    }
}
