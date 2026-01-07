# Background-Safe Attendance Execution Implementation

## Overview

This implementation provides a **foreground service-based attendance system** that continues monitoring location and applying 2-minute entry/exit rules even when the app is closed, phone is locked, or app is removed from recents.

## Architecture

### 1. Foreground Service (Android Native)
**File:** `android/app/src/main/kotlin/com/example/demoapp/ForegroundAttendanceService.kt`

- **Always running** when auto attendance is ON
- Uses **persistent notification** (required for foreground services)
- Hosts location monitoring and timer engine
- Survives app kill and restart (START_STICKY)

### 2. Flutter Bridge
**File:** `lib/services/foreground_attendance_service.dart`

- Communicates with Android service via MethodChannel
- Receives events via EventChannel
- Provides clean Dart API for AttendanceService

### 3. Integration
**File:** `lib/services/attendance_service.dart`

- Starts/stops foreground service when auto attendance is enabled/disabled
- Syncs state with service events
- Handles recovery on app restart

## Key Features

### ✅ 1. Foreground Service
- Runs continuously with persistent notification
- Uses `FOREGROUND_SERVICE_LOCATION` type
- Registered in AndroidManifest.xml

### ✅ 2. Background Location Permissions
Already configured in AndroidManifest.xml:
- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION`
- `FOREGROUND_SERVICE_LOCATION`

### ✅ 3. Grace Timer Engine
**2-minute entry timer:**
- Starts when user enters location
- After 2 minutes, automatically performs check-in
- Persisted in SharedPreferences
- Restored on app restart

**2-minute exit timer:**
- Starts when user exits location while checked in
- After 2 minutes, automatically performs check-out
- Persisted in SharedPreferences
- Restored on app restart

### ✅ 4. Battery Compliance
- **Low accuracy location:** Prefers NETWORK_PROVIDER over GPS
- **30-minute deep validation:** Periodic location checks every 30 minutes
- **Resource release:** Location updates only when needed
- **Distance filter:** 10 meters minimum distance for updates
- **Time interval:** 30 seconds between location updates

### ✅ 5. Recovery Logic
- **State persistence:** All state saved in SharedPreferences
- **Timer restoration:** Grace timers restored with remaining time
- **Service restart:** Service automatically restarts if killed (START_STICKY)
- **State sync:** Flutter app syncs with service state on restart

## Implementation Details

### Service Lifecycle

1. **Start Service:**
   ```dart
   await ForegroundAttendanceService.startService(workLocations);
   ```
   - Creates persistent notification
   - Starts location monitoring
   - Initializes grace timers
   - Performs immediate location check

2. **Stop Service:**
   ```dart
   await ForegroundAttendanceService.stopService();
   ```
   - Stops location monitoring
   - Cancels all timers
   - Removes notification
   - Cleans up resources

3. **Update Locations:**
   ```dart
   await ForegroundAttendanceService.updateWorkLocations(workLocations);
   ```
   - Updates work locations without restarting service

### Grace Timer Implementation

**Entry Timer:**
- Triggered when user enters location
- 2-minute countdown
- On expiry: Performs check-in
- Persisted: `entry_timer_start` timestamp
- Restored: Calculates remaining time and resumes

**Exit Timer:**
- Triggered when user exits location while checked in
- 2-minute countdown
- On expiry: Performs check-out
- Persisted: `exit_timer_start` timestamp
- Restored: Calculates remaining time and resumes

### Location Monitoring

**Settings:**
- Provider: NETWORK_PROVIDER (preferred) or GPS_PROVIDER (fallback)
- Update interval: 30 seconds
- Distance filter: 10 meters
- Accuracy: Low (network-based for battery efficiency)

**Deep Validation:**
- Runs every 30 minutes
- Performs comprehensive location check
- Validates check-in/check-out status
- Updates service state

### State Persistence

**SharedPreferences Keys:**
- `is_enabled`: Service running status
- `is_checked_in`: Current check-in status
- `location_id`: Current location ID
- `check_in_time`: Check-in timestamp
- `entry_timer_start`: Entry timer start time
- `exit_timer_start`: Exit timer start time
- `last_location_lat`: Last known latitude
- `last_location_lng`: Last known longitude
- `work_locations_json`: Work locations JSON

### Event Communication

**Service → Flutter:**
- Check-in events: Broadcast → MainActivity → EventChannel → Flutter
- Check-out events: Broadcast → MainActivity → EventChannel → Flutter

**Flutter → Service:**
- Start service: MethodChannel → MainActivity → Intent
- Stop service: MethodChannel → MainActivity → Intent
- Update locations: MethodChannel → MainActivity → Intent

## Usage

### Starting the Service

The service is automatically started when auto attendance is enabled:

```dart
await attendanceService.enable();
```

This will:
1. Request location permissions
2. Start foreground service
3. Begin location monitoring
4. Initialize grace timers

### Stopping the Service

The service is automatically stopped when auto attendance is disabled:

```dart
await attendanceService.disable();
```

This will:
1. Stop foreground service
2. Cancel all timers
3. Stop location monitoring

### Updating Locations

When work locations change:

```dart
await attendanceService.refreshWorkLocations();
```

This updates locations in the running service without restarting it.

## Recovery on App Restart

When the app restarts:

1. **Service Check:**
   - Checks if service is still running
   - If running, syncs state
   - If not running but was enabled, restarts service

2. **Timer Restoration:**
   - Reads timer start times from SharedPreferences
   - Calculates remaining time
   - Resumes timers with remaining time

3. **State Sync:**
   - Reads check-in status from SharedPreferences
   - Updates Flutter state to match service state
   - Handles expired timers (performs check-in/check-out if needed)

## Testing

### Test Scenarios

1. **App Closed:**
   - Enable auto attendance
   - Close app completely
   - Enter location → Wait 2 minutes → Should auto check-in
   - Exit location → Wait 2 minutes → Should auto check-out

2. **Phone Locked:**
   - Enable auto attendance
   - Lock phone
   - Enter location → Wait 2 minutes → Should auto check-in

3. **App Removed from Recents:**
   - Enable auto attendance
   - Swipe away from recents
   - Service should continue running
   - Check notification bar for persistent notification

4. **App Restart:**
   - Enable auto attendance
   - Enter location (timer starts)
   - Kill app
   - Restart app
   - Timer should resume with remaining time

5. **Battery Optimization:**
   - Request battery optimization exemption
   - Service should continue running even with battery saver enabled

## Files Modified/Created

### Created:
- `android/app/src/main/kotlin/com/example/demoapp/ForegroundAttendanceService.kt`
- `lib/services/foreground_attendance_service.dart`
- `BACKGROUND_ATTENDANCE_IMPLEMENTATION.md`

### Modified:
- `android/app/src/main/AndroidManifest.xml` - Added service registration
- `android/app/src/main/kotlin/com/example/demoapp/MainActivity.kt` - Added service communication
- `lib/services/attendance_service.dart` - Integrated foreground service

## Permissions

All required permissions are already in AndroidManifest.xml:
- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_LOCATION`
- `POST_NOTIFICATIONS`

## Notification

The service displays a persistent notification:
- **Title:** "Attendance Monitoring"
- **Content:** Shows current status (checked in/out)
- **Priority:** LOW (non-intrusive)
- **Category:** SERVICE
- **Ongoing:** true (cannot be dismissed)

## Notes

1. **Battery Optimization:**
   - Users should be prompted to disable battery optimization
   - Service will work but may be limited by system

2. **Location Accuracy:**
   - Uses network-based location for battery efficiency
   - GPS used only as fallback
   - Sufficient for geofencing within 100m radius

3. **Service Restart:**
   - Service uses START_STICKY
   - Android will restart service if killed
   - State is persisted, so recovery is automatic

4. **Grace Timers:**
   - Timers survive app kill and restart
   - Remaining time is calculated and resumed
   - Expired timers trigger immediate action

## Troubleshooting

### Service Not Starting
- Check if location permissions are granted
- Check if FOREGROUND_SERVICE_LOCATION permission is granted
- Check logcat for errors

### Timers Not Working
- Check SharedPreferences for timer start times
- Verify service is running (check notification)
- Check logcat for timer-related logs

### Location Not Updating
- Check if location services are enabled
- Check if network/GPS providers are enabled
- Check logcat for location update errors

### State Not Syncing
- Check if EventChannel is properly set up
- Check if broadcasts are being received
- Check logcat for event-related logs

