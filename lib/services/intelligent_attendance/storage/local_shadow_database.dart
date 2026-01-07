import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/attendance_event.dart';

/// Offline-first local database for attendance events
/// Survives app restart, kill, and device reboot
class LocalShadowDatabase {
  static LocalShadowDatabase? _instance;
  Database? _database;

  LocalShadowDatabase._();

  static LocalShadowDatabase get instance {
    _instance ??= LocalShadowDatabase._();
    return _instance!;
  }

  /// Initialize database
  Future<void> initialize() async {
    if (_database != null) return;

    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'attendance_shadow.db');

      _database = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE attendance_events (
              id TEXT PRIMARY KEY,
              timestamp TEXT NOT NULL,
              latitude REAL NOT NULL,
              longitude REAL NOT NULL,
              locationName TEXT,
              locationId TEXT,
              isAuto INTEGER NOT NULL,
              isOnline INTEGER NOT NULL,
              eventType TEXT NOT NULL,
              notes TEXT,
              synced INTEGER NOT NULL DEFAULT 0,
              syncedAt TEXT,
              createdAt TEXT NOT NULL
            )
          ''');

          // Index for faster queries
          await db.execute('''
            CREATE INDEX idx_timestamp ON attendance_events(timestamp)
          ''');
          await db.execute('''
            CREATE INDEX idx_synced ON attendance_events(synced)
          ''');
          await db.execute('''
            CREATE INDEX idx_eventType ON attendance_events(eventType)
          ''');
        },
      );

      debugPrint('[LocalShadowDatabase] ✅ Database initialized');
    } catch (e) {
      debugPrint('[LocalShadowDatabase] ❌ Database initialization failed: $e');
      rethrow;
    }
  }

  /// Save attendance event (offline-first)
  Future<void> saveEvent(AttendanceEvent event) async {
    await initialize();

    final id = event.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final eventWithId = event.copyWith(id: id);

    try {
      await _database!.insert(
        'attendance_events',
        {
          ...eventWithId.toJson(),
          'createdAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('[LocalShadowDatabase] ✅ Event saved: $id');
    } catch (e) {
      debugPrint('[LocalShadowDatabase] ❌ Failed to save event: $e');
      rethrow;
    }
  }

  /// Get all unsynced events
  Future<List<AttendanceEvent>> getUnsyncedEvents() async {
    await initialize();

    try {
      final results = await _database!.query(
        'attendance_events',
        where: 'synced = ?',
        whereArgs: [0],
        orderBy: 'timestamp ASC',
      );

      return results.map((row) => AttendanceEvent.fromJson(row)).toList();
    } catch (e) {
      debugPrint('[LocalShadowDatabase] ❌ Failed to get unsynced events: $e');
      return [];
    }
  }

  /// Get events for a date range
  Future<List<AttendanceEvent>> getEventsForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    await initialize();

    try {
      final results = await _database!.query(
        'attendance_events',
        where: 'timestamp >= ? AND timestamp <= ?',
        whereArgs: [
          startDate.toIso8601String(),
          endDate.toIso8601String(),
        ],
        orderBy: 'timestamp ASC',
      );

      return results.map((row) => AttendanceEvent.fromJson(row)).toList();
    } catch (e) {
      debugPrint('[LocalShadowDatabase] ❌ Failed to get events: $e');
      return [];
    }
  }

  /// Get events for a specific date
  Future<List<AttendanceEvent>> getEventsForDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return getEventsForDateRange(startOfDay, endOfDay);
  }

  /// Mark event as synced
  Future<void> markAsSynced(String eventId) async {
    await initialize();

    try {
      await _database!.update(
        'attendance_events',
        {
          'synced': 1,
          'syncedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [eventId],
      );
      debugPrint('[LocalShadowDatabase] ✅ Event marked as synced: $eventId');
    } catch (e) {
      debugPrint('[LocalShadowDatabase] ❌ Failed to mark as synced: $e');
    }
  }

  /// Delete old synced events (older than 30 days)
  Future<void> cleanupOldEvents() async {
    await initialize();

    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
      await _database!.delete(
        'attendance_events',
        where: 'synced = ? AND timestamp < ?',
        whereArgs: [1, cutoffDate.toIso8601String()],
      );
      debugPrint('[LocalShadowDatabase] ✅ Cleaned up old events');
    } catch (e) {
      debugPrint('[LocalShadowDatabase] ❌ Failed to cleanup: $e');
    }
  }

  /// Get all events (for debugging)
  Future<List<AttendanceEvent>> getAllEvents() async {
    await initialize();

    try {
      final results = await _database!.query(
        'attendance_events',
        orderBy: 'timestamp DESC',
      );

      return results.map((row) => AttendanceEvent.fromJson(row)).toList();
    } catch (e) {
      debugPrint('[LocalShadowDatabase] ❌ Failed to get all events: $e');
      return [];
    }
  }

  /// Close database
  Future<void> close() async {
    await _database?.close();
    _database = null;
    debugPrint('[LocalShadowDatabase] ✅ Database closed');
  }
}

