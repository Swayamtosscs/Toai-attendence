/// INTEGRATION GUIDE FOR AUTO ATTENDANCE SYSTEM
/// 
/// STEP 1: Add dependencies to pubspec.yaml
/// 
/// dependencies:
///   geolocator: ^10.1.0
///   geofence_service: ^2.0.0
///   workmanager: ^0.5.2
///   shared_preferences: ^2.2.2
///   http: ^1.1.0
/// 
/// STEP 2: Android Permissions (android/app/src/main/AndroidManifest.xml)
/// 
/// <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
/// <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
/// <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
/// <uses-permission android:name="android.permission.WAKE_LOCK" />
/// 
/// STEP 3: iOS Permissions (ios/Runner/Info.plist)
/// 
/// <key>NSLocationWhenInUseUsageDescription</key>
/// <string>We need your location to track attendance automatically</string>
/// <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
/// <string>We need your location to track attendance even when app is in background</string>
/// <key>UIBackgroundModes</key>
/// <array>
///   <string>location</string>
///   <string>fetch</string>
/// </array>
/// 
/// STEP 4: Initialize in main.dart (Already done)
/// 
/// STEP 5: Initialize service after user login
/// 
/// Example in auth_screens.dart or after successful login:
/// 
/// ```dart
/// import 'services/attendance_service_factory.dart';
/// 
/// // After successful login:
/// final attendanceService = await AttendanceServiceFactory.create();
/// 
/// // Store service instance (use Provider, GetIt, or singleton)
/// // For example, store in a global variable or state management
/// ```
/// 
/// STEP 6: Create UI Toggle Widget
/// 
/// See example widget below
/// 
/// STEP 7: Handle App Lifecycle
/// 
/// In your main screen or app lifecycle handler:
/// 
/// ```dart
/// @override
/// void didChangeAppLifecycleState(AppLifecycleState state) {
///   if (state == AppLifecycleState.resumed) {
///     // Validate location when app resumes
///     attendanceService?.validateCurrentLocation();
///   }
/// }
/// ```



