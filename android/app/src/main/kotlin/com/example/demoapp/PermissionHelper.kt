package com.example.demoapp

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * Helper class for managing all required permissions
 * Ensures smooth first-install experience with proper permission requests
 */
object PermissionHelper {
    
    const val PERMISSION_REQUEST_CODE = 1001
    const val BACKGROUND_LOCATION_REQUEST_CODE = 1002
    
    /**
     * All required permissions for the attendance system
     */
    val REQUIRED_PERMISSIONS = mutableListOf<String>().apply {
        add(Manifest.permission.ACCESS_FINE_LOCATION)
        add(Manifest.permission.ACCESS_COARSE_LOCATION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            add(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            add(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    
    /**
     * Check if all required permissions are granted
     */
    fun hasAllPermissions(context: Context): Boolean {
        return REQUIRED_PERMISSIONS.all { permission ->
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
        }
    }
    
    /**
     * Check if foreground location permission is granted
     */
    fun hasForegroundLocationPermission(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED ||
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    /**
     * Check if background location permission is granted
     */
    fun hasBackgroundLocationPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return true // Not required before Android 10
        }
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    /**
     * Request all required permissions
     * Should be called from Activity
     */
    fun requestAllPermissions(activity: Activity) {
        val permissionsToRequest = REQUIRED_PERMISSIONS.filter { permission ->
            ContextCompat.checkSelfPermission(activity, permission) != PackageManager.PERMISSION_GRANTED
        }
        
        if (permissionsToRequest.isNotEmpty()) {
            // Request foreground location first
            val foregroundLocationPermissions = permissionsToRequest.filter {
                it == Manifest.permission.ACCESS_FINE_LOCATION ||
                it == Manifest.permission.ACCESS_COARSE_LOCATION
            }
            
            if (foregroundLocationPermissions.isNotEmpty()) {
                ActivityCompat.requestPermissions(
                    activity,
                    foregroundLocationPermissions.toTypedArray(),
                    PERMISSION_REQUEST_CODE
                )
            }
            
            // Request other permissions (notifications, etc.)
            val otherPermissions = permissionsToRequest.filter {
                it != Manifest.permission.ACCESS_FINE_LOCATION &&
                it != Manifest.permission.ACCESS_COARSE_LOCATION &&
                it != Manifest.permission.ACCESS_BACKGROUND_LOCATION
            }
            
            if (otherPermissions.isNotEmpty()) {
                ActivityCompat.requestPermissions(
                    activity,
                    otherPermissions.toTypedArray(),
                    PERMISSION_REQUEST_CODE
                )
            }
        }
    }
    
    /**
     * Request background location permission (must be requested separately after foreground)
     */
    fun requestBackgroundLocationPermission(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (!hasBackgroundLocationPermission(activity)) {
                ActivityCompat.requestPermissions(
                    activity,
                    arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                    BACKGROUND_LOCATION_REQUEST_CODE
                )
            }
        }
    }
    
    /**
     * Open app settings for manual permission grant
     */
    fun openAppSettings(activity: Activity) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", activity.packageName, null)
        }
        activity.startActivity(intent)
    }
    
    /**
     * Check if user should see rationale for permission
     */
    fun shouldShowRationale(activity: Activity, permission: String): Boolean {
        return ActivityCompat.shouldShowRequestPermissionRationale(activity, permission)
    }
}

