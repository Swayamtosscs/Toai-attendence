import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../storage/local_shadow_database.dart';
import '../../attendance_api_client.dart';

/// Syncs offline events to server when online
/// Non-blocking, runs in background
class SyncManager {
  final LocalShadowDatabase _database = LocalShadowDatabase.instance;
  final AttendanceApiClient _apiClient;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _syncTimer;
  bool _isSyncing = false;

  SyncManager({required AttendanceApiClient apiClient})
      : _apiClient = apiClient;

  /// Start automatic syncing
  Future<void> start() async {
    debugPrint('[SyncManager] 🚀 Starting sync manager');

    // Initial sync attempt
    await _attemptSync();

    // Listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        if (results.any((r) => r != ConnectivityResult.none)) {
          debugPrint('[SyncManager] ✅ Internet connected - attempting sync');
          _attemptSync();
        }
      },
    );

    // Periodic sync every 5 minutes (when online)
    _syncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _attemptSync(),
    );
  }

  /// Stop syncing
  void stop() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
    debugPrint('[SyncManager] 🛑 Sync manager stopped');
  }

  /// Attempt to sync unsynced events
  Future<void> _attemptSync() async {
    if (_isSyncing) {
      debugPrint('[SyncManager] ⏳ Sync already in progress');
      return;
    }

    // Check connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      debugPrint('[SyncManager] ⚠️ No internet - skipping sync');
      return;
    }

    _isSyncing = true;

    try {
      final unsyncedEvents = await _database.getUnsyncedEvents();
      if (unsyncedEvents.isEmpty) {
        debugPrint('[SyncManager] ✅ No unsynced events');
        return;
      }

      debugPrint('[SyncManager] 📤 Syncing ${unsyncedEvents.length} events');

      for (final event in unsyncedEvents) {
        try {
          if (event.eventType == 'CHECK_IN') {
            await _apiClient.checkIn(
              latitude: event.latitude,
              longitude: event.longitude,
              notes: event.notes ?? 'Auto check-in (synced)',
            );
          } else if (event.eventType == 'CHECK_OUT') {
            await _apiClient.checkOut(
              latitude: event.latitude,
              longitude: event.longitude,
              notes: event.notes ?? (event.isAuto ? 'Auto check-out (synced)' : 'Manual check-out (synced)'),
            );
          }

          // Mark as synced (events from DB should have IDs, but check for safety)
          if (event.id != null) {
            await _database.markAsSynced(event.id!);
            debugPrint('[SyncManager] ✅ Synced event: ${event.id}');
          } else {
            debugPrint('[SyncManager] ⚠️ Event has no ID, skipping markAsSynced');
          }
        } catch (e) {
          debugPrint('[SyncManager] ❌ Failed to sync event ${event.id ?? 'unknown'}: $e');
          // Continue with next event
        }
      }

      debugPrint('[SyncManager] ✅ Sync completed');
    } catch (e) {
      debugPrint('[SyncManager] ❌ Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Manual sync trigger
  Future<void> syncNow() async {
    await _attemptSync();
  }

  /// Dispose resources
  void dispose() {
    stop();
  }
}

