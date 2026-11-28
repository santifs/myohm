package com.volumhealth.app.di

import android.content.Context
import androidx.room.Room
import com.volumhealth.core.ble.PairedDeviceManager
import com.volumhealth.core.ble.BioMessBleManager
import com.volumhealth.core.database.AppDatabase
import com.volumhealth.core.database.MeasurementHistoryManager
import com.volumhealth.core.database.dao.AthleteDao
import com.volumhealth.core.database.dao.MeasurementDao
import com.volumhealth.core.database.dao.MeasurementSessionDao
import com.volumhealth.core.database.dao.NewMeasurementDao
import com.volumhealth.core.database.dao.PatientDao
import com.volumhealth.core.database.dao.SessionDao
import com.volumhealth.app.locale.LanguageManager
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase =
        if (com.volumhealth.app.myohm.data.MyohmDemo.isEnabled(context)) {
            Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java).build()
        } else Room.databaseBuilder(context, AppDatabase::class.java, "volum-health.db")
            .addMigrations(
                AppDatabase.MIGRATION_3_4,
                AppDatabase.MIGRATION_4_5,
                AppDatabase.MIGRATION_5_6,
                AppDatabase.MIGRATION_6_7,
                AppDatabase.MIGRATION_7_8,
                AppDatabase.MIGRATION_8_9
            )
            .build()

    @Provides
    @Singleton
    fun providePairedDeviceManager(@ApplicationContext context: Context): PairedDeviceManager =
        PairedDeviceManager(context)

    @Provides
    @Singleton
    fun provideBioMessBleManager(
        @ApplicationContext context: Context,
        pairedDeviceManager: PairedDeviceManager
    ): BioMessBleManager = BioMessBleManager(context, pairedDeviceManager)

    @Provides
    fun provideMeasurementDao(database: AppDatabase): MeasurementDao = database.measurementDao()

    @Provides
    fun provideSessionDao(database: AppDatabase): SessionDao = database.sessionDao()

    @Provides
    fun providePatientDao(database: AppDatabase): PatientDao = database.patientDao()

    @Provides
    @Singleton
    fun provideAthleteDao(database: AppDatabase): AthleteDao {
        return database.athleteDao()
    }

    @Provides
    @Singleton
    fun provideMeasurementSessionDao(database: AppDatabase): MeasurementSessionDao {
        return database.measurementSessionDao()
    }

    @Provides
    @Singleton
    fun provideNewMeasurementDao(database: AppDatabase): NewMeasurementDao {
        return database.newMeasurementDao()
    }

    @Provides
    fun provideIoDispatcher(): CoroutineDispatcher = Dispatchers.IO

    @Provides
    @Singleton
    fun provideLanguageManager(@ApplicationContext context: Context): LanguageManager =
        LanguageManager(context)

}
