package com.example.demoapp

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val PREFS_NAME = "app_prefs"
        private const val KEY_FIRST_LAUNCH = "first_launch"
        private const val KEY_PERMISSIONS_REQUESTED = "permissions_requested"
    }
    private val CHANNEL = "com.example.demoapp/power"
    private val ATTENDANCE_SERVICE_CHANNEL = "com.example.demoapp/attendance_service"
    private val ATTENDANCE_EVENTS_CHANNEL = "com.example.demoapp/attendance_events"
    private lateinit var powerManager: PowerManager
    private var eventSink: EventChannel.EventSink? = null
    private var attendanceEventReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        powerManager = getSystemService(POWER_SERVICE) as PowerManager
        
        // Handle first launch - request permissions and disable battery optimizations
        handleFirstLaunch()

        // Power management channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestIgnoreBatteryOptimizations" -> {
                    val success = requestBatteryOptimizationExemption()
                    result.success(success)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val isIgnoring = isBatteryOptimizationIgnored()
                    result.success(isIgnoring)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Attendance service channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ATTENDANCE_SERVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    try {
                        val locationsJson = call.argument<String>("locations_json")
                        val apiBaseUrl = call.argument<String>("api_base_url")
                        val authToken = call.argument<String>("auth_token")
                        
                        // Start LocationService first for continuous location tracking
                        startLocationService()
                        
                        // Then start ForegroundAttendanceService
                        startForegroundService(locationsJson, apiBaseUrl, authToken)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to start service: ${e.message}", null)
                    }
                }
                "stopForegroundService" -> {
                    try {
                        stopForegroundService()
                        stopLocationService()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to stop service: ${e.message}", null)
                    }
                }
                "updateWorkLocations" -> {
                    try {
                        val locationsJson = call.argument<String>("locations_json")
                        if (locationsJson != null) {
                            updateWorkLocations(locationsJson)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENT", "locations_json is required", null)
                        }
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to update locations: ${e.message}", null)
                    }
                }
                "isServiceRunning" -> {
                    result.success(isServiceRunning())
                }
                "manualToggleOff" -> {
                    try {
                        manualToggleOff()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to toggle off: ${e.message}", null)
                    }
                }
                "requestPermissions" -> {
                    requestAllPermissions()
                    result.success(true)
                }
                "hasAllPermissions" -> {
                    result.success(PermissionHelper.hasAllPermissions(this))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Attendance events channel (for receiving check-in/check-out events)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ATTENDANCE_EVENTS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerAttendanceEventReceiver()
                }
                
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    unregisterAttendanceEventReceiver()
                }
            }
        )
    }
    
    private fun registerAttendanceEventReceiver() {
        if (attendanceEventReceiver != null) return
        
        attendanceEventReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    "com.example.demoapp.CHECK_IN" -> {
                        val locationId = intent.getStringExtra("location_id")
                        val timestamp = intent.getLongExtra("timestamp", 0)
                        eventSink?.success(mapOf(
                            "type" to "checkIn",
                            "location_id" to (locationId ?: ""),
                            "timestamp" to timestamp
                        ))
                    }
                    "com.example.demoapp.CHECK_OUT" -> {
                        val timestamp = intent.getLongExtra("timestamp", 0)
                        eventSink?.success(mapOf(
                            "type" to "checkOut",
                            "timestamp" to timestamp
                        ))
                    }
                    "com.example.demoapp.TIMER_START" -> {
                        val timerType = intent.getStringExtra("type")
                        val duration = intent.getIntExtra("duration", 120)
                        eventSink?.success(mapOf(
                            "type" to "timerStart",
                            "timerType" to timerType,
                            "duration" to duration
                        ))
                    }
                    "com.example.demoapp.TIMER_UPDATE" -> {
                        val timerType = intent.getStringExtra("type")
                        val remaining = intent.getIntExtra("remaining", 0)
                        eventSink?.success(mapOf(
                            "type" to "timerUpdate",
                            "timerType" to timerType,
                            "remaining" to remaining
                        ))
                    }
                    "com.example.demoapp.TIMER_COMPLETE" -> {
                        val timerType = intent.getStringExtra("type")
                        eventSink?.success(mapOf(
                            "type" to "timerComplete",
                            "timerType" to timerType
                        ))
                    }
                    "com.example.demoapp.TIMER_CANCELLED" -> {
                        val timerType = intent.getStringExtra("type")
                        eventSink?.success(mapOf(
                            "type" to "timerCancelled",
                            "timerType" to timerType
                        ))
                    }
                }
            }
        }
        
        val filter = IntentFilter().apply {
            addAction("com.example.demoapp.CHECK_IN")
            addAction("com.example.demoapp.CHECK_OUT")
            addAction("com.example.demoapp.TIMER_START")
            addAction("com.example.demoapp.TIMER_UPDATE")
            addAction("com.example.demoapp.TIMER_COMPLETE")
            addAction("com.example.demoapp.TIMER_CANCELLED")
        }
        registerReceiver(attendanceEventReceiver, filter)
    }
    
    private fun unregisterAttendanceEventReceiver() {
        attendanceEventReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                // Receiver not registered
            }
        }
        attendanceEventReceiver = null
    }
    
    override fun onDestroy() {
        super.onDestroy()
        unregisterAttendanceEventReceiver()
    }
    
    private fun startLocationService() {
        try {
            val intent = Intent(this, LocationService::class.java).apply {
                action = LocationService.ACTION_START
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(this, intent)
            } else {
                startService(intent)
            }
            Log.d(TAG, "LocationService started")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting LocationService", e)
        }
    }
    
    private fun stopLocationService() {
        try {
            val intent = Intent(this, LocationService::class.java).apply {
                action = LocationService.ACTION_STOP
            }
            stopService(intent)
            Log.d(TAG, "LocationService stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping LocationService", e)
        }
    }
    
    private fun startForegroundService(locationsJson: String?, apiBaseUrl: String? = null, authToken: String? = null) {
        val intent = Intent(this, ForegroundAttendanceService::class.java).apply {
            action = ForegroundAttendanceService.ACTION_START
            if (locationsJson != null) {
                putExtra("locations_json", locationsJson)
            }
            if (apiBaseUrl != null) {
                putExtra("api_base_url", apiBaseUrl)
            }
            if (authToken != null) {
                putExtra("auth_token", authToken)
            }
        }
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
    
    private fun stopForegroundService() {
        val intent = Intent(this, ForegroundAttendanceService::class.java).apply {
            action = ForegroundAttendanceService.ACTION_STOP
        }
        stopService(intent)
    }
    
    private fun updateWorkLocations(locationsJson: String) {
        val intent = Intent(this, ForegroundAttendanceService::class.java).apply {
            action = ForegroundAttendanceService.ACTION_UPDATE_LOCATIONS
            putExtra("locations_json", locationsJson)
        }
        startService(intent)
    }
    
    private fun isServiceRunning(): Boolean {
        // Check if service is running by checking SharedPreferences
        val prefs = getSharedPreferences("attendance_service_prefs", MODE_PRIVATE)
        return prefs.getBoolean("is_enabled", false)
    }

    private fun requestBatteryOptimizationExemption(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val packageName = packageName
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
                true
            } else {
                true // Pre-Marshmallow doesn't have battery optimizations
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val packageName = packageName
                powerManager.isIgnoringBatteryOptimizations(packageName)
            } else {
                true // Pre-Marshmallow doesn't have battery optimizations
            }
        } catch (e: Exception) {
            false
        }
    }
    
    private fun manualToggleOff() {
        val intent = Intent(this, ForegroundAttendanceService::class.java).apply {
            action = ForegroundAttendanceService.ACTION_MANUAL_TOGGLE_OFF
        }
        startService(intent)
    }
    
    private fun requestAllPermissions() {
        // Only request if not already requested to avoid multiple prompts
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val permissionsRequested = prefs.getBoolean(KEY_PERMISSIONS_REQUESTED, false)
        
        if (!permissionsRequested) {
            Log.d(TAG, "Requesting permissions for first time")
            PermissionHelper.requestAllPermissions(this)
            prefs.edit().putBoolean(KEY_PERMISSIONS_REQUESTED, true).apply()
        } else {
            Log.d(TAG, "Permissions already requested - checking status")
            // Check if permissions are missing and request again
            if (!PermissionHelper.hasAllPermissions(this)) {
                Log.d(TAG, "Some permissions missing - requesting again")
                PermissionHelper.requestAllPermissions(this)
            }
        }
    }
    
    /**
     * Handle first launch - request permissions and disable battery optimizations
     */
    private fun handleFirstLaunch() {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val isFirstLaunch = prefs.getBoolean(KEY_FIRST_LAUNCH, true)
            
            if (isFirstLaunch) {
                Log.d(TAG, "First launch detected - setting up app")
                
                // Mark as not first launch
                prefs.edit().putBoolean(KEY_FIRST_LAUNCH, false).apply()
                
                // Request battery optimization exemption on first launch
                // This is critical for background location to work in release
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    if (!isBatteryOptimizationIgnored()) {
                        Log.d(TAG, "Requesting battery optimization exemption")
                        // Request will show system dialog - user must approve
                        window.decorView.postDelayed({
                            requestBatteryOptimizationExemption()
                        }, 1000)
                    }
                }
                
                // Request permissions after a short delay to ensure activity is ready
                window.decorView.postDelayed({
                    if (!PermissionHelper.hasAllPermissions(this)) {
                        Log.d(TAG, "Requesting permissions on first launch")
                        requestAllPermissions()
                    }
                }, 500)
            } else {
                // Not first launch - just check if permissions are granted
                if (!PermissionHelper.hasAllPermissions(this)) {
                    Log.d(TAG, "Permissions missing - requesting")
                    window.decorView.postDelayed({
                        requestAllPermissions()
                    }, 500)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in handleFirstLaunch", e)
        }
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        Log.d(TAG, "onRequestPermissionsResult: requestCode=$requestCode")
        
        when (requestCode) {
            PermissionHelper.PERMISSION_REQUEST_CODE -> {
                val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                Log.d(TAG, "Foreground permissions granted: $allGranted")
                
                // Check if foreground location granted, then request background
                if (PermissionHelper.hasForegroundLocationPermission(this) &&
                    !PermissionHelper.hasBackgroundLocationPermission(this) &&
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    Log.d(TAG, "Requesting background location permission")
                    // Delay to avoid showing two dialogs at once
                    window.decorView.postDelayed({
                        PermissionHelper.requestBackgroundLocationPermission(this)
                    }, 1000)
                }
            }
            PermissionHelper.BACKGROUND_LOCATION_REQUEST_CODE -> {
                val granted = grantResults.isNotEmpty() && 
                             grantResults[0] == PackageManager.PERMISSION_GRANTED
                Log.d(TAG, "Background location permission granted: $granted")
                
                if (!granted) {
                    Log.w(TAG, "Background location not granted - app may have limited functionality")
                }
            }
        }
    }
    
    override fun onResume() {
        super.onResume()
        // Check battery optimization status when app resumes
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!isBatteryOptimizationIgnored()) {
                Log.w(TAG, "Battery optimization not ignored - background location may be limited")
            }
        }
    }
}
