package com.volumhealth.core.database

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.volumhealth.core.database.dao.MeasurementDao
import com.volumhealth.core.database.util.toEntity
import com.volumhealth.core.model.Gender
import com.volumhealth.core.model.ImpedanceData
import com.volumhealth.core.model.MeasurementPoint
import com.volumhealth.core.model.PatientSnapshot
import com.volumhealth.core.model.ProcessingState
import com.volumhealth.core.model.RawMeasurement
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Clock
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class MeasurementDaoTest {

    private lateinit var db: AppDatabase
    private lateinit var dao: MeasurementDao

    @Before
    fun setup() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        dao = db.measurementDao()
    }

    @After
    fun tearDown() {
        db.close()
    }

    @Test
    fun insertAndReadMeasurement() = runTest {
        val measurement = RawMeasurement(
            rawData = ImpedanceData(
                repetitions = listOf(
                    listOf(MeasurementPoint(frequency = 1000f, magnitude = 40f, phase = -10f))
                ),
                timestamp = Clock.System.now(),
                deviceInfo = null
            ),
            patientSnapshot = PatientSnapshot(
                name = "Test",
                exerciseName = "Run",
                measurementNumber = 1,
                age = 28,
                gender = Gender.FEMALE,
                height = 170f,
                weight = 60f,
                bmi = 21f,
                timestamp = Clock.System.now()
            ),
            captureTimestamp = Clock.System.now()
        )
        dao.insert(measurement.toEntity())

        val fromDb = dao.getMeasurementsByState(ProcessingState.PENDING)
        assertEquals(1, fromDb.size)
        val flowValue = dao.getAllMeasurements().first()
        assertEquals(1, flowValue.size)
        assertEquals(measurement.id, flowValue.first().id)
    }
}
