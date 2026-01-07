# Flutter Integration Example

## How to Use the Geo Attendance System from Flutter

### 1. Initialize Method Channels

```dart
import 'package:flutter/services.dart';

class AttendanceServiceBridge {
  static const MethodChannel _methodChannel = MethodChannel('com.example.demoapp/attendance_service');
  static const EventChannel _eventChannel = EventChannel('com.example.demoapp/attendance_events');
  
  // Request all permissions on first install
  static Future<bool> requestPermissions() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('requestPermissions');
      return result ?? false;
    } catch (e) {
      print('Error requesting permissions: $e');
      return false;
    }
  }
  
  // Check if all permissions granted
  static Future<bool> hasAllPermissions() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('hasAllPermissions');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
  
  // Start foreground service
  static Future<bool> startService({
    required List<WorkLocation> locations,
    required String apiBaseUrl,
    required String authToken,
  }) async {
    try {
      final locationsJson = jsonEncode(
        locations.map((loc) => loc.toJson()).toList(),
      );
      
      final result = await _methodChannel.invokeMethod<bool>(
        'startForegroundService',
        {
          'locations_json': locationsJson,
          'api_base_url': apiBaseUrl,
          'auth_token': authToken,
        },
      );
      return result ?? false;
    } catch (e) {
      print('Error starting service: $e');
      return false;
    }
  }
  
  // Stop foreground service
  static Future<bool> stopService() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopForegroundService');
      return result ?? false;
    } catch (e) {
      print('Error stopping service: $e');
      return false;
    }
  }
  
  // Manual toggle OFF (final check-out)
  static Future<bool> manualToggleOff() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('manualToggleOff');
      return result ?? false;
    } catch (e) {
      print('Error toggling off: $e');
      return false;
    }
  }
  
  // Check if service is running
  static Future<bool> isServiceRunning() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isServiceRunning');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
  
  // Listen to attendance events
  static Stream<Map<String, dynamic>> get attendanceEvents {
    return _eventChannel.receiveBroadcastStream()
        .map((event) => event as Map<String, dynamic>);
  }
}
```

### 2. Usage in Your Flutter App

```dart
import 'package:flutter/material.dart';

class AttendanceScreen extends StatefulWidget {
  @override
  _AttendanceScreenState createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool _isServiceRunning = false;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  
  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _listenToEvents();
  }
  
  Future<void> _checkPermissions() async {
    final hasPermissions = await AttendanceServiceBridge.hasAllPermissions();
    if (!hasPermissions) {
      await AttendanceServiceBridge.requestPermissions();
    }
  }
  
  void _listenToEvents() {
    _eventSubscription = AttendanceServiceBridge.attendanceEvents.listen((event) {
      if (event['type'] == 'checkIn') {
        _showSnackBar('Auto check-in successful!');
        setState(() {
          _isCheckedIn = true;
        });
      } else if (event['type'] == 'checkOut') {
        _showSnackBar('Auto check-out successful!');
        setState(() {
          _isCheckedIn = false;
        });
      } else if (event['type'] == 'timerStart') {
        final timerType = event['timerType'];
        final duration = event['duration'];
        _showSnackBar('$timerType timer started: $duration seconds');
      } else if (event['type'] == 'timerUpdate') {
        final remaining = event['remaining'];
        // Update UI with countdown
      } else if (event['type'] == 'timerComplete') {
        _showSnackBar('Timer completed - action performed');
      }
    });
  }
  
  Future<void> _startAutoAttendance() async {
    // Get work locations from your API or storage
    final locations = await _getWorkLocations();
    final apiBaseUrl = await _getApiBaseUrl();
    final authToken = await _getAuthToken();
    
    final success = await AttendanceServiceBridge.startService(
      locations: locations,
      apiBaseUrl: apiBaseUrl,
      authToken: authToken,
    );
    
    if (success) {
      setState(() {
        _isServiceRunning = true;
      });
      _showSnackBar('Auto attendance started!');
    } else {
      _showSnackBar('Failed to start service');
    }
  }
  
  Future<void> _stopAutoAttendance() async {
    final success = await AttendanceServiceBridge.stopService();
    if (success) {
      setState(() {
        _isServiceRunning = false;
      });
      _showSnackBar('Auto attendance stopped');
    }
  }
  
  Future<void> _manualToggleOff() async {
    final success = await AttendanceServiceBridge.manualToggleOff();
    if (success) {
      _showSnackBar('Manual toggle OFF - final check-out performed');
    }
  }
  
  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Auto Attendance')),
      body: Column(
        children: [
          SwitchListTile(
            title: Text('Auto Attendance'),
            value: _isServiceRunning,
            onChanged: (value) {
              if (value) {
                _startAutoAttendance();
              } else {
                _stopAutoAttendance();
              }
            },
          ),
          ListTile(
            title: Text('Manual Toggle OFF'),
            subtitle: Text('Final check-out & disable auto check-in'),
            trailing: IconButton(
              icon: Icon(Icons.power_settings_new),
              onPressed: _manualToggleOff,
            ),
          ),
        ],
      ),
    );
  }
}
```

### 3. First Install Permission Flow

```dart
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _requestPermissionsOnFirstLaunch();
  }
  
  Future<void> _requestPermissionsOnFirstLaunch() async {
    // Check if first launch
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = prefs.getBool('first_launch') ?? true;
    
    if (isFirstLaunch) {
      // Request all permissions
      final granted = await AttendanceServiceBridge.requestPermissions();
      
      if (granted) {
        // Mark as not first launch
        await prefs.setBool('first_launch', false);
      }
    }
    
    // Navigate to home
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomeScreen()),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
```

---

## Event Types

The event channel emits these event types:

1. **checkIn**: Auto check-in performed
   ```json
   {
     "type": "checkIn",
     "location_id": "loc_123",
     "timestamp": 1234567890
   }
   ```

2. **checkOut**: Auto check-out performed
   ```json
   {
     "type": "checkOut",
     "timestamp": 1234567890
   }
   ```

3. **timerStart**: Grace timer started
   ```json
   {
     "type": "timerStart",
     "timerType": "entry" | "exit",
     "duration": 60
   }
   ```

4. **timerUpdate**: Timer countdown update
   ```json
   {
     "type": "timerUpdate",
     "timerType": "entry" | "exit",
     "remaining": 45
   }
   ```

5. **timerComplete**: Timer completed
   ```json
   {
     "type": "timerComplete",
     "timerType": "entry" | "exit"
   }
   ```

6. **timerCancelled**: Timer cancelled
   ```json
   {
     "type": "timerCancelled",
     "timerType": "entry" | "exit"
   }
   ```

7. **manualToggleOff**: Manual toggle OFF performed
   ```json
   {
     "type": "manualToggleOff",
     "timestamp": 1234567890
   }
   ```

---

## Best Practices

1. **Always check permissions before starting service**
2. **Handle permission denials gracefully**
3. **Show user-friendly messages for timer countdown**
4. **Update UI based on service state**
5. **Handle offline scenarios (events will sync automatically)**

---

## Testing

1. Install app on device
2. Grant all permissions when prompted
3. Enable auto attendance
4. Move to work location → Should see 1-minute timer → Auto check-in
5. Move away from location → Should see 1-minute timer → Auto check-out
6. Manually toggle OFF → Should perform final check-out
7. Try to check-in again → Should be blocked until next day
8. Test offline → Events should save locally
9. Go online → Events should sync automatically

---

## Troubleshooting

### Service not starting
- Check if permissions granted
- Check if battery optimization disabled
- Check logs: `adb logcat | grep ForegroundAttendanceService`

### Events not syncing
- Check internet connection
- Check auth token is valid
- Check logs: `adb logcat | grep AttendanceSyncWorker`

### Location not updating
- Check location services enabled
- Check GPS enabled
- Check background location permission granted

