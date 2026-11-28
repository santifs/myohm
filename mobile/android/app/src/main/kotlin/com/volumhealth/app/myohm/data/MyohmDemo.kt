package com.volumhealth.app.myohm.data

import android.content.Context
import com.volumhealth.app.BuildConfig
import com.volumhealth.app.myohm.domain.LimbSide
import com.volumhealth.app.myohm.domain.MeasurementKind
import com.volumhealth.app.myohm.domain.MyohmMuscle
import com.volumhealth.core.model.Athlete
import com.volumhealth.core.model.BiologicalSex
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.MeasurementPoint
import kotlinx.datetime.Clock
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.TimeZone
import kotlinx.datetime.minus
import kotlinx.datetime.toLocalDateTime
import java.io.File
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.minutes

/**
 * Debug-only review data. Enabled by creating `files/myohm-demo` in the app sandbox
 * (`adb shell run-as com.myohm.app touch files/myohm-demo`); the app then uses an
 * in-memory database and separate preferences, so real data is never touched.
 */
object MyohmDemo {
    fun isEnabled(context: Context): Boolean =
        BuildConfig.DEBUG && File(context.filesDir, "myohm-demo").exists()

    /** Cole-model sweep with the device's sign convention (phase negative). */
    fun sweep(r0: Double, rInf: Double, fc: Double, alpha: Double, noise: Double = 0.0): ImpedanceData {
        val freqs = (0 until 48).map { 4_000 * (198_000.0 / 4_000).pow(it / 47.0) }
        fun rep(seed: Double) = freqs.mapIndexed { i, f ->
            val x = (f / fc).pow(alpha)
            val a = alpha * PI / 2
            val denRe = 1 + x * cos(a)
            val denIm = x * sin(a)
            val den = denRe * denRe + denIm * denIm
            val jitter = 1 + noise * sin(i * 1.7 + seed)
            val re = rInf + (r0 - rInf) * denRe / den * jitter
            val im = -(r0 - rInf) * denIm / den * jitter
            MeasurementPoint(frequency = f.toFloat(), magnitude = sqrt(re * re + im * im).toFloat(), phase = (atan2(im, re) * 180 / PI).toFloat())
        }
        return ImpedanceData(listOf(rep(0.0), rep(1.0), rep(2.0)), Clock.System.now(), null)
    }

    suspend fun seed(repository: MyohmRepository): String {
        val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        val ana = Athlete(
            fullName = "Ana García", dateOfBirth = today.minus(DatePeriod(years = 34)), biologicalSex = BiologicalSex.FEMALE,
            heightCm = 168.0, weightKg = 61.6, isAthlete = false, createdAt = Clock.System.now() - 90.days
        )
        val javier = Athlete(
            fullName = "Javier Ruiz", dateOfBirth = today.minus(DatePeriod(years = 27)), biologicalSex = BiologicalSex.MALE,
            heightCm = 181.0, weightKg = 78.0, isAthlete = true, createdAt = Clock.System.now() - 80.days
        )
        repository.savePerson(ana, isNew = true)
        repository.savePerson(javier, isNew = true)
        val now = Clock.System.now()
        listOf(60, 45, 30, 20, 9, 2).forEachIndexed { i, d ->
            repository.saveMeasurement(
                MeasurementKind.WholeBody(62.4 - i * 0.16, restCompleted = true), ana.id,
                sweep(690.0 + i * 3, 468.0, 46_000.0, 0.72, 0.004), now - d.days
            )
        }
        listOf(40, 26, 14, 7, 3, 0).forEachIndexed { i, d ->
            repository.saveMeasurement(
                MeasurementKind.Muscle(MyohmMuscle.QUADRICEPS, LimbSide.RIGHT, 100), ana.id,
                sweep(62.0 + i * 0.4, 34.0, 70_000.0, 0.78, 0.003), now - d.days - 5.minutes
            )
        }
        repository.saveMeasurement(
            MeasurementKind.Muscle(MyohmMuscle.BICEPS, LimbSide.LEFT, 75), ana.id,
            sweep(88.0, 52.0, 75_000.0, 0.75), now - 6.days
        )
        // Last whole-body weight should stay as the profile weight.
        repository.updateWeight(ana.id, 61.6)
        return ana.id
    }
}
