package com.example.demoapp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Broadcast receiver that restarts the attendance service after device reboot
 * Ensures continuous monitoring even after phone restarts
 */
class BootReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "BootReceiver"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || 
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            intent.action == Intent.ACTION_PACKAGE_REPLACED) {
            
            Log.d(TAG, "Device booted or app updated - checking if service should restart")
            
            // Check if service was enabled before reboot
            val prefs = context.getSharedPreferences("attendance_service_prefs", Context.MODE_PRIVATE)
            val wasEnabled = prefs.getBoolean("is_enabled", false)
            
            if (wasEnabled) {
                Log.d(TAG, "Service was enabled - restarting foreground service")
                
                // Restart LocationService first
                val locationServiceIntent = Intent(context, LocationService::class.java).apply {
                    action = LocationService.ACTION_START
                }
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    context.startForegroundService(locationServiceIntent)
                } else {
                    context.startService(locationServiceIntent)
                }
                
                // Restart the ForegroundAttendanceService with saved configuration
                val serviceIntent = Intent(context, ForegroundAttendanceService::class.java).apply {
                    action = ForegroundAttendanceService.ACTION_START
                    // Service will load locations and auth token from SharedPreferences
                }
                
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
                
                Log.d(TAG, "✅ Services restarted after boot")
            } else {
                Log.d(TAG, "Service was not enabled - skipping restart")
            }
        }
    }
}

