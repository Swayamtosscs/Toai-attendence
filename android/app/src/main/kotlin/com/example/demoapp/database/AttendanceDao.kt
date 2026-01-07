package com.example.demoapp.database

import androidx.room.*
import kotlinx.coroutines.flow.Flow

/**
 * Data Access Object for attendance events
 * Provides CRUD operations for offline storage
 */
@Dao
interface AttendanceDao {
    
    /**
     * Insert or replace an attendance event
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertEvent(event: AttendanceEvent)
    
    /**
     * Get all unsynced events (for sync worker)
     */
    @Query("SELECT * FROM attendance_events WHERE synced = 0 ORDER BY timestamp ASC")
    suspend fun getUnsyncedEvents(): List<AttendanceEvent>
    
    /**
     * Mark event as synced
     */
    @Query("UPDATE attendance_events SET synced = 1, syncedAt = :syncedAt WHERE id = :eventId")
    suspend fun markAsSynced(eventId: String, syncedAt: Long = System.currentTimeMillis())
    
    /**
     * Get events for a specific date range
     */
    @Query("SELECT * FROM attendance_events WHERE timestamp >= :startTime AND timestamp <= :endTime ORDER BY timestamp ASC")
    suspend fun getEventsForDateRange(startTime: Long, endTime: Long): List<AttendanceEvent>
    
    /**
     * Get all events (for debugging/admin)
     */
    @Query("SELECT * FROM attendance_events ORDER BY timestamp DESC")
    fun getAllEvents(): Flow<List<AttendanceEvent>>
    
    /**
     * Delete old synced events (cleanup - keep last 30 days)
     */
    @Query("DELETE FROM attendance_events WHERE synced = 1 AND timestamp < :cutoffTime")
    suspend fun deleteOldSyncedEvents(cutoffTime: Long)
    
    /**
     * Get count of unsynced events
     */
    @Query("SELECT COUNT(*) FROM attendance_events WHERE synced = 0")
    suspend fun getUnsyncedCount(): Int
    
    /**
     * Delete all events (for testing/reset)
     */
    @Query("DELETE FROM attendance_events")
    suspend fun deleteAllEvents()
}

