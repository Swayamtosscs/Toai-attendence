 Auto Attendance System - Usage Guide

## Step 1: Add Dependencies

Add these to your `pubspec.yaml`:

```yaml
dependencies:
  geolocator: ^10.1.0
  geofence_service: ^2.0.0
  workmanager: ^0.5.2
  # shared_preferences: ^2.2.2  # Already added
  # http: ^1.2.2  # Already added
```

Run: `flutter pub get`

## Step 2: Android Permissions

Add to `android/app/src/main/AndroidManifest.xml` (inside `<manifest>` tag):

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

## Step 3: iOS Permissions

Add to `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to track attendance automatically</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need your location to track attendance even when app is in background</string>
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>fetch</string>
</array>
```

## Step 4: Initialize After Login

In `lib/auth_screens.dart`, after successful login, add:

```dart
import 'services/attendance_service_factory.dart';

// After line 192 (after Navigator.pushReplacementNamed):
// Initialize auto attendance service
try {
  await AttendanceServiceFactory.create();
} catch (e) {
  // Handle error silently or log it
  print('Auto attendance initialization failed: $e');
}
```

## Step 5: Add Toggle Widget to Your UI

### Option A: Add to Home Screen

In `lib/home_screen.dart`, add the toggle widget:

```dart
import 'widgets/auto_attendance_toggle.dart';

// In your build method, add before or after check-in/out card:
AutoAttendanceToggle(),
```

### Option B: Add to Profile/Settings Screen

In `lib/profile_screen.dart`, add:

```dart
import 'widgets/auto_attendance_toggle.dart';

// In your settings list:
AutoAttendanceToggle(),
```

## Step 6: Handle App Lifecycle (Optional but Recommended)

In `lib/main_navigation.dart`, add lifecycle handling:

```dart
import 'package:flutter/widgets.dart';
import 'services/attendance_service_factory.dart';

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Validate location when app resumes
      AttendanceServiceFactory.getInstance().then((service) {
        service.validateCurrentLocation();
      });
    }
  }
  
  // ... rest of your code
}
```

## Step 7: Backend API Endpoints Required

Your backend must have these endpoints:

1. **GET /work-locations**
   ```json
   Response: {
     "locations": [
       {
         "id": "loc1",
         "name": "Office Building",
         "latitude": 22.3072,
         "longitude": 73.1812,
         "radius": 100.0
       }
     ]
   }
   ```

2. **POST /check-in**
   ```json
   Request: {
     "latitude": 22.3072,
     "longitude": 73.1812,
     "locationId": "loc1",
     "timestamp": "2024-01-01T09:00:00Z"
   }
   ```

3. **POST /check-out**
   ```json
   Request: {
     "latitude": 22.3072,
     "longitude": 73.1812,
     "timestamp": "2024-01-01T18:00:00Z"
   }
   ```

## How It Works

1. **User enables toggle** → Service requests location permissions
2. **User enters work location** → Geofence triggers → Auto check-in
3. **User exits work location** → Geofence triggers → Auto check-out
4. **Every 30 minutes** → Background worker validates location → Forces check-out if outside
5. **App resumes** → Validates current location

## Testing

1. Enable the toggle
2. Walk to a work location (within radius)
3. Should auto check-in
4. Walk away from location
5. Should auto check-out

## Troubleshooting

- **Permissions not granted**: Check Android/iOS permission setup
- **Not checking in**: Verify work locations are fetched correctly
- **Background not working**: Check workmanager initialization in main.dart
- **API errors**: Verify backend endpoints match the expected format



