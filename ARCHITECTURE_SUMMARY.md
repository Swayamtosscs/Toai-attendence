# Geo-Based Attendance System - Architecture Summary

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter App Layer                        │
│  - UI Components                                             │
│  - Method Channels (start/stop service, permissions)        │
│  - Event Channels (listen to check-in/out events)           │
└──────────────────────┬──────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                  Android Native Layer                        │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         MainActivity (Permission Handler)             │  │
│  │  - Request permissions on first install                │  │
│  │  - Bridge Flutter ↔ Native                           │  │
│  └──────────────────────────────────────────────────────┘  │
│                        │                                     │
│                        ▼                                     │
│  ┌──────────────────────────────────────────────────────┐  │
│  │    ForegroundAttendanceService (Core Engine)         │  │
│  │  - Continuous location monitoring (30-60s)             │  │
│  │  - Geo-fence detection                                │  │
│  │  - 1-minute grace timers                              │  │
│  │  - Auto check-in/check-out                             │  │
│  │  - Manual toggle OFF handling                          │  │
│  └────────────┬───────────────────────┬──────────────────┘  │
│               │                       │                      │
│               ▼                       ▼                      │
│  ┌──────────────────────┐  ┌─────────────────────────────┐  │
│  │   Room Database      │  │   API Calls (OkHttp)        │  │
│  │  - Offline storage   │  │  - Check-in API             │  │
│  │  - Event persistence │  │  - Check-out API            │  │
│  └──────────┬──────────┘  └─────────────────────────────┘  │
│             │                                                │
│             ▼                                                │
│  ┌──────────────────────────────────────────────────────┐  │
│  │      AttendanceSyncWorker (WorkManager)              │  │
│  │  - Periodic sync (15 min)                             │  │
│  │  - Immediate sync on offline events                  │  │
│  │  - Retry logic                                        │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         BootReceiver                                   │  │
│  │  - Auto-restart service after reboot                  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔄 Data Flow

### Check-In Flow

```
1. User enters geo radius
   ↓
2. Location update detected (30-60s interval)
   ↓
3. Check if inside radius → YES
   ↓
4. Start 1-minute entry grace timer
   ↓
5. Timer expires (1 minute)
   ↓
6. Check if auto check-in disabled → NO
   ↓
7. Get current location
   ↓
8. Call check-in API
   ├─ Success → Save to DB (synced=true)
   └─ Failure → Save to DB (synced=false) → Trigger sync worker
   ↓
9. Update toggle state → ON
   ↓
10. Broadcast event to Flutter
```

### Check-Out Flow

```
1. User leaves geo radius
   ↓
2. Location update detected
   ↓
3. Check if inside radius → NO
   ↓
4. Start 1-minute exit grace timer
   ↓
5. Timer expires (1 minute)
   ↓
6. Get current location
   ↓
7. Call check-out API
   ├─ Success → Save to DB (synced=true)
   └─ Failure → Save to DB (synced=false) → Trigger sync worker
   ↓
8. Update toggle state → OFF
   ↓
9. Broadcast event to Flutter
```

### Manual Toggle OFF Flow

```
1. User manually turns toggle OFF
   ↓
2. ACTION_MANUAL_TOGGLE_OFF received
   ↓
3. Perform check-out immediately
   ↓
4. Save to DB
   ↓
5. Set auto check-in disabled flag
   ↓
6. Store today's date
   ↓
7. Cancel any entry timers
   ↓
8. Broadcast event to Flutter
   ↓
9. Next day (midnight) → Flag auto-resets
```

### Offline Sync Flow

```
1. Event saved to DB (synced=false)
   ↓
2. Trigger immediate sync worker
   ↓
3. Worker checks network → Available
   ↓
4. Get unsynced events from DB
   ↓
5. For each event:
   ├─ Call appropriate API (check-in/check-out)
   ├─ Success → Mark as synced
   └─ Failure → Keep unsynced (retry later)
   ↓
6. Periodic sync runs every 15 minutes
```

---

## 🗄️ Database Schema

### AttendanceEvent Entity

```kotlin
@Entity(tableName = "attendance_events")
data class AttendanceEvent(
    @PrimaryKey val id: String,
    val eventType: String,        // "CHECK_IN" | "CHECK_OUT"
    val timestamp: Long,           // Unix timestamp (ms)
    val latitude: Double,
    val longitude: Double,
    val locationId: String?,
    val locationName: String?,
    val notes: String?,
    val isAuto: Boolean,          // true = auto, false = manual
    val synced: Boolean,          // Sync status
    val syncedAt: Long?,          // When synced
    val createdAt: Long            // Creation time
)
```

### DAO Operations

- `insertEvent()` - Save event
- `getUnsyncedEvents()` - Get events to sync
- `markAsSynced()` - Mark event as synced
- `getEventsForDateRange()` - Query by date
- `deleteOldSyncedEvents()` - Cleanup old data

---

## 🔐 Permission Management

### Required Permissions

1. **ACCESS_FINE_LOCATION** - High accuracy GPS
2. **ACCESS_COARSE_LOCATION** - Network-based location
3. **ACCESS_BACKGROUND_LOCATION** - Background tracking (Android 10+)
4. **POST_NOTIFICATIONS** - Foreground service notification (Android 13+)
5. **FOREGROUND_SERVICE** - Run foreground service
6. **FOREGROUND_SERVICE_LOCATION** - Location foreground service
7. **RECEIVE_BOOT_COMPLETED** - Auto-restart after reboot
8. **WAKE_LOCK** - Keep device awake (if needed)

### Permission Flow

```
App Launch
   ↓
Check if first launch
   ↓
Request foreground location
   ↓
User grants → Request background location (Android 10+)
   ↓
User grants → Request notifications (Android 13+)
   ↓
All granted → Service can start
```

---

## ⚙️ Configuration Constants

### Location Updates
```kotlin
LOCATION_UPDATE_INTERVAL_MS = 30_000L  // 30 seconds
LOCATION_UPDATE_DISTANCE_M = 10f       // 10 meters
```

### Grace Timers
```kotlin
GRACE_ENTRY_TIMER_MS = 60_000L  // 1 minute
GRACE_EXIT_TIMER_MS = 60_000L   // 1 minute
```

### Sync Intervals
```kotlin
Periodic sync: 15 minutes
Flex interval: 5 minutes
```

### Deep Validation
```kotlin
DEEP_VALIDATION_INTERVAL_MS = 1_800_000L  // 30 minutes
```

---

## 🔋 Battery Optimization

### Strategies

1. **Location Provider Priority**:
   - Prefer NETWORK_PROVIDER (battery efficient)
   - Fallback to GPS only if network unavailable

2. **Update Intervals**:
   - 30-60 second intervals (not continuous)
   - 10-meter distance threshold

3. **Battery Optimization Exemption**:
   - Request user to disable battery optimization
   - Critical for reliable background operation

---

## 🚨 Error Handling

### API Failures
- Event saved to DB with `synced=false`
- WorkManager syncs when online
- Retry logic with exponential backoff

### Location Failures
- Fallback to last known location
- Retry with delay
- Log errors for debugging

### Service Crashes
- `START_STICKY` ensures auto-restart
- State restored from SharedPreferences
- Grace timers restored if active

### Network Failures
- Events queued in DB
- Automatic sync when online
- No data loss

---

## 📊 State Management

### SharedPreferences Keys

```kotlin
KEY_IS_ENABLED              // Service enabled flag
KEY_IS_CHECKED_IN            // Current check-in state
KEY_LOCATION_ID              // Current location ID
KEY_CHECK_IN_TIME            // Last check-in time
KEY_ENTRY_TIMER_START        // Entry timer start time
KEY_EXIT_TIMER_START         // Exit timer start time
KEY_LAST_LOCATION_LAT        // Last known latitude
KEY_LAST_LOCATION_LNG        // Last known longitude
KEY_WORK_LOCATIONS           // Work locations JSON
KEY_AUTH_TOKEN               // API auth token
KEY_API_BASE_URL             // API base URL
KEY_MANUAL_TOGGLE_OFF_DATE   // Date of manual toggle OFF
KEY_AUTO_CHECKIN_DISABLED    // Auto check-in disabled flag
```

---

## 🔄 Service Lifecycle

### Start
1. Check permissions
2. Initialize database
3. Load work locations
4. Start foreground service
5. Start location monitoring
6. Start deep validation timer
7. Enqueue sync worker

### Stop
1. Stop location monitoring
2. Cancel all timers
3. Stop foreground service
4. Save state to SharedPreferences

### Restart (After Kill/Reboot)
1. BootReceiver detects restart
2. Check if service was enabled
3. Restore state from SharedPreferences
4. Restart service with saved config
5. Restore grace timers if active

---

## 🧪 Testing Scenarios

### 1. Normal Flow
- Enter location → 1 min timer → Auto check-in
- Leave location → 1 min timer → Auto check-out

### 2. Multiple Cycles
- Multiple check-in/check-out cycles in same day

### 3. Manual Toggle OFF
- Toggle OFF → Final check-out → Auto check-in disabled
- Next day → Auto check-in re-enabled

### 4. Offline Scenario
- Event saved to DB
- API fails → Marked unsynced
- Go online → Auto sync

### 5. App Kill
- Service restarts automatically
- State restored

### 6. Phone Reboot
- BootReceiver restarts service
- State restored

### 7. Permission Denial
- Graceful handling
- User can grant later

---

## 📈 Performance Considerations

1. **Database Operations**: All DB operations run on background thread
2. **API Calls**: Non-blocking with timeout (10 seconds)
3. **Location Updates**: Optimized intervals (30-60s)
4. **Memory**: Efficient state management with SharedPreferences
5. **Battery**: Network provider preferred over GPS

---

## 🔒 Security

1. **Auth Token**: Stored in SharedPreferences (encrypted on Android 10+)
2. **API Calls**: HTTPS only (configured in network_security_config.xml)
3. **Location Data**: Stored locally, synced securely
4. **Permissions**: Runtime permission requests (Android 6+)

---

## 🎯 Key Features Summary

✅ Continuous GPS monitoring (30-60s intervals)  
✅ 1-minute grace timers for entry/exit  
✅ Multiple check-in/check-out cycles per day  
✅ Manual toggle OFF = final check-out  
✅ Auto check-in disabled until next day  
✅ Offline support with Room database  
✅ Auto-sync with WorkManager  
✅ Survives app kills and reboots  
✅ Battery optimized  
✅ Android 10+ compliant  
✅ Smooth first-install experience  

---

**The system is production-ready and fully integrated!** 🚀

