import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'attendance_api_client.dart';

class GeofenceManager {
  final StreamController<GeofenceEvent> _eventController =
      StreamController<GeofenceEvent>.broadcast();
  Stream<GeofenceEvent> get eventStream => _eventController.stream;

  List<WorkLocation> _workLocations = [];
  bool _isMonitoring = false;
  String? _currentLocationId;
  Timer? _locationCheckTimer;
  StreamSubscription<Position>? _positionSubscription;
  bool _isFirstCheck = true;

  Future<void> initialize(List<WorkLocation> workLocations) async {
    _workLocations = workLocations;
  }

  Future<void> startMonitoring() async {
    if (_isMonitoring) {
      debugPrint('[GeofenceManager] Already monitoring, stopping first');
      await stopMonitoring();
    }
    if (_positionSubscription != null) {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
    }
    if (_locationCheckTimer != null) {
      _locationCheckTimer?.cancel();
      _locationCheckTimer = null;
    }
    try {
      _locationCheckTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _checkLocation(),
      );
      try {
        _positionSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
            timeLimit: Duration(seconds: 10),
          ),
        ).listen(
          (position) {
            _checkLocationAtPosition(position);
          },
          onError: (error) {
            Future.delayed(const Duration(seconds: 5), () {
              _checkLocation();
            });
          },
          cancelOnError: false,
        );
      } catch (e) {
        debugPrint('[GeofenceManager] Failed to start position stream: $e');
      }
      _isFirstCheck = true;
      await _checkLocation();
      _isFirstCheck = false;
      _isMonitoring = true;
    } catch (e) {
      throw GeofenceException('Failed to start monitoring: $e');
    }
  }

  Future<void> _checkLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        return;
      }
      Position? position;
      int retries = 3;
      for (int i = 0; i < retries; i++) {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          );
          break;
        } catch (e) {
          if (i < retries - 1) {
            await Future.delayed(Duration(seconds: 2));
          } else {
            return;
          }
        }
      }
      if (position != null) {
        await _checkLocationAtPosition(position);
      }
    } catch (e) {
      debugPrint('[GeofenceManager] Location check error: $e');
    }
  }

  Future<void> _checkLocationAtPosition(Position position) async {
    if (_workLocations.isEmpty) return;
    String? insideLocationId;
    double? minDistance;
    for (final location in _workLocations) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        location.latitude,
        location.longitude,
      );
      if (distance <= location.radius) {
        if (minDistance == null || distance < minDistance) {
          insideLocationId = location.id;
          minDistance = distance;
        }
      }
    }
    if (insideLocationId != null && _currentLocationId != insideLocationId) {
      if (_currentLocationId != null) {
        _eventController.add(GeofenceEvent(
          type: GeofenceEventType.EXIT,
          locationId: _currentLocationId!,
          timestamp: DateTime.now(),
        ));
      }
      _currentLocationId = insideLocationId;
      _eventController.add(GeofenceEvent(
        type: GeofenceEventType.ENTER,
        locationId: insideLocationId,
        timestamp: DateTime.now(),
      ));
    } else if (insideLocationId == null && _currentLocationId != null) {
      final exitedLocationId = _currentLocationId;
      _currentLocationId = null;
      _eventController.add(GeofenceEvent(
        type: GeofenceEventType.EXIT,
        locationId: exitedLocationId!,
        timestamp: DateTime.now(),
      ));
    } else if (insideLocationId != null && _currentLocationId == insideLocationId) {
      if (_isFirstCheck) {
        _eventController.add(GeofenceEvent(
          type: GeofenceEventType.ENTER,
          locationId: insideLocationId,
          timestamp: DateTime.now(),
        ));
      }
    }
  }

  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;
    try {
      _locationCheckTimer?.cancel();
      _locationCheckTimer = null;
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      _isMonitoring = false;
      _currentLocationId = null;
      _isFirstCheck = true;
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      debugPrint('[GeofenceManager] Error stopping: $e');
      _isMonitoring = false;
      _currentLocationId = null;
    }
  }

  String? getCurrentLocationId() => _currentLocationId;
  bool get isMonitoring => _isMonitoring;
  List<WorkLocation> getWorkLocations() => List.unmodifiable(_workLocations);

  Future<void> updateWorkLocations(List<WorkLocation> workLocations) async {
    final wasMonitoring = _isMonitoring;
    final oldLocationIds = _workLocations.map((l) => l.id).toSet();
    final newLocationIds = workLocations.map((l) => l.id).toSet();
    
    // Check if current location still exists
    if (_currentLocationId != null && !newLocationIds.contains(_currentLocationId)) {
      debugPrint('[GeofenceManager] ⚠️ Current location $_currentLocationId no longer exists, clearing');
      if (wasMonitoring) {
        // Emit exit event for removed location
        _eventController.add(GeofenceEvent(
          type: GeofenceEventType.EXIT,
          locationId: _currentLocationId!,
          timestamp: DateTime.now(),
        ));
      }
      _currentLocationId = null;
    }
    
    if (wasMonitoring) {
      await stopMonitoring();
    }
    _workLocations = workLocations;
    if (wasMonitoring) {
      await startMonitoring();
    }
    
    debugPrint('[GeofenceManager] ✅ Locations updated: ${oldLocationIds.length} → ${newLocationIds.length}');
  }

  void dispose() {
    stopMonitoring();
    _eventController.close();
  }
}

class GeofenceEvent {
  final GeofenceEventType type;
  final String locationId;
  final DateTime timestamp;

  GeofenceEvent({
    required this.type,
    required this.locationId,
    required this.timestamp,
  });
}

enum GeofenceEventType {
  ENTER,
  EXIT,
}

class GeofenceException implements Exception {
  final String message;
  GeofenceException(this.message);
  @override
  String toString() => 'GeofenceException: $message';
}
