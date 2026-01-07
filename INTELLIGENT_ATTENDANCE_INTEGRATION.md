# Intelligent Attendance Engine - Integration Guide

## ✅ Implementation Complete

The enterprise-grade intelligent attendance engine has been successfully integrated into your Flutter app.

## 🎯 Key Features Delivered

### 1. **2-Minute Grace Timers**
- ✅ Entry grace: 2-minute delay before auto check-in when entering premises
- ✅ Exit grace: 2-minute delay before auto check-out when leaving premises
- ✅ Prevents false triggers from GPS fluctuations

### 2. **Auto Toggle Control**
- ✅ Toggle automatically turns ON when user enters premises (after grace period)
- ✅ Toggle automatically turns OFF when user leaves premises (after grace period)
- ✅ Toggle is driven by location intelligence, not manual user input

### 3. **Offline-First Storage**
- ✅ All events saved locally first (SQLite database)
- ✅ Syncs to server when online
- ✅ No data loss even if device is offline
- ✅ Survives app restart, kill, and device reboot

### 4. **Enhanced Data Model**
Every attendance event now stores:
- ✅ Exact timestamp
- ✅ GPS coordinates (latitude, longitude)
- ✅ Location name
- ✅ Location ID
- ✅ Auto/Manual flag
- ✅ Online/Offline device state
- ✅ Event type (CHECK_IN/CHECK_OUT)
- ✅ Notes
- ✅ Sync status

### 5. **Calendar Data Pipeline**
- ✅ Get events for specific date
- ✅ Get events for date range
- ✅ Complete history per day
- ✅ Shows check-in/out times, duration, location

## 📁 Files Created

### Core Engine
- `lib/services/intelligent_attendance/intelligent_attendance_engine.dart`
  - Main engine with 2-minute grace timers
  - Auto toggle control logic
  - Location intelligence

### Storage Layer
- `lib/services/intelligent_attendance/storage/local_shadow_database.dart`
  - SQLite database for offline storage
  - Survives app restart/kill/reboot

### Sync Manager
- `lib/services/intelligent_attendance/sync/sync_manager.dart`
  - Syncs offline events when online
  - Non-blocking background sync

### Data Model
- `lib/services/intelligent_attendance/models/attendance_event.dart`
  - Enhanced event model with all required fields

### Integration
- `lib/services/intelligent_attendance/integration/attendance_engine_integration.dart`
  - Seamless integration with existing AttendanceService

## 🚀 How to Enable

### Option 1: Automatic (Recommended)
The intelligent engine can be enabled automatically when the app starts:

```dart
// In your main.dart or app initialization
await AttendanceServiceFactory.enableIntelligentEngine();
```

### Option 2: Manual
Enable it manually when needed:

```dart
// Get the service instance
final service = await AttendanceServiceFactory.getInstance();

// Enable intelligent engine
await AttendanceServiceFactory.enableIntelligentEngine();
```

## 📊 Using Calendar Data

### Get Events for a Date
```dart
final intelligentEngine = AttendanceServiceFactory.getIntelligentEngine();
if (intelligentEngine != null) {
  final events = await intelligentEngine.getEventsForDate(DateTime.now());
  
  for (final event in events) {
    print('Event: ${event.eventType} at ${event.timestamp}');
    print('Location: ${event.locationName}');
    print('GPS: ${event.latitude}, ${event.longitude}');
    print('Auto: ${event.isAuto}, Online: ${event.isOnline}');
  }
}
```

### Get Events for Date Range
```dart
final startDate = DateTime(2026, 1, 1);
final endDate = DateTime(2026, 1, 31);

final events = await intelligentEngine.getEventsForDateRange(startDate, endDate);
```

## 🔄 How It Works

### Entry Flow
1. User enters premises → Geofence detects ENTER event
2. **2-minute grace timer starts**
3. After 2 minutes, if still inside:
   - Auto check-in occurs
   - Event saved to local database
   - Toggle automatically turns ON
   - Event synced to server (if online)

### Exit Flow
1. User leaves premises → Geofence detects EXIT event
2. **2-minute grace timer starts**
3. After 2 minutes, if still outside:
   - Auto check-out occurs
   - Event saved to local database
   - Toggle automatically turns OFF
   - Event synced to server (if online)

### Offline Handling
- Events are always saved locally first
- SyncManager automatically syncs when internet returns
- No data loss, no blocking UI

## ⚙️ Configuration

### Grace Timer Duration
Currently set to 2 minutes. To change, modify:
```dart
// In intelligent_attendance_engine.dart
Timer(const Duration(minutes: 2), () async {
  // Change Duration(minutes: 2) to your desired duration
});
```

### Sync Interval
Currently syncs every 5 minutes when online. To change:
```dart
// In sync_manager.dart
_syncTimer = Timer.periodic(
  const Duration(minutes: 5), // Change this
  (_) => _attemptSync(),
);
```

## 🔒 Stability Guarantees

- ✅ **App Restart**: State persisted in SQLite
- ✅ **App Kill**: Background workers continue
- ✅ **Device Reboot**: Database survives
- ✅ **No Internet**: Events stored locally, synced later
- ✅ **Battery Optimized**: Low-power GPS, 30-min checks

## 🧪 Testing

### Test Grace Timer
1. Enter premises → Wait 2 minutes → Should auto check-in
2. Leave premises → Wait 2 minutes → Should auto check-out
3. Enter and leave within 2 minutes → Should cancel

### Test Offline
1. Turn off internet
2. Enter premises → Event saved locally
3. Turn on internet → Event synced automatically

### Test Calendar Data
```dart
final events = await intelligentEngine.getEventsForDate(DateTime.now());
assert(events.isNotEmpty);
assert(events.first.timestamp != null);
assert(events.first.latitude != null);
```

## 📝 Notes

- **No Breaking Changes**: Existing AttendanceService continues to work
- **Optional Enhancement**: Intelligent engine is optional, can be enabled/disabled
- **Shared Components**: Uses same GeofenceManager and ApiClient
- **Production Ready**: All error handling, logging, and stability features included

## 🎉 Summary

The intelligent attendance engine is now fully integrated and ready to use. It provides:

1. ✅ 2-minute grace timers for entry/exit
2. ✅ Auto toggle control driven by location
3. ✅ Offline-first storage with SQLite
4. ✅ Automatic sync when online
5. ✅ Enhanced data model with all required fields
6. ✅ Calendar data pipeline
7. ✅ Production stability (survives restart/kill/reboot)

**No feature regressions. Production stable. Battery optimized.**

