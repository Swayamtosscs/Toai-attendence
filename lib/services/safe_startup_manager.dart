import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_service_factory.dart';
import 'foreground_attendance_service.dart';
import 'attendance_api_client.dart' show AttendanceApiClient, WorkLocation;
import 'location_repository.dart';
import 'geofence_manager.dart';

/// Safe startup manager - implements staged initialization
/// Prevents crashes by ensuring proper initialization sequence
class SafeStartupManager {
  static const String _keyStartupPhase = 'startup_phase';
  static const String _keyPermissionsGranted = 'permissions_granted';
  static const String _keyStateRestored = 'state_restored';
  
  /// Phase 1: Safe Boot - Only basic initialization
  static Future<bool> phase1SafeBoot() async {
    try {
      debugPrint('[SafeStartup] Phase 1: Safe Boot');
      
      // Only initialize basic dependencies
      // No services, no location, no permissions yet
      
      await SharedPreferences.getInstance();
      debugPrint('[SafeStartup] ✅ Phase 1 complete');
      return true;
    } catch (e, stackTrace) {
      debugPrint('[SafeStartup] ❌ Phase 1 failed: $e');
      debugPrint('[SafeStartup] Stack: $stackTrace');
      return false;
    }
  }
  
  /// Phase 2: Permission Gate - Request and verify permissions
  static Future<bool> phase2PermissionGate() async {
    try {
      debugPrint('[SafeStartup] Phase 2: Permission Gate');
      
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[SafeStartup] ⚠️ Location services disabled');
        // Don't crash - just return false
        return false;
      }
      
      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      
      // Request permission if denied
      if (permission == LocationPermission.denied) {
        debugPrint('[SafeStartup] Requesting location permission...');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('[SafeStartup] ⚠️ Location permission denied');
          return false;
        }
      }
      
      // Check if permanently denied
      if (permission == LocationPermission.deniedForever) {
        debugPrint('[SafeStartup] ⚠️ Location permission denied forever');
        return false;
      }
      
      // For Android, we need background location for foreground service
      if (Platform.isAndroid) {
        if (permission == LocationPermission.whileInUse) {
          debugPrint('[SafeStartup] ⚠️ Only while-in-use permission - background may be limited');
          // Continue anyway - foreground service will work
        } else if (permission == LocationPermission.always) {
          debugPrint('[SafeStartup] ✅ Background location permission granted');
        }
      }
      
      // Save permission status
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyPermissionsGranted, true);
      
      debugPrint('[SafeStartup] ✅ Phase 2 complete - Permissions granted');
      return true;
    } catch (e, stackTrace) {
      debugPrint('[SafeStartup] ❌ Phase 2 failed: $e');
      debugPrint('[SafeStartup] Stack: $stackTrace');
      return false;
    }
  }
  
  /// Phase 3: State Restore - Load persisted state
  static Future<StartupState> phase3StateRestore() async {
    try {
      debugPrint('[SafeStartup] Phase 3: State Restore');
      
      final prefs = await SharedPreferences.getInstance();
      
      // Load auto attendance state
      final wasManuallyDisabled = prefs.getBool('auto_attendance_manually_disabled') ?? false;
      final isEnabled = wasManuallyDisabled 
          ? false 
          : (prefs.getBool('auto_attendance_enabled') ?? false);
      
      // Load check-in state
      final isCheckedIn = prefs.getBool('is_checked_in') ?? false;
      final locationId = prefs.getString('check_in_location_id');
      final checkInTimestampStr = prefs.getString('check_in_timestamp');
      final checkInTimestamp = checkInTimestampStr != null 
          ? DateTime.tryParse(checkInTimestampStr) 
          : null;
      
      // Load timer states
      // Note: Timer states are stored in Android's native SharedPreferences by the Kotlin service
      // They may not be accessible from Flutter's SharedPreferences, but that's okay
      // The foreground service will restore and broadcast timer updates when it restarts
      // For now, we'll try to read from Flutter's SharedPreferences (if saved there)
      // Otherwise, timer state will be restored from service events
      int? entryTimerRemaining;
      int? exitTimerRemaining;
      
      try {
        // Try to read timer start times (may not exist if stored in native prefs)
        final entryTimerStartStr = prefs.getString('entry_timer_start');
        final exitTimerStartStr = prefs.getString('exit_timer_start');
        
        if (entryTimerStartStr != null) {
          final entryTimerStart = int.tryParse(entryTimerStartStr) ?? 0;
          if (entryTimerStart > 0) {
            final elapsed = DateTime.now().millisecondsSinceEpoch - entryTimerStart;
            final remaining = 60000 - elapsed; // 1 minute = 60000ms
            if (remaining > 0) {
              entryTimerRemaining = (remaining / 1000).round(); // Convert to seconds
            }
          }
        }
        
        if (exitTimerStartStr != null) {
          final exitTimerStart = int.tryParse(exitTimerStartStr) ?? 0;
          if (exitTimerStart > 0) {
            final elapsed = DateTime.now().millisecondsSinceEpoch - exitTimerStart;
            final remaining = 60000 - elapsed; // 1 minute = 60000ms
            if (remaining > 0) {
              exitTimerRemaining = (remaining / 1000).round(); // Convert to seconds
            }
          }
        }
      } catch (e) {
        debugPrint('[SafeStartup] Could not restore timer states: $e');
        // Timer states will be restored from service events instead
      }
      
      final state = StartupState(
        isEnabled: isEnabled,
        isCheckedIn: isCheckedIn,
        locationId: locationId,
        checkInTimestamp: checkInTimestamp,
        entryTimerRemaining: entryTimerRemaining,
        exitTimerRemaining: exitTimerRemaining,
      );
      
      await prefs.setBool(_keyStateRestored, true);
      debugPrint('[SafeStartup] ✅ Phase 3 complete - State restored');
      debugPrint('[SafeStartup] State: enabled=$isEnabled, checkedIn=$isCheckedIn, entryTimer=${entryTimerRemaining}s, exitTimer=${exitTimerRemaining}s');
      
      return state;
    } catch (e, stackTrace) {
      debugPrint('[SafeStartup] ❌ Phase 3 failed: $e');
      debugPrint('[SafeStartup] Stack: $stackTrace');
      // Return default state on error
      return StartupState(
        isEnabled: false,
        isCheckedIn: false,
      );
    }
  }
  
  /// Phase 4: Engine Startup - Start services only after permissions and state are ready
  static Future<bool> phase4EngineStartup(StartupState state) async {
    try {
      debugPrint('[SafeStartup] Phase 4: Engine Startup');
      
      // Only start if auto attendance was enabled
      if (!state.isEnabled) {
        debugPrint('[SafeStartup] Auto attendance not enabled - skipping engine startup');
        return true; // Not an error - just not needed
      }
      
      // FIXED: Load work locations into LocationRepository (single source of truth)
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('api_base_url') ?? 'http://103.14.120.163:8092/api';
      
      final locationRepo = LocationRepository.instance;
      if (!locationRepo.isLoaded) {
        try {
          final apiClient = AttendanceApiClient(baseUrl: baseUrl);
          await locationRepo.loadLocations(apiClient);
          apiClient.dispose();
          
          if (locationRepo.hasLocations) {
            debugPrint('[SafeStartup] ✅ Loaded ${locationRepo.workLocations.length} work locations into LocationRepository');
          } else {
            debugPrint('[SafeStartup] ⚠️ No work locations found');
          }
        } catch (e) {
          debugPrint('[SafeStartup] ⚠️ Failed to load work locations: $e');
          // Continue anyway
        }
      } else {
        debugPrint('[SafeStartup] ✅ Locations already loaded in LocationRepository');
      }
      
      // Get locations from repository
      final workLocations = locationRepo.workLocations;
      
      // Start foreground service (Android only) - CRITICAL for auto check-in/out
      if (Platform.isAndroid && workLocations.isNotEmpty) {
        try {
          debugPrint('[SafeStartup] 🚀 Starting foreground service with ${workLocations.length} locations...');
          final started = await ForegroundAttendanceService.startService(workLocations);
          if (started) {
            debugPrint('[SafeStartup] ✅ Foreground service started successfully');
          } else {
            debugPrint('[SafeStartup] ❌ Foreground service start failed - will retry');
            // Retry after delay
            Future.delayed(const Duration(seconds: 3), () async {
              try {
                final retryStarted = await ForegroundAttendanceService.startService(workLocations);
                if (retryStarted) {
                  debugPrint('[SafeStartup] ✅ Foreground service started on retry');
                } else {
                  debugPrint('[SafeStartup] ❌ Foreground service retry also failed');
                }
              } catch (e) {
                debugPrint('[SafeStartup] ❌ Foreground service retry error: $e');
              }
            });
          }
        } catch (e) {
          debugPrint('[SafeStartup] ❌ Foreground service error: $e');
          // Retry after delay
          Future.delayed(const Duration(seconds: 3), () async {
            try {
              await ForegroundAttendanceService.startService(workLocations);
            } catch (e2) {
              debugPrint('[SafeStartup] ❌ Foreground service retry error: $e2');
            }
          });
        }
      } else if (Platform.isAndroid && workLocations.isEmpty) {
        debugPrint('[SafeStartup] ⚠️ No work locations - cannot start foreground service');
      }
      
      debugPrint('[SafeStartup] ✅ Phase 4 complete');
      return true;
    } catch (e, stackTrace) {
      debugPrint('[SafeStartup] ❌ Phase 4 failed: $e');
      debugPrint('[SafeStartup] Stack: $stackTrace');
      return false;
    }
  }
  
  /// Complete startup pipeline - runs all phases in order
  static Future<StartupResult> executeStartupPipeline() async {
    debugPrint('[SafeStartup] ========================================');
    debugPrint('[SafeStartup] Starting safe startup pipeline');
    debugPrint('[SafeStartup] ========================================');
    
    // Phase 1: Safe Boot
    final phase1Success = await phase1SafeBoot();
    if (!phase1Success) {
      debugPrint('[SafeStartup] ❌ Pipeline failed at Phase 1');
      return StartupResult(
        success: false,
        phase: 1,
        state: StartupState(isEnabled: false, isCheckedIn: false),
      );
    }
    
    // Phase 2: Permission Gate
    final phase2Success = await phase2PermissionGate();
    if (!phase2Success) {
      debugPrint('[SafeStartup] ⚠️ Pipeline stopped at Phase 2 (permissions not granted)');
      // Not a failure - user may grant later
      return StartupResult(
        success: true, // App can still work
        phase: 2,
        state: StartupState(isEnabled: false, isCheckedIn: false),
        permissionsGranted: false,
      );
    }
    
    // Phase 3: State Restore
    final state = await phase3StateRestore();
    
    // Phase 4: Engine Startup (only if enabled)
    if (state.isEnabled) {
      final phase4Success = await phase4EngineStartup(state);
      if (!phase4Success) {
        debugPrint('[SafeStartup] ⚠️ Pipeline completed with warnings at Phase 4');
        // Not a failure - app can still work
      }
    }
    
    debugPrint('[SafeStartup] ========================================');
    debugPrint('[SafeStartup] ✅ Startup pipeline completed');
    debugPrint('[SafeStartup] ========================================');
    
    return StartupResult(
      success: true,
      phase: 4,
      state: state,
      permissionsGranted: true,
    );
  }
  
  /// Check if permissions are granted (for UI)
  static Future<bool> arePermissionsGranted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyPermissionsGranted) ?? false;
    } catch (e) {
      return false;
    }
  }
}

/// Startup state - contains restored state information
class StartupState {
  final bool isEnabled;
  final bool isCheckedIn;
  final String? locationId;
  final DateTime? checkInTimestamp;
  final int? entryTimerRemaining; // Remaining seconds for entry timer
  final int? exitTimerRemaining; // Remaining seconds for exit timer
  
  StartupState({
    required this.isEnabled,
    required this.isCheckedIn,
    this.locationId,
    this.checkInTimestamp,
    this.entryTimerRemaining,
    this.exitTimerRemaining,
  });
}

/// Startup result - contains pipeline execution result
class StartupResult {
  final bool success;
  final int phase; // Last completed phase
  final StartupState state;
  final bool permissionsGranted;
  
  StartupResult({
    required this.success,
    required this.phase,
    required this.state,
    this.permissionsGranted = false,
  });
}

