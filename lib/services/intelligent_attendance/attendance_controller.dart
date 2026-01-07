import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../geofence_manager.dart';
import '../attendance_api_client.dart';
import '../auth_api_service.dart';
import '../location_repository.dart';
import 'models/attendance_event.dart';
import 'storage/local_shadow_database.dart';
import 'sync/sync_manager.dart';

class AttendanceState {
  final String userId;
  final String date; // YYYY-MM-DD
  final bool enabled;
  final bool checkedIn;
  final bool manuallyDisabled;
  final String? insideLocationId;
  final DateTime? checkInTime;

  AttendanceState({
    required this.userId,
    required this.date,
    required this.enabled,
    required this.checkedIn,
    required this.manuallyDisabled,
    this.insideLocationId,
    this.checkInTime,
  });

  bool get isValid => !(enabled == false && checkedIn == true);
  
  bool isForToday() {
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return date == todayStr;
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'date': date,
      'enabled': enabled,
      'checkedIn': checkedIn,
      'manuallyDisabled': manuallyDisabled,
      'insideLocationId': insideLocationId,
      'checkInTime': checkInTime?.toIso8601String(),
    };
  }

  static AttendanceState? fromJson(Map<String, dynamic> json) {
    try {
      final state = AttendanceState(
        userId: json['userId'] as String,
        date: json['date'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        checkedIn: json['checkedIn'] as bool? ?? false,
        manuallyDisabled: json['manuallyDisabled'] as bool? ?? false,
        insideLocationId: json['insideLocationId'] as String?,
        checkInTime: json['checkInTime'] != null
            ? DateTime.parse(json['checkInTime'] as String).toLocal()
            : null,
      );
      return state.isValid ? state : null;
    } catch (e) {
      return null;
    }
  }
}

class AttendanceController {
  static AttendanceController? _instance;
  static String? _currentSessionUserId;
  static bool _isInitializing = false;

  final GeofenceManager _geofenceManager;
  final AttendanceApiClient _apiClient;
  final LocalShadowDatabase _database = LocalShadowDatabase.instance;
  late final SyncManager _syncManager;
  final AuthApiService _authService = AuthApiService();

  String? _userId;
  bool _engineRunning = false;
  bool _engineReady = false;
  Timer? _periodicValidationTimer;
  Timer? _entryGraceTimer;
  Timer? _exitGraceTimer;
  DateTime? _entryGraceStartTime;
  DateTime? _exitGraceStartTime;
  String? _pendingLocationId;
  bool _isEnabled = true;
  bool _isSessionCheckedIn = false;
  DateTime? _sessionCheckInTime;
  bool _isManuallyDisabled = false;
  String? _insideLocationId;
  StreamSubscription<GeofenceEvent>? _geofenceSubscription;
  bool _isCheckInInProgress = false;
  bool _isCheckOutInProgress = false;
  bool _isRestoringState = false;
  bool _isLoadingLocations = false;
  bool _isBootstrapInProgress = false;
  bool _isEntryTimerStarting = false;
  bool _isExitTimerStarting = false;
  int _entrySecondsLeft = 0;
  int _exitSecondsLeft = 0;
  String? _lastProcessedEventId;
  DateTime? _lastEventProcessedAt;
  String? _lastKnownDate;
  Timer? _dayChangeCheckTimer;

  bool get _entryTimerRunning => _entryGraceTimer != null && _entryGraceTimer!.isActive;
  bool get _exitTimerRunning => _exitGraceTimer != null && _exitGraceTimer!.isActive;
  bool get isReady => _engineReady && _engineRunning;

  final StreamController<IntelligentAttendanceState> _stateController =
      StreamController<IntelligentAttendanceState>.broadcast();
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  final StreamController<int> _countdownController =
      StreamController<int>.broadcast();

  Stream<IntelligentAttendanceState> get stateStream => _stateController.stream;
  Stream<String> get messageStream => _messageController.stream;
  Stream<int> get countdownStream => _countdownController.stream;

  AttendanceController._internal({
    required GeofenceManager geofenceManager,
    required AttendanceApiClient apiClient,
  })  : _geofenceManager = geofenceManager,
        _apiClient = apiClient {
    _syncManager = SyncManager(apiClient: apiClient);
  }

  static AttendanceController getInstance({
    required GeofenceManager geofenceManager,
    required AttendanceApiClient apiClient,
  }) {
    _instance ??= AttendanceController._internal(
      geofenceManager: geofenceManager,
      apiClient: apiClient,
    );
    return _instance!;
  }

  static AttendanceController? get currentInstance => _instance;

  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
    _currentSessionUserId = null;
    _isInitializing = false;
  }

  String _getStorageKey(String userId, String date) => 'attendance_state_${userId}_$date';
  
  String _getTodayDateString() {
    final today = DateTime.now();
    return '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  }

  Future<AttendanceState?> _loadStateFromStorage(String userId, String date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(userId, date);
      final jsonString = prefs.getString(key);
      if (jsonString == null) return null;
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final state = AttendanceState.fromJson(json);
      if (state != null && state.userId == userId && state.date == date && state.isValid) return state;
      if (state != null && (!state.isValid || state.userId != userId || state.date != date)) {
        await prefs.remove(key);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveStateToStorage(AttendanceState state) async {
    if (!state.isValid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_getStorageKey(state.userId, state.date), jsonEncode(state.toJson()));
    } catch (e) {
      debugPrint('[AttendanceController] Failed to save state: $e');
    }
  }
  
  Future<void> _clearOldStates(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final todayDate = _getTodayDateString();
      for (final key in keys) {
        if (key.startsWith('attendance_state_${userId}_')) {
          final datePart = key.replaceFirst('attendance_state_${userId}_', '');
          if (datePart != todayDate) {
            await prefs.remove(key);
          }
        }
      }
    } catch (e) {
      debugPrint('[AttendanceController] Failed to clear old states: $e');
    }
  }

  Future<void> _clearStateFromStorage(String userId, String date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getStorageKey(userId, date));
    } catch (e) {
      debugPrint('[AttendanceController] Failed to clear state: $e');
    }
  }

  Future<void> _clearAllAttendanceStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('attendance_state_')) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('[AttendanceController] Failed to clear all storage: $e');
    }
  }

  Future<void> shutdown() async {
    if (!_engineRunning) {
      debugPrint('[AttendanceController] ⚠️ Engine not running, shutdown skipped');
      return;
    }
    debugPrint('[AttendanceController] 🔴 Shutting down engine...');
    _engineRunning = false;
    _engineReady = false;
    _entryGraceTimer?.cancel();
    _exitGraceTimer?.cancel();
    _entryGraceTimer = null;
    _exitGraceTimer = null;
    _entryGraceStartTime = null;
    _exitGraceStartTime = null;
    _entrySecondsLeft = 0;
    _exitSecondsLeft = 0;
    _pendingLocationId = null;
    _isEntryTimerStarting = false;
    _isExitTimerStarting = false;
    _periodicValidationTimer?.cancel();
    _periodicValidationTimer = null;
    _dayChangeCheckTimer?.cancel();
    _dayChangeCheckTimer = null;
    _geofenceSubscription?.cancel();
    _geofenceSubscription = null;
    try {
      await _geofenceManager.stopMonitoring();
    } catch (e) {
      debugPrint('[AttendanceController] ⚠️ Failed to stop geofence: $e');
    }
    _syncManager.stop();
    _countdownController.add(0);
    _lastProcessedEventId = null;
    _lastEventProcessedAt = null;
    _lastKnownDate = null;
    debugPrint('[AttendanceController] ✅ Engine shut down');
  }

  Future<void> resetForUser(String userId) async {
    await shutdown();
    if (_userId != null && _userId != userId) {
      final todayDate = _getTodayDateString();
      await _clearStateFromStorage(_userId!, todayDate);
    }
    _userId = null;
    _isSessionCheckedIn = false;
    _sessionCheckInTime = null;
    _isManuallyDisabled = false;
    _insideLocationId = null;
    _isEnabled = true;
    _isCheckInInProgress = false;
    _isCheckOutInProgress = false;
    _isRestoringState = false;
    _isLoadingLocations = false;
    _isBootstrapInProgress = false;
    _isEntryTimerStarting = false;
    _isExitTimerStarting = false;
    _entrySecondsLeft = 0;
    _exitSecondsLeft = 0;
    _lastProcessedEventId = null;
    _lastEventProcessedAt = null;
    _lastKnownDate = null;
    _pendingLocationId = null;
    _entryGraceStartTime = null;
    _exitGraceStartTime = null;
    try {
      await _geofenceManager.stopMonitoring();
    } catch (e) {
      debugPrint('[AttendanceController] Failed to stop geofence in reset: $e');
    }
    if (!_stateController.isClosed) {
      _stateController.add(IntelligentAttendanceState(
        isCheckedIn: false,
        toggleState: false,
        status: 'ABSENT',
        isManuallyDisabled: false,
        isEnabled: true,
        entryTimerRunning: false,
        exitTimerRunning: false,
        entrySecondsLeft: 0,
        exitSecondsLeft: 0,
      ));
    }
  }

  Future<void> restoreStateForUser(String userId) async {
    if (_isRestoringState) {
      debugPrint('[AttendanceController] ⚠️ Already restoring state, ignoring duplicate call');
      return;
    }
    if (_userId == userId && _engineRunning && _engineReady) {
      _emitState();
      return;
    }
    if (_userId != null && _userId != userId) {
      await resetForUser(userId);
    }
    _isRestoringState = true;
    _userId = userId;
    _currentSessionUserId = userId;
    
    // Clear all timers first
    _entryGraceTimer?.cancel();
    _exitGraceTimer?.cancel();
    _entryGraceTimer = null;
    _exitGraceTimer = null;
    _entryGraceStartTime = null;
    _exitGraceStartTime = null;
    _entrySecondsLeft = 0;
    _exitSecondsLeft = 0;
    _pendingLocationId = null;
    _isEntryTimerStarting = false;
    _isExitTimerStarting = false;
    
    final todayDate = _getTodayDateString();
    await _clearOldStates(userId);
    
    _isEnabled = true;
    _isSessionCheckedIn = false;
    _sessionCheckInTime = null;
    _isManuallyDisabled = false;
    _insideLocationId = null;
    
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      
      // MANDATORY: Fetch today's attendance from server - source of truth
      final attendanceRecords = await _authService.getAttendanceRecords(
        userId: userId,
        startDate: startOfDay,
        endDate: endOfDay,
      ).timeout(const Duration(seconds: 10), onTimeout: () => <AttendanceRecord>[]);
      
      AttendanceRecord? todayRecord;
      for (var record in attendanceRecords) {
        if (record.checkInAt != null) {
          final checkInDate = record.checkInAt!.toLocal();
          final checkInStartOfDay = DateTime(
            checkInDate.year,
            checkInDate.month,
            checkInDate.day,
          );
          final todayStartOfDay = DateTime(
            today.year,
            today.month,
            today.day,
          );
          if (checkInStartOfDay == todayStartOfDay && record.checkOutAt == null) {
            todayRecord = record;
            break;
          }
        }
      }
      
      // MANDATORY FIX 1: If today's data is empty, force checkedIn = false
      if (todayRecord == null || todayRecord.checkInAt == null) {
        debugPrint('[AttendanceController] 🌅 New day - no check-in for today, forcing fresh session');
        _isSessionCheckedIn = false;
        _sessionCheckInTime = null;
        _insideLocationId = null;
        _isEnabled = true;
        _isManuallyDisabled = false;
        
        // Load saved state only for preferences (enabled/manuallyDisabled), not check-in status
        final savedState = await _loadStateFromStorage(userId, todayDate);
        if (savedState != null && savedState.userId == userId && savedState.date == todayDate && savedState.isValid) {
          _isEnabled = savedState.enabled;
          _isManuallyDisabled = savedState.manuallyDisabled;
        } else {
          // If saved state is from different date, ignore it completely
          if (savedState != null && savedState.date != todayDate) {
            debugPrint('[AttendanceController] 🗑️ Saved state from different date ($savedState.date), wiping');
            await _clearStateFromStorage(userId, savedState.date);
          }
        }
      } else {
        // Today has check-in record - use server data as source of truth
        _isSessionCheckedIn = true;
        _sessionCheckInTime = todayRecord.checkInAt!.toLocal();
        
        final savedState = await _loadStateFromStorage(userId, todayDate);
        if (savedState != null && savedState.userId == userId && savedState.date == todayDate && savedState.isValid) {
          _isEnabled = savedState.enabled;
          _isManuallyDisabled = savedState.manuallyDisabled;
          _insideLocationId = savedState.insideLocationId;
        }
      }
      
      // Validate state consistency
      if (_isEnabled == false && _isSessionCheckedIn == true) {
        debugPrint('[AttendanceController] ⚠️ Invalid state: enabled=false, checkedIn=true, fixing');
        _isSessionCheckedIn = false;
        _sessionCheckInTime = null;
        _insideLocationId = null;
        _isEnabled = true;
        await _clearStateFromStorage(userId, todayDate);
      }
      
      await _saveCurrentState();
      _emitState();
    } catch (e) {
      debugPrint('[AttendanceController] ❌ Failed to restore state: $e');
      // On error, default to fresh session for today
      _isEnabled = true;
      _isSessionCheckedIn = false;
      _sessionCheckInTime = null;
      _isManuallyDisabled = false;
      _insideLocationId = null;
      await _saveCurrentState();
      _emitState();
    } finally {
      _isRestoringState = false;
    }
  }

  Future<void> _saveCurrentState() async {
    if (_userId == null) return;
    if (_isEnabled == false && _isSessionCheckedIn == true) {
      _isSessionCheckedIn = false;
      _sessionCheckInTime = null;
      _insideLocationId = null;
    }
    final todayDate = _getTodayDateString();
    final state = AttendanceState(
      userId: _userId!,
      date: todayDate,
      enabled: _isEnabled,
      checkedIn: _isSessionCheckedIn,
      manuallyDisabled: _isManuallyDisabled,
      insideLocationId: _insideLocationId,
      checkInTime: _sessionCheckInTime,
    );
    if (state.isValid) {
      await _saveStateToStorage(state);
    }
  }

  void _emitState() {
    if (!_stateController.isClosed) {
      _stateController.add(IntelligentAttendanceState(
        isCheckedIn: _isSessionCheckedIn,
        toggleState: _isSessionCheckedIn,
        status: _isSessionCheckedIn ? 'PRESENT' : 'ABSENT',
        checkInTime: _sessionCheckInTime,
        isManuallyDisabled: _isManuallyDisabled,
        isEnabled: _isEnabled,
        entryTimerRunning: _entryTimerRunning,
        exitTimerRunning: _exitTimerRunning,
        entrySecondsLeft: _entrySecondsLeft,
        exitSecondsLeft: _exitSecondsLeft,
      ));
    }
  }

  Future<void> _startGeofenceMonitoring() async {
    if (_geofenceSubscription != null) {
      _geofenceSubscription?.cancel();
      _geofenceSubscription = null;
    }
    try {
      _geofenceSubscription = _geofenceManager.eventStream.listen(
        _handleGeofenceEvent,
        onError: (error) {
          debugPrint('[AttendanceController] Geofence error: $error');
        },
      );
      await _geofenceManager.startMonitoring();
    } catch (e) {
      debugPrint('[AttendanceController] Failed to start geofence: $e');
    }
  }

  Future<void> _checkDayChange() async {
    if (_userId == null) return;
    final todayDate = _getTodayDateString();
    if (_lastKnownDate != null && _lastKnownDate != todayDate) {
      debugPrint('[AttendanceController] 📅 Day change detected: $_lastKnownDate → $todayDate');
      _lastKnownDate = todayDate;
      // Day changed - restore state for new day
      await restoreStateForUser(_userId!);
      // Re-evaluate location after day change
      if (_engineRunning) {
        await Future.delayed(const Duration(seconds: 1));
        await _evaluateCurrentLocation();
      }
    } else if (_lastKnownDate == null) {
      _lastKnownDate = todayDate;
    }
  }

  Future<void> _validateLocationId(String? locationId) async {
    if (locationId == null) return;
    final workLocations = _geofenceManager.getWorkLocations();
    final locationExists = workLocations.any((loc) => loc.id == locationId);
    if (!locationExists) {
      debugPrint('[AttendanceController] ⚠️ Location $locationId no longer exists, clearing state');
      _insideLocationId = null;
      _pendingLocationId = null;
      if (_entryTimerRunning) {
        _entryGraceTimer?.cancel();
        _entryGraceTimer = null;
        _entryGraceStartTime = null;
        _entrySecondsLeft = 0;
        _isEntryTimerStarting = false;
        _countdownController.add(0);
      }
      await _saveCurrentState();
      _emitState();
    }
  }

  Future<void> _evaluateCurrentLocation() async {
    if (!_isEnabled || _isManuallyDisabled || !_engineRunning || _userId == null) return;
    try {
      final workLocations = _geofenceManager.getWorkLocations();
      if (workLocations.isEmpty) {
        // No locations available - clear any location-dependent state
        if (_insideLocationId != null) {
          _insideLocationId = null;
          await _saveCurrentState();
        }
        if (_entryTimerRunning) {
          _entryGraceTimer?.cancel();
          _entryGraceTimer = null;
          _pendingLocationId = null;
          _entryGraceStartTime = null;
          _entrySecondsLeft = 0;
          _isEntryTimerStarting = false;
          _countdownController.add(0);
          _emitState();
        }
        return;
      }
      
      // Validate current location ID still exists
      await _validateLocationId(_insideLocationId);
      await _validateLocationId(_pendingLocationId);
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      String? foundLocationId;
      for (final location in workLocations) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          location.latitude,
          location.longitude,
        );
        if (distance <= location.radius) {
          foundLocationId = location.id;
          break;
        }
      }
      
      // RULE 1: Inside + Not checked-in → Start entry timer
      if (foundLocationId != null) {
        if (_isSessionCheckedIn) {
          // RULE 2: Inside + Checked-in → Do nothing
          if (_insideLocationId != foundLocationId) {
            _insideLocationId = foundLocationId;
            await _saveCurrentState();
          }
          // Cancel any running timers
          if (_entryTimerRunning) {
            _entryGraceTimer?.cancel();
            _entryGraceTimer = null;
            _pendingLocationId = null;
            _entryGraceStartTime = null;
            _entrySecondsLeft = 0;
            _isEntryTimerStarting = false;
            _countdownController.add(0);
            _emitState();
          }
          if (_exitTimerRunning) {
            _exitGraceTimer?.cancel();
            _exitGraceTimer = null;
            _exitGraceStartTime = null;
            _exitSecondsLeft = 0;
            _isExitTimerStarting = false;
            _countdownController.add(0);
            _emitState();
          }
        } else {
          // RULE 1: Inside + Not checked-in → Start entry timer ONLY if not already running
          if (!_entryTimerRunning && !_isEntryTimerStarting) {
            await _startEntryTimer(foundLocationId);
          }
        }
      } else {
        // RULE 3: Outside + Checked-in → Start exit timer
        if (_isSessionCheckedIn && !_exitTimerRunning) {
          await _startExitTimer();
        }
        // RULE 4: Outside + Not checked-in → Do nothing (cancel entry timer if running)
        else if (!_isSessionCheckedIn && _entryTimerRunning) {
          _entryGraceTimer?.cancel();
          _entryGraceTimer = null;
          _pendingLocationId = null;
          _entryGraceStartTime = null;
          _entrySecondsLeft = 0;
          _countdownController.add(0);
          _emitState();
        }
        if (_insideLocationId != null) {
          _insideLocationId = null;
          await _saveCurrentState();
        }
      }
    } catch (e) {
      debugPrint('[AttendanceController] Location evaluation failed: $e');
    }
  }

  Future<void> reloadLocations(List<WorkLocation> workLocations) async {
    if (!_engineRunning || _userId == null) {
      debugPrint('[AttendanceController] ⚠️ Cannot reload locations - engine not running');
      return;
    }
    if (workLocations.isEmpty) {
      debugPrint('[AttendanceController] ⚠️ Cannot reload - no locations provided');
      return;
    }
    
    debugPrint('[AttendanceController] 🔄 Reloading locations (${workLocations.length} locations)');
    
    // Validate current location ID before updating
    await _validateLocationId(_insideLocationId);
    await _validateLocationId(_pendingLocationId);
    
    // Update geofence manager
    await _geofenceManager.updateWorkLocations(workLocations);
    
    // Re-evaluate current position with new locations
    await Future.delayed(const Duration(milliseconds: 500));
    await _evaluateCurrentLocation();
    
    debugPrint('[AttendanceController] ✅ Locations reloaded and re-evaluated');
  }

  Future<void> bootstrap(String userId, List<WorkLocation> workLocations) async {
    if (_engineRunning && _userId == userId && _engineReady) {
      debugPrint('[AttendanceController] ⚠️ Engine already running for user $userId');
      _emitState();
      return;
    }
    if (_isBootstrapInProgress) {
      debugPrint('[AttendanceController] ⚠️ Bootstrap already in progress, ignoring duplicate call');
      return;
    }
    if (_engineRunning) {
      debugPrint('[AttendanceController] ⚠️ Engine running for different user, shutting down');
      await shutdown();
    }
    if (workLocations.isEmpty) {
      throw Exception('Cannot bootstrap: work locations not loaded');
    }
    _isBootstrapInProgress = true;
    _isInitializing = true;
    try {
      await restoreStateForUser(userId);
      _engineRunning = true;
      await _geofenceManager.initialize(workLocations);
      await _database.initialize();
      await _syncManager.start();
      await _startGeofenceMonitoring();
      _engineReady = true;
      _lastKnownDate = _getTodayDateString();
      _emitState();
      if (_isSessionCheckedIn && _sessionCheckInTime != null) {
        final localTime = _sessionCheckInTime!.toLocal();
        final hour = localTime.hour % 12 == 0 ? 12 : localTime.hour % 12;
        final minutes = localTime.minute.toString().padLeft(2, '0');
        final period = localTime.hour >= 12 ? 'PM' : 'AM';
        _messageController.add('✅ Checked in at $hour:$minutes $period');
      }
      await Future.delayed(const Duration(seconds: 1));
      if (_engineRunning) {
        // Check if it's a new day (not checked in) and user is inside location
        // If so, automatically start the 1-minute check-in timer
        if (!_isSessionCheckedIn) {
          try {
            final workLocations = _geofenceManager.getWorkLocations();
            if (workLocations.isNotEmpty) {
              final position = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: Duration(seconds: 10),
                ),
              );
              String? foundLocationId;
              for (final location in workLocations) {
                final distance = Geolocator.distanceBetween(
                  position.latitude,
                  position.longitude,
                  location.latitude,
                  location.longitude,
                );
                if (distance <= location.radius) {
                  foundLocationId = location.id;
                  break;
                }
              }
              // If user is inside location on a new day, start entry timer
              if (foundLocationId != null && !_entryTimerRunning && !_isEntryTimerStarting) {
                debugPrint('[AttendanceController] 🌅 New day detected - user inside location, starting auto check-in timer');
                await _startEntryTimer(foundLocationId);
              }
            }
          } catch (e) {
            debugPrint('[AttendanceController] ⚠️ Failed to check location for new day auto check-in: $e');
          }
        }
        await _evaluateCurrentLocation();
      }
      _periodicValidationTimer?.cancel();
      _periodicValidationTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) {
          if (_engineRunning) {
            _evaluateCurrentLocation();
          }
        },
      );
      
      // Start day change monitoring
      _lastKnownDate = _getTodayDateString();
      _dayChangeCheckTimer?.cancel();
      _dayChangeCheckTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) {
          if (_engineRunning && _userId != null) {
            _checkDayChange();
          }
        },
      );
    } catch (e) {
      debugPrint('[AttendanceController] ❌ Failed to bootstrap: $e');
      _engineRunning = false;
      _engineReady = false;
      rethrow;
    } finally {
      _isInitializing = false;
      _isBootstrapInProgress = false;
    }
  }

  Future<void> _handleGeofenceEvent(GeofenceEvent event) async {
    if (!_isEnabled || _isManuallyDisabled || !_engineRunning || _userId == null) return;
    
    final eventId = '${event.type}_${event.locationId}_${event.timestamp?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}';
    if (_lastProcessedEventId == eventId) {
      debugPrint('[AttendanceController] ⚠️ Duplicate geofence event ignored: $eventId');
      return;
    }
    if (_lastEventProcessedAt != null && 
        DateTime.now().difference(_lastEventProcessedAt!) < const Duration(milliseconds: 500)) {
      debugPrint('[AttendanceController] ⚠️ Geofence event too soon after last, ignoring');
      return;
    }
    _lastProcessedEventId = eventId;
    _lastEventProcessedAt = DateTime.now();
    
    if (event.type == GeofenceEventType.ENTER) {
      // RULE 2: Inside + Checked-in → Do nothing
      if (_isSessionCheckedIn) {
        if (_insideLocationId != event.locationId) {
          _insideLocationId = event.locationId;
          await _saveCurrentState();
        }
        // Cancel any running timers
        if (_entryTimerRunning) {
          _entryGraceTimer?.cancel();
          _entryGraceTimer = null;
          _pendingLocationId = null;
          _entryGraceStartTime = null;
          _entrySecondsLeft = 0;
          _countdownController.add(0);
          _emitState();
        }
        if (_exitTimerRunning) {
          _exitGraceTimer?.cancel();
          _exitGraceTimer = null;
          _exitGraceStartTime = null;
          _exitSecondsLeft = 0;
          _countdownController.add(0);
          _emitState();
        }
        return;
      }
      // RULE 1: Inside + Not checked-in → Start entry timer ONLY if not already running
      else if (!_entryTimerRunning && !_isEntryTimerStarting) {
        debugPrint('[AttendanceController] 🚀 ENTER event - starting entry timer for location: ${event.locationId}');
        await _startEntryTimer(event.locationId);
      } else {
        debugPrint('[AttendanceController] ⚠️ ENTER event ignored - entry timer already running or starting');
      }
    } 
    else if (event.type == GeofenceEventType.EXIT) {
      // RULE 3: Outside + Checked-in → Start exit timer
      if (_isSessionCheckedIn && !_exitTimerRunning && !_isExitTimerStarting) {
        await _startExitTimer();
      }
      // RULE 4: Outside + Not checked-in → Do nothing (cancel entry timer)
      else if (!_isSessionCheckedIn && _entryTimerRunning) {
        _entryGraceTimer?.cancel();
        _entryGraceTimer = null;
        _pendingLocationId = null;
        _entryGraceStartTime = null;
        _entrySecondsLeft = 0;
        _countdownController.add(0);
        _emitState();
      }
      if (_insideLocationId != null) {
        _insideLocationId = null;
        await _saveCurrentState();
      }
    }
  }

  Future<void> _startEntryTimer(String locationId) async {
    if (_entryTimerRunning) {
      debugPrint('[AttendanceController] ⚠️ Entry timer already running, ignoring start request');
      return;
    }
    if (_isEntryTimerStarting) {
      debugPrint('[AttendanceController] ⚠️ Entry timer start already in progress');
      return;
    }
    if (_isSessionCheckedIn) {
      debugPrint('[AttendanceController] ⚠️ Cannot start entry timer - already checked in');
      return;
    }
    if (!_engineRunning) {
      debugPrint('[AttendanceController] ⚠️ Cannot start entry timer - engine not running');
      return;
    }
    if (_userId == null) {
      debugPrint('[AttendanceController] ⚠️ Cannot start entry timer - no user ID');
      return;
    }
    
    _isEntryTimerStarting = true;
    try {
      debugPrint('[AttendanceController] ⏱️ Starting entry timer for location: $locationId');
      // Cancel exit timer if running (timers never overlap)
      _exitGraceTimer?.cancel();
      _exitGraceTimer = null;
      _exitGraceStartTime = null;
      _exitSecondsLeft = 0;
      
      _pendingLocationId = locationId;
      _entryGraceStartTime = DateTime.now();
      _entrySecondsLeft = 60;
      _messageController.add('Stay inside for 1 minute — auto check-in in progress');
      _countdownController.add(_entrySecondsLeft);
      _emitState();
      
      _entryGraceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_isSessionCheckedIn) {
          debugPrint('[AttendanceController] ✅ Checked in during entry timer - cancelling');
          timer.cancel();
          _entryGraceTimer = null;
          _pendingLocationId = null;
          _entryGraceStartTime = null;
          _entrySecondsLeft = 0;
          _isEntryTimerStarting = false;
          _countdownController.add(0);
          _emitState();
          return;
        }
        if (!_engineRunning) {
          debugPrint('[AttendanceController] ⚠️ Engine stopped during entry timer - cancelling');
          timer.cancel();
          _entryGraceTimer = null;
          _pendingLocationId = null;
          _entryGraceStartTime = null;
          _entrySecondsLeft = 0;
          _isEntryTimerStarting = false;
          _countdownController.add(0);
          _emitState();
          return;
        }
        _entrySecondsLeft--;
        _countdownController.add(_entrySecondsLeft);
        _emitState();
        if (_entrySecondsLeft <= 0) {
          debugPrint('[AttendanceController] ⏱️ Entry timer completed (60s) - proceeding with check-in');
          timer.cancel();
          _entryGraceTimer = null;
          _entrySecondsLeft = 0;
          _isEntryTimerStarting = false;
          _completeEntryGrace(locationId);
        }
      });
    } finally {
      _isEntryTimerStarting = false;
    }
  }

  Future<void> _completeEntryGrace(String locationId) async {
    debugPrint('[AttendanceController] 🔄 Completing entry grace for location: $locationId');
    if (_isSessionCheckedIn) {
      debugPrint('[AttendanceController] ⚠️ Already checked in - skipping entry grace completion');
      _pendingLocationId = null;
      _entryGraceStartTime = null;
      _entrySecondsLeft = 0;
      _isEntryTimerStarting = false;
      _countdownController.add(0);
      _emitState();
      return;
    }
    if (!_engineRunning) {
      debugPrint('[AttendanceController] ⚠️ Engine not running - cannot complete entry grace');
      _pendingLocationId = null;
      _entryGraceStartTime = null;
      _entrySecondsLeft = 0;
      _isEntryTimerStarting = false;
      _countdownController.add(0);
      _emitState();
      return;
    }
    if (_userId == null) {
      debugPrint('[AttendanceController] ⚠️ No user ID - cannot complete entry grace');
      _pendingLocationId = null;
      _entryGraceStartTime = null;
      _entrySecondsLeft = 0;
      _isEntryTimerStarting = false;
      _countdownController.add(0);
      _emitState();
      return;
    }
    if (_isCheckInInProgress) {
      debugPrint('[AttendanceController] ⚠️ Check-in already in progress - skipping');
      return;
    }
    // Validate location still exists
    final workLocations = _geofenceManager.getWorkLocations();
    final locationExists = workLocations.any((loc) => loc.id == locationId);
    if (!locationExists) {
      debugPrint('[AttendanceController] ⚠️ Location $locationId no longer exists - cannot check in');
      _pendingLocationId = null;
      _entryGraceStartTime = null;
      _entrySecondsLeft = 0;
      _isEntryTimerStarting = false;
      _countdownController.add(0);
      _emitState();
      return;
    }
    
    final currentLocationId = _geofenceManager.getCurrentLocationId();
    if (currentLocationId != locationId) {
      debugPrint('[AttendanceController] ⚠️ Location changed during timer - cannot check in. Expected: $locationId, Current: $currentLocationId');
      _pendingLocationId = null;
      _entryGraceStartTime = null;
      _entrySecondsLeft = 0;
      _isEntryTimerStarting = false;
      _countdownController.add(0);
      _emitState();
      return;
    }
    _isCheckInInProgress = true;
    try {
      debugPrint('[AttendanceController] ✅ Proceeding with auto check-in at location: $locationId');
      await _performAutoCheckIn(locationId);
      if (_isSessionCheckedIn) {
        debugPrint('[AttendanceController] ✅ Check-in successful - preventing timer restart');
        _pendingLocationId = null;
        _entryGraceStartTime = null;
        _entrySecondsLeft = 0;
        _isEntryTimerStarting = false;
        _countdownController.add(0);
        _emitState();
        debugPrint('[AttendanceController] ✅ Entry grace completed successfully - user is now checked in');
      } else {
        debugPrint('[AttendanceController] ⚠️ Check-in did not complete - state not updated');
        _pendingLocationId = null;
        _entryGraceStartTime = null;
        _entrySecondsLeft = 0;
        _isEntryTimerStarting = false;
        _countdownController.add(0);
        _emitState();
      }
    } catch (e) {
      debugPrint('[AttendanceController] ❌ Entry grace completion failed: $e');
      _messageController.add('⚠️ Check-in failed: $e');
      _pendingLocationId = null;
      _entryGraceStartTime = null;
      _entrySecondsLeft = 0;
      _isEntryTimerStarting = false;
      _countdownController.add(0);
      _emitState();
    } finally {
      _isCheckInInProgress = false;
    }
  }

  Future<void> _startExitTimer() async {
    if (_exitTimerRunning) {
      debugPrint('[AttendanceController] ⚠️ Exit timer already running, ignoring start request');
      return;
    }
    if (_isExitTimerStarting) {
      debugPrint('[AttendanceController] ⚠️ Exit timer start already in progress');
      return;
    }
    if (!_isSessionCheckedIn) {
      debugPrint('[AttendanceController] ⚠️ Cannot start exit timer - not checked in');
      return;
    }
    if (!_engineRunning) {
      debugPrint('[AttendanceController] ⚠️ Cannot start exit timer - engine not running');
      return;
    }
    if (_userId == null) {
      debugPrint('[AttendanceController] ⚠️ Cannot start exit timer - no user ID');
      return;
    }
    
    _isExitTimerStarting = true;
    try {
      // Cancel entry timer if running (timers never overlap)
      _entryGraceTimer?.cancel();
      _entryGraceTimer = null;
      _entryGraceStartTime = null;
      _pendingLocationId = null;
      _entrySecondsLeft = 0;
      
      _exitGraceStartTime = DateTime.now();
      _exitSecondsLeft = 60;
      _messageController.add('Outside location — returning within 1 minute will cancel checkout');
      _countdownController.add(_exitSecondsLeft);
      _emitState();
      
      _exitGraceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!_engineRunning || !_isSessionCheckedIn) {
          debugPrint('[AttendanceController] ⚠️ Engine stopped or not checked in - cancelling exit timer');
          timer.cancel();
          _exitGraceTimer = null;
          _exitGraceStartTime = null;
          _exitSecondsLeft = 0;
          _isExitTimerStarting = false;
          _countdownController.add(0);
          _emitState();
          return;
        }
        _exitSecondsLeft--;
        _countdownController.add(_exitSecondsLeft);
        _emitState();
        if (_exitSecondsLeft <= 0) {
          debugPrint('[AttendanceController] ⏱️ Exit timer completed (60s) - proceeding with check-out');
          timer.cancel();
          _exitGraceTimer = null;
          _exitSecondsLeft = 0;
          _isExitTimerStarting = false;
          _completeExitGrace();
        }
      });
    } finally {
      _isExitTimerStarting = false;
    }
  }

  Future<void> _completeExitGrace() async {
    debugPrint('[AttendanceController] 🔄 Completing exit grace');
    if (!_isSessionCheckedIn) {
      debugPrint('[AttendanceController] ⚠️ Not checked in - skipping exit grace completion');
      _exitGraceStartTime = null;
      _exitSecondsLeft = 0;
      _isExitTimerStarting = false;
      _countdownController.add(0);
      _emitState();
      return;
    }
    if (!_engineRunning) {
      debugPrint('[AttendanceController] ⚠️ Engine not running - cannot complete exit grace');
      _exitGraceStartTime = null;
      _exitSecondsLeft = 0;
      _isExitTimerStarting = false;
      _countdownController.add(0);
      _emitState();
      return;
    }
    if (_userId == null) {
      debugPrint('[AttendanceController] ⚠️ No user ID - cannot complete exit grace');
      _exitGraceStartTime = null;
      _exitSecondsLeft = 0;
      _isExitTimerStarting = false;
      _countdownController.add(0);
      _emitState();
      return;
    }
    final currentLocationId = _geofenceManager.getCurrentLocationId();
    if (currentLocationId != null) {
      debugPrint('[AttendanceController] ✅ Returned to location during grace period - cancelling checkout');
      _messageController.add('Returned to location during grace period');
      _exitGraceStartTime = null;
      _exitSecondsLeft = 0;
      _isExitTimerStarting = false;
      _countdownController.add(0);
      _insideLocationId = currentLocationId;
      await _saveCurrentState();
      _emitState();
      return;
    }
    if (_isCheckOutInProgress) {
      debugPrint('[AttendanceController] ⚠️ Check-out already in progress - skipping');
      return;
    }
    _isCheckOutInProgress = true;
    try {
      debugPrint('[AttendanceController] ✅ Proceeding with auto check-out');
      await _performAutoCheckOut();
      if (!_isSessionCheckedIn) {
        debugPrint('[AttendanceController] ✅ Check-out successful - preventing timer restart');
        _exitGraceStartTime = null;
        _exitSecondsLeft = 0;
        _isExitTimerStarting = false;
        _countdownController.add(0);
        await _saveCurrentState();
        _emitState();
        debugPrint('[AttendanceController] ✅ Exit grace completed successfully - user is now checked out');
      } else {
        debugPrint('[AttendanceController] ⚠️ Check-out did not complete - state not updated');
        _exitGraceStartTime = null;
        _exitSecondsLeft = 0;
        _isExitTimerStarting = false;
        _countdownController.add(0);
        _emitState();
      }
    } catch (e) {
      debugPrint('[AttendanceController] ❌ Exit grace completion failed: $e');
      _messageController.add('⚠️ Check-out failed: $e');
      _exitGraceStartTime = null;
      _exitSecondsLeft = 0;
      _isExitTimerStarting = false;
      _countdownController.add(0);
      _emitState();
    } finally {
      _isCheckOutInProgress = false;
    }
  }

  Future<void> _performAutoCheckIn(String locationId) async {
    if (_isSessionCheckedIn) {
      debugPrint('[AttendanceController] ⚠️ Already checked in - skipping auto check-in');
      return;
    }
    if (!_engineRunning) {
      debugPrint('[AttendanceController] ⚠️ Engine not running - cannot perform check-in');
      return;
    }
    if (_userId == null) {
      debugPrint('[AttendanceController] ⚠️ No user ID - cannot perform check-in');
      return;
    }
    // Note: _isCheckInInProgress is already set by caller (_completeEntryGrace)
    try {
      if (_userId != null) {
        final today = DateTime.now();
        final startOfDay = DateTime(today.year, today.month, today.day);
        final endOfDay = startOfDay.add(const Duration(days: 1));
        try {
          final attendanceRecords = await _authService.getAttendanceRecords(
            userId: _userId!,
            startDate: startOfDay,
            endDate: endOfDay,
          ).timeout(const Duration(seconds: 3), onTimeout: () => <AttendanceRecord>[]);
          AttendanceRecord? activeCheckIn;
          try {
            activeCheckIn = attendanceRecords.firstWhere(
              (record) => record.checkInAt != null && record.checkOutAt == null,
            );
          } catch (e) {
            activeCheckIn = null;
          }
          if (activeCheckIn != null && activeCheckIn.checkInAt != null) {
            _isSessionCheckedIn = true;
            _sessionCheckInTime = activeCheckIn.checkInAt!.toLocal();
            _insideLocationId = locationId;
            await _saveCurrentState();
            _emitState();
            _messageController.add('✅ Already checked in at ${_formatTime(_sessionCheckInTime!)}');
            return;
          }
        } catch (e) {
          debugPrint('[AttendanceController] API check failed: $e');
        }
      }
      if (_isSessionCheckedIn) return;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final workLocations = _geofenceManager.getWorkLocations();
      final location = workLocations.firstWhere(
        (loc) => loc.id == locationId,
        orElse: () => workLocations.first,
      );
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline = !connectivityResult.contains(ConnectivityResult.none);
      final checkInTime = DateTime.now();
      final eventId = checkInTime.millisecondsSinceEpoch.toString();
      final event = AttendanceEvent(
        id: eventId,
        timestamp: checkInTime,
        latitude: position.latitude,
        longitude: position.longitude,
        locationName: location.name,
        locationId: locationId,
        isAuto: true,
        isOnline: isOnline,
        eventType: 'CHECK_IN',
        notes: 'Auto check-in',
      );
      await _database.saveEvent(event);
      debugPrint('[AttendanceController] ✅ Setting check-in state locally');
      _isSessionCheckedIn = true;
      _sessionCheckInTime = checkInTime;
      _insideLocationId = locationId;
      await _saveCurrentState();
      _emitState();
      _messageController.add('✅ Automatically checked in at ${location.name}');
      debugPrint('[AttendanceController] ✅ Check-in state set: isSessionCheckedIn=$_isSessionCheckedIn, checkInTime=$_sessionCheckInTime');
      if (isOnline) {
        try {
          await _apiClient.checkIn(
            latitude: position.latitude,
            longitude: position.longitude,
            notes: 'Auto check-in',
          );
          await _database.markAsSynced(eventId);
          final updatedRecords = await _authService.getAttendanceRecords(
            userId: _userId!,
            startDate: DateTime(checkInTime.year, checkInTime.month, checkInTime.day),
            endDate: DateTime(checkInTime.year, checkInTime.month, checkInTime.day).add(const Duration(days: 1)),
          ).timeout(const Duration(seconds: 3), onTimeout: () => <AttendanceRecord>[]);
          try {
            final latestRecord = updatedRecords.firstWhere(
              (record) => record.checkInAt != null && record.checkOutAt == null,
            );
            if (latestRecord.checkInAt != null) {
              _sessionCheckInTime = latestRecord.checkInAt!.toLocal();
              await _saveCurrentState();
              _emitState();
            }
          } catch (e) {
            debugPrint('[AttendanceController] Failed to update check-in time: $e');
          }
        } catch (e) {
          debugPrint('[AttendanceController] Check-in API failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[AttendanceController] Auto check-in failed: $e');
      _messageController.add('❌ Check-in failed: $e');
    } finally {
      _isCheckInInProgress = false;
    }
  }

  Future<void> _performAutoCheckOut() async {
    if (!_isSessionCheckedIn) {
      debugPrint('[AttendanceController] ⚠️ Not checked in - skipping auto check-out');
      return;
    }
    if (!_engineRunning) {
      debugPrint('[AttendanceController] ⚠️ Engine not running - cannot perform check-out');
      return;
    }
    if (_userId == null) {
      debugPrint('[AttendanceController] ⚠️ No user ID - cannot perform check-out');
      return;
    }
    // Note: _isCheckOutInProgress is already set by caller (_completeExitGrace)
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline = !connectivityResult.contains(ConnectivityResult.none);
      final eventId = DateTime.now().millisecondsSinceEpoch.toString();
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
      await _database.saveEvent(event);
      debugPrint('[AttendanceController] ✅ Setting check-out state locally');
      _isSessionCheckedIn = false;
      _sessionCheckInTime = null;
      _insideLocationId = null;
      await _saveCurrentState();
      _emitState();
      _messageController.add('✅ Automatically checked out');
      debugPrint('[AttendanceController] ✅ Check-out state set: isSessionCheckedIn=$_isSessionCheckedIn');
      if (isOnline) {
        try {
          await _apiClient.checkOut(
            latitude: position.latitude,
            longitude: position.longitude,
            notes: 'Auto check-out',
          );
          await _database.markAsSynced(eventId);
          debugPrint('[AttendanceController] ✅ Check-out API call successful');
        } catch (e) {
          debugPrint('[AttendanceController] ⚠️ Check-out API failed: $e - but local check-out succeeded');
        }
      }
      debugPrint('[AttendanceController] ✅ Auto check-out completed successfully');
    } catch (e) {
      debugPrint('[AttendanceController] Auto check-out failed: $e');
      _messageController.add('❌ Check-out failed: $e');
    } finally {
      _isCheckOutInProgress = false;
    }
  }

  Future<void> manualToggleOff() async {
    _entryGraceTimer?.cancel();
    _exitGraceTimer?.cancel();
    _entryGraceStartTime = null;
    _exitGraceStartTime = null;
    _entrySecondsLeft = 0;
    _exitSecondsLeft = 0;
    _pendingLocationId = null;
    _countdownController.add(0);
    _emitState();
    _isManuallyDisabled = true;
    if (_isSessionCheckedIn) {
      await _performAutoCheckOut();
    }
    _isSessionCheckedIn = false;
    _sessionCheckInTime = null;
    _insideLocationId = null;
    await _saveCurrentState();
    _emitState();
    _messageController.add('Manual check-out completed');
  }

  Future<List<AttendanceEvent>> getEventsForDate(DateTime date) async {
    return await _database.getEventsForDate(date);
  }

  IntelligentAttendanceState getCurrentState() {
    return IntelligentAttendanceState(
      isCheckedIn: _isSessionCheckedIn,
      toggleState: _isSessionCheckedIn,
      status: _isSessionCheckedIn ? 'PRESENT' : 'ABSENT',
      isManuallyDisabled: _isManuallyDisabled,
      isEnabled: _isEnabled,
      checkInTime: _sessionCheckInTime,
    );
  }

  Future<void> clearAllStorage() async {
    await _clearAllAttendanceStorage();
  }

  /// Handle app resume - check for day change and re-evaluate state
  Future<void> handleAppResume() async {
    if (!_engineRunning || _userId == null) return;
    debugPrint('[AttendanceController] 📱 App resumed - checking state');
    
    // Check for day change
    await _checkDayChange();
    
    // Re-evaluate current location
    await Future.delayed(const Duration(milliseconds: 500));
    await _evaluateCurrentLocation();
    
    // Emit current state
    _emitState();
  }

  String _formatTime(DateTime time) {
    final local = time.isUtc ? time.toLocal() : time;
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minutes = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minutes $period';
  }

  void dispose() {
    shutdown();
    _stateController.close();
    _messageController.close();
    _countdownController.close();
  }
}

class IntelligentAttendanceState {
  final bool isCheckedIn;
  final bool toggleState;
  final String status;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String? locationName;
  final bool isManuallyDisabled;
  final bool isEnabled;
  final bool entryTimerRunning;
  final bool exitTimerRunning;
  final int entrySecondsLeft;
  final int exitSecondsLeft;

  IntelligentAttendanceState({
    required this.isCheckedIn,
    required this.toggleState,
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.locationName,
    this.isManuallyDisabled = false,
    this.isEnabled = true,
    this.entryTimerRunning = false,
    this.exitTimerRunning = false,
    this.entrySecondsLeft = 0,
    this.exitSecondsLeft = 0,
  });
}
