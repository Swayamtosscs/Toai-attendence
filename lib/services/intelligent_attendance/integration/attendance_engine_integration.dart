import 'package:flutter/foundation.dart';
import '../intelligent_attendance_engine.dart';
import '../../attendance_service.dart';
import '../../geofence_manager.dart';
import '../../attendance_api_client.dart';

/// Integration layer between existing AttendanceService and Intelligent Engine
/// Provides seamless integration without breaking existing functionality
class AttendanceEngineIntegration {
  final AttendanceService _attendanceService;
  IntelligentAttendanceEngine? _intelligentEngine;
  bool _isIntelligentModeEnabled = false;

  AttendanceEngineIntegration({
    required AttendanceService attendanceService,
  }) : _attendanceService = attendanceService;

  /// Enable intelligent mode (with grace timers and auto toggle)
  Future<void> enableIntelligentMode({
    required GeofenceManager geofenceManager,
    required AttendanceApiClient apiClient,
  }) async {
    if (_isIntelligentModeEnabled) return;

    try {
      _intelligentEngine = IntelligentAttendanceEngine(
        geofenceManager: geofenceManager,
        apiClient: apiClient,
      );

      // Listen to toggle changes from intelligent engine
      _intelligentEngine!.toggleStream.listen((toggleState) async {
        debugPrint('[Integration] 🔄 Toggle state changed: $toggleState');
        // Sync toggle state with existing service
        if (toggleState) {
          // Toggle ON - ensure service is enabled and checked in
          try {
            if (!_attendanceService.getCurrentState().isEnabled) {
              await _attendanceService.enable();
            }
            // If not checked in, the intelligent engine already did check-in
            // Just ensure the service state is synced
            debugPrint('[Integration] ✅ Service enabled - Auto check-in completed');
          } catch (e) {
            debugPrint('[Integration] ⚠️ Failed to enable service: $e');
          }
        } else {
          // Toggle OFF - disable service (check-out already done by intelligent engine)
          try {
            if (_attendanceService.getCurrentState().isEnabled) {
              await _attendanceService.disable();
            }
            debugPrint('[Integration] ✅ Service disabled - Auto check-out completed');
          } catch (e) {
            debugPrint('[Integration] ⚠️ Failed to disable service: $e');
          }
        }
      });

      _isIntelligentModeEnabled = true;
      debugPrint('[Integration] ✅ Intelligent mode enabled');
    } catch (e) {
      debugPrint('[Integration] ❌ Failed to enable intelligent mode: $e');
    }
  }

  /// Disable intelligent mode
  void disableIntelligentMode() {
    _intelligentEngine?.dispose();
    _intelligentEngine = null;
    _isIntelligentModeEnabled = false;
    debugPrint('[Integration] 🛑 Intelligent mode disabled');
  }

  /// Get events for calendar (from intelligent engine if enabled, otherwise from service)
  Future<List> getEventsForDate(DateTime date) async {
    if (_isIntelligentModeEnabled && _intelligentEngine != null) {
      return await _intelligentEngine!.getEventsForDate(date);
    }
    // Fallback to existing service data
    return [];
  }

  /// Get events for date range
  Future<List> getEventsForDateRange(DateTime startDate, DateTime endDate) async {
    if (_isIntelligentModeEnabled && _intelligentEngine != null) {
      return await _intelligentEngine!.getEventsForDateRange(startDate, endDate);
    }
    // Fallback to existing service data
    return [];
  }

  /// Check if intelligent mode is enabled
  bool get isIntelligentModeEnabled => _isIntelligentModeEnabled;

  /// Dispose resources
  void dispose() {
    disableIntelligentMode();
  }
}

