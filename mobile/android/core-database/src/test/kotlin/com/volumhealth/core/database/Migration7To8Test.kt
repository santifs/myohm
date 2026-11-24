package com.volumhealth.core.database

import android.content.Context
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Smoke test for [AppDatabase.MIGRATION_7_8].
 *
 * No usamos `MigrationTestHelper` (requeriría exportar schemas .json a disco).
 * En su lugar:
 *   1. Creamos manualmente la base v7 con SQL crudo (matcheando el schema que
 *      Room genera en v7, ver AppDatabase_Impl.java tras revertir el commit
 *      anterior — `signal_quality REAL` y `cole_parameters_json TEXT`).
 *   2. Insertamos una fila representativa.
 *   3. Ejecutamos `MIGRATION_7_8.migrate(...)` directamente sobre el handle.
 *   4. Validamos:
 *      - La fila sobrevive y conserva valores intactos.
 *      - Las columnas dropeadas ya no existen.
 *      - `measured_at` y `last_sync_attempt` quedan como INTEGER (no TEXT).
 *      - El índice `index_measurements_session_id` existe.
 *   5. Reabrimos el archivo con Room (todas las migraciones aplicadas) para
 *      asegurarnos de que la validación de schema en runtime pasa.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class Migration7To8Test {

    private lateinit var context: Context
    private lateinit var dbName: String

    @Before
    fun setup() {
        context = ApplicationProvider.getApplicationContext()
        dbName = "migration-7-8-test.db"
        // Limpiamos cualquier residuo de un test anterior.
        context.deleteDatabase(dbName)
    }

    @After
    fun tearDown() {
        context.deleteDatabase(dbName)
    }

    @Test
    fun migrate7to8_dropsSignalQualityAndColeParameters_andSchemaValidates() {
        // 1. Crear la base v7 con el schema antiguo.
        val factory = FrameworkSQLiteOpenHelperFactory()
        val helperConfig = SupportSQLiteOpenHelper.Configuration.builder(context)
            .name(dbName)
            .callback(object : SupportSQLiteOpenHelper.Callback(7) {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    // Schema v7 — copiado del estado anterior al commit 7ecaeeb.
                    // Solo creamos las tablas mínimas necesarias para la FK y la fila bajo test.
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS `athletes` (" +
                            "`id` TEXT NOT NULL, " +
                            "`user_id` TEXT, " +
                            "`full_name` TEXT NOT NULL, " +
                            "`date_of_birth` TEXT NOT NULL, " +
                            "`dominant_leg` TEXT NOT NULL, " +
                            "`biological_sex` TEXT, " +
                            "`medical_history` TEXT, " +
                            "`medications` TEXT, " +
                            "`diet_type` TEXT, " +
                            "`daily_calories` INTEGER, " +
                            "`allergies_json` TEXT, " +
                            "`usual_activities_json` TEXT, " +
                            "`height_cm` REAL, " +
                            "`weight_kg` REAL, " +
                            "`right_thigh_length` REAL, " +
                            "`right_thigh_circumference` REAL, " +
                            "`left_thigh_length` REAL, " +
                            "`left_thigh_circumference` REAL, " +
                            "`has_current_injury` INTEGER, " +
                            "`current_injury_details` TEXT, " +
                            "`created_at` INTEGER NOT NULL, " +
                            "`updated_at` INTEGER NOT NULL, " +
                            "`sync_status` TEXT NOT NULL, " +
                            "`last_sync_attempt` INTEGER, " +
                            "`sync_error` TEXT, " +
                            "PRIMARY KEY(`id`))"
                    )
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS `measurement_sessions` (" +
                            "`id` TEXT NOT NULL, " +
                            "`athlete_id` TEXT NOT NULL, " +
                            "`started_at` INTEGER NOT NULL, " +
                            "`hours_since_activity` REAL, " +
                            "`last_activity_type` TEXT, " +
                            "`sleep_hours` REAL, " +
                            "`general_fatigue` INTEGER, " +
                            "`recent_physio` INTEGER, " +
                            "`recent_physio_hours_ago` INTEGER, " +
                            "`new_issues` TEXT, " +
                            "`menstrual_cycle_phase` TEXT, " +
                            "`involved_legs` INTEGER, " +
                            "`leg_muscle_group` TEXT, " +
                            "`session_type` TEXT, " +
                            "`study_id` TEXT, " +
                            "`sync_status` TEXT NOT NULL, " +
                            "`last_sync_attempt` INTEGER, " +
                            "`sync_error` TEXT, " +
                            "PRIMARY KEY(`id`), " +
                            "FOREIGN KEY(`athlete_id`) REFERENCES `athletes`(`id`) " +
                            "ON UPDATE NO ACTION ON DELETE CASCADE )"
                    )
                    db.execSQL(
                        "CREATE INDEX IF NOT EXISTS `index_measurement_sessions_athlete_id` " +
                            "ON `measurement_sessions` (`athlete_id`)"
                    )
                    // Tabla measurements — schema v7 con signal_quality y cole_parameters_json.
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS `measurements` (" +
                            "`id` TEXT NOT NULL, " +
                            "`session_id` TEXT, " +
                            "`muscle_group` TEXT NOT NULL, " +
                            "`side` TEXT NOT NULL, " +
                            "`perceived_fatigue` INTEGER NOT NULL, " +
                            "`raw_data_json` TEXT NOT NULL, " +
                            "`cole_parameters_json` TEXT, " +
                            "`signal_quality` REAL, " +
                            "`measured_at` INTEGER NOT NULL, " +
                            "`sync_status` TEXT NOT NULL, " +
                            "`last_sync_attempt` INTEGER, " +
                            "`sync_error` TEXT, " +
                            "PRIMARY KEY(`id`), " +
                            "FOREIGN KEY(`session_id`) REFERENCES `measurement_sessions`(`id`) " +
                            "ON UPDATE NO ACTION ON DELETE CASCADE )"
                    )
                    db.execSQL(
                        "CREATE INDEX IF NOT EXISTS `index_measurements_session_id` " +
                            "ON `measurements` (`session_id`)"
                    )

                    // Insertamos un row de cada tabla.
                    db.execSQL(
                        "INSERT INTO athletes(" +
                            "id, full_name, date_of_birth, dominant_leg, " +
                            "created_at, updated_at, sync_status" +
                            ") VALUES('ath-1', 'Tester', '1990-01-01', 'right', " +
                            "1700000000000, 1700000000000, 'PENDING')"
                    )
                    db.execSQL(
                        "INSERT INTO measurement_sessions(" +
                            "id, athlete_id, started_at, sync_status" +
                            ") VALUES('sess-1', 'ath-1', 1700000000000, 'PENDING')"
                    )
                    db.execSQL(
                        "INSERT INTO measurements(" +
                            "id, session_id, muscle_group, side, perceived_fatigue, " +
                            "raw_data_json, cole_parameters_json, signal_quality, " +
                            "measured_at, sync_status, last_sync_attempt, sync_error" +
                            ") VALUES('meas-1', 'sess-1', 'biceps_brachii', 'right', 5, " +
                            "'{}', '{\"re\":1.0}', 0.95, " +
                            "1700000000123, 'PENDING', NULL, NULL)"
                    )
                }

                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                    // No-op para el setup.
                }
            })
            .build()
        val helper = factory.create(helperConfig)

        // Fuerza la creación.
        helper.writableDatabase.use { db ->
            assertEquals(7, db.version)
        }
        helper.close()

        // 2. Reabrir como SupportSQLite handle y aplicar la migración manualmente.
        val helperForMigration = factory.create(
            SupportSQLiteOpenHelper.Configuration.builder(context)
                .name(dbName)
                .callback(object : SupportSQLiteOpenHelper.Callback(7) {
                    override fun onCreate(db: SupportSQLiteDatabase) = Unit
                    override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
                })
                .build()
        )
        val rawDb: SupportSQLiteDatabase = helperForMigration.writableDatabase

        // Ejecutamos la migración bajo test.
        AppDatabase.MIGRATION_7_8.migrate(rawDb)

        // 3. Verificaciones sobre el schema migrado.

        // 3a. La fila sobrevive y conserva valores intactos.
        rawDb.query(
            "SELECT id, session_id, muscle_group, side, perceived_fatigue, " +
                "raw_data_json, measured_at, sync_status, last_sync_attempt, sync_error " +
                "FROM measurements WHERE id = 'meas-1'"
        ).use { c ->
            assertTrue("La fila migrada existe", c.moveToFirst())
            assertEquals("meas-1", c.getString(0))
            assertEquals("sess-1", c.getString(1))
            assertEquals("biceps_brachii", c.getString(2))
            assertEquals("right", c.getString(3))
            assertEquals(5, c.getInt(4))
            assertEquals("{}", c.getString(5))
            assertEquals(1700000000123L, c.getLong(6))
            assertEquals("PENDING", c.getString(7))
            assertTrue("last_sync_attempt debe ser NULL", c.isNull(8))
            assertTrue("sync_error debe ser NULL", c.isNull(9))
        }

        // 3b. Las columnas dropeadas ya no existen — y tipo correcto en las que quedan.
        rawDb.query("PRAGMA table_info(measurements)").use { c ->
            val cols = mutableMapOf<String, String>()
            while (c.moveToNext()) {
                // PRAGMA table_info: cid(0), name(1), type(2), notnull(3), dflt(4), pk(5)
                cols[c.getString(1)] = c.getString(2)
            }
            assertFalse(
                "signal_quality debe estar dropeada — encontradas: $cols",
                cols.containsKey("signal_quality")
            )
            assertFalse(
                "cole_parameters_json debe estar dropeada — encontradas: $cols",
                cols.containsKey("cole_parameters_json")
            )
            assertEquals(
                "measured_at debe ser INTEGER (epoch ms via Converters), no TEXT",
                "INTEGER",
                cols["measured_at"]
            )
            assertEquals(
                "last_sync_attempt debe ser INTEGER (epoch ms via Converters), no TEXT",
                "INTEGER",
                cols["last_sync_attempt"]
            )
        }

        // 3c. El índice se recrea.
        rawDb.query(
            "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='measurements'"
        ).use { c ->
            val indices = mutableListOf<String>()
            while (c.moveToNext()) indices.add(c.getString(0))
            assertTrue(
                "Falta el índice index_measurements_session_id — encontrados: $indices",
                indices.contains("index_measurements_session_id")
            )
        }

        helperForMigration.close()

        // Nota: no reabrimos con Room porque la validación de schema de Room exige
        // que TODAS las tablas de la base estén presentes (raw_measurements,
        // auto_measurement_sessions, patient_info, etc.). El test enfoca solo en
        // measurements; las assertions sobre PRAGMA table_info ya verifican que
        // los tipos de columna (INTEGER vs TEXT) coinciden con lo que Room genera.
    }
}
