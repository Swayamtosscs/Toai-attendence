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
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

class LocationService : Service() {
    companion object {
        private const val TAG = "LocationService"
        private const val NOTIFICATION_ID = 1002
        private const val CHANNEL_ID = "location_service_channel"
        private const val CHANNEL_NAME = "Location Tracking"
        
        const val ACTION_START = "com.example.demoapp.LOCATION_SERVICE_START"
        const val ACTION_STOP = "com.example.demoapp.LOCATION_SERVICE_STOP"
        
        private const val LOCATION_UPDATE_INTERVAL_MS = 15_000L // 15 seconds
        private const val LOCATION_UPDATE_DISTANCE_M = 5f // 5 meters
    }
    
    private lateinit var locationManager: LocationManager
    private lateinit var powerManager: PowerManager
    private lateinit var wakeLock: PowerManager.WakeLock
    private var locationListener: LocationListener? = null
    private val handler = Handler(Looper.getMainLooper())
    private var isRunning = false
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "LocationService onCreate")
        
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$TAG::WakeLock")
        wakeLock.setReferenceCounted(false)
        
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: ${intent?.action}")
        
        when (intent?.action) {
            ACTION_START -> {
                startLocationTracking()
            }
            ACTION_STOP -> {
                stopLocationTracking()
                stopSelf()
            }
        }
        
        return START_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    private fun startLocationTracking() {
        if (isRunning) {
            Log.d(TAG, "Location tracking already running")
            return
        }
        
        // Check permissions
        val hasFineLocation = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
        val hasCoarseLocation = checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
        
        if (!hasFineLocation && !hasCoarseLocation) {
            Log.e(TAG, "Location permissions not granted")
            stopSelf()
            return
        }
        
        Log.d(TAG, "Starting location tracking")
        isRunning = true
        
        // Acquire wake lock to keep CPU running
        if (!wakeLock.isHeld) {
            wakeLock.acquire(10 * 60 * 60 * 1000L) // 10 hours max
        }
        
        // Start foreground service
        startForeground(NOTIFICATION_ID, createNotification())
        
        // Start location updates
        startLocationUpdates()
        
        // Periodic location check to ensure updates continue
        handler.postDelayed(periodicLocationCheck, LOCATION_UPDATE_INTERVAL_MS)
    }
    
    private fun stopLocationTracking() {
        if (!isRunning) {
            return
        }
        
        Log.d(TAG, "Stopping location tracking")
        isRunning = false
        
        // Release wake lock
        if (wakeLock.isHeld) {
            wakeLock.release()
        }
        
        // Stop location updates
        stopLocationUpdates()
        
        // Cancel periodic check
        handler.removeCallbacks(periodicLocationCheck)
        
        stopForeground(true)
    }
    
    private fun startLocationUpdates() {
        if (locationListener != null) {
            return
        }
        
        try {
            locationListener = object : LocationListener {
                override fun onLocationChanged(location: Location) {
                    Log.d(TAG, "Location: ${location.latitude}, ${location.longitude}, accuracy=${location.accuracy}m")
                    
                    // Save location to SharedPreferences for ForegroundAttendanceService
                    val prefs = getSharedPreferences("attendance_service_prefs", Context.MODE_PRIVATE)
                    prefs.edit()
                        .putFloat("last_location_lat", location.latitude.toFloat())
                        .putFloat("last_location_lng", location.longitude.toFloat())
                        .putLong("last_location_time", System.currentTimeMillis())
                        .apply()
                    
                    // Broadcast location update
                    sendBroadcast(Intent("com.example.demoapp.LOCATION_UPDATE").apply {
                        putExtra("latitude", location.latitude)
                        putExtra("longitude", location.longitude)
                        putExtra("accuracy", location.accuracy)
                        putExtra("timestamp", System.currentTimeMillis())
                    })
                    
                    // Update notification
                    updateNotification(location)
                }
                
                override fun onProviderEnabled(provider: String) {
                    Log.d(TAG, "Provider enabled: $provider")
                }
                
                override fun onProviderDisabled(provider: String) {
                    Log.w(TAG, "Provider disabled: $provider")
                    // Restart with different provider
                    handler.postDelayed({
                        restartLocationUpdates()
                    }, 2000)
                }
            }
            
            // Request location from all available providers
            val hasFineLocation = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
            val hasCoarseLocation = checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
            
            if (hasFineLocation || hasCoarseLocation) {
                // Use all available providers for maximum reliability
                val providers = mutableListOf<String>()
                
                if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    providers.add(LocationManager.GPS_PROVIDER)
                }
                if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    providers.add(LocationManager.NETWORK_PROVIDER)
                }
                if (locationManager.isProviderEnabled(LocationManager.PASSIVE_PROVIDER)) {
                    providers.add(LocationManager.PASSIVE_PROVIDER)
                }
                
                for (provider in providers) {
                    try {
                        locationManager.requestLocationUpdates(
                            provider,
                            LOCATION_UPDATE_INTERVAL_MS,
                            LOCATION_UPDATE_DISTANCE_M,
                            locationListener!!
                        )
                        Log.d(TAG, "Location updates started for provider: $provider")
                    } catch (e: SecurityException) {
                        Log.e(TAG, "Security exception for provider $provider", e)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error starting provider $provider", e)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting location updates", e)
        }
    }
    
    private fun stopLocationUpdates() {
        locationListener?.let {
            try {
                locationManager.removeUpdates(it)
                Log.d(TAG, "Location updates stopped")
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping location updates", e)
            }
        }
        locationListener = null
    }
    
    private fun restartLocationUpdates() {
        stopLocationUpdates()
        if (isRunning) {
            startLocationUpdates()
        }
    }
    
    private val periodicLocationCheck = object : Runnable {
        override fun run() {
            if (!isRunning) return
            
            // Force location update check
            try {
                val hasFineLocation = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
                val hasCoarseLocation = checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
                
                if (hasFineLocation || hasCoarseLocation) {
                    // Get last known location
                    val providers = locationManager.getProviders(true)
                    for (provider in providers) {
                        try {
                            val location = locationManager.getLastKnownLocation(provider)
                            if (location != null && System.currentTimeMillis() - location.time < 60000) {
                                // Location is fresh (< 1 minute old)
                                locationListener?.onLocationChanged(location)
                                break
                            }
                        } catch (e: SecurityException) {
                            // Skip
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error in periodic location check", e)
            }
            
            // Schedule next check
            handler.postDelayed(this, LOCATION_UPDATE_INTERVAL_MS)
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
                    description = "Continuous location tracking for attendance"
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                }
                
                val notificationManager = getSystemService(NotificationManager::class.java)
                notificationManager.createNotificationChannel(channel)
            } catch (e: Exception) {
                Log.e(TAG, "Error creating notification channel", e)
            }
        }
    }
    
    private fun createNotification(location: Location? = null): Notification {
        val locationText = if (location != null) {
            "Lat: ${String.format("%.6f", location.latitude)}, Lng: ${String.format("%.6f", location.longitude)}"
        } else {
            "Tracking location..."
        }
        
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Location Tracking Active")
            .setContentText(locationText)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }
    
    private fun updateNotification(location: Location) {
        if (isRunning) {
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.notify(NOTIFICATION_ID, createNotification(location))
        }
    }
    
    override fun onDestroy() {
        Log.d(TAG, "LocationService onDestroy")
        stopLocationTracking()
        super.onDestroy()
    }
}





