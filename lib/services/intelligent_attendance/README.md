# Intelligent Attendance Engine

Enterprise-grade attendance engine with 2-minute grace timers, offline-first storage, and auto toggle control.

## Features

### ✅ 2-Minute Grace Timers
- **Entry Grace**: When user enters premises, waits 2 minutes before auto check-in
- **Exit Grace**: When user leaves premises, waits 2 minutes before auto check-out
- Prevents false triggers from GPS fluctuations

### ✅ Auto Toggle Control
- Toggle is **driven by location intelligence**, not user input
- Automatically turns ON when user enters premises (after grace period)
- Automatically turns OFF when user leaves premises (after grace period)
- No manual toggle needed

### ✅ Offline-First Storage
- All events saved locally first (LocalShadowDatabase)
- Syncs to server when online (SyncManager)
- No data loss even if device is offline
- Survives app restart, kill, and device reboot

### ✅ Enhanced Data Model
Every attendance event stores:
- Exact timestamp
- GPS coordinates (latitude, longitude)
- Location name
- Location ID
- Auto/Manual flag
- Online/Offline device state
- Event type (CHECK_IN/CHECK_OUT)
- Notes
- Sync status

### ✅ Calendar Data Pipeline
- Get events for specific date
- Get events for date range
- Complete history per day
- Shows check-in/out times, duration, location

## Architecture

```
IntelligentAttendanceEngine
├── GeofenceManager (location monitoring)
├── LocalShadowDatabase (offline storage)
├── SyncManager (sync when online)
└── Grace Timer System (2-minute delays)
```

## Usage

### Basic Integration

```dart
// In AttendanceServiceFactory or main initialization
final geofenceManager = GeofenceManager();
final apiClient = AttendanceApiClient(baseUrl: baseUrl);
final intelligentEngine = IntelligentAttendanceEngine(
  geofenceManager: geofenceManager,
  apiClient: apiClient,
);

// Engine automatically handles:
// - 2-minute grace timers
// - Auto check-in/out
// - Toggle control
// - Offline storage
// - Sync when online
```

### Get Calendar Data

```dart
// Get events for a specific date
final events = await intelligentEngine.getEventsForDate(DateTime.now());

// Get events for date range
final events = await intelligentEngine.getEventsForDateRange(
  startDate,
  endDate,
);

// Each event contains:
// - timestamp
// - latitude, longitude
// - locationName
// - isAuto
// - isOnline
// - eventType
```

## Integration with Existing Service

The engine integrates seamlessly with existing `AttendanceService`:

1. **No Breaking Changes**: Existing service continues to work
2. **Optional Enhancement**: Intelligent engine can be enabled optionally
3. **Shared Components**: Uses same GeofenceManager and ApiClient

## Stability

- ✅ Survives app restart
- ✅ Survives app kill
- ✅ Survives device reboot
- ✅ Works offline
- ✅ Battery optimized (low-power GPS, 30-min checks)

## Files

- `models/attendance_event.dart` - Enhanced data model
- `storage/local_shadow_database.dart` - Offline SQLite storage
- `sync/sync_manager.dart` - Online sync manager
- `intelligent_attendance_engine.dart` - Main engine with grace timers
- `integration/attendance_engine_integration.dart` - Integration layer

