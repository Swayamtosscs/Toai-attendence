package com.example.demoapp.database

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.Date

/**
 * Room entity for storing attendance events offline
 * Supports check-in and check-out events with full location data
 */
@Entity(tableName = "attendance_events")
data class AttendanceEvent(
    @PrimaryKey
    val id: String,
    val eventType: String, // "CHECK_IN" or "CHECK_OUT"
    val timestamp: Long, // Unix timestamp in milliseconds
    val latitude: Double,
    val longitude: Double,
    val locationId: String?,
    val locationName: String?,
    val notes: String?,
    val isAuto: Boolean, // true for auto, false for manual
    val synced: Boolean = false, // true if synced to server
    val syncedAt: Long? = null, // Timestamp when synced
    val createdAt: Long = System.currentTimeMillis()
)

