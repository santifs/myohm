package com.volumhealth.app.history

import android.content.Context
import android.net.Uri
import androidx.core.content.FileProvider
import com.volumhealth.core.database.dao.MeasurementSessionDao
import com.volumhealth.core.database.dao.NewMeasurementDao
import com.volumhealth.app.data.AthleteRepository
import com.volumhealth.core.model.RawMeasurement
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.util.Locale
import javax.inject.Inject
import kotlin.math.abs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.datetime.Clock

class HistoryExporter @Inject constructor(
    @ApplicationContext private val context: Context,
    private val sessionDao: MeasurementSessionDao,
    private val newMeasurementDao: NewMeasurementDao,
    private val athleteRepository: AthleteRepository
) {

    data class ExportResult(
        val uri: Uri,
        val mimeType: String = "text/csv",
        val fileName: String
    )

    suspend fun exportMeasurements(
        measurements: List<RawMeasurement>,
        suffix: String? = null
    ): ExportResult = withContext(Dispatchers.IO) {
        val annotations = buildAnnotationMap(measurements)
        val csv = buildCsv(measurements, annotations)
        val exportsDir = File(context.cacheDir, "exports").apply { mkdirs() }
        val timestamp = Clock.System.now().toString().replace(":", "-")
        val sanitizedSuffix = suffix?.takeIf { it.isNotBlank() }?.let { "_${sanitize(it)}" } ?: ""
        val fileName = "volum_measurements_${timestamp}$sanitizedSuffix.csv"
        val file = File(exportsDir, fileName)
        file.writeText(csv)

        val authority = "${context.packageName}.fileprovider"
        val uri = FileProvider.getUriForFile(context, authority, file)
        ExportResult(uri = uri, fileName = file.name)
    }

    data class Annotation(val subject: String?, val label: String?)

    /**
     * Joins legacy raw measurements with new measurement+session+athlete rows by
     * capture-time proximity (5 s) to recover subject name and free-form label.
     */
    private suspend fun buildAnnotationMap(
        raws: List<RawMeasurement>
    ): Map<String, Annotation> = withContext(Dispatchers.IO) {
        val sessions = runCatching { sessionDao.getAllSessions().first() }.getOrDefault(emptyList())
        val newMeasurements = runCatching { newMeasurementDao.getAllMeasurements().first() }.getOrDefault(emptyList())
        if (newMeasurements.isEmpty() || sessions.isEmpty()) return@withContext emptyMap()
        val sessionsById = sessions.associateBy { it.id }

        val athleteCache = mutableMapOf<String, String?>()
        suspend fun nameOf(athleteId: String): String? =
            athleteCache.getOrPut(athleteId) {
                athleteRepository.getAthleteById(athleteId)?.displayName
            }

        val result = mutableMapOf<String, Annotation>()
        for (raw in raws) {
            // Only explicit IDs establish ownership; nearby laboratory captures are unrelated.
            val nearest = newMeasurements.firstOrNull { it.id == raw.id && it.sessionId != null }
                ?: continue
            val session = sessionsById[nearest.sessionId] ?: continue
            val subject = nameOf(session.athleteId)
            val label = session.sessionType?.takeIf { it.isNotBlank() }
            if (subject == null && label == null) continue
            result[raw.id] = Annotation(subject = subject, label = label)
        }
        result
    }

    fun buildCsv(
        measurements: List<RawMeasurement>,
        annotations: Map<String, Annotation> = emptyMap()
    ): String {
        val header = listOf(
            "Timestamp",
            "MeasurementID",
            "Subject",
            "Label",
            "Repetition",
            "PatientName",
            "PatientAge",
            "PatientGender",
            "ProcessingState",
            "Frequency(Hz)",
            "Magnitude(Ω)",
            "Phase(°)",
            "Re(Ω)",
            "Ri(Ω)",
            "Cm(nF)",
            "fc(kHz)",
            "alpha",
            "FitError(%)",
            "Quality"
        ).joinToString(",")

        if (measurements.isEmpty()) {
            return header
        }

        val locale = Locale.US
        val builder = StringBuilder().appendLine(header)

        measurements.forEach { measurement ->
            val timestamp = measurement.captureTimestamp.toString()
            val patient = measurement.patientSnapshot
            val patientName = patient?.name ?: "N/A"
            val patientAge = patient?.age ?: 0
            val patientGender = patient?.gender?.name?.lowercase(locale)?.replaceFirstChar { it.titlecase(locale) } ?: "N/A"
            val processingState = measurement.processingState.name.lowercase(locale).replaceFirstChar { it.titlecase(locale) }
            val annotation = annotations[measurement.id]
            val subject = annotation?.subject ?: ""
            val label = annotation?.label ?: ""
            val results = measurement.results
            val reValue = results?.Re
            val riValue = results?.Ri
            val cmValue = results?.Cm
            val fcValue = results?.fc
            val alphaValue = results?.alpha
            val errorValue = results?.error
            val qualityValue = results?.quality?.score

            measurement.rawData.repetitions.forEachIndexed { repIndex, points ->
                points.forEach { point ->
                    val row = listOf(
                        timestamp,
                        measurement.id,
                        csvEscape(subject),
                        csvEscape(label),
                        (repIndex + 1).toString(),
                        patientName,
                        patientAge.toString(),
                        patientGender,
                        processingState,
                        formatFloat(point.frequency, 0, locale),
                        formatFloat(point.magnitude, 4, locale),
                        formatFloat(point.phase, 2, locale),
                        formatFloat(reValue, 2, locale, blankIfNull = true),
                        formatFloat(riValue, 2, locale, blankIfNull = true),
                        formatFloat(cmValue, 3, locale, blankIfNull = true),
                        formatFloat(fcValue, 3, locale, blankIfNull = true),
                        formatFloat(alphaValue, 3, locale, blankIfNull = true),
                        formatFloat(errorValue, 2, locale, blankIfNull = true),
                        formatFloat(qualityValue, 3, locale, blankIfNull = true)
                    )
                    builder.appendLine(row.joinToString(","))
                }
            }
        }

        return builder.toString()
    }

    private fun csvEscape(value: String): String {
        if (value.isEmpty()) return ""
        val needsQuote = value.contains(',') || value.contains('"') || value.contains('\n')
        val escaped = value.replace("\"", "\"\"")
        return if (needsQuote) "\"$escaped\"" else escaped
    }

    private fun formatFloat(
        value: Float?,
        decimals: Int,
        locale: Locale,
        blankIfNull: Boolean = false
    ): String {
        return when {
            value == null -> if (blankIfNull) "" else "0"
            decimals == 0 -> String.format(locale, "%.0f", value)
            else -> String.format(locale, "%.${decimals}f", value)
        }
    }

    private fun sanitize(input: String): String = input.replace("[^A-Za-z0-9_]".toRegex(), "_")
}
