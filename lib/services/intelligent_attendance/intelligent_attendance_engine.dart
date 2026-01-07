import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../geofence_manager.dart';
import '../attendance_api_client.dart';
import '../auth_api_service.dart';
import '../location_repository.dart';
import 'models/attendance_event.dart';
import 'storage/local_shadow_database.dart';
import 'sync/sync_manager.dart';

/// Intelligent Attendance Engine with 1-minute grace timers
/// Auto toggle control driven by location intelligence
class IntelligentAttendanceEngine {
  final GeofenceManager _geofenceManager;
  final AttendanceApiClient _apiClient;
  final LocalShadowDatabase _database = LocalShadowDatabase.instance;
  late final SyncManager _syncManager;

  // Grace timer state
  Timer? _entryGraceTimer;
  Timer? _exitGraceTimer;
  DateTime? _entryGraceStartTime;
  DateTime? _exitGraceStartTime;
  String? _pendingLocationId;

  // Current state
  bool _isInsideLocation = false;
  bool _toggleState = false; // Auto-controlled by location
  StreamSubscription<GeofenceEvent>? _geofenceSubscription;

  // Stream controllers
  final StreamController<bool> _toggleController =
      StreamController<bool>.broadcast();
  Stream<bool> get toggleStream => _toggleController.stream;

  IntelligentAttendanceEngine({
    required GeofenceManager geofenceManager,
    required AttendanceApiClient apiClient,
  })  : _geofenceManager = geofenceManager,
        _apiClient = apiClient {
    _syncManager = SyncManager(apiClient: apiClient);
    _initialize();
  }

  /// Initialize engine
  Future<void> _initialize() async {
    await _database.initialize();
    await _syncManager.start();

    // Listen to geofence events
    _geofenceSubscription = _geofenceManager.eventStream.listen(
      _handleGeofenceEvent,
      onError: (error) {
        debugPrint('[IntelligentEngine] ⚠️ Geofence error: $error');
      },
    );

    // Start geofence monitoring
    try {
      await _geofenceManager.startMonitoring();
      debugPrint('[IntelligentEngine] ✅ Geofence monitoring started');
      
      // Check if already at location (for immediate check-in if already inside)
      // Do immediate check first, then periodic checks
      _checkInitialLocation();
    } catch (e) {
      debugPrint('[IntelligentEngine] ⚠️ Failed to start geofence monitoring: $e');
    }

    debugPrint('[IntelligentEngine] ✅ Engine initialized');
  }

  /// Check initial location after login/startup
  Future<void> _checkInitialLocation() async {
    // Wait a bit for geofence to initialize
    await Future.delayed(const Duration(seconds: 3));
    
    try {
      debugPrint('[IntelligentEngine] 🔍 Checking initial location after login...');
      
      // FIXED: Check LocationRepository instead of infinite retry
      final locationRepo = LocationRepository.instance;
      final workLocations = _geofenceManager.getWorkLocations();
      
      if (workLocations.isEmpty) {
        if (locationRepo.hasLocations) {
          // Locations exist but not in geofence manager - update it
          debugPrint('[IntelligentEngine] 📍 Updating geofence manager with LocationRepository locations');
          await _geofenceManager.initialize(locationRepo.workLocations);
          // Retry once after update
          Future.delayed(const Duration(seconds: 1), () => _checkInitialLocation());
          return;
        } else if (!locationRepo.isLoaded) {
          // Still loading - wait once more
          debugPrint('[IntelligentEngine] ⏱️ Locations still loading, waiting 2 seconds...');
          Future.delayed(const Duration(seconds: 2), () => _checkInitialLocation());
          return;
        } else {
          // Loaded but empty - stop retrying
          debugPrint('[IntelligentEngine] ❌ No locations available - stopping retry');
          return;
        }
      }

      debugPrint('[IntelligentEngine] 📍 Found ${workLocations.length} work locations');

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      debugPrint('[IntelligentEngine] 📍 Current position: ${position.latitude}, ${position.longitude}');

      // Check if inside any location
      for (final location in workLocations) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          location.latitude,
          location.longitude,
        );

        debugPrint('[IntelligentEngine] 📍 Location: ${location.name}, Distance: ${distance.toStringAsFixed(2)}m, Radius: ${location.radius}m');

        if (distance <= location.radius) {
          debugPrint('[IntelligentEngine] ✅ FOUND! Already at location: ${location.name} (${location.id})');
          debugPrint('[IntelligentEngine] 📍 Distance: ${distance.toStringAsFixed(2)}m (within ${location.radius}m radius)');
          
          if (!_isInsideLocation) {
            debugPrint('[IntelligentEngine] ⏱️ Starting 1-minute entry grace timer NOW...');
            debugPrint('[IntelligentEngine] ⏱️ After 1 minute, automatic check-in will happen');
            await _handleEntry(location.id);
          } else {
            debugPrint('[IntelligentEngine] ℹ️ Already inside location and checked in');
          }
          return; // Found location, exit
        }
      }
      
      debugPrint('[IntelligentEngine] ⚠️ Not inside any work location currently');
    } catch (e) {
      debugPrint('[IntelligentEngine] ⚠️ Error checking initial location: $e');
      // Retry after 3 seconds
      Future.delayed(const Duration(seconds: 3), () => _checkInitialLocation());
    }
  }

  /// Handle geofence events with grace timers
  Future<void> _handleGeofenceEvent(GeofenceEvent event) async {
    debugPrint('[IntelligentEngine] 📍 Geofence event: ${event.type} at ${event.locationId}');

    if (event.type == GeofenceEventType.ENTER) {
      await _handleEntry(event.locationId);
    } else if (event.type == GeofenceEventType.EXIT) {
      await _handleExit(event.locationId);
    }
  }

  /// Handle entry with 1-minute grace timer
  Future<void> _handleEntry(String locationId) async {
    // Cancel any exit grace timer
    _exitGraceTimer?.cancel();
    _exitGraceStartTime = null;

    // If already inside, ignore
    if (_isInsideLocation && _pendingLocationId == locationId) {
      return;
    }

    _pendingLocationId = locationId;
    _entryGraceStartTime = DateTime.now();

    debugPrint('[IntelligentEngine] ⏱️ Entry grace timer started (1 minute)');

    // Start 1-minute grace timer
    _entryGraceTimer?.cancel();
    _entryGraceTimer = Timer(const Duration(minutes: 1), () async {
      // Check if still inside after grace period
      final currentLocationId = _geofenceManager.getCurrentLocationId();
      if (currentLocationId == locationId) {
        debugPrint('[IntelligentEngine] ✅ Still inside after grace period - Auto check-in');
        await _performAutoCheckIn(locationId);
        _isInsideLocation = true;
        _pendingLocationId = null;
        _entryGraceStartTime = null;
      } else {
        debugPrint('[IntelligentEngine] ⚠️ Left location during grace period - Cancelled');
        _pendingLocationId = null;
        _entryGraceStartTime = null;
      }
    });
  }

  /// Handle exit with 1-minute grace timer
  Future<void> _handleExit(String locationId) async {
    // Cancel any entry grace timer
    _entryGraceTimer?.cancel();
    _entryGraceStartTime = null;
    _pendingLocationId = null;

    // If already outside, ignore
    if (!_isInsideLocation) {
      return;
    }

    _exitGraceStartTime = DateTime.now();

    debugPrint('[IntelligentEngine] ⏱️ Exit grace timer started (1 minute)');

    // Start 1-minute grace timer
    _exitGraceTimer?.cancel();
    _exitGraceTimer = Timer(const Duration(minutes: 1), () async {
      // Check if still outside after grace period
      final currentLocationId = _geofenceManager.getCurrentLocationId();
      if (currentLocationId == null) {
        debugPrint('[IntelligentEngine] ✅ Still outside after grace period - Auto check-out');
        await _performAutoCheckOut();
        _isInsideLocation = false;
        _exitGraceStartTime = null;
      } else {
        debugPrint('[IntelligentEngine] ⚠️ Returned to location during grace period - Cancelled');
        _exitGraceStartTime = null;
      }
    });
  }

  /// Perform auto check-in
  Future<void> _performAutoCheckIn(String locationId) async {
    try {
      // Get current position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Get location name
      final workLocations = _geofenceManager.getWorkLocations();
      final location = workLocations.firstWhere(
        (loc) => loc.id == locationId,
        orElse: () => workLocations.first,
      );

      // Check connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline = !connectivityResult.contains(ConnectivityResult.none);

      // Generate event ID before saving
      final eventId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Create event with ID
      final event = AttendanceEvent(
        id: eventId,
        timestamp: DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
        locationName: location.name,
        locationId: locationId,
        isAuto: true,
        isOnline: isOnline,
        eventType: 'CHECK_IN',
        notes: 'Auto check-in',
      );

      // Save to local database first (offline-first)
      await _database.saveEvent(event);

      // Try to sync if online - Call BOTH APIs
      if (isOnline) {
        try {
          // Call AttendanceApiClient
          final response = await _apiClient.checkIn(
            latitude: position.latitude,
            longitude: position.longitude,
            notes: 'Auto check-in',
          );
          
          debugPrint('[IntelligentEngine] ✅ Check-in successful: ${response.id}');
          
          await _database.markAsSynced(eventId);
          debugPrint('[IntelligentEngine] ✅ Auto check-in synced to server (both APIs)');
        } catch (e) {
          debugPrint('[IntelligentEngine] ⚠️ Auto check-in API failed (saved locally): $e');
        }
      }

      // Auto toggle ON - This will trigger the integration to enable attendance service
      _toggleState = true;
      _toggleController.add(_toggleState);
      debugPrint('[IntelligentEngine] ✅ Toggle auto-enabled (ON) - Check-in completed');

    } catch (e) {
      debugPrint('[IntelligentEngine] ❌ Auto check-in failed: $e');
    }
  }

  /// Perform auto check-out
  Future<void> _performAutoCheckOut() async {
    try {
      // Get current position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Check connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline = !connectivityResult.contains(ConnectivityResult.none);

      // Generate event ID before saving
      final eventId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Create event with ID
      final event = AttendanceEvent(
        id: eventId,
        timestamp: DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
        isAuto: true,
        isOnline: isOnline,
        eventType: 'CHECK_OUT',
        notes: 'Auto check-out',
      );

      // Save to local database first (offline-first)
      await _database.saveEvent(event);

      // Try to sync if online - Call BOTH APIs
      if (isOnline) {
        try {
          // Call AttendanceApiClient
          final response = await _apiClient.checkOut(
            latitude: position.latitude,
            longitude: position.longitude,
            notes: 'Auto check-out',
          );
          
          debugPrint('[IntelligentEngine] ✅ Check-out successful: ${response.id}');
          debugPrint('[IntelligentEngine] 📊 Work duration: ${response.workDurationMinutes} minutes');
          
          await _database.markAsSynced(eventId);
          debugPrint('[IntelligentEngine] ✅ Auto check-out synced to server (both APIs)');
        } catch (e) {
          debugPrint('[IntelligentEngine] ⚠️ Auto check-out API failed (saved locally): $e');
        }
      }

      // Auto toggle OFF - This will trigger the integration to disable attendance service
      _toggleState = false;
      _toggleController.add(_toggleState);
      debugPrint('[IntelligentEngine] ✅ Toggle auto-disabled (OFF) - Check-out completed');

    } catch (e) {
      debugPrint('[IntelligentEngine] ❌ Auto check-out failed: $e');
    }
  }

  /// Save manual check-in event (called from UI buttons)
  Future<void> saveManualCheckIn({
    required double latitude,
    required double longitude,
    String? locationName,
    String? locationId,
    String? notes,
  }) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline = !connectivityResult.contains(ConnectivityResult.none);

      final event = AttendanceEvent(
        timestamp: DateTime.now(),
        latitude: latitude,
        longitude: longitude,
        locationName: locationName,
        locationId: locationId,
        isAuto: false, // Manual check-in
        isOnline: isOnline,
        eventType: 'CHECK_IN',
        notes: notes ?? 'Manual check-in',
      );

      await _database.saveEvent(event);
      debugPrint('[IntelligentEngine] ✅ Manual check-in saved to database');
    } catch (e) {
      debugPrint('[IntelligentEngine] ❌ Failed to save manual check-in: $e');
    }
  }

  /// Save manual check-out event (called from UI buttons)
  Future<void> saveManualCheckOut({
    required double latitude,
    required double longitude,
    String? notes,
  }) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline = !connectivityResult.contains(ConnectivityResult.none);

      final event = AttendanceEvent(
        timestamp: DateTime.now(),
        latitude: latitude,
        longitude: longitude,
        isAuto: false, // Manual check-out
        isOnline: isOnline,
        eventType: 'CHECK_OUT',
        notes: notes ?? 'Manual check-out',
      );

      await _database.saveEvent(event);
      debugPrint('[IntelligentEngine] ✅ Manual check-out saved to database');
    } catch (e) {
      debugPrint('[IntelligentEngine] ❌ Failed to save manual check-out: $e');
    }
  }

  /// Get events for calendar display
  Future<List<AttendanceEvent>> getEventsForDate(DateTime date) async {
    return await _database.getEventsForDate(date);
  }

  /// Get events for date range
  Future<List<AttendanceEvent>> getEventsForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    return await _database.getEventsForDateRange(startDate, endDate);
  }

  /// Get current toggle state
  bool get toggleState => _toggleState;

  /// Dispose resources
  void dispose() {
    _entryGraceTimer?.cancel();
    _exitGraceTimer?.cancel();
    _geofenceSubscription?.cancel();
    _syncManager.stop();
    _toggleController.close();
    debugPrint('[IntelligentEngine] ✅ Engine disposed');
  }
}

