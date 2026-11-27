package com.volumhealth.core.database

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.volumhealth.core.database.dao.AthleteDao
import com.volumhealth.core.database.dao.MeasurementDao
import com.volumhealth.core.database.dao.MeasurementSessionDao
import com.volumhealth.core.database.dao.NewMeasurementDao
import com.volumhealth.core.database.dao.PatientDao
import com.volumhealth.core.database.dao.SessionDao
import com.volumhealth.core.database.entity.AthleteEntity
import com.volumhealth.core.database.entity.AutoMeasurementSessionEntity
import com.volumhealth.core.database.entity.MeasurementEntity
import com.volumhealth.core.database.entity.MeasurementSessionEntity
import com.volumhealth.core.database.entity.PatientInfoEntity
import com.volumhealth.core.database.entity.RawMeasurementEntity

@Database(
    entities = [
        RawMeasurementEntity::class,
        AutoMeasurementSessionEntity::class,
        PatientInfoEntity::class,
        AthleteEntity::class,
        MeasurementSessionEntity::class,
        MeasurementEntity::class
    ],
    version = 9,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun measurementDao(): MeasurementDao
    abstract fun sessionDao(): SessionDao
    abstract fun patientDao(): PatientDao
    abstract fun athleteDao(): AthleteDao
    abstract fun measurementSessionDao(): MeasurementSessionDao
    abstract fun newMeasurementDao(): NewMeasurementDao

    companion object {
        val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE athletes ADD COLUMN height_cm REAL")
                db.execSQL("ALTER TABLE athletes ADD COLUMN weight_kg REAL")
                db.execSQL("ALTER TABLE athletes ADD COLUMN right_thigh_length REAL")
                db.execSQL("ALTER TABLE athletes ADD COLUMN right_thigh_circumference REAL")
                db.execSQL("ALTER TABLE athletes ADD COLUMN left_thigh_length REAL")
                db.execSQL("ALTER TABLE athletes ADD COLUMN left_thigh_circumference REAL")
                db.execSQL("ALTER TABLE athletes ADD COLUMN has_current_injury INTEGER")
                db.execSQL("ALTER TABLE athletes ADD COLUMN current_injury_details TEXT")
            }
        }

        val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE measurement_sessions ADD COLUMN involved_legs INTEGER")
                db.execSQL("ALTER TABLE measurement_sessions ADD COLUMN leg_muscle_group TEXT")
            }
        }

        val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE measurement_sessions ADD COLUMN session_type TEXT")
            }
        }

        val MIGRATION_6_7 = object : Migration(6, 7) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE measurement_sessions ADD COLUMN study_id TEXT")
            }
        }

        val MIGRATION_7_8 = object : Migration(7, 8) {
            override fun migrate(db: SupportSQLiteDatabase) {
                // SQLite < 3.35 no soporta DROP COLUMN — recreamos la tabla.
                // Schema copiado verbatim del CREATE TABLE que genera Room para
                // MeasurementEntity en v8 (ver AppDatabase_Impl#createAllTables).
                // Tipos críticos: measured_at INTEGER NOT NULL, last_sync_attempt INTEGER
                // (Instant -> epoch ms vía Converters.instantToEpoch).
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `measurements_new` (" +
                        "`id` TEXT NOT NULL, " +
                        "`session_id` TEXT, " +
                        "`muscle_group` TEXT NOT NULL, " +
                        "`side` TEXT NOT NULL, " +
                        "`perceived_fatigue` INTEGER NOT NULL, " +
                        "`raw_data_json` TEXT NOT NULL, " +
                        "`measured_at` INTEGER NOT NULL, " +
                        "`sync_status` TEXT NOT NULL, " +
                        "`last_sync_attempt` INTEGER, " +
                        "`sync_error` TEXT, " +
                        "PRIMARY KEY(`id`), " +
                        "FOREIGN KEY(`session_id`) REFERENCES `measurement_sessions`(`id`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )"
                )
                db.execSQL(
                    "INSERT INTO `measurements_new` (" +
                        "id, session_id, muscle_group, side, perceived_fatigue, " +
                        "raw_data_json, measured_at, sync_status, last_sync_attempt, sync_error" +
                        ") SELECT id, session_id, muscle_group, side, perceived_fatigue, " +
                        "raw_data_json, measured_at, sync_status, last_sync_attempt, sync_error " +
                        "FROM `measurements`"
                )
                db.execSQL("DROP TABLE `measurements`")
                db.execSQL("ALTER TABLE `measurements_new` RENAME TO `measurements`")
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_measurements_session_id` " +
                        "ON `measurements` (`session_id`)"
                )
            }
        }

        val MIGRATION_8_9 = object : Migration(8, 9) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE athletes ADD COLUMN is_athlete INTEGER")
                db.execSQL("ALTER TABLE measurements ADD COLUMN person_id TEXT")
                db.execSQL("ALTER TABLE measurements ADD COLUMN band_mm INTEGER")
                db.execSQL("ALTER TABLE measurements ADD COLUMN body_weight_kg REAL")
                db.execSQL("ALTER TABLE measurements ADD COLUMN rest_completed INTEGER")
            }
        }
    }
}
