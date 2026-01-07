import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_api_client.dart';
import 'geofence_manager.dart';
import 'location_repository.dart';
import 'background_location_worker.dart';
import 'location_config.dart';
import 'auth_api_service.dart';
import 'device_power_manager.dart';
import 'foreground_attendance_service.dart';
import 'attendance_service_factory.dart';

/// Main service for automatic attendance tracking
/// Orchestrates geofence monitoring, API calls, and state management
class AttendanceService {
  final AttendanceApiClient _apiClient;
  final GeofenceManager _geofenceManager;
  final StreamController<ServiceAttendanceState> _stateController =
      StreamController<ServiceAttendanceState>.broadcast();

  Stream<ServiceAttendanceState> get stateStream => _stateController.stream;
  ServiceAttendanceState _currentState = ServiceAttendanceState.initial();

  bool _isInitialized = false;
  StreamSubscription<GeofenceEvent>? _geofenceSubscription;
  StreamSubscription<AttendanceServiceEvent>? _foregroundServiceSubscription;
  Timer? _periodicLocationCheckTimer;

  AttendanceService({
    required AttendanceApiClient apiClient,
    required GeofenceManager geofenceManager,
  })  : _apiClient = apiClient,
        _geofenceManager = geofenceManager {
    _initialize();
  }

  /// Initialize service
  Future<void> _initialize() async {
    if (_isInitialized) return;

    try {
      // Load persisted state
      await _loadState();

      // Setup geofence event listener
      _geofenceSubscription = _geofenceManager.eventStream.listen(
        _handleGeofenceEvent,
        onError: (error) {
          _updateState(_currentState.copyWith(
            error: error.toString(),
          ));
        },
      );

      // Setup foreground service event listener (Android only)
      if (Platform.isAndroid) {
        _foregroundServiceSubscription = ForegroundAttendanceService.eventStream.listen(
          _handleForegroundServiceEvent,
          onError: (error) {
            debugPrint('[AttendanceService] Foreground service event error: $error');
          },
        );
      }

      // Start periodic location check every 30 minutes
      _startPeriodicLocationCheck();

      // Restore foreground service if it was running (Android only)
      if (Platform.isAndroid && _currentState.isEnabled) {
        _restoreForegroundService();
      }

      _isInitialized = true;
    } catch (e) {
      _updateState(_currentState.copyWith(error: e.toString()));
    }
  }

  /// Load persisted state from SharedPreferences
  /// PERMANENT ON: Defaults to enabled unless manually disabled
  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    // PERMANENT ON BEHAVIOR: Default to enabled (true) unless user manually disabled
    // Respects manual disable flag - if manually disabled, stays OFF
    final wasManuallyDisabled = prefs.getBool('auto_attendance_manually_disabled') ?? false;
    final isEnabled = wasManuallyDisabled 
        ? false 
        : (prefs.getBool('auto_attendance_enabled') ?? true); // Default ON if not manually disabled
    final isCheckedIn = prefs.getBool('is_checked_in') ?? false;
    final locationId = prefs.getString('check_in_location_id');
    final checkInTimestamp = prefs.getString('check_in_timestamp');

    _currentState = ServiceAttendanceState(
      isEnabled: isEnabled,
      isCheckedIn: isCheckedIn,
      currentLocationId: locationId,
      checkInTimestamp: checkInTimestamp != null
          ? DateTime.parse(checkInTimestamp)
          : null,
      error: null,
    );

    _stateController.add(_currentState);
    debugPrint('[AttendanceService] State loaded: Enabled=$isEnabled, CheckedIn=$isCheckedIn, ManuallyDisabled=$wasManuallyDisabled');
  }

  /// Initialize with work locations from backend
  /// [autoStart] - If false, only initializes locations without starting services
  /// FIXED: Uses LocationRepository for single source of truth
  Future<void> initializeWithLocations({bool autoStart = false}) async {
    try {
      // FIXED: Load locations into LocationRepository first
      final locationRepo = LocationRepository.instance;
      if (!locationRepo.isLoaded) {
        debugPrint('[AttendanceService] 📍 Loading locations into LocationRepository...');
        await locationRepo.loadLocations(_apiClient);
      }
      
      // FIXED: Use locations from LocationRepository
      List<WorkLocation> workLocations = locationRepo.workLocations;
      
      // If no locations from repository, use fallback
      if (workLocations.isEmpty) {
        debugPrint('[AttendanceService] ⚠️ No locations in repository, using fallback...');
        final customLocation = await LocationConfig.getCustomLocation();
        if (customLocation != null) {
          workLocations = [customLocation];
          locationRepo.setLocations(workLocations);
        } else {
          // Use default location as fallback
          workLocations = [LocationConfig.getDefaultLocation()];
          locationRepo.setLocations(workLocations);
        }
      }
      
      // FIXED: Initialize geofence manager with LocationRepository locations
      await _geofenceManager.initialize(workLocations);
      
      // Only auto-start if explicitly requested (for safe startup)
      if (!autoStart) {
        debugPrint('[AttendanceService] Locations initialized (auto-start disabled)');
        return;
      }

      // PERMANENT ON BEHAVIOR: Auto-enable attendance service on initialization
      // Toggle stays ON permanently unless user manually disables it
      // Only enable if not already enabled (respects manual disable)
      final prefs = await SharedPreferences.getInstance();
      final wasManuallyDisabled = prefs.getBool('auto_attendance_manually_disabled') ?? false;
      
      // If manually disabled, respect that. Otherwise, enable by default.
      if (!_currentState.isEnabled && !wasManuallyDisabled) {
        try {
          final hasPermission = await _requestLocationPermissions();
          if (hasPermission) {
            // Request battery optimization exemption for reliable background execution
            try {
              final isIgnoring = await DevicePowerManager.isIgnoringBatteryOptimizations();
              if (!isIgnoring) {
                debugPrint('[AttendanceService] Requesting battery optimization exemption...');
                await DevicePowerManager.requestIgnoreBatteryOptimizations();
              }
            } catch (e) {
              debugPrint('[AttendanceService] ⚠️ Battery optimization request failed: $e');
            }

            await _geofenceManager.startMonitoring();
            await prefs.setBool('auto_attendance_enabled', true);
            _updateState(_currentState.copyWith(isEnabled: true, error: null));
            
            // Start foreground service (Android only)
            if (Platform.isAndroid) {
              try {
                final workLocations = _geofenceManager.getWorkLocations();
                if (workLocations.isNotEmpty) {
                  await ForegroundAttendanceService.startService(workLocations);
                  debugPrint('[AttendanceService] ✅ Foreground service started');
                }
              } catch (e) {
                debugPrint('[AttendanceService] ⚠️ Foreground service start failed: $e');
              }
            }
            
            // Register background task for periodic checks
            try {
              await BackgroundLocationWorker.registerPeriodicTask();
              debugPrint('[AttendanceService] ✅ Background task registered');
            } catch (e) {
              debugPrint('[AttendanceService] ⚠️ Background task registration failed: $e');
            }
            
            // CORE BEHAVIOR: Do immediate location check to auto check-in if already at location
            // CRASH-PROOF: Wrapped in try-catch
            try {
              debugPrint('[AttendanceService] 🔄 Performing immediate location check for auto check-in...');
              await _periodicLocationValidation();
              debugPrint('[AttendanceService] ✅ Initialization location check completed');
            } catch (e) {
              debugPrint('[AttendanceService] ⚠️ Initialization location check failed: $e');
              // Retry after short delay
              Future.delayed(const Duration(seconds: 3), () async {
                try {
                  await _periodicLocationValidation();
                  debugPrint('[AttendanceService] ✅ Retry initialization check completed');
                } catch (e2) {
                  debugPrint('[AttendanceService] ⚠️ Retry initialization check failed: $e2');
                }
              });
            }
          }
        } catch (e) {
          // If auto-enable fails, continue without it
          debugPrint('[AttendanceService] Auto-enable failed: $e');
        }
      } else if (_currentState.isEnabled) {
        // Ensure permissions are granted before starting monitoring
        final hasPermission = await _requestLocationPermissions();
        if (hasPermission) {
          // Request battery optimization exemption
          try {
            final isIgnoring = await DevicePowerManager.isIgnoringBatteryOptimizations();
            if (!isIgnoring) {
              debugPrint('[AttendanceService] Requesting battery optimization exemption...');
              await DevicePowerManager.requestIgnoreBatteryOptimizations();
            }
          } catch (e) {
            debugPrint('[AttendanceService] ⚠️ Battery optimization request failed: $e');
          }

          await _geofenceManager.startMonitoring();
          debugPrint('[AttendanceService] ✅ Geofence monitoring started');
          
          // Start foreground service (Android only)
          if (Platform.isAndroid) {
            try {
              final workLocations = _geofenceManager.getWorkLocations();
              if (workLocations.isNotEmpty) {
                await ForegroundAttendanceService.startService(workLocations);
                debugPrint('[AttendanceService] ✅ Foreground service started');
              }
            } catch (e) {
              debugPrint('[AttendanceService] ⚠️ Foreground service start failed: $e');
            }
          }
          
          // Register background task for periodic checks
          try {
            await BackgroundLocationWorker.registerPeriodicTask();
            debugPrint('[AttendanceService] ✅ Background task registered');
          } catch (e) {
            debugPrint('[AttendanceService] ⚠️ Background task registration failed: $e');
          }
          
          // CORE BEHAVIOR: Do immediate location check to auto check-in if at location
          // CRASH-PROOF: Wrapped in try-catch
          try {
            debugPrint('[AttendanceService] 🔄 Performing immediate location check for auto check-in...');
            await _periodicLocationValidation();
            debugPrint('[AttendanceService] ✅ Initial location validation completed');
          } catch (e) {
            debugPrint('[AttendanceService] ⚠️ Initial location validation failed: $e');
            // Retry after short delay
            Future.delayed(const Duration(seconds: 3), () async {
              try {
                await _periodicLocationValidation();
                debugPrint('[AttendanceService] ✅ Retry location validation completed');
              } catch (e2) {
                debugPrint('[AttendanceService] ⚠️ Retry initial validation failed: $e2');
              }
            });
          }
        } else {
          debugPrint('[AttendanceService] ⚠️ Location permissions not granted - cannot start monitoring');
          _updateState(_currentState.copyWith(
            error: 'Location permissions required for auto attendance',
          ));
        }
      }
    } catch (e) {
      _updateState(_currentState.copyWith(error: e.toString()));
    }
  }

  /// Enable automatic attendance tracking
  /// CORE BEHAVIOR: When enabled, user must be automatically checked in
  Future<void> enable() async {
    if (_currentState.isEnabled) return;

    try {
      // Request location permissions
      final hasPermission = await _requestLocationPermissions();
      if (!hasPermission) {
        throw AttendanceException('Location permissions not granted');
      }

      // Request battery optimization exemption for reliable background execution
      try {
        final isIgnoring = await DevicePowerManager.isIgnoringBatteryOptimizations();
        if (!isIgnoring) {
          debugPrint('[AttendanceService] Requesting battery optimization exemption...');
          await DevicePowerManager.requestIgnoreBatteryOptimizations();
        }
      } catch (e) {
        debugPrint('[AttendanceService] ⚠️ Battery optimization request failed: $e');
        // Continue - not critical for functionality
      }

      // Start geofence monitoring
      await _geofenceManager.startMonitoring();

      // Start foreground service (Android only) - this is the primary background mechanism
      // CRITICAL: Service must start to enable auto check-in/check-out
      if (Platform.isAndroid) {
        try {
          final workLocations = _geofenceManager.getWorkLocations();
          if (workLocations.isNotEmpty) {
            debugPrint('[AttendanceService] 🚀 Starting foreground service with ${workLocations.length} locations...');
            final started = await ForegroundAttendanceService.startService(workLocations);
            if (started) {
              debugPrint('[AttendanceService] ✅ Foreground service started successfully');
            } else {
              debugPrint('[AttendanceService] ❌ Foreground service start failed - auto check-in/out will not work');
              // Retry after delay
              Future.delayed(const Duration(seconds: 2), () async {
                try {
                  final retryStarted = await ForegroundAttendanceService.startService(workLocations);
                  if (retryStarted) {
                    debugPrint('[AttendanceService] ✅ Foreground service started on retry');
                  } else {
                    debugPrint('[AttendanceService] ❌ Foreground service retry also failed');
                  }
                } catch (e) {
                  debugPrint('[AttendanceService] ❌ Foreground service retry error: $e');
                }
              });
            }
          } else {
            debugPrint('[AttendanceService] ⚠️ No work locations available - cannot start foreground service');
          }
        } catch (e) {
          debugPrint('[AttendanceService] ❌ Foreground service error: $e');
          // Retry after delay
          Future.delayed(const Duration(seconds: 2), () async {
            try {
              final workLocations = _geofenceManager.getWorkLocations();
              if (workLocations.isNotEmpty) {
                await ForegroundAttendanceService.startService(workLocations);
              }
            } catch (e2) {
              debugPrint('[AttendanceService] ❌ Foreground service retry error: $e2');
            }
          });
        }
      }

      // Register background task (only on mobile, as backup)
      try {
        await BackgroundLocationWorker.registerPeriodicTask();
        debugPrint('[AttendanceService] ✅ Background task registered');
      } catch (e) {
        debugPrint('[AttendanceService] ⚠️ Background task registration failed: $e');
        // Silent fail on Windows/Web
      }

      // Update state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_attendance_enabled', true);
      await prefs.setBool('auto_attendance_manually_disabled', false); // Clear manual disable flag

      _updateState(_currentState.copyWith(isEnabled: true, error: null));
      
      // CORE BEHAVIOR: Immediately check-in if at location when auto attendance is enabled
      // This ensures user is checked in as soon as toggle is turned ON
      // Do immediate check first, then periodic checks
      // CRASH-PROOF: Wrapped in try-catch
      try {
        // Immediate check (no delay) - FORCE CHECK-IN
        debugPrint('[AttendanceService] 🔄 Performing immediate location check for auto check-in...');
        await _periodicLocationValidation();
        debugPrint('[AttendanceService] ✅ Immediate location check completed');
      } catch (e) {
        debugPrint('[AttendanceService] ⚠️ Immediate location check failed: $e');
        // Retry after short delay
        Future.delayed(const Duration(seconds: 3), () async {
          try {
            await _periodicLocationValidation();
            debugPrint('[AttendanceService] ✅ Retry location check completed');
          } catch (e2) {
            debugPrint('[AttendanceService] ⚠️ Retry location check failed: $e2');
          }
        });
      }
    } catch (e) {
      _updateState(_currentState.copyWith(error: e.toString()));
      rethrow;
    }
  }

  /// Disable automatic attendance tracking
  /// CORE BEHAVIOR: When disabled, immediately check-out the user with exact real-time
  Future<void> disable() async {
    if (!_currentState.isEnabled) return;

    try {
      // CORE BEHAVIOR: Immediately check-out when auto attendance is turned OFF
      // Capture exact real-time checkout time BEFORE API call
      DateTime? realCheckoutTime;
      if (_currentState.isCheckedIn) {
        // Capture real checkout time immediately (before API call)
        realCheckoutTime = DateTime.now();
        debugPrint('[AttendanceService] 🔴 Toggle OFF - Real checkout time captured: ${realCheckoutTime.toIso8601String()}');
        
        await _performCheckOut(realCheckoutTime: realCheckoutTime);
      }

      // Stop geofence monitoring
      await _geofenceManager.stopMonitoring();

      // Stop foreground service (Android only)
      if (Platform.isAndroid) {
        try {
          await ForegroundAttendanceService.stopService();
          debugPrint('[AttendanceService] ✅ Foreground service stopped');
        } catch (e) {
          debugPrint('[AttendanceService] ⚠️ Foreground service stop error: $e');
        }
      }

      // Cancel background task (only on mobile)
      try {
        await BackgroundLocationWorker.cancelTask();
      } catch (e) {
        // Silent fail on Windows/Web
      }
      
      // PERMANENT ON: Mark as manually disabled - this is the ONLY way to turn OFF
      // User must explicitly turn toggle OFF - it will NOT auto-enable on next app start
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_attendance_manually_disabled', true);
      await prefs.setBool('auto_attendance_enabled', false);
      debugPrint('[AttendanceService] 🔴 Toggle manually disabled - will NOT auto-enable on restart');

      _updateState(_currentState.copyWith(
        isEnabled: false,
        isCheckedIn: false,
        currentLocationId: null,
        checkInTimestamp: null,
        error: null,
      ));
    } catch (e) {
      _updateState(_currentState.copyWith(error: e.toString()));
      rethrow;
    }
  }

  /// Handle geofence events (ENTER/EXIT)
  /// This is called automatically when location is detected
  Future<void> _handleGeofenceEvent(GeofenceEvent event) async {
    if (!_currentState.isEnabled) {
      debugPrint('[AttendanceService] ⚠️ Geofence event ignored - auto attendance disabled');
      return;
    }

    try {
      debugPrint('[AttendanceService] 📍 Geofence event: ${event.type} at location: ${event.locationId}');
      
      if (event.type == GeofenceEventType.ENTER) {
        // Automatic check-in when location is entered
        if (!_currentState.isCheckedIn) {
          debugPrint('[AttendanceService] ✅ ENTER event - Triggering auto check-in');
          await _performCheckIn(event.locationId);
        } else {
          debugPrint('[AttendanceService] ℹ️ ENTER event - Already checked in');
        }
      } else if (event.type == GeofenceEventType.EXIT) {
        // Automatic check-out when location is left
        if (_currentState.isCheckedIn) {
          debugPrint('[AttendanceService] 🔴 EXIT event - Triggering auto check-out');
          await _performCheckOut();
        } else {
          debugPrint('[AttendanceService] ℹ️ EXIT event - Already checked out');
        }
      }
    } catch (e) {
      debugPrint('[AttendanceService] ❌ Geofence event handling error: $e');
      _updateState(_currentState.copyWith(error: e.toString()));
    }
  }

  /// Start periodic location check every 5 minutes for better responsiveness on real devices
  /// CRASH-PROOF: Wrapped in try-catch to prevent auto attendance from stopping
  void _startPeriodicLocationCheck() {
    _periodicLocationCheckTimer?.cancel();
    _periodicLocationCheckTimer = Timer.periodic(
      const Duration(minutes: 5), // Reduced from 30 to 5 minutes for faster detection
      (_) {
        // CRASH-PROOF: Never let periodic validation crash the service
        try {
          _periodicLocationValidation();
        } catch (e, stackTrace) {
          debugPrint('[AttendanceService] ❌ Periodic location validation crashed (safe failure): $e');
          debugPrint('[AttendanceService] Stack trace: $stackTrace');
          // Update state with error but don't crash
          _updateState(_currentState.copyWith(
            error: 'Location check failed: ${e.toString()}',
          ));
        }
      },
    );
  }

  /// Periodic location validation - checks every 30 minutes
  /// If in location and not checked in -> auto check-in
  /// If not in location and checked in -> auto check-out
  Future<void> _periodicLocationValidation() async {
    if (!_currentState.isEnabled) return;

    try {
      // Check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[AttendanceService] Location service disabled');
        return;
      }

      // Get current position with timeout
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15), // Timeout after 15 seconds
        ),
      );
      
      debugPrint('[AttendanceService] Periodic validation - Position: ${position.latitude}, ${position.longitude}');

      // Get work locations - use initialized locations from geofence manager first
      // This avoids backend API calls on every periodic check
      List<WorkLocation> workLocations = _geofenceManager.getWorkLocations();
      
      // If no locations in geofence manager, try to fetch from backend or use fallback
      if (workLocations.isEmpty) {
        try {
          workLocations = await _apiClient.getWorkLocations();
          if (workLocations.isNotEmpty) {
            // Update geofence manager with fetched locations
            await _geofenceManager.updateWorkLocations(workLocations);
          }
        } catch (e) {
          print('[AttendanceService] Backend location fetch failed, using fallback: $e');
          // Use fallback locations if backend fails
          final customLocation = await LocationConfig.getCustomLocation();
          if (customLocation != null) {
            workLocations = [customLocation];
            await _geofenceManager.updateWorkLocations(workLocations);
          } else {
            // Use default location as final fallback
            workLocations = [LocationConfig.getDefaultLocation()];
            await _geofenceManager.updateWorkLocations(workLocations);
          }
          print('[AttendanceService] Using fallback location: ${workLocations.first.name}');
        }
      }
      
      if (workLocations.isEmpty) {
        print('[AttendanceService] No work locations available for validation');
        return;
      }
      
      // Check if user is inside any work location
      bool isInsideLocation = false;
      String? insideLocationId;
      double? minDistance;

      for (final location in workLocations) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          location.latitude,
          location.longitude,
        );

        if (distance <= location.radius) {
          isInsideLocation = true;
          if (minDistance == null || distance < minDistance) {
            insideLocationId = location.id;
            minDistance = distance;
          }
        }
      }

      // CORE BEHAVIOR: Auto check-in if inside location and not checked in
      if (isInsideLocation && insideLocationId != null && !_currentState.isCheckedIn) {
        debugPrint('[AttendanceService] ✅ Location detected - Auto check-in triggered at ${DateTime.now()}');
        debugPrint('[AttendanceService] Inside location: $insideLocationId, Distance: ${minDistance?.toStringAsFixed(2)}m');
        try {
          await _performCheckIn(insideLocationId);
          debugPrint('[AttendanceService] ✅ Auto check-in completed successfully');
        } catch (e) {
          debugPrint('[AttendanceService] ❌ Auto check-in failed: $e');
          // Don't throw - will retry on next check
        }
      }
      // CORE BEHAVIOR: Auto check-out if outside location and checked in
      // PERMANENT ON: Toggle stays ON - only checks out, doesn't disable toggle
      else if (!isInsideLocation && _currentState.isCheckedIn) {
        debugPrint('[AttendanceService] ⚠️ Outside location range - Auto check-out triggered at ${DateTime.now()}');
        debugPrint('[AttendanceService] ℹ️ Toggle remains ON - will auto check-in when back in range');
        await _performCheckOut();
      } else {
        debugPrint('[AttendanceService] Location check: Inside=${isInsideLocation}, CheckedIn=${_currentState.isCheckedIn}');
      }
    } catch (e) {
      // Log error but don't crash - location check will retry in 30 minutes
      print('[AttendanceService] ❌ Periodic location validation error: $e');
      // Try to use fallback location for immediate check-in if possible
      try {
        final customLocation = await LocationConfig.getCustomLocation();
        if (customLocation != null && !_currentState.isCheckedIn) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );
          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            customLocation.latitude,
            customLocation.longitude,
          );
          if (distance <= customLocation.radius) {
            print('[AttendanceService] ✅ Fallback location check - Auto check-in triggered');
            await _performCheckIn(customLocation.id);
          }
        }
      } catch (fallbackError) {
        print('[AttendanceService] Fallback location check also failed: $fallbackError');
      }
    }
  }

  /// Perform check-in - calls BOTH APIs (auto attendance + manual)
  Future<void> _performCheckIn(String locationId) async {
    // Prevent duplicate check-ins
    if (_currentState.isCheckedIn) {
      // If already checked in to same location, ignore
      if (_currentState.currentLocationId == locationId) {
        return;
      }
      // If checked in to different location, check-out first
      await _performCheckOut();
    }

    try {
      // Check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[AttendanceService] Location service disabled');
        return;
      }

      // Get current position with timeout
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15), // Timeout after 15 seconds
        ),
      );
      
      debugPrint('[AttendanceService] Periodic validation - Position: ${position.latitude}, ${position.longitude}');

      // Call BOTH APIs - Auto attendance API (with location) + Manual API
      // CRASH-PROOF: Both API calls wrapped in try-catch to prevent crashes
      bool autoApiSuccess = false;
      bool manualApiSuccess = false;
      
      // 1. Auto attendance check-in API (with location)
      try {
        final response = await _apiClient.checkIn(
          latitude: position.latitude,
          longitude: position.longitude,
          notes: 'Auto check-in',
        );
        autoApiSuccess = true;
        debugPrint('[AttendanceService] ✅ Auto attendance check-in API succeeded');
      } catch (e) {
        debugPrint('[AttendanceService] ⚠️ Auto attendance check-in API failed: $e');
        // Continue to try manual API
      }

      // 2. Also call manual check-in API (with location and notes) - BOTH APIs CALLED
      try {
        final authService = AuthApiService();
        await authService.checkIn(notes: 'Auto check-in');
        manualApiSuccess = true;
        debugPrint('[AttendanceService] ✅ Manual check-in API succeeded');
        authService.dispose();
      } catch (e) {
        debugPrint('[AttendanceService] ⚠️ Manual check-in API failed: $e');
        // Continue with state update if at least one API succeeded
      }

      // If both APIs failed, don't update state (but don't crash)
      if (!autoApiSuccess && !manualApiSuccess) {
        debugPrint('[AttendanceService] ❌ Both check-in APIs failed - not updating state');
        throw AttendanceException('Both check-in APIs failed. Please try again.');
      }
      
      debugPrint('[AttendanceService] ✅ Check-in completed (Auto: $autoApiSuccess, Manual: $manualApiSuccess)');

      // Update local state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_checked_in', true);
      await prefs.setString('check_in_location_id', locationId);
      await prefs.setString('check_in_timestamp', DateTime.now().toIso8601String());

      _updateState(_currentState.copyWith(
        isCheckedIn: true,
        currentLocationId: locationId,
        checkInTimestamp: DateTime.now(),
        error: null,
      ));
      
      print('[AttendanceService] Auto check-in successful at ${DateTime.now()}');
    } catch (e) {
      _updateState(_currentState.copyWith(error: e.toString()));
      rethrow;
    }
  }


  /// Perform check-out
  /// [realCheckoutTime] - Optional real-time checkout time (used when toggle is turned OFF)
  /// Multiple check-outs are now allowed, so we don't check if checked in
  Future<void> _performCheckOut({DateTime? realCheckoutTime}) async {
    // Multiple check-outs are allowed, so we can check-out even if not checked in
    // Remove the check-in requirement - allow check-out anytime

    try {
      // Capture real checkout time if not provided (for manual checkouts)
      final checkoutTime = realCheckoutTime ?? DateTime.now();
      debugPrint('[AttendanceService] ✅ Check-out time: ${checkoutTime.toIso8601String()}');
      
      // Check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[AttendanceService] Location service disabled');
        return;
      }

      // Get current position with timeout
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15), // Timeout after 15 seconds
        ),
      );
      
      debugPrint('[AttendanceService] Periodic validation - Position: ${position.latitude}, ${position.longitude}');

      // Call BOTH APIs - Auto attendance API + Manual API
      // CRASH-PROOF: Both API calls wrapped in try-catch to prevent crashes
      bool autoApiSuccess = false;
      bool manualApiSuccess = false;
      
      // 1. Auto attendance check-out API (with location and notes)
      try {
        await _apiClient.checkOut(
          latitude: position.latitude,
          longitude: position.longitude,
          notes: 'Auto check-out',
        );
        autoApiSuccess = true;
        debugPrint('[AttendanceService] ✅ Auto attendance check-out API succeeded');
      } catch (e) {
        debugPrint('[AttendanceService] ⚠️ Auto attendance check-out API failed: $e');
        // Continue to try manual API
      }

      // 2. Also call manual check-out API (with location and notes) - BOTH APIs CALLED
      try {
        final authService = AuthApiService();
        await authService.checkOut(notes: 'Auto check-out');
        manualApiSuccess = true;
        debugPrint('[AttendanceService] ✅ Manual check-out API succeeded');
        authService.dispose();
      } catch (e) {
        debugPrint('[AttendanceService] ⚠️ Manual check-out API failed: $e');
        // Continue with state update if at least one API succeeded
      }

      // If both APIs failed, don't update state (but don't crash)
      // However, with multiple check-outs allowed, we should still allow check-out even if APIs fail
      // The backend will handle the check-out logic
      if (!autoApiSuccess && !manualApiSuccess) {
        debugPrint('[AttendanceService] ⚠️ Both check-out APIs failed, but allowing check-out to proceed');
        // Don't throw error - allow check-out to proceed
        // The user can still check-out manually via the button
      }
      
      debugPrint('[AttendanceService] ✅ Check-out completed (Auto: $autoApiSuccess, Manual: $manualApiSuccess)');

      // Update local state with real checkout time
      // Multiple check-outs are allowed, so we don't necessarily set isCheckedIn to false
      // The state will be updated based on the actual check-out response
      final prefs = await SharedPreferences.getInstance();
      // Store real checkout time
      await prefs.setString('check_out_timestamp', checkoutTime.toIso8601String());
      debugPrint('[AttendanceService] ✅ Real checkout time stored: ${checkoutTime.toIso8601String()}');

      // Only update state if at least one API succeeded
      if (autoApiSuccess || manualApiSuccess) {
        _updateState(_currentState.copyWith(
          isCheckedIn: false,
          currentLocationId: null,
          checkInTimestamp: null,
          error: null,
        ));
      }
      
      debugPrint('[AttendanceService] ✅ Check-out completed at ${checkoutTime.toIso8601String()} (real-time)');
    } catch (e) {
      _updateState(_currentState.copyWith(error: e.toString()));
      rethrow;
    }
  }

  /// Request location permissions
  Future<bool> _requestLocationPermissions() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[AttendanceService] ⚠️ Location services are disabled');
        // Try to open location settings
        try {
          await Geolocator.openLocationSettings();
        } catch (e) {
          debugPrint('[AttendanceService] Failed to open location settings: $e');
        }
        return false;
      }

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('[AttendanceService] Current permission status: $permission');
      
      // Request permission if denied
      if (permission == LocationPermission.denied) {
        debugPrint('[AttendanceService] Requesting location permission...');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('[AttendanceService] ❌ Location permission denied by user');
          return false;
        }
      }

      // Check if permanently denied
      if (permission == LocationPermission.deniedForever) {
        debugPrint('[AttendanceService] ❌ Location permission denied forever');
        // Try to open app settings
        try {
          await Geolocator.openAppSettings();
        } catch (e) {
          debugPrint('[AttendanceService] Failed to open app settings: $e');
        }
        return false;
      }

      // For Android, request background location if we have whileInUse
      // Note: Background location requires additional user action in settings
      if (permission == LocationPermission.whileInUse) {
        debugPrint('[AttendanceService] ✅ While-in-use permission granted');
        // Background location will work when app is in foreground
        // For background, user needs to grant it in settings
      } else if (permission == LocationPermission.always) {
        debugPrint('[AttendanceService] ✅ Always/Background permission granted');
      }

      debugPrint('[AttendanceService] ✅ Location permission granted: $permission');
      return true;
    } catch (e) {
      debugPrint('[AttendanceService] ❌ Permission request error: $e');
      return false;
    }
  }

  /// Update state and notify listeners
  void _updateState(ServiceAttendanceState newState) {
    _currentState = newState;
    _stateController.add(_currentState);
  }

  /// Get current state
  ServiceAttendanceState getCurrentState() => _currentState;

  /// Validate current location - called on app resume
  /// Restarts monitoring if enabled and performs immediate location check
  Future<void> validateCurrentLocation() async {
    if (!_currentState.isEnabled) return;

    try {
      debugPrint('[AttendanceService] 🔄 App resumed - Validating location and restarting service...');
      
      // Check permissions
      final hasPermission = await _requestLocationPermissions();
      if (!hasPermission) {
        debugPrint('[AttendanceService] ⚠️ Permissions not granted on resume');
        return;
      }

      // Restart geofence monitoring
      try {
        await _geofenceManager.stopMonitoring();
      } catch (e) {
        // Ignore if not monitoring
      }
      await _geofenceManager.startMonitoring();
      debugPrint('[AttendanceService] ✅ Geofence monitoring restarted');

      // Re-register background task
      try {
        await BackgroundLocationWorker.registerPeriodicTask();
        debugPrint('[AttendanceService] ✅ Background task re-registered');
      } catch (e) {
        debugPrint('[AttendanceService] ⚠️ Background task re-registration failed: $e');
      }

      // Perform immediate location validation
      try {
        await _periodicLocationValidation();
        debugPrint('[AttendanceService] ✅ Location validation completed on resume');
      } catch (e) {
        debugPrint('[AttendanceService] ⚠️ Location validation failed on resume: $e');
      }
    } catch (e) {
      debugPrint('[AttendanceService] ❌ Error validating location on resume: $e');
    }
  }

  /// Refresh work locations from backend
  Future<void> refreshWorkLocations() async {
    try {
      final workLocations = await _apiClient.getWorkLocations();
      
      // Update LocationRepository
      final locationRepo = LocationRepository.instance;
      locationRepo.setLocations(workLocations);
      
      await _geofenceManager.updateWorkLocations(workLocations);
      
      // Notify AttendanceController if it exists
      final controller = AttendanceServiceFactory.getAttendanceController();
      if (controller != null && controller.isReady) {
        await controller.reloadLocations(workLocations);
        debugPrint('[AttendanceService] ✅ AttendanceController notified of location changes');
      }
      
      // Update foreground service locations (Android only)
      if (Platform.isAndroid && _currentState.isEnabled) {
        try {
          await ForegroundAttendanceService.updateWorkLocations(workLocations);
          debugPrint('[AttendanceService] ✅ Foreground service locations updated');
        } catch (e) {
          debugPrint('[AttendanceService] ⚠️ Failed to update foreground service locations: $e');
        }
      }
    } catch (e) {
      _updateState(_currentState.copyWith(error: e.toString()));
    }
  }
  
  /// Handle events from foreground service
  Future<void> _handleForegroundServiceEvent(AttendanceServiceEvent event) async {
    debugPrint('[AttendanceService] Foreground service event: ${event.type}');
    
    try {
      if (event.type == AttendanceEventType.checkIn) {
        // Service performed check-in - sync with our state
        if (!_currentState.isCheckedIn && event.locationId != null) {
          // Update state to match service
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_checked_in', true);
          await prefs.setString('check_in_location_id', event.locationId!);
          await prefs.setString('check_in_timestamp', event.timestamp.toIso8601String());
          
          _updateState(_currentState.copyWith(
            isCheckedIn: true,
            currentLocationId: event.locationId,
            checkInTimestamp: event.timestamp,
            error: null,
          ));
          
          debugPrint('[AttendanceService] ✅ State synced with foreground service check-in');
        }
      } else if (event.type == AttendanceEventType.checkOut) {
        // Service performed check-out - sync with our state
        if (_currentState.isCheckedIn) {
          // Update state to match service
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_checked_in', false);
          await prefs.remove('check_in_location_id');
          await prefs.remove('check_in_timestamp');
          await prefs.setString('check_out_timestamp', event.timestamp.toIso8601String());
          
          _updateState(_currentState.copyWith(
            isCheckedIn: false,
            currentLocationId: null,
            checkInTimestamp: null,
            error: null,
          ));
          
          debugPrint('[AttendanceService] ✅ State synced with foreground service check-out');
        }
      }
    } catch (e) {
      debugPrint('[AttendanceService] Error handling foreground service event: $e');
    }
  }
  
  /// Restore foreground service if it was running before app restart
  Future<void> _restoreForegroundService() async {
    if (!Platform.isAndroid) return;
    
    try {
      // Check if service is already running
      final isRunning = await ForegroundAttendanceService.isServiceRunning();
      if (isRunning) {
        debugPrint('[AttendanceService] Foreground service already running');
        
        // Update locations in case they changed
        final workLocations = _geofenceManager.getWorkLocations();
        if (workLocations.isNotEmpty) {
          await ForegroundAttendanceService.updateWorkLocations(workLocations);
        }
        
        // Sync state from service (service persists state in SharedPreferences)
        await _syncStateFromService();
        return;
      }
      
      // Service not running - start it
      final workLocations = _geofenceManager.getWorkLocations();
      if (workLocations.isEmpty) {
        // Try to get locations first
        try {
          final locations = await _apiClient.getWorkLocations();
          if (locations.isNotEmpty) {
            await _geofenceManager.updateWorkLocations(locations);
            final started = await ForegroundAttendanceService.startService(locations);
            if (started) {
              debugPrint('[AttendanceService] ✅ Foreground service restored');
              await _syncStateFromService();
            }
          }
        } catch (e) {
          debugPrint('[AttendanceService] ⚠️ Failed to restore foreground service: $e');
        }
      } else {
        final started = await ForegroundAttendanceService.startService(workLocations);
        if (started) {
          debugPrint('[AttendanceService] ✅ Foreground service restored');
          await _syncStateFromService();
        }
      }
    } catch (e) {
      debugPrint('[AttendanceService] ⚠️ Error restoring foreground service: $e');
    }
  }
  
  /// Sync state from foreground service SharedPreferences
  Future<void> _syncStateFromService() async {
    try {
      // The service uses its own SharedPreferences file
      // We need to read from the same file or use a different mechanism
      // For now, we'll rely on the service events to sync state
      debugPrint('[AttendanceService] State sync from service - relying on events');
    } catch (e) {
      debugPrint('[AttendanceService] Error syncing state from service: $e');
    }
  }


  /// Manual check-in (for button clicks)
  Future<void> manualCheckIn() async {
    if (!_currentState.isEnabled) {
      // If not enabled, enable it first
      await enable();
    }
    
    // Get current location and find nearest work location
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      
      final workLocations = await _apiClient.getWorkLocations();
      if (workLocations.isEmpty) {
        throw AttendanceException('No work locations configured');
      }
      
      // Find nearest location
      String? nearestLocationId;
      double minDistance = double.infinity;
      
      for (final location in workLocations) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          location.latitude,
          location.longitude,
        );
        
        if (distance < minDistance) {
          minDistance = distance;
          nearestLocationId = location.id;
        }
      }
      
      if (nearestLocationId != null) {
        await _performCheckIn(nearestLocationId);
      } else {
        throw AttendanceException('Could not determine work location');
      }
    } catch (e) {
      _updateState(_currentState.copyWith(error: e.toString()));
      rethrow;
    }
  }

  /// Manual check-out (for button clicks)
  /// PERMANENT ON BEHAVIOR: Manual check-out does NOT disable auto attendance toggle
  /// Toggle remains ON - user can only disable via toggle switch
  Future<void> manualCheckOut() async {
    await _performCheckOut();
    
    // PERMANENT ON: Do NOT disable auto attendance on manual check-out
    // Toggle stays ON - only user can disable via toggle switch
    // This allows auto check-in to work again when user returns to location
    
    debugPrint('[AttendanceService] Manual check-out completed - Auto attendance remains ON');
  }

  /// Dispose resources
  void dispose() {
    _periodicLocationCheckTimer?.cancel();
    _geofenceSubscription?.cancel();
    _foregroundServiceSubscription?.cancel();
    _geofenceManager.dispose();
    _apiClient.dispose();
    _stateController.close();
  }
}

/// Service attendance state model (legacy)
/// NOTE: AttendanceState is owned by attendance_controller.dart
/// This class is renamed to ServiceAttendanceState to avoid conflicts
class ServiceAttendanceState {
  final bool isEnabled;
  final bool isCheckedIn;
  final String? currentLocationId;
  final DateTime? checkInTimestamp;
  final String? error;

  ServiceAttendanceState({
    required this.isEnabled,
    required this.isCheckedIn,
    this.currentLocationId,
    this.checkInTimestamp,
    this.error,
  });

  factory ServiceAttendanceState.initial() {
    return ServiceAttendanceState(
      isEnabled: false,
      isCheckedIn: false,
    );
  }

  ServiceAttendanceState copyWith({
    bool? isEnabled,
    bool? isCheckedIn,
    String? currentLocationId,
    DateTime? checkInTimestamp,
    String? error,
  }) {
    return ServiceAttendanceState(
      isEnabled: isEnabled ?? this.isEnabled,
      isCheckedIn: isCheckedIn ?? this.isCheckedIn,
      currentLocationId: currentLocationId ?? this.currentLocationId,
      checkInTimestamp: checkInTimestamp ?? this.checkInTimestamp,
      error: error,
    );
  }
}

/// Custom exception for attendance service
class AttendanceException implements Exception {
  final String message;
  AttendanceException(this.message);

  @override
  String toString() => 'AttendanceException: $message';
}

