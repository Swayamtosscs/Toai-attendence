# Quick Integration Example

## 1. Add Dependencies (Already done in pubspec.yaml)

Run: `flutter pub get`

## 2. Add Permissions

### Android: `android/app/src/main/AndroidManifest.xml`
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
```

### iOS: `ios/Runner/Info.plist`
Add location usage descriptions.

## 3. Initialize After Login

In `lib/auth_screens.dart`, add after line 193:

```dart
// After successful login
if (!mounted) return;
Navigator.pushReplacementNamed(context, AppRoutes.main);

// ADD THIS:
import 'services/attendance_service_factory.dart';
try {
  await AttendanceServiceFactory.create();
} catch (e) {
  // Silent fail - user can enable manually later
}
```

## 4. Add Toggle Widget to Home Screen

In `lib/home_screen.dart`, add import at top:

```dart
import 'widgets/auto_attendance_toggle.dart';
```

Then in your build method, add the widget (around line 650, after User Info Card):

```dart
// After User Info Card
AutoAttendanceToggle(),

SizedBox(height: 25),

// Check In/Out Card
```

## 5. That's It!

The system will:
- ✅ Auto check-in when entering work location
- ✅ Auto check-out when exiting
- ✅ Validate every 30 minutes in background
- ✅ Persist toggle state

## Testing

1. Open app and login
2. Go to Home screen
3. Toggle "Auto Attendance" ON
4. Grant location permissions
5. Walk to a work location → Auto check-in happens
6. Walk away → Auto check-out happens



