import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_api_client.dart';
import 'storage_service.dart';

/// Flutter bridge for Android ForegroundAttendanceService
/// Handles communication between Flutter and native Android service
class ForegroundAttendanceService {
  static const MethodChannel _channel = MethodChannel('com.example.demoapp/attendance_service');
  static const EventChannel _eventChannel = EventChannel('com.example.demoapp/attendance_events');
  
  static StreamSubscription? _eventSubscription;
  static StreamController<AttendanceServiceEvent>? _eventController;
  
  /// Get or create event controller
  static StreamController<AttendanceServiceEvent> get _getEventController {
    _eventController ??= StreamController<AttendanceServiceEvent>.broadcast();
    return _eventController!;
  }
  
  /// Stream of events from the foreground service
  static Stream<AttendanceServiceEvent> get eventStream {
    try {
      return _getEventController.stream;
    } catch (e) {
      debugPrint('[ForegroundAttendanceService] Error getting event stream: $e');
      // Return empty stream if controller fails
      return const Stream<AttendanceServiceEvent>.empty();
    }
  }
  
  /// Start the foreground service
  /// [workLocations] - List of work locations to monitor
  static Future<bool> startService(List<WorkLocation> workLocations) async {
    try {
      // Get API base URL and auth token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final apiBaseUrl = prefs.getString('api_base_url') ?? 'http://103.14.120.163:8092/api';
      
      // Get auth token - try multiple keys
      String? authToken = prefs.getString('auth_token');
      if (authToken == null || authToken.isEmpty) {
        // Try to get from StorageService
        try {
          final storageService = await StorageService.getAuthToken();
          authToken = storageService;
        } catch (e) {
          debugPrint('[ForegroundAttendanceService] Failed to get token from StorageService: $e');
        }
      }
      
      if (authToken == null || authToken.isEmpty) {
        debugPrint('[ForegroundAttendanceService] ⚠️ Auth token not found - API calls may fail');
      } else {
        debugPrint('[ForegroundAttendanceService] ✅ Auth token found (length: ${authToken.length})');
      }
      
      // Convert work locations to JSON
      final locationsJson = jsonEncode(
        workLocations.map((loc) => {
          'id': loc.id,
          'name': loc.name,
          'latitude': loc.latitude,
          'longitude': loc.longitude,
          'radius': loc.radius,
        }).toList(),
      );
      
      final result = await _channel.invokeMethod<bool>(
        'startForegroundService',
        {
          'locations_json': locationsJson,
          'api_base_url': apiBaseUrl,
          'auth_token': authToken ?? '',
        },
      );
      
      // Start listening to events
      _startEventListening();
      
      debugPrint('[ForegroundAttendanceService] Service started: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('[ForegroundAttendanceService] Error starting service: $e');
      return false;
    }
  }
  
  /// Stop the foreground service
  static Future<bool> stopService() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopForegroundService');
      
      // Stop listening to events
      _stopEventListening();
      
      debugPrint('[ForegroundAttendanceService] Service stopped: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('[ForegroundAttendanceService] Error stopping service: $e');
      return false;
    }
  }
  
  /// Update work locations in the running service
  static Future<bool> updateWorkLocations(List<WorkLocation> workLocations) async {
    try {
      // Convert work locations to JSON
      final locationsJson = jsonEncode(
        workLocations.map((loc) => {
          'id': loc.id,
          'name': loc.name,
          'latitude': loc.latitude,
          'longitude': loc.longitude,
          'radius': loc.radius,
        }).toList(),
      );
      
      final result = await _channel.invokeMethod<bool>(
        'updateWorkLocations',
        {'locations_json': locationsJson},
      );
      
      debugPrint('[ForegroundAttendanceService] Locations updated: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('[ForegroundAttendanceService] Error updating locations: $e');
      return false;
    }
  }
  
  /// Check if the service is currently running
  static Future<bool> isServiceRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isServiceRunning');
      return result ?? false;
    } catch (e) {
      debugPrint('[ForegroundAttendanceService] Error checking service status: $e');
      return false;
    }
  }
  
  /// Start listening to events from the service
  static void _startEventListening() {
    if (_eventSubscription != null) {
      debugPrint('[ForegroundAttendanceService] Event listening already started');
      return;
    }
    
    // Ensure event controller exists
    final controller = _getEventController;
    
    // Check if event controller is closed
    if (controller.isClosed) {
      debugPrint('[ForegroundAttendanceService] Event controller is closed, cannot start listening');
      return;
    }
    
    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          try {
            if (event == null) return;
            
            final Map<dynamic, dynamic> eventMap = event as Map<dynamic, dynamic>;
            final type = eventMap['type'] as String?;
            final timestamp = eventMap['timestamp'] as int?;
            
            // Get event controller safely
            final eventController = _eventController;
            if (eventController == null || eventController.isClosed) {
              debugPrint('[ForegroundAttendanceService] Event controller is closed, cannot add event');
              return;
            }
            
            if (type == 'checkIn' && timestamp != null) {
              final locationId = eventMap['location_id'] as String?;
              if (!eventController.isClosed) {
                eventController.add(AttendanceServiceEvent(
                  type: AttendanceEventType.checkIn,
                  locationId: locationId,
                  timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
                ));
                debugPrint('[ForegroundAttendanceService] Check-in event: $locationId at ${DateTime.fromMillisecondsSinceEpoch(timestamp)}');
              }
            } else if (type == 'checkOut' && timestamp != null) {
              if (!eventController.isClosed) {
                eventController.add(AttendanceServiceEvent(
                  type: AttendanceEventType.checkOut,
                  timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
                ));
                debugPrint('[ForegroundAttendanceService] Check-out event at ${DateTime.fromMillisecondsSinceEpoch(timestamp)}');
              }
            } else if (type == 'timerStart') {
              final timerType = eventMap['timerType'] as String?;
              final duration = eventMap['duration'] as int?;
              if (!eventController.isClosed) {
                eventController.add(AttendanceServiceEvent(
                  type: timerType == 'entry' ? AttendanceEventType.timerStartEntry : AttendanceEventType.timerStartExit,
                  timestamp: DateTime.now(),
                ));
                debugPrint('[ForegroundAttendanceService] Timer started: $timerType, duration: $duration');
              }
            } else if (type == 'timerUpdate') {
              final timerType = eventMap['timerType'] as String?;
              final remaining = eventMap['remaining'] as int?;
              if (!eventController.isClosed) {
                eventController.add(AttendanceServiceEvent(
                  type: timerType == 'entry' ? AttendanceEventType.timerUpdateEntry : AttendanceEventType.timerUpdateExit,
                  timestamp: DateTime.now(),
                  timerRemaining: remaining,
                ));
              }
            } else if (type == 'timerComplete') {
              final timerType = eventMap['timerType'] as String?;
              if (!eventController.isClosed) {
                eventController.add(AttendanceServiceEvent(
                  type: timerType == 'entry' ? AttendanceEventType.timerCompleteEntry : AttendanceEventType.timerCompleteExit,
                  timestamp: DateTime.now(),
                ));
                debugPrint('[ForegroundAttendanceService] Timer completed: $timerType');
              }
            } else if (type == 'timerCancelled') {
              final timerType = eventMap['timerType'] as String?;
              if (!eventController.isClosed) {
                eventController.add(AttendanceServiceEvent(
                  type: timerType == 'entry' ? AttendanceEventType.timerCancelledEntry : AttendanceEventType.timerCancelledExit,
                  timestamp: DateTime.now(),
                ));
                debugPrint('[ForegroundAttendanceService] Timer cancelled: $timerType');
              }
            }
          } catch (e) {
            debugPrint('[ForegroundAttendanceService] Error parsing event: $e');
          }
        },
        onError: (error) {
          debugPrint('[ForegroundAttendanceService] Event stream error: $error');
          // Don't crash - just log the error
        },
        cancelOnError: false, // Continue listening even on error
      );
      
      debugPrint('[ForegroundAttendanceService] Event listening started');
    } catch (e, stackTrace) {
      debugPrint('[ForegroundAttendanceService] Failed to start event listening: $e');
      debugPrint('[ForegroundAttendanceService] Stack trace: $stackTrace');
      // Don't crash app if event channel fails - app should work without foreground service events
      _eventSubscription = null;
    }
  }
  
  /// Stop listening to events
  static void _stopEventListening() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    debugPrint('[ForegroundAttendanceService] Event listening stopped');
  }
  
  /// Dispose resources
  static void dispose() {
    _stopEventListening();
    _eventController?.close();
    _eventController = null;
  }
}

/// Event types from the foreground service
enum AttendanceEventType {
  checkIn,
  checkOut,
  timerStartEntry,
  timerStartExit,
  timerUpdateEntry,
  timerUpdateExit,
  timerCompleteEntry,
  timerCompleteExit,
  timerCancelledEntry,
  timerCancelledExit,
}

/// Event from the foreground service
class AttendanceServiceEvent {
  final AttendanceEventType type;
  final String? locationId;
  final DateTime timestamp;
  final int? timerRemaining; // Remaining seconds for timer
  
  AttendanceServiceEvent({
    required this.type,
    this.locationId,
    required this.timestamp,
    this.timerRemaining,
  });
}

