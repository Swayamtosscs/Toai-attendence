import 'package:flutter/foundation.dart';
import 'attendance_api_client.dart';

class LocationRepository {
  static LocationRepository? _instance;
  static LocationRepository get instance {
    _instance ??= LocationRepository._();
    return _instance!;
  }
  
  LocationRepository._();
  
  List<WorkLocation> _workLocations = [];
  bool _isLoaded = false;
  bool _isLoading = false;
  final List<VoidCallback> _listeners = [];
  
  List<WorkLocation> get workLocations => List.unmodifiable(_workLocations);
  bool get hasLocations => _workLocations.isNotEmpty;
  bool get isLoaded => _isLoaded;
  
  Future<void> loadLocations(AttendanceApiClient apiClient) async {
    if (_isLoading) {
      while (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }
    if (_isLoaded && _workLocations.isNotEmpty) {
      return;
    }
    _isLoading = true;
    try {
      _workLocations = await apiClient.getWorkLocations();
      _isLoaded = true;
      _notifyListeners();
    } catch (e) {
      debugPrint('[LocationRepository] Failed to load locations: $e');
      _isLoaded = true;
      _workLocations = [];
      rethrow;
    } finally {
      _isLoading = false;
    }
  }
  
  void setLocations(List<WorkLocation> locations) {
    _workLocations = locations;
    _isLoaded = true;
    _notifyListeners();
  }
  
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }
  
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
  
  void _notifyListeners() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (e) {
        debugPrint('[LocationRepository] Error notifying listener: $e');
      }
    }
  }
  
  void reset() {
    _workLocations = [];
    _isLoaded = false;
    _isLoading = false;
    _listeners.clear();
  }
}
