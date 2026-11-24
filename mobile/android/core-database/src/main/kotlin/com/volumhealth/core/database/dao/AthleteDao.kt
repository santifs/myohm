package com.volumhealth.core.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.volumhealth.core.database.entity.AthleteEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.datetime.Instant

@Dao
interface AthleteDao {

    @Query("SELECT * FROM athletes WHERE user_id = :userId ORDER BY full_name ASC")
    fun getAthletesByUser(userId: String): Flow<List<AthleteEntity>>

    @Query("SELECT * FROM athletes ORDER BY full_name ASC")
    fun getAllAthletes(): Flow<List<AthleteEntity>>

    @Query("SELECT * FROM athletes WHERE id = :id")
    suspend fun getAthleteById(id: String): AthleteEntity?

    @Query("SELECT * FROM athletes WHERE id = :id")
    fun getAthleteByIdFlow(id: String): Flow<AthleteEntity?>

    @Query("SELECT * FROM athletes WHERE sync_status IN ('PENDING', 'MODIFIED', 'FAILED')")
    suspend fun getAthletesNeedingSync(): List<AthleteEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(athlete: AthleteEntity)

    @Update
    suspend fun update(athlete: AthleteEntity)

    @Delete
    suspend fun delete(athlete: AthleteEntity)

    @Query("DELETE FROM athletes WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("UPDATE athletes SET sync_status = :status WHERE id = :id")
    suspend fun updateSyncStatus(id: String, status: String)

    @Query("UPDATE athletes SET sync_status = :status, last_sync_attempt = :timestamp, sync_error = :error WHERE id = :id")
    suspend fun updateSyncResult(id: String, status: String, timestamp: Instant, error: String?)

    /**
     * Fill [userId] on any athlete that currently has a null user_id and reset their
     * sync status so they upload on the next sync cycle. Used to repair rows created
     * before the [Athlete.minimal] factory required a userId.
     */
    @Query("""
        UPDATE athletes
        SET user_id = :userId, sync_status = 'PENDING'
        WHERE user_id IS NULL
    """)
    suspend fun fillMissingUserId(userId: String): Int

    /**
     * Claim local athletes whose user_id differs from the current auth UID.
     * Rewrites user_id and marks them PENDING so the next sync retries the INSERT
     * (which otherwise fails the RLS check `auth.uid() = user_id`). Remote-sourced
     * rows sit in SYNCED so they are exempt; only local PENDING/FAILED rows are
     * touched.
     *
     * Returns the number of rows updated.
     */
    @Query("""
        UPDATE athletes
        SET user_id = :uid, sync_status = 'PENDING', last_sync_attempt = NULL, sync_error = NULL
        WHERE user_id IS NOT NULL
          AND user_id != :uid
          AND sync_status IN ('PENDING', 'FAILED')
    """)
    suspend fun claimOrphanAthletes(uid: String): Int
}
