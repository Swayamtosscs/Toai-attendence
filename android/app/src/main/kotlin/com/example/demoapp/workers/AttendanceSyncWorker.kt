package com.example.demoapp.workers

import android.content.Context
import android.util.Log
import androidx.work.*
import com.example.demoapp.database.AppDatabase
import com.example.demoapp.database.AttendanceEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * WorkManager worker for syncing offline attendance events to server
 * Runs automatically when internet is available
 */
class AttendanceSyncWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {
    
    companion object {
        private const val TAG = "AttendanceSyncWorker"
        private const val WORK_NAME = "attendance_sync_work"
        
        /**
         * Enqueue periodic sync work (runs every 15 minutes when conditions are met)
         */
        fun enqueuePeriodicSync(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .setRequiresBatteryNotLow(false)
                .setRequiresCharging(false)
                .build()
            
            val syncRequest = PeriodicWorkRequestBuilder<AttendanceSyncWorker>(
                15, TimeUnit.MINUTES,
                5, TimeUnit.MINUTES // Flex interval
            )
                .setConstraints(constraints)
                .addTag(WORK_NAME)
                .build()
            
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                syncRequest
            )
            
            Log.d(TAG, "Periodic sync work enqueued")
        }
        
        /**
         * Enqueue one-time immediate sync
         */
        fun enqueueImmediateSync(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
            
            val syncRequest = OneTimeWorkRequestBuilder<AttendanceSyncWorker>()
                .setConstraints(constraints)
                .addTag(WORK_NAME)
                .build()
            
            WorkManager.getInstance(context).enqueue(syncRequest)
            Log.d(TAG, "Immediate sync work enqueued")
        }
    }
    
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "Starting attendance sync worker")
            
            val database = AppDatabase.getDatabase(applicationContext)
            val dao = database.attendanceDao()
            
            // Get all unsynced events
            val unsyncedEvents = dao.getUnsyncedEvents()
            
            if (unsyncedEvents.isEmpty()) {
                Log.d(TAG, "No unsynced events to sync")
                return@withContext Result.success()
            }
            
            Log.d(TAG, "Found ${unsyncedEvents.size} unsynced events")
            
            // Get API configuration from SharedPreferences
            val prefs = applicationContext.getSharedPreferences("attendance_service_prefs", Context.MODE_PRIVATE)
            val apiBaseUrl = prefs.getString("api_base_url", null)
                ?: applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getString("flutter.api_base_url", null)
                ?: "http://103.14.120.163:8092/api"
            
            val authToken = prefs.getString("auth_token", null)
                ?: applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getString("flutter.auth_token", null)
                    ?: applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        .getString("auth_token", null)
            
            if (authToken.isNullOrEmpty()) {
                Log.e(TAG, "Auth token not available - cannot sync")
                return@withContext Result.retry() // Retry later when token might be available
            }
            
            val httpClient = OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .readTimeout(10, TimeUnit.SECONDS)
                .writeTimeout(10, TimeUnit.SECONDS)
                .build()
            
            var successCount = 0
            var failureCount = 0
            
            // Sync each event
            for (event in unsyncedEvents) {
                try {
                    val success = syncEvent(event, apiBaseUrl, authToken, httpClient)
                    if (success) {
                        // Mark as synced
                        dao.markAsSynced(event.id)
                        successCount++
                        Log.d(TAG, "✅ Synced event: ${event.id}")
                    } else {
                        failureCount++
                        Log.w(TAG, "⚠️ Failed to sync event: ${event.id}")
                    }
                } catch (e: Exception) {
                    failureCount++
                    Log.e(TAG, "❌ Error syncing event ${event.id}: ${e.message}", e)
                }
            }
            
            Log.d(TAG, "Sync completed: $successCount succeeded, $failureCount failed")
            
            // If all synced, return success; otherwise retry
            if (failureCount == 0) {
                Result.success()
            } else if (successCount > 0) {
                // Partial success - retry failed ones
                Result.retry()
            } else {
                // All failed - retry
                Result.retry()
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Sync worker error: ${e.message}", e)
            Result.retry()
        }
    }
    
    private suspend fun syncEvent(
        event: AttendanceEvent,
        apiBaseUrl: String,
        authToken: String,
        httpClient: OkHttpClient
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            val endpoint = when (event.eventType) {
                "CHECK_IN" -> "$apiBaseUrl/attendance/check-in"
                "CHECK_OUT" -> "$apiBaseUrl/attendance/check-out"
                else -> {
                    Log.e(TAG, "Unknown event type: ${event.eventType}")
                    return@withContext false
                }
            }
            
            val json = JSONObject().apply {
                put("latitude", event.latitude)
                put("longitude", event.longitude)
                if (event.notes != null && event.notes.isNotEmpty()) {
                    put("notes", event.notes)
                }
            }
            
            val requestBody = json.toString().toRequestBody("application/json".toMediaType())
            
            val request = Request.Builder()
                .url(endpoint)
                .post(requestBody)
                .addHeader("Content-Type", "application/json")
                .addHeader("Accept", "application/json")
                .addHeader("Authorization", "Bearer $authToken")
                .build()
            
            val response = httpClient.newCall(request).execute()
            val success = response.isSuccessful
            response.close()
            
            if (success) {
                Log.d(TAG, "✅ API call successful for event: ${event.id}")
            } else {
                Log.e(TAG, "❌ API call failed for event ${event.id}: ${response.code}")
            }
            
            success
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error calling API for event ${event.id}: ${e.message}", e)
            false
        }
    }
}

