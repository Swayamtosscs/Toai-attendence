import 'attendance_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Helper class to configure work locations
/// You can set default location coordinates here
class LocationConfig {
  /// Get default work location if backend doesn't provide any
  /// Replace these coordinates with your actual office location
  static WorkLocation getDefaultLocation() {
    return WorkLocation(
      id: 'default_office',
      name: 'Main Office',
      latitude: 22.3072, // Replace with your office latitude
      longitude: 73.1812, // Replace with your office longitude
      radius: 100.0, // Radius in meters (100m = ~328 feet)
    );
  }

  /// Save custom location coordinates
  static Future<void> saveCustomLocation({
    required double latitude,
    required double longitude,
    double radius = 100.0,
    String name = 'Custom Location',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('custom_location_lat', latitude);
    await prefs.setDouble('custom_location_lng', longitude);
    await prefs.setDouble('custom_location_radius', radius);
    await prefs.setString('custom_location_name', name);
  }

  /// Get saved custom location
  static Future<WorkLocation?> getCustomLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('custom_location_lat');
    final lng = prefs.getDouble('custom_location_lng');
    
    if (lat != null && lng != null) {
      return WorkLocation(
        id: 'custom_location',
        name: prefs.getString('custom_location_name') ?? 'Custom Location',
        latitude: lat,
        longitude: lng,
        radius: prefs.getDouble('custom_location_radius') ?? 100.0,
      );
    }
    return null;
  }

  /// Clear custom location
  static Future<void> clearCustomLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_location_lat');
    await prefs.remove('custom_location_lng');
    await prefs.remove('custom_location_radius');
    await prefs.remove('custom_location_name');
  }
}

