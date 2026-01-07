package com.example.demoapp

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.example.demoapp.database.AppDatabase
import com.example.demoapp.database.AttendanceEvent
import com.example.demoapp.workers.AttendanceSyncWorker
import kotlinx.coroutines.*
import java.util.concurrent.TimeUnit
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.Calendar

/**
 * Foreground service for continuous attendance monitoring
 * Runs even when app is closed, locked, or removed from recents
 * Implements 1-minute grace timers for entry/exit
 */
class ForegroundAttendanceService : Service() {
    companion object {
        private const val TAG = "ForegroundAttendanceService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "attendance_foreground_channel"
        private const val CHANNEL_NAME = "Attendance Monitoring"
        
        // Grace timer durations (1 minute = 60 seconds)
        private const val GRACE_ENTRY_TIMER_MS = 60_000L // 1 minute
        private const val GRACE_EXIT_TIMER_MS = 60_000L // 1 minute
        
        // Location update intervals
        private const val LOCATION_UPDATE_INTERVAL_MS = 30_000L // 30 seconds
        private const val LOCATION_UPDATE_DISTANCE_M = 10f // 10 meters
        
        // Deep validation interval (30 minutes)
        private const val DEEP_VALIDATION_INTERVAL_MS = 1_800_000L // 30 minutes
        
        // SharedPreferences keys
        private const val PREFS_NAME = "attendance_service_prefs"
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_IS_ENABLED = "is_enabled"
        private const val KEY_IS_CHECKED_IN = "is_checked_in"
        private const val KEY_LOCATION_ID = "location_id"
        private const val KEY_CHECK_IN_TIME = "check_in_time"
        private const val KEY_ENTRY_TIMER_START = "entry_timer_start"
        private const val KEY_EXIT_TIMER_START = "exit_timer_start"
        private const val KEY_LAST_LOCATION_LAT = "last_location_lat"
        private const val KEY_LAST_LOCATION_LNG = "last_location_lng"
        private const val KEY_WORK_LOCATIONS = "work_locations_json"
        private const val KEY_AUTH_TOKEN = "auth_token"
        private const val KEY_API_BASE_URL = "api_base_url"
        private const val KEY_MANUAL_TOGGLE_OFF_DATE = "manual_toggle_off_date" // Date when manual toggle was turned OFF
        private const val KEY_AUTO_CHECKIN_DISABLED = "auto_checkin_disabled" // Flag to disable auto check-in
        
        // Actions
        const val ACTION_START = "com.example.demoapp.START_SERVICE"
        const val ACTION_STOP = "com.example.demoapp.STOP_SERVICE"
        const val ACTION_UPDATE_LOCATIONS = "com.example.demoapp.UPDATE_LOCATIONS"
        const val ACTION_MANUAL_TOGGLE_OFF = "com.example.demoapp.MANUAL_TOGGLE_OFF"
    }
    
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var locationManager: LocationManager
    private lateinit var prefs: SharedPreferences
    private lateinit var flutterPrefs: SharedPreferences
    private lateinit var database: AppDatabase
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .build()
    private var locationListener: LocationListener? = null
    private var entryTimerHandler: Handler? = null
    private var exitTimerHandler: Handler? = null
    private var deepValidationHandler: Handler? = null
    private var entryTimerRunnable: Runnable? = null
    private var exitTimerRunnable: Runnable? = null
    private var deepValidationRunnable: Runnable? = null
    private var entryCountdownHandler: Handler? = null
    private var exitCountdownHandler: Handler? = null
    private var entryCountdownRunnable: Runnable? = null
    private var exitCountdownRunnable: Runnable? = null
    
    private var isServiceRunning = false
    private var isInsideLocation = false
    private var currentLocationId: String? = null
    private var workLocations: List<WorkLocation> = emptyList()
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate")
        
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        flutterPrefs = getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
        database = AppDatabase.getDatabase(this)
        
        createNotificationChannel()
        
        // Check if new day - reset manual toggle OFF flag
        checkAndResetManualToggleFlag()
        
        // Restore state from SharedPreferences
        restoreState()
        
        // Restore grace timers if they were active
        restoreGraceTimers()
        
        // Start periodic sync worker
        AttendanceSyncWorker.enqueuePeriodicSync(this)
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Always log important service actions, even in release
        Log.d(TAG, "onStartCommand: ${intent?.action}")
        
        when (intent?.action) {
            ACTION_START -> {
                val locationsJson = intent?.getStringExtra("locations_json")
                val apiBaseUrl = intent?.getStringExtra("api_base_url")
                val authToken = intent?.getStringExtra("auth_token")
                startService(locationsJson, apiBaseUrl, authToken)
            }
            ACTION_STOP -> {
                stopService()
            }
            ACTION_UPDATE_LOCATIONS -> {
                val locationsJson = intent.getStringExtra("locations_json")
                if (locationsJson != null) {
                    updateWorkLocations(locationsJson)
                }
            }
            ACTION_MANUAL_TOGGLE_OFF -> {
                handleManualToggleOff()
            }
        }
        
        return START_STICKY // Restart if killed
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    private fun startService(locationsJson: String? = null, apiBaseUrl: String? = null, authToken: String? = null) {
        if (isServiceRunning) {
            Log.d(TAG, "Service already running")
            // Update locations if provided
            if (locationsJson != null) {
                updateWorkLocations(locationsJson)
            }
            return
        }
        
        // Check permissions before starting service
        val hasFineLocation = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
        val hasCoarseLocation = checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
        
        if (!hasFineLocation && !hasCoarseLocation) {
            Log.e(TAG, "Cannot start service: Location permissions not granted")
            // Don't crash - just log and return
            return
        }
        
        Log.d(TAG, "Starting foreground service")
        isServiceRunning = true
        
        // Save API base URL and auth token for API calls
        if (apiBaseUrl != null) {
            prefs.edit().putString(KEY_API_BASE_URL, apiBaseUrl).apply()
            Log.d(TAG, "Saved API base URL: $apiBaseUrl")
        }
        if (authToken != null && authToken.isNotEmpty()) {
            prefs.edit().putString(KEY_AUTH_TOKEN, authToken).apply()
            Log.d(TAG, "Saved auth token (length: ${authToken.length})")
        } else {
            Log.w(TAG, "⚠️ Auth token is empty or null - API calls will fail")
            // Try to get from Flutter SharedPreferences
            val flutterToken = flutterPrefs.getString("auth_token", null)
            if (flutterToken != null && flutterToken.isNotEmpty()) {
                prefs.edit().putString(KEY_AUTH_TOKEN, flutterToken).apply()
                Log.d(TAG, "Retrieved auth token from Flutter SharedPreferences")
            } else {
                Log.e(TAG, "❌ Auth token not found in any location")
            }
        }
        
        // Update work locations if provided
        if (locationsJson != null) {
            updateWorkLocations(locationsJson)
        } else {
            // Load from saved preferences
            loadWorkLocations()
        }
        
        // Save enabled state
        prefs.edit().putBoolean(KEY_IS_ENABLED, true).apply()
        
        // Start foreground with notification
        startForeground(NOTIFICATION_ID, createNotification())
        
        // Start location monitoring
        startLocationMonitoring()
        
        // Start deep validation timer
        startDeepValidation()
        
        // Perform immediate location check - CRITICAL for auto check-in/out
        serviceScope.launch {
            // Small delay to ensure location service is ready
            delay(1000)
            
            // Get fresh location first
            var location = getCurrentLocation()
            if (location == null) {
                // Wait a bit more and try again
                delay(2000)
                location = getCurrentLocation()
            }
            
            if (location != null) {
                // Save location
                prefs.edit()
                    .putFloat(KEY_LAST_LOCATION_LAT, location.latitude.toFloat())
                    .putFloat(KEY_LAST_LOCATION_LNG, location.longitude.toFloat())
                    .apply()
                Log.d(TAG, "Service started - checking location: ${location.latitude}, ${location.longitude}")
                // Check location immediately - this will start timer if inside location
                checkLocationAtPosition(location.latitude, location.longitude)
            } else {
                // Fallback to last known location
                Log.d(TAG, "No fresh location - using last known location")
                performLocationCheck()
            }
        }
    }
    
    private fun stopService() {
        Log.d(TAG, "Stopping foreground service")
        isServiceRunning = false
        
        // Save disabled state
        prefs.edit().putBoolean(KEY_IS_ENABLED, false).apply()
        
        // Stop location monitoring
        stopLocationMonitoring()
        
        // Cancel all timers
        cancelGraceTimers()
        cancelDeepValidation()
        
        // Stop foreground service
        stopForeground(true)
        stopSelf()
    }
    
    private fun startLocationMonitoring() {
        if (locationListener != null) {
            return // Already monitoring
        }
        
        try {
            locationListener = object : LocationListener {
                override fun onLocationChanged(location: Location) {
                    // Release-safe logging - log important location updates
                    // In release, only log if accuracy is good to reduce log spam
                    val shouldLog = try {
                        // Check if debug build (may not be available in all builds)
                        javaClass.classLoader?.loadClass("com.example.demoapp.BuildConfig")?.getField("DEBUG")?.getBoolean(null) ?: false
                    } catch (e: Exception) {
                        // Assume release build, only log high-quality locations
                        location.accuracy < 50
                    }
                    
                    if (shouldLog || location.accuracy < 50) {
                        Log.d(TAG, "Location update: ${location.latitude}, ${location.longitude}, accuracy=${location.accuracy}m")
                    }
                    
                    // Save last known location
                    prefs.edit()
                        .putFloat(KEY_LAST_LOCATION_LAT, location.latitude.toFloat())
                        .putFloat(KEY_LAST_LOCATION_LNG, location.longitude.toFloat())
                        .apply()
                    
                    // Check location immediately
                    serviceScope.launch {
                        checkLocationAtPosition(location.latitude, location.longitude)
                    }
                }
                
                override fun onProviderEnabled(provider: String) {
                    Log.d(TAG, "Location provider enabled: $provider")
                }
                
                override fun onProviderDisabled(provider: String) {
                    Log.w(TAG, "Location provider disabled: $provider")
                    // Try to switch to another provider
                    serviceScope.launch {
                        delay(1000)
                        restartLocationMonitoring()
                    }
                }
            }
            
            // Request location updates with proper permissions
            val hasFineLocation = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
            val hasCoarseLocation = checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
            val hasBackgroundLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                checkSelfPermission(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
            } else {
                true // Not required before Android 10
            }
            
            if (!hasFineLocation && !hasCoarseLocation) {
                Log.e(TAG, "No location permissions granted")
                return
            }
            
            // In release mode, use PASSIVE_PROVIDER first (most battery efficient)
            // Then fall back to NETWORK_PROVIDER, then GPS_PROVIDER
            val providers = mutableListOf<String>()
            
            // Add PASSIVE_PROVIDER for battery efficiency (uses other apps' location updates)
            if (locationManager.isProviderEnabled(LocationManager.PASSIVE_PROVIDER)) {
                providers.add(LocationManager.PASSIVE_PROVIDER)
            }
            
            // Add NETWORK_PROVIDER (good balance of accuracy and battery)
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                providers.add(LocationManager.NETWORK_PROVIDER)
            }
            
            // Add GPS_PROVIDER for high accuracy (use only if needed)
            if (hasFineLocation && locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                providers.add(LocationManager.GPS_PROVIDER)
            }
            
            if (providers.isEmpty()) {
                Log.e(TAG, "No location providers available")
                return
            }
            
            // Request updates from all available providers
            // This ensures location updates continue even if one provider fails
            for (provider in providers) {
                try {
                    if (locationListener != null) {
                        locationManager.requestLocationUpdates(
                            provider,
                            LOCATION_UPDATE_INTERVAL_MS,
                            LOCATION_UPDATE_DISTANCE_M,
                            locationListener!!
                        )
                        Log.d(TAG, "Location monitoring started with provider: $provider")
                    }
                } catch (e: SecurityException) {
                    Log.e(TAG, "Security exception for provider $provider", e)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start provider $provider", e)
                }
            }
            
            Log.d(TAG, "Location monitoring started with ${providers.size} provider(s)")
        } catch (e: SecurityException) {
            Log.e(TAG, "Location permission not granted", e)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start location monitoring", e)
        }
    }
    
    /**
     * Restart location monitoring (useful when provider is disabled)
     */
    private fun restartLocationMonitoring() {
        stopLocationMonitoring()
        startLocationMonitoring()
    }
    
    private fun stopLocationMonitoring() {
        locationListener?.let {
            try {
                locationManager.removeUpdates(it)
                Log.d(TAG, "Location monitoring stopped")
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping location monitoring", e)
            }
        }
        locationListener = null
    }
    
    private suspend fun performLocationCheck() {
        try {
            // First try to get location from LocationService (if available)
            val locationServiceLat = prefs.getFloat("last_location_lat", 0f).toDouble()
            val locationServiceLng = prefs.getFloat("last_location_lng", 0f).toDouble()
            val locationServiceTime = prefs.getLong("last_location_time", 0)
            
            // Use LocationService location if it's fresh (< 1 minute old)
            if (locationServiceLat != 0.0 && locationServiceLng != 0.0 && 
                System.currentTimeMillis() - locationServiceTime < 60000) {
                Log.d(TAG, "Using LocationService location: $locationServiceLat, $locationServiceLng")
                prefs.edit()
                    .putFloat(KEY_LAST_LOCATION_LAT, locationServiceLat.toFloat())
                    .putFloat(KEY_LAST_LOCATION_LNG, locationServiceLng.toFloat())
                    .apply()
                checkLocationAtPosition(locationServiceLat, locationServiceLng)
                return
            }
            
            // Always try to get fresh location first for accuracy
            val location = getCurrentLocation()
            if (location != null) {
                Log.d(TAG, "Got fresh location: ${location.latitude}, ${location.longitude}")
                prefs.edit()
                    .putFloat(KEY_LAST_LOCATION_LAT, location.latitude.toFloat())
                    .putFloat(KEY_LAST_LOCATION_LNG, location.longitude.toFloat())
                    .apply()
                checkLocationAtPosition(location.latitude, location.longitude)
            } else {
                // Fallback to last known location
                val lastLat = prefs.getFloat(KEY_LAST_LOCATION_LAT, 0f).toDouble()
                val lastLng = prefs.getFloat(KEY_LAST_LOCATION_LNG, 0f).toDouble()
                
                if (lastLat != 0.0 && lastLng != 0.0) {
                    Log.d(TAG, "Using last known location: $lastLat, $lastLng")
                    checkLocationAtPosition(lastLat, lastLng)
                } else {
                    Log.w(TAG, "No location available - will retry when location updates")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error performing location check", e)
        }
    }
    
    private suspend fun checkLocationAtPosition(lat: Double, lng: Double) {
        if (workLocations.isEmpty()) {
            loadWorkLocations()
        }
        
        if (workLocations.isEmpty()) {
            Log.w(TAG, "No work locations configured")
            return
        }
        
        // Find if inside any location
        var insideLocation: WorkLocation? = null
        var minDistance = Double.MAX_VALUE
        
        for (location in workLocations) {
            val distance = calculateDistance(lat, lng, location.latitude, location.longitude)
            if (distance <= location.radius && distance < minDistance) {
                insideLocation = location
                minDistance = distance
            }
        }
        
        val wasInside = isInsideLocation
        val wasCheckedIn = prefs.getBoolean(KEY_IS_CHECKED_IN, false)
        
        if (insideLocation != null) {
            // Inside location
            isInsideLocation = true
            currentLocationId = insideLocation.id
            
            if (!wasInside) {
                // Just entered - start entry grace timer
                Log.d(TAG, "Entered location: ${insideLocation.name}, starting entry grace timer (1 minute)")
                startEntryGraceTimer(insideLocation.id)
            } else if (wasInside && !wasCheckedIn) {
                // Still inside but not checked in - check if entry timer expired
                val entryTimerStart = prefs.getLong(KEY_ENTRY_TIMER_START, 0)
                if (entryTimerStart > 0) {
                    val elapsed = System.currentTimeMillis() - entryTimerStart
                    if (elapsed >= GRACE_ENTRY_TIMER_MS) {
                        // Timer expired - perform check-in
                        Log.d(TAG, "Entry timer expired - performing check-in")
                        serviceScope.launch {
                            performCheckIn(insideLocation.id)
                        }
                    }
                } else {
                    // No timer running but inside and not checked in - start timer
                    Log.d(TAG, "Inside location but no timer - starting entry grace timer")
                    startEntryGraceTimer(insideLocation.id)
                }
            } else if (wasInside && wasCheckedIn) {
                // Inside and checked in - cancel any exit timer if running
                val exitTimerStart = prefs.getLong(KEY_EXIT_TIMER_START, 0)
                if (exitTimerStart > 0) {
                    Log.d(TAG, "Back inside location - cancelling exit timer")
                    cancelExitTimer()
                }
            }
        } else {
            // Outside location
            isInsideLocation = false
            currentLocationId = null
            
            if (wasInside && wasCheckedIn) {
                // Just exited while checked in - start exit grace timer
                Log.d(TAG, "Exited location, starting exit grace timer (1 minute)")
                startExitGraceTimer()
            } else if (!wasInside && wasCheckedIn) {
                // Still outside but checked in - check if exit timer expired
                val exitTimerStart = prefs.getLong(KEY_EXIT_TIMER_START, 0)
                if (exitTimerStart > 0) {
                    val elapsed = System.currentTimeMillis() - exitTimerStart
                    if (elapsed >= GRACE_EXIT_TIMER_MS) {
                        // Timer expired - perform check-out
                        Log.d(TAG, "Exit timer expired - performing check-out")
                        serviceScope.launch {
                            performCheckOut()
                        }
                    }
                } else {
                    // No timer running but outside and checked in - start timer
                    Log.d(TAG, "Outside location but no timer - starting exit grace timer")
                    startExitGraceTimer()
                }
            } else if (!wasInside && !wasCheckedIn) {
                // Outside and not checked in - cancel any entry timer if running
                val entryTimerStart = prefs.getLong(KEY_ENTRY_TIMER_START, 0)
                if (entryTimerStart > 0) {
                    Log.d(TAG, "Still outside location - cancelling entry timer")
                    cancelEntryTimer()
                }
            }
        }
        
        // Update notification
        updateNotification()
    }
    
    private fun startEntryGraceTimer(locationId: String) {
        cancelEntryTimer()
        
        val timerStart = System.currentTimeMillis()
        prefs.edit().putLong(KEY_ENTRY_TIMER_START, timerStart).apply()
        
        // Broadcast timer start
        sendBroadcast(Intent("com.example.demoapp.TIMER_START").apply {
            putExtra("type", "entry")
            putExtra("duration", 60) // 1 minute in seconds
        })
        
        // Start countdown updates (every second)
        var remainingSeconds = 60
        entryCountdownHandler = Handler(Looper.getMainLooper())
        entryCountdownRunnable = object : Runnable {
            override fun run() {
                if (remainingSeconds > 0) {
                    // Broadcast countdown update
                    sendBroadcast(Intent("com.example.demoapp.TIMER_UPDATE").apply {
                        putExtra("type", "entry")
                        putExtra("remaining", remainingSeconds)
                    })
                    remainingSeconds--
                    entryCountdownHandler?.postDelayed(this, 1000)
                } else {
                    // Timer expired
                    entryCountdownHandler?.removeCallbacks(this)
                }
            }
        }
        entryCountdownHandler?.post(entryCountdownRunnable!!)
        
        entryTimerHandler = Handler(Looper.getMainLooper())
        entryTimerRunnable = Runnable {
            Log.d(TAG, "Entry grace timer expired - performing check-in")
            // Broadcast timer complete
            sendBroadcast(Intent("com.example.demoapp.TIMER_COMPLETE").apply {
                putExtra("type", "entry")
            })
            serviceScope.launch {
                performCheckIn(locationId)
            }
            cancelEntryTimer()
        }
        
        entryTimerHandler?.postDelayed(entryTimerRunnable!!, GRACE_ENTRY_TIMER_MS)
        Log.d(TAG, "Entry grace timer started (1 minute)")
    }
    
    private fun startExitGraceTimer() {
        cancelExitTimer()
        
        val timerStart = System.currentTimeMillis()
        prefs.edit().putLong(KEY_EXIT_TIMER_START, timerStart).apply()
        
        // Broadcast timer start
        sendBroadcast(Intent("com.example.demoapp.TIMER_START").apply {
            putExtra("type", "exit")
            putExtra("duration", 60) // 1 minute in seconds
        })
        
        // Start countdown updates (every second)
        var remainingSeconds = 60
        exitCountdownHandler = Handler(Looper.getMainLooper())
        exitCountdownRunnable = object : Runnable {
            override fun run() {
                if (remainingSeconds > 0) {
                    // Broadcast countdown update
                    sendBroadcast(Intent("com.example.demoapp.TIMER_UPDATE").apply {
                        putExtra("type", "exit")
                        putExtra("remaining", remainingSeconds)
                    })
                    remainingSeconds--
                    exitCountdownHandler?.postDelayed(this, 1000)
                } else {
                    // Timer expired
                    exitCountdownHandler?.removeCallbacks(this)
                }
            }
        }
        exitCountdownHandler?.post(exitCountdownRunnable!!)
        
        exitTimerHandler = Handler(Looper.getMainLooper())
        exitTimerRunnable = Runnable {
            Log.d(TAG, "Exit grace timer expired - performing check-out")
            // Broadcast timer complete
            sendBroadcast(Intent("com.example.demoapp.TIMER_COMPLETE").apply {
                putExtra("type", "exit")
            })
            serviceScope.launch {
                performCheckOut()
            }
            cancelExitTimer()
        }
        
        exitTimerHandler?.postDelayed(exitTimerRunnable!!, GRACE_EXIT_TIMER_MS)
        Log.d(TAG, "Exit grace timer started (1 minute)")
    }
    
    private fun cancelEntryTimer() {
        entryTimerHandler?.removeCallbacks(entryTimerRunnable ?: return)
        entryTimerHandler = null
        entryTimerRunnable = null
        entryCountdownHandler?.removeCallbacks(entryCountdownRunnable ?: return)
        entryCountdownHandler = null
        entryCountdownRunnable = null
        prefs.edit().remove(KEY_ENTRY_TIMER_START).apply()
        // Broadcast timer cancelled
        sendBroadcast(Intent("com.example.demoapp.TIMER_CANCELLED").apply {
            putExtra("type", "entry")
        })
    }
    
    private fun cancelExitTimer() {
        exitTimerHandler?.removeCallbacks(exitTimerRunnable ?: return)
        exitTimerHandler = null
        exitTimerRunnable = null
        exitCountdownHandler?.removeCallbacks(exitCountdownRunnable ?: return)
        exitCountdownHandler = null
        exitCountdownRunnable = null
        prefs.edit().remove(KEY_EXIT_TIMER_START).apply()
        // Broadcast timer cancelled
        sendBroadcast(Intent("com.example.demoapp.TIMER_CANCELLED").apply {
            putExtra("type", "exit")
        })
    }
    
    private fun cancelGraceTimers() {
        cancelEntryTimer()
        cancelExitTimer()
    }
    
    private suspend fun performCheckIn(locationId: String) {
        // Check if auto check-in is disabled (manual toggle OFF)
        if (isAutoCheckInDisabled()) {
            Log.d(TAG, "Auto check-in disabled (manual toggle OFF) - skipping")
            return
        }
        
        if (prefs.getBoolean(KEY_IS_CHECKED_IN, false)) {
            Log.d(TAG, "Already checked in, skipping")
            return
        }
        
        try {
            Log.d(TAG, "🚀 Performing check-in for location: $locationId")
            
            // Get current location with retry
            var location = getCurrentLocation()
            if (location == null) {
                Log.w(TAG, "No location available, waiting 2 seconds and retrying...")
                delay(2000)
                location = getCurrentLocation()
            }
            
            if (location == null) {
                Log.e(TAG, "❌ Cannot get current location for check-in after retry")
                // Try to use last known location
                val lastLat = prefs.getFloat(KEY_LAST_LOCATION_LAT, 0f).toDouble()
                val lastLng = prefs.getFloat(KEY_LAST_LOCATION_LNG, 0f).toDouble()
                if (lastLat != 0.0 && lastLng != 0.0) {
                    Log.d(TAG, "Using last known location: $lastLat, $lastLng")
                    location = android.location.Location("last_known").apply {
                        latitude = lastLat
                        longitude = lastLng
                    }
                } else {
                    Log.e(TAG, "❌ No location available for check-in")
                    return
                }
            }
            
            Log.d(TAG, "📍 Check-in location: ${location.latitude}, ${location.longitude}")
            
            // Call check-in API with retry
            var apiSuccess = false
            var retryCount = 0
            val maxRetries = 3
            
            while (!apiSuccess && retryCount < maxRetries) {
                apiSuccess = withContext(Dispatchers.IO) {
                    callCheckInAPI(location!!.latitude, location!!.longitude)
                }
                
                if (!apiSuccess && retryCount < maxRetries - 1) {
                    retryCount++
                    Log.w(TAG, "⚠️ Check-in API call failed, retrying ($retryCount/$maxRetries)...")
                    delay(2000) // Wait 2 seconds before retry
                } else {
                    break
                }
            }
            
            if (apiSuccess) {
                // Save check-in state only after successful API call
                val checkInTime = System.currentTimeMillis()
                prefs.edit()
                    .putBoolean(KEY_IS_CHECKED_IN, true)
                    .putString(KEY_LOCATION_ID, locationId)
                    .putLong(KEY_CHECK_IN_TIME, checkInTime)
                    .apply()
                
                // Save to Room database for offline support
                saveEventToDatabase(
                    eventType = "CHECK_IN",
                    latitude = location.latitude,
                    longitude = location.longitude,
                    locationId = locationId,
                    notes = "Auto check-in",
                    isAuto = true
                )
                
                // Cancel entry timer
                cancelEntryTimer()
                
                // Notify Flutter app via broadcast
                sendBroadcast(Intent("com.example.demoapp.CHECK_IN").apply {
                    putExtra("location_id", locationId)
                    putExtra("timestamp", checkInTime)
                })
                
                Log.d(TAG, "✅ Check-in completed successfully - API called and state saved")
                updateNotification()
            } else {
                Log.e(TAG, "❌ Check-in API call failed after $maxRetries attempts")
                
                // Save to database even if API failed (offline support)
                saveEventToDatabase(
                    eventType = "CHECK_IN",
                    latitude = location.latitude,
                    longitude = location.longitude,
                    locationId = locationId,
                    notes = "Auto check-in (offline)",
                    isAuto = true,
                    synced = false
                )
                
                // Trigger sync worker
                AttendanceSyncWorker.enqueueImmediateSync(this)
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error performing check-in", e)
            e.printStackTrace()
        }
    }
    
    private suspend fun performCheckOut() {
        if (!prefs.getBoolean(KEY_IS_CHECKED_IN, false)) {
            Log.d(TAG, "Not checked in, skipping check-out")
            return
        }
        
        try {
            Log.d(TAG, "🚀 Performing check-out")
            
            // Get current location with retry
            var location = getCurrentLocation()
            if (location == null) {
                Log.w(TAG, "No location available, waiting 2 seconds and retrying...")
                delay(2000)
                location = getCurrentLocation()
            }
            
            if (location == null) {
                Log.e(TAG, "❌ Cannot get current location for check-out after retry")
                // Try to use last known location
                val lastLat = prefs.getFloat(KEY_LAST_LOCATION_LAT, 0f).toDouble()
                val lastLng = prefs.getFloat(KEY_LAST_LOCATION_LNG, 0f).toDouble()
                if (lastLat != 0.0 && lastLng != 0.0) {
                    Log.d(TAG, "Using last known location: $lastLat, $lastLng")
                    location = android.location.Location("last_known").apply {
                        latitude = lastLat
                        longitude = lastLng
                    }
                } else {
                    Log.e(TAG, "❌ No location available for check-out")
                    return
                }
            }
            
            Log.d(TAG, "📍 Check-out location: ${location.latitude}, ${location.longitude}")
            
            // Call check-out API with retry
            var apiSuccess = false
            var retryCount = 0
            val maxRetries = 3
            
            while (!apiSuccess && retryCount < maxRetries) {
                apiSuccess = withContext(Dispatchers.IO) {
                    callCheckOutAPI(location!!.latitude, location!!.longitude)
                }
                
                if (!apiSuccess && retryCount < maxRetries - 1) {
                    retryCount++
                    Log.w(TAG, "⚠️ Check-out API call failed, retrying ($retryCount/$maxRetries)...")
                    delay(2000) // Wait 2 seconds before retry
                } else {
                    break
                }
            }
            
            if (apiSuccess) {
                // Save check-out state only after successful API call
                val checkOutTime = System.currentTimeMillis()
                prefs.edit()
                    .putBoolean(KEY_IS_CHECKED_IN, false)
                    .remove(KEY_LOCATION_ID)
                    .remove(KEY_CHECK_IN_TIME)
                    .apply()
                
                // Save to Room database for offline support
                saveEventToDatabase(
                    eventType = "CHECK_OUT",
                    latitude = location.latitude,
                    longitude = location.longitude,
                    locationId = null,
                    notes = "Auto check-out",
                    isAuto = true
                )
                
                // Cancel exit timer
                cancelExitTimer()
                
                // Notify Flutter app via broadcast
                sendBroadcast(Intent("com.example.demoapp.CHECK_OUT").apply {
                    putExtra("timestamp", checkOutTime)
                })
                
                Log.d(TAG, "✅ Check-out completed successfully - API called and state saved")
                updateNotification()
            } else {
                Log.e(TAG, "❌ Check-out API call failed after $maxRetries attempts")
                
                // Save to database even if API failed (offline support)
                saveEventToDatabase(
                    eventType = "CHECK_OUT",
                    latitude = location.latitude,
                    longitude = location.longitude,
                    locationId = null,
                    notes = "Auto check-out (offline)",
                    isAuto = true,
                    synced = false
                )
                
                // Trigger sync worker
                AttendanceSyncWorker.enqueueImmediateSync(this)
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error performing check-out", e)
            e.printStackTrace()
        }
    }
    
    private fun callCheckInAPI(latitude: Double, longitude: Double): Boolean {
        return try {
            // Get API base URL from service prefs or Flutter prefs
            val baseUrl = prefs.getString(KEY_API_BASE_URL, null)
                ?: flutterPrefs.getString("flutter.api_base_url", null)
                ?: "http://103.14.120.163:8092/api"
            
            // Get auth token from service prefs or Flutter SharedPreferences
            val authToken = prefs.getString(KEY_AUTH_TOKEN, null)
                ?: flutterPrefs.getString("flutter.auth_token", null)
                ?: flutterPrefs.getString("auth_token", null)
            
            if (authToken.isNullOrEmpty()) {
                Log.e(TAG, "❌ Auth token is missing - cannot call check-in API")
                return false
            }
            
            val url = "$baseUrl/attendance/check-in"
            Log.d(TAG, "📡 Calling check-in API: $url")
            Log.d(TAG, "📍 Location: $latitude, $longitude")
            Log.d(TAG, "🔑 Auth token present: ${authToken.isNotEmpty()}")
            
            val json = JSONObject().apply {
                put("latitude", latitude)
                put("longitude", longitude)
                put("notes", "Auto check-in")
            }
            
            val requestBody = json.toString().toRequestBody("application/json".toMediaType())
            
            val requestBuilder = Request.Builder()
                .url(url)
                .post(requestBody)
                .addHeader("Content-Type", "application/json")
                .addHeader("Accept", "application/json")
            
            if (authToken.isNotEmpty()) {
                requestBuilder.addHeader("Authorization", "Bearer $authToken")
            }
            
            val request = requestBuilder.build()
            
            val response = httpClient.newCall(request).execute()
            val responseBody = response.body?.string()
            val success = response.isSuccessful
            
            if (success) {
                Log.d(TAG, "✅ Check-in API call successful: ${response.code}")
                Log.d(TAG, "📦 Response: $responseBody")
            } else {
                Log.e(TAG, "❌ Check-in API call failed: ${response.code}")
                Log.e(TAG, "📦 Error response: $responseBody")
            }
            
            response.close()
            success
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error calling check-in API", e)
            e.printStackTrace()
            false
        }
    }
    
    private fun callCheckOutAPI(latitude: Double, longitude: Double): Boolean {
        return try {
            // Get API base URL from service prefs or Flutter prefs
            val baseUrl = prefs.getString(KEY_API_BASE_URL, null)
                ?: flutterPrefs.getString("flutter.api_base_url", null)
                ?: "http://103.14.120.163:8092/api"
            
            // Get auth token from service prefs or Flutter SharedPreferences
            val authToken = prefs.getString(KEY_AUTH_TOKEN, null)
                ?: flutterPrefs.getString("flutter.auth_token", null)
                ?: flutterPrefs.getString("auth_token", null)
            
            if (authToken.isNullOrEmpty()) {
                Log.e(TAG, "❌ Auth token is missing - cannot call check-out API")
                return false
            }
            
            val url = "$baseUrl/attendance/check-out"
            Log.d(TAG, "📡 Calling check-out API: $url")
            Log.d(TAG, "📍 Location: $latitude, $longitude")
            Log.d(TAG, "🔑 Auth token present: ${authToken.isNotEmpty()}")
            
            val json = JSONObject().apply {
                put("latitude", latitude)
                put("longitude", longitude)
                put("notes", "Auto check-out")
            }
            
            val requestBody = json.toString().toRequestBody("application/json".toMediaType())
            
            val requestBuilder = Request.Builder()
                .url(url)
                .post(requestBody)
                .addHeader("Content-Type", "application/json")
                .addHeader("Accept", "application/json")
            
            if (authToken.isNotEmpty()) {
                requestBuilder.addHeader("Authorization", "Bearer $authToken")
            }
            
            val request = requestBuilder.build()
            
            val response = httpClient.newCall(request).execute()
            val responseBody = response.body?.string()
            val success = response.isSuccessful
            
            if (success) {
                Log.d(TAG, "✅ Check-out API call successful: ${response.code}")
                Log.d(TAG, "📦 Response: $responseBody")
            } else {
                Log.e(TAG, "❌ Check-out API call failed: ${response.code}")
                Log.e(TAG, "📦 Error response: $responseBody")
            }
            
            response.close()
            success
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error calling check-out API", e)
            e.printStackTrace()
            false
        }
    }
    
    private fun startDeepValidation() {
        cancelDeepValidation()
        
        deepValidationHandler = Handler(Looper.getMainLooper())
        deepValidationRunnable = Runnable {
            Log.d(TAG, "Performing deep validation (30 minutes)")
            serviceScope.launch {
                performLocationCheck()
            }
            // Schedule next validation
            deepValidationHandler?.postDelayed(deepValidationRunnable!!, DEEP_VALIDATION_INTERVAL_MS)
        }
        
        deepValidationHandler?.postDelayed(deepValidationRunnable!!, DEEP_VALIDATION_INTERVAL_MS)
    }
    
    private fun cancelDeepValidation() {
        deepValidationHandler?.removeCallbacks(deepValidationRunnable ?: return)
        deepValidationHandler = null
        deepValidationRunnable = null
    }
    
    private fun getCurrentLocation(): Location? {
        return try {
            val hasFineLocation = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
            val hasCoarseLocation = checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
            
            if (!hasFineLocation && !hasCoarseLocation) {
                Log.w(TAG, "No location permissions granted")
                return null
            }
            
            // Try to get location from all available providers
            // Order: GPS (most accurate) -> Network -> Passive
            val providers = locationManager.getProviders(true)
            var bestLocation: Location? = null
            var bestAccuracy = Float.MAX_VALUE
            
            for (provider in providers) {
                try {
                    val location = locationManager.getLastKnownLocation(provider)
                    if (location != null) {
                        // Prefer location with better accuracy
                        if (location.accuracy < bestAccuracy) {
                            bestLocation = location
                            bestAccuracy = location.accuracy
                        }
                    }
                } catch (e: SecurityException) {
                    // Skip this provider if no permission
                    continue
                } catch (e: Exception) {
                    // Log but continue trying other providers
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Log.w(TAG, "Error getting location from $provider: ${e.message}")
                    }
                }
            }
            
            bestLocation
        } catch (e: SecurityException) {
            Log.e(TAG, "Location permission not granted", e)
            null
        } catch (e: Exception) {
            Log.e(TAG, "Error getting current location", e)
            null
        }
    }
    
    private fun calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val results = FloatArray(1)
        Location.distanceBetween(lat1, lon1, lat2, lon2, results)
        return results[0].toDouble()
    }
    
    private fun loadWorkLocations() {
        try {
            val locationsJson = prefs.getString(KEY_WORK_LOCATIONS, null)
            if (locationsJson != null) {
                workLocations = parseWorkLocations(locationsJson)
                Log.d(TAG, "Loaded ${workLocations.size} work locations")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error loading work locations", e)
        }
    }
    
    private fun updateWorkLocations(locationsJson: String) {
        try {
            prefs.edit().putString(KEY_WORK_LOCATIONS, locationsJson).apply()
            workLocations = parseWorkLocations(locationsJson)
            Log.d(TAG, "Updated work locations: ${workLocations.size} locations")
        } catch (e: Exception) {
            Log.e(TAG, "Error updating work locations", e)
        }
    }
    
    private fun parseWorkLocations(json: String): List<WorkLocation> {
        // Simple JSON parsing - expects format: [{"id":"...","name":"...","latitude":...,"longitude":...,"radius":...},...]
        val locations = mutableListOf<WorkLocation>()
        try {
            val jsonArray = org.json.JSONArray(json)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                locations.add(WorkLocation(
                    id = obj.getString("id"),
                    name = obj.getString("name"),
                    latitude = obj.getDouble("latitude"),
                    longitude = obj.getDouble("longitude"),
                    radius = obj.getDouble("radius")
                ))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing work locations JSON", e)
        }
        return locations
    }
    
    private fun restoreState() {
        isServiceRunning = prefs.getBoolean(KEY_IS_ENABLED, false)
        val wasCheckedIn = prefs.getBoolean(KEY_IS_CHECKED_IN, false)
        currentLocationId = prefs.getString(KEY_LOCATION_ID, null)
        
        if (isServiceRunning) {
            Log.d(TAG, "Restoring service state: checkedIn=$wasCheckedIn, locationId=$currentLocationId")
            loadWorkLocations()
        }
    }
    
    private fun restoreGraceTimers() {
        if (!isServiceRunning) return
        
        val entryTimerStart = prefs.getLong(KEY_ENTRY_TIMER_START, 0)
        val exitTimerStart = prefs.getLong(KEY_EXIT_TIMER_START, 0)
        val isCheckedIn = prefs.getBoolean(KEY_IS_CHECKED_IN, false)
        
        if (entryTimerStart > 0) {
            val elapsed = System.currentTimeMillis() - entryTimerStart
            val remaining = GRACE_ENTRY_TIMER_MS - elapsed
            
            if (remaining > 0 && !isCheckedIn) {
                // Restore entry timer
                val locationId = prefs.getString(KEY_LOCATION_ID, null) ?: return
                entryTimerHandler = Handler(Looper.getMainLooper())
                entryTimerRunnable = Runnable {
                    Log.d(TAG, "Restored entry timer expired - performing check-in")
                    serviceScope.launch {
                        performCheckIn(locationId)
                    }
                    cancelEntryTimer()
                }
                entryTimerHandler?.postDelayed(entryTimerRunnable!!, remaining)
                Log.d(TAG, "Restored entry grace timer with $remaining ms remaining")
            } else if (remaining <= 0 && !isCheckedIn) {
                // Timer expired while app was closed - perform check-in now
                val locationId = prefs.getString(KEY_LOCATION_ID, null)
                if (locationId != null) {
                    serviceScope.launch {
                        performCheckIn(locationId)
                    }
                }
                cancelEntryTimer()
            }
        }
        
        if (exitTimerStart > 0) {
            val elapsed = System.currentTimeMillis() - exitTimerStart
            val remaining = GRACE_EXIT_TIMER_MS - elapsed
            
            if (remaining > 0 && isCheckedIn) {
                // Restore exit timer
                exitTimerHandler = Handler(Looper.getMainLooper())
                exitTimerRunnable = Runnable {
                    Log.d(TAG, "Restored exit timer expired - performing check-out")
                    serviceScope.launch {
                        performCheckOut()
                    }
                    cancelExitTimer()
                }
                exitTimerHandler?.postDelayed(exitTimerRunnable!!, remaining)
                Log.d(TAG, "Restored exit grace timer with $remaining ms remaining")
            } else if (remaining <= 0 && isCheckedIn) {
                // Timer expired while app was closed - perform check-out now
                serviceScope.launch {
                    performCheckOut()
                }
                cancelExitTimer()
            }
        }
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Monitors your location for automatic attendance tracking"
                    setShowBadge(false)
                    // Enable vibration and sound for important notifications
                    enableVibration(false)
                    setSound(null, null)
                    // Set importance to low to reduce interruption
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                
                val notificationManager = getSystemService(NotificationManager::class.java)
                notificationManager.createNotificationChannel(channel)
                Log.d(TAG, "Notification channel created")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create notification channel", e)
                // Continue anyway - notification may still work
            }
        }
    }
    
    private fun createNotification(): Notification {
        val isCheckedIn = prefs.getBoolean(KEY_IS_CHECKED_IN, false)
        val locationId = prefs.getString(KEY_LOCATION_ID, null)
        val statusText = if (isCheckedIn) {
            "Checked in${if (locationId != null) " at $locationId" else ""}"
        } else {
            "Monitoring location..."
        }
        
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Attendance Monitoring")
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
    
    private fun updateNotification() {
        if (isServiceRunning) {
            val notificationManager = NotificationManagerCompat.from(this)
            notificationManager.notify(NOTIFICATION_ID, createNotification())
        }
    }
    
    override fun onDestroy() {
        Log.d(TAG, "Service onDestroy")
        cancelGraceTimers()
        cancelDeepValidation()
        stopLocationMonitoring()
        serviceScope.cancel()
        super.onDestroy()
    }
    
    /**
     * Save attendance event to Room database for offline support
     */
    private suspend fun saveEventToDatabase(
        eventType: String,
        latitude: Double,
        longitude: Double,
        locationId: String?,
        notes: String?,
        isAuto: Boolean,
        synced: Boolean = true
    ) {
        try {
            val event = AttendanceEvent(
                id = "${eventType}_${System.currentTimeMillis()}",
                eventType = eventType,
                timestamp = System.currentTimeMillis(),
                latitude = latitude,
                longitude = longitude,
                locationId = locationId,
                locationName = workLocations.find { it.id == locationId }?.name,
                notes = notes,
                isAuto = isAuto,
                synced = synced,
                syncedAt = if (synced) System.currentTimeMillis() else null
            )
            
            database.attendanceDao().insertEvent(event)
            Log.d(TAG, "✅ Event saved to database: ${event.id}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error saving event to database: ${e.message}", e)
        }
    }
    
    /**
     * Handle manual toggle OFF - perform final check-out and disable auto check-in
     */
    private fun handleManualToggleOff() {
        Log.d(TAG, "Manual toggle OFF - performing final check-out")
        
        serviceScope.launch {
            // Perform check-out
            performCheckOut()
            
            // Disable auto check-in until next day
            val today = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis
            
            prefs.edit()
                .putBoolean(KEY_AUTO_CHECKIN_DISABLED, true)
                .putLong(KEY_MANUAL_TOGGLE_OFF_DATE, today)
                .apply()
            
            // Cancel any entry timer
            cancelEntryTimer()
            
            Log.d(TAG, "✅ Manual toggle OFF - auto check-in disabled until next day")
            
            // Notify Flutter
            sendBroadcast(Intent("com.example.demoapp.MANUAL_TOGGLE_OFF").apply {
                putExtra("timestamp", System.currentTimeMillis())
            })
        }
    }
    
    /**
     * Check if auto check-in is disabled (manual toggle OFF)
     */
    private fun isAutoCheckInDisabled(): Boolean {
        val isDisabled = prefs.getBoolean(KEY_AUTO_CHECKIN_DISABLED, false)
        if (!isDisabled) return false
        
        // Check if it's a new day - reset flag
        val toggleOffDate = prefs.getLong(KEY_MANUAL_TOGGLE_OFF_DATE, 0)
        val today = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        
        if (toggleOffDate < today) {
            // New day - reset flag
            prefs.edit()
                .putBoolean(KEY_AUTO_CHECKIN_DISABLED, false)
                .remove(KEY_MANUAL_TOGGLE_OFF_DATE)
                .apply()
            Log.d(TAG, "New day - auto check-in re-enabled")
            return false
        }
        
        return true
    }
    
    /**
     * Check if new day and reset manual toggle flag
     */
    private fun checkAndResetManualToggleFlag() {
        val toggleOffDate = prefs.getLong(KEY_MANUAL_TOGGLE_OFF_DATE, 0)
        if (toggleOffDate == 0L) return
        
        val today = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        
        if (toggleOffDate < today) {
            // New day - reset flag
            prefs.edit()
                .putBoolean(KEY_AUTO_CHECKIN_DISABLED, false)
                .remove(KEY_MANUAL_TOGGLE_OFF_DATE)
                .apply()
            Log.d(TAG, "New day detected - manual toggle flag reset")
        }
    }
    
    // Data class for work location
    data class WorkLocation(
        val id: String,
        val name: String,
        val latitude: Double,
        val longitude: Double,
        val radius: Double
    )
}

