/// Enhanced attendance event model with all required fields
class AttendanceEvent {
  final String? id; // Local ID (UUID) or server ID
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final String? locationName;
  final String? locationId;
  final bool isAuto; // true for auto, false for manual
  final bool isOnline; // true if device was online when event occurred
  final String eventType; // 'CHECK_IN' or 'CHECK_OUT'
  final String? notes;
  final bool synced; // true if synced to server
  final DateTime? syncedAt; // When synced to server

  AttendanceEvent({
    this.id,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.locationName,
    this.locationId,
    required this.isAuto,
    required this.isOnline,
    required this.eventType,
    this.notes,
    this.synced = false,
    this.syncedAt,
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
      'locationId': locationId,
      'isAuto': isAuto ? 1 : 0,
      'isOnline': isOnline ? 1 : 0,
      'eventType': eventType,
      'notes': notes,
      'synced': synced ? 1 : 0,
      'syncedAt': syncedAt?.toIso8601String(),
    };
  }

  /// Create from JSON
  factory AttendanceEvent.fromJson(Map<String, dynamic> json) {
    return AttendanceEvent(
      id: json['id'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      locationName: json['locationName'] as String?,
      locationId: json['locationId'] as String?,
      isAuto: (json['isAuto'] as int) == 1,
      isOnline: (json['isOnline'] as int) == 1,
      eventType: json['eventType'] as String,
      notes: json['notes'] as String?,
      synced: (json['synced'] as int) == 1,
      syncedAt: json['syncedAt'] != null
          ? DateTime.parse(json['syncedAt'] as String)
          : null,
    );
  }

  /// Create a copy with updated fields
  AttendanceEvent copyWith({
    String? id,
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    String? locationName,
    String? locationId,
    bool? isAuto,
    bool? isOnline,
    String? eventType,
    String? notes,
    bool? synced,
    DateTime? syncedAt,
  }) {
    return AttendanceEvent(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      locationId: locationId ?? this.locationId,
      isAuto: isAuto ?? this.isAuto,
      isOnline: isOnline ?? this.isOnline,
      eventType: eventType ?? this.eventType,
      notes: notes ?? this.notes,
      synced: synced ?? this.synced,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }
}

