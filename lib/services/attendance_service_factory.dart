import 'package:flutter/foundation.dart';
import 'attendance_api_client.dart';
import 'geofence_manager.dart';
import 'attendance_service.dart';
import 'location_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'storage_service.dart';
import 'intelligent_attendance/attendance_controller.dart';

class AttendanceServiceFactory {
  static const String _defaultBaseUrl = 'http://103.14.120.163:8092/api';
  static AttendanceService? _instance;
  static GeofenceManager? _geofenceManager;
  static AttendanceApiClient? _apiClient;
  static String? _currentUserId;
  static bool _isInitializing = false;
  static bool _initialized = false;

  static Future<AttendanceService> create() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('api_base_url') ?? _defaultBaseUrl;
      final apiClient = AttendanceApiClient(baseUrl: baseUrl);
      final geofenceManager = GeofenceManager();
      final attendanceService = AttendanceService(
        apiClient: apiClient,
        geofenceManager: geofenceManager,
      );
      try {
        await attendanceService.initializeWithLocations(autoStart: false);
      } catch (e) {
        debugPrint('[AttendanceServiceFactory] Failed to initialize: $e');
      }
      return attendanceService;
    } catch (e) {
      debugPrint('[AttendanceServiceFactory] Fatal error: $e');
      rethrow;
    }
  }

  static Future<AttendanceService> getInstance() async {
    _instance ??= await create();
    return _instance!;
  }

  static AttendanceController? getAttendanceController() {
    final controller = AttendanceController.currentInstance;
    if (controller != null && controller.isReady) {
      return controller;
    }
    return null;
  }

  static Future<AttendanceController> initializeController() async {
    if (_initialized && _currentUserId != null) {
      final user = await StorageService.getUserData();
      if (user != null && _currentUserId == user.id) {
        final controller = AttendanceController.currentInstance;
        if (controller != null && controller.isReady) {
          debugPrint('[AttendanceServiceFactory] Already initialized for user ${user.id}, returning existing controller');
          return controller;
        }
      }
    }
    if (_isInitializing) {
      debugPrint('[AttendanceServiceFactory] ⚠️ Initialization already in progress, waiting...');
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      final controller = AttendanceController.currentInstance;
      if (controller != null && controller.isReady) {
        return controller;
      }
      throw Exception('Initialization completed but controller not ready');
    }
    _isInitializing = true;
    try {
      debugPrint('[AttendanceServiceFactory] 🚀 Initializing attendance controller...');
      final user = await StorageService.getUserData();
      if (user == null) {
        throw Exception('No user logged in');
      }
      if (_currentUserId != null && _currentUserId != user.id) {
        debugPrint('[AttendanceServiceFactory] ⚠️ User changed, resetting previous session');
        await reset();
      }
      _currentUserId = user.id;
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('api_base_url') ?? _defaultBaseUrl;
      _apiClient?.dispose();
      _geofenceManager?.dispose();
      _apiClient = AttendanceApiClient(baseUrl: baseUrl);
      _geofenceManager = GeofenceManager();
      final locationRepo = LocationRepository.instance;
      locationRepo.reset();
      int retries = 3;
      List<WorkLocation> workLocations = [];
      for (int i = 0; i < retries; i++) {
        try {
          await locationRepo.loadLocations(_apiClient!);
          workLocations = locationRepo.workLocations;
          if (workLocations.isNotEmpty) break;
          if (i < retries - 1) {
            await Future.delayed(Duration(seconds: 2 * (i + 1)));
          }
        } catch (e) {
          debugPrint('[AttendanceServiceFactory] Location load attempt ${i + 1} failed: $e');
          if (i == retries - 1) {
            throw Exception('Failed to load work locations after $retries attempts');
          }
        }
      }
      if (workLocations.isEmpty) {
        throw Exception('No work locations available');
      }
      await _geofenceManager!.initialize(workLocations);
      final controller = AttendanceController.getInstance(
        geofenceManager: _geofenceManager!,
        apiClient: _apiClient!,
      );
      await controller.restoreStateForUser(user.id);
      await Future.delayed(const Duration(milliseconds: 500));
      await controller.bootstrap(user.id, workLocations);
      _initialized = true;
      debugPrint('[AttendanceServiceFactory] ✅ Attendance controller initialized');
      return controller;
    } catch (e) {
      debugPrint('[AttendanceServiceFactory] ❌ Failed to initialize controller: $e');
      _initialized = false;
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  static Future<void> reset() async {
    debugPrint('[AttendanceServiceFactory] 🔴 Resetting attendance system...');
    AttendanceController.resetInstance();
    _instance?.dispose();
    _instance = null;
    _geofenceManager?.dispose();
    _geofenceManager = null;
    _apiClient?.dispose();
    _apiClient = null;
    _currentUserId = null;
    _isInitializing = false;
    _initialized = false;
    final locationRepo = LocationRepository.instance;
    locationRepo.reset();
    debugPrint('[AttendanceServiceFactory] ✅ Attendance system reset complete');
  }
}
