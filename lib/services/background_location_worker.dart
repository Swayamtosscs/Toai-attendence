import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_api_client.dart';

/// Background task callback dispatcher
/// Must be top-level function for workmanager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (task == BackgroundLocationWorker.taskName) {
        await BackgroundLocationWorker.performLocationValidation();
        return Future.value(true);
      }
      return Future.value(false);
    } catch (e) {
      // Log error but don't crash
      return Future.value(false);
    }
  });
}

/// Background worker for periodic location validation
/// Runs every 30 minutes to verify user location and force check-out if needed
class BackgroundLocationWorker {
  static const String taskName = 'attendanceLocationValidation';
  static const Duration validationInterval = Duration(minutes: 30);

  /// Initialize background worker
  /// Call this once in main.dart after app initialization
  /// Only works on Android/iOS, skips on Windows/Web
  static Future<void> initialize() async {
    // Only initialize on mobile platforms
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }
    
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );
    } catch (e) {
      // Handle initialization errors gracefully
      print('Workmanager initialization failed: $e');
    }
  }

  /// Register periodic background task
  /// Only works on Android/iOS
  static Future<void> registerPeriodicTask() async {
    // Only register on mobile platforms
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }
    
    try {
      // Use more lenient constraints for better reliability on real devices
      // Minimum interval is 15 minutes on Android, but we request 30 minutes
      await Workmanager().registerPeriodicTask(
        taskName,
        taskName,
        frequency: Duration(minutes: 30),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false, // Allow even on low battery
          requiresCharging: false, // Don't require charging
          requiresDeviceIdle: false, // Don't require device idle
          requiresStorageNotLow: false, // Don't require storage space
        ),
        initialDelay: Duration(minutes: 30), // First run after 30 minutes
      );
      await markTaskRegistered(true);
    } catch (e) {
      print('Failed to register background task: $e');
    }
  }

  /// Cancel background task
  /// Only works on Android/iOS
  static Future<void> cancelTask() async {
    // Only cancel on mobile platforms
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }
    
    try {
      await Workmanager().cancelByUniqueName(taskName);
      await markTaskRegistered(false);
    } catch (e) {
      print('Failed to cancel background task: $e');
    }
  }


  /// Perform location validation
  /// Checks if user is still inside work location, forces check-out if not
  static Future<void> performLocationValidation() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if auto-attendance is enabled
      final isEnabled = prefs.getBool('auto_attendance_enabled') ?? false;
      if (!isEnabled) return;

      // Check if user is currently checked in
      final isCheckedIn = prefs.getBool('is_checked_in') ?? false;
      if (!isCheckedIn) return;

      // Get current location
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      // Get work locations
      final baseUrl = prefs.getString('api_base_url') ?? '';
      if (baseUrl.isEmpty) return;

      final apiClient = AttendanceApiClient(baseUrl: baseUrl);
      List<WorkLocation> workLocations;
      try {
        workLocations = await apiClient.getWorkLocations();
      } catch (e) {
        apiClient.dispose();
        return;
      }

      // Check if user is inside any work location
      bool isInsideLocation = false;
      for (final location in workLocations) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          location.latitude,
          location.longitude,
        );

        if (distance <= location.radius) {
          isInsideLocation = true;
          break;
        }
      }

      // If not inside any location, force check-out
      if (!isInsideLocation) {
        final userId = prefs.getString('user_id');
        if (userId != null) {
          try {
            await apiClient.checkOut(
              latitude: position.latitude,
              longitude: position.longitude,
            );

            // Update local state
            await prefs.setBool('is_checked_in', false);
            await prefs.remove('check_in_location_id');
            await prefs.remove('check_in_timestamp');
          } catch (e) {
            // Log error but continue
          }
        }
      }

      apiClient.dispose();
    } catch (e) {
      // Silently handle errors in background
    }
  }

  /// Check if background task is registered
  static Future<bool> isTaskRegistered() async {
    // Workmanager doesn't provide direct check, so we use SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('background_task_registered') ?? false;
  }

  /// Mark task as registered
  static Future<void> markTaskRegistered(bool registered) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('background_task_registered', registered);
  }
}

