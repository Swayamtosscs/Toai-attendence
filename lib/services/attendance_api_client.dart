import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';
import 'safe_json_decoder.dart';

/// API client for attendance-related backend calls
/// Handles check-in, check-out, and work location fetching
class AttendanceApiClient {
  final String baseUrl;
  final http.Client _httpClient;

  AttendanceApiClient({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Get authentication token from AuthApiService
  Future<String?> _getAuthToken() async {
    final token = await StorageService.getAuthToken();
    return token;
  }

  /// Build headers with authentication
  Future<Map<String, String>> _buildHeaders() async {
    final token = await _getAuthToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Check-in API call
  /// Returns check-in response or throws AttendanceApiException
  Future<CheckInResponse> checkIn({
    required double latitude,
    required double longitude,
    String? locationId, // Optional, not sent to API
    String? notes,
  }) async {
    final url = '$baseUrl/attendance/check-in';
    final uri = Uri.parse(url);
    
    try {
      final headers = await _buildHeaders();
      final body = jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      });

      // Deep logging before API call
      debugPrint('[AttendanceApiClient] 🔵 Check-in API call');
      debugPrint('[AttendanceApiClient] URL: $url');
      debugPrint('[AttendanceApiClient] Method: POST');
      debugPrint('[AttendanceApiClient] Headers: ${headers.keys.join(", ")}');
      debugPrint('[AttendanceApiClient] Body: $body');

      final response = await _httpClient.post(
        uri,
        headers: headers,
        body: body,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw AttendanceApiException('Check-in request timeout'),
      );

      // Deep logging after response
      final responsePreview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      debugPrint('[AttendanceApiClient] ✅ Check-in response received');
      debugPrint('[AttendanceApiClient] Status: ${response.statusCode}');
      debugPrint('[AttendanceApiClient] Response preview: $responsePreview');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: url,
          statusCode: response.statusCode,
        );
        
        // Handle response format: {success: true, data: {...}}
        final data = responseData['data'] as Map<String, dynamic>? ?? responseData;
        return CheckInResponse.fromJson(data);
      } else if (response.statusCode == 401) {
        throw AttendanceApiException('Authentication failed');
      } else {
        try {
          final error = SafeJsonDecoder.safeJsonDecode(
            response.body,
            url: url,
            statusCode: response.statusCode,
          );
          throw AttendanceApiException(
            error['message'] as String? ?? 'Check-in failed',
          );
        } on FormatException catch (e) {
          throw AttendanceApiException(
            'Check-in failed (Status: ${response.statusCode}): ${e.message}',
          );
        }
      }
    } catch (e) {
      if (e is AttendanceApiException) rethrow;
      debugPrint('[AttendanceApiClient] ❌ Check-in error: $e');
      throw AttendanceApiException('Network error: ${e.toString()}');
    }
  }

  /// Check-out API call
  /// Returns check-out response or throws AttendanceApiException
  Future<CheckOutResponse> checkOut({
    required double latitude,
    required double longitude,
    String? notes,
  }) async {
    final url = '$baseUrl/attendance/check-out';
    final uri = Uri.parse(url);
    
    try {
      final headers = await _buildHeaders();
      final body = jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      });

      // Deep logging before API call
      debugPrint('[AttendanceApiClient] 🔵 Check-out API call');
      debugPrint('[AttendanceApiClient] URL: $url');
      debugPrint('[AttendanceApiClient] Method: POST');
      debugPrint('[AttendanceApiClient] Headers: ${headers.keys.join(", ")}');
      debugPrint('[AttendanceApiClient] Body: $body');

      final response = await _httpClient.post(
        uri,
        headers: headers,
        body: body,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw AttendanceApiException('Check-out request timeout'),
      );

      // Deep logging after response
      final responsePreview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      debugPrint('[AttendanceApiClient] ✅ Check-out response received');
      debugPrint('[AttendanceApiClient] Status: ${response.statusCode}');
      debugPrint('[AttendanceApiClient] Response preview: $responsePreview');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final payload = SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: url,
          statusCode: response.statusCode,
        );
        // Handle new API format with nested 'data' field
        final data = payload['data'] as Map<String, dynamic>? ?? payload;
        return CheckOutResponse.fromJson(data);
      } else if (response.statusCode == 401) {
        throw AttendanceApiException('Authentication failed');
      } else {
        try {
          final error = SafeJsonDecoder.safeJsonDecode(
            response.body,
            url: url,
            statusCode: response.statusCode,
          );
          throw AttendanceApiException(
            error['message'] as String? ?? 'Check-out failed',
          );
        } on FormatException catch (e) {
          throw AttendanceApiException(
            'Check-out failed (Status: ${response.statusCode}): ${e.message}',
          );
        }
      }
    } catch (e) {
      if (e is AttendanceApiException) rethrow;
      debugPrint('[AttendanceApiClient] ❌ Check-out error: $e');
      throw AttendanceApiException('Network error: ${e.toString()}');
    }
  }

  /// Fetch work locations from backend
  /// Returns list of work locations or throws AttendanceApiException
  Future<List<WorkLocation>> getWorkLocations() async {
    final url = '$baseUrl/work-locations';
    final uri = Uri.parse(url);
    
    try {
      final headers = await _buildHeaders();

      // Deep logging before API call
      debugPrint('[AttendanceApiClient] 🔵 Get work locations API call');
      debugPrint('[AttendanceApiClient] URL: $url');
      debugPrint('[AttendanceApiClient] Method: GET');
      debugPrint('[AttendanceApiClient] Headers: ${headers.keys.join(", ")}');

      final response = await _httpClient.get(
        uri,
        headers: headers,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw AttendanceApiException('Fetch locations timeout'),
      );

      // Deep logging after response
      final responsePreview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      debugPrint('[AttendanceApiClient] ✅ Get locations response received');
      debugPrint('[AttendanceApiClient] Status: ${response.statusCode}');
      debugPrint('[AttendanceApiClient] Response preview: $responsePreview');

      if (response.statusCode == 200) {
        final responseData = SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: url,
          statusCode: response.statusCode,
        );
        
        // Handle new response format: {success: true, data: [...]}
        // Also support old format: {locations: [...]}
        List<dynamic> locations = [];
        if (responseData['data'] != null && responseData['data'] is List) {
          locations = responseData['data'] as List<dynamic>;
        } else if (responseData['locations'] != null && responseData['locations'] is List) {
          locations = responseData['locations'] as List<dynamic>;
        }
        
        // Filter out inactive locations if isActive field exists
        final activeLocations = locations.where((loc) {
          if (loc is Map<String, dynamic>) {
            final isActive = loc['isActive'];
            return isActive == null || isActive == true;
          }
          return true;
        }).toList();
        
        return activeLocations
            .map((loc) => WorkLocation.fromJson(loc as Map<String, dynamic>))
            .toList();
      } else if (response.statusCode == 401) {
        throw AttendanceApiException('Authentication failed');
      } else {
        try {
          final error = SafeJsonDecoder.safeJsonDecode(
            response.body,
            url: url,
            statusCode: response.statusCode,
          );
          throw AttendanceApiException(
            error['message'] as String? ?? 'Failed to fetch work locations',
          );
        } on FormatException catch (e) {
          throw AttendanceApiException(
            'Failed to fetch work locations (Status: ${response.statusCode}): ${e.message}',
          );
        }
      }
    } catch (e) {
      if (e is AttendanceApiException) rethrow;
      debugPrint('[AttendanceApiClient] ❌ Get locations error: $e');
      throw AttendanceApiException('Network error: ${e.toString()}');
    }
  }

  /// Employee suggests a new work location for admin approval
  /// POST /work-locations/suggestions
  /// Returns backend message (e.g. "Location suggestion submitted successfully")
  Future<String> suggestWorkLocation({
    required String name,
    required double latitude,
    required double longitude,
    required double radius,
    String? notes,
  }) async {
    final url = '$baseUrl/work-locations/suggestions';
    final uri = Uri.parse(url);

    try {
      final headers = await _buildHeaders();
      final body = jsonEncode({
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      });

      // Deep logging before API call
      debugPrint('[AttendanceApiClient] 🔵 Suggest work location API call');
      debugPrint('[AttendanceApiClient] URL: $url');
      debugPrint('[AttendanceApiClient] Method: POST');
      debugPrint('[AttendanceApiClient] Headers: ${headers.keys.join(", ")}');
      debugPrint('[AttendanceApiClient] Body: $body');

      final response = await _httpClient
          .post(
            uri,
            headers: headers,
            body: body,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw AttendanceApiException(
              'Location suggestion request timeout',
            ),
          );

      // Deep logging after response
      final responsePreview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      debugPrint('[AttendanceApiClient] ✅ Suggest work location response');
      debugPrint('[AttendanceApiClient] Status: ${response.statusCode}');
      debugPrint('[AttendanceApiClient] Response preview: $responsePreview');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: url,
          statusCode: response.statusCode,
        );

        final message =
            data['message']?.toString() ?? 'Location suggestion submitted';
        return message;
      } else if (response.statusCode == 401) {
        throw AttendanceApiException('Authentication failed');
      } else {
        try {
          final error = SafeJsonDecoder.safeJsonDecode(
            response.body,
            url: url,
            statusCode: response.statusCode,
          );
          throw AttendanceApiException(
            error['message'] as String? ??
                error['error'] as String? ??
                'Failed to submit location suggestion',
          );
        } on FormatException catch (e) {
          throw AttendanceApiException(
            'Failed to submit location suggestion (Status: ${response.statusCode}): ${e.message}',
          );
        }
      }
    } catch (e) {
      if (e is AttendanceApiException) rethrow;
      debugPrint('[AttendanceApiClient] ❌ Suggest work location error: $e');
      throw AttendanceApiException('Network error: ${e.toString()}');
    }
  }

  /// Get work location suggestions (for admin)
  /// GET /work-locations/suggestions?status=pending
  Future<List<LocationSuggestion>> getLocationSuggestions({
    String status = 'pending',
  }) async {
    final url = '$baseUrl/work-locations/suggestions?status=$status';
    final uri = Uri.parse(url);

    try {
      final headers = await _buildHeaders();

      debugPrint('[AttendanceApiClient] 🔵 Get location suggestions API call');
      debugPrint('[AttendanceApiClient] URL: $url');
      debugPrint('[AttendanceApiClient] Method: GET');

      final response = await _httpClient
          .get(
            uri,
            headers: headers,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw AttendanceApiException('Fetch suggestions timeout'),
          );

      final responsePreview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      debugPrint('[AttendanceApiClient] ✅ Get suggestions response');
      debugPrint('[AttendanceApiClient] Status: ${response.statusCode}');
      debugPrint('[AttendanceApiClient] Response preview: $responsePreview');

      if (response.statusCode == 200) {
        final data = SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: url,
          statusCode: response.statusCode,
        );

        final list = (data['data'] as List<dynamic>? ?? [])
            .map((e) => LocationSuggestion.fromJson(
                  e as Map<String, dynamic>,
                ))
            .toList();
        return list;
      } else if (response.statusCode == 401) {
        throw AttendanceApiException('Authentication failed');
      } else {
        try {
          final error = SafeJsonDecoder.safeJsonDecode(
            response.body,
            url: url,
            statusCode: response.statusCode,
          );
          throw AttendanceApiException(
            error['message'] as String? ??
                error['error'] as String? ??
                'Failed to fetch location suggestions',
          );
        } on FormatException catch (e) {
          throw AttendanceApiException(
            'Failed to fetch location suggestions (Status: ${response.statusCode}): ${e.message}',
          );
        }
      }
    } catch (e) {
      if (e is AttendanceApiException) rethrow;
      debugPrint('[AttendanceApiClient] ❌ Get suggestions error: $e');
      throw AttendanceApiException('Network error: ${e.toString()}');
    }
  }

  /// Approve / reject a work location suggestion (admin)
  /// PATCH /work-locations/suggestions/{id}
  /// status: "approved" or "rejected"
  Future<LocationSuggestionDecisionResult> decideLocationSuggestion({
    required String suggestionId,
    required String status,
    String? reason,
  }) async {
    final url = '$baseUrl/work-locations/suggestions/$suggestionId';
    final uri = Uri.parse(url);

    try {
      final headers = await _buildHeaders();
      final body = jsonEncode({
        'status': status,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });

      debugPrint('[AttendanceApiClient] 🔵 Decide suggestion API call');
      debugPrint('[AttendanceApiClient] URL: $url');
      debugPrint('[AttendanceApiClient] Method: PATCH');
      debugPrint('[AttendanceApiClient] Body: $body');

      final response = await _httpClient
          .patch(
            uri,
            headers: headers,
            body: body,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw AttendanceApiException(
              'Suggestion decision timeout',
            ),
          );

      final responsePreview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      debugPrint('[AttendanceApiClient] ✅ Decide suggestion response');
      debugPrint('[AttendanceApiClient] Status: ${response.statusCode}');
      debugPrint('[AttendanceApiClient] Response preview: $responsePreview');

      if (response.statusCode == 200) {
        final data = SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: url,
          statusCode: response.statusCode,
        );
        return LocationSuggestionDecisionResult.fromJson(
          data['data'] as Map<String, dynamic>? ?? {},
        );
      } else if (response.statusCode == 401) {
        throw AttendanceApiException('Authentication failed');
      } else {
        try {
          final error = SafeJsonDecoder.safeJsonDecode(
            response.body,
            url: url,
            statusCode: response.statusCode,
          );
          throw AttendanceApiException(
            error['message'] as String? ??
                error['error'] as String? ??
                'Failed to update suggestion',
          );
        } on FormatException catch (e) {
          throw AttendanceApiException(
            'Failed to update suggestion (Status: ${response.statusCode}): ${e.message}',
          );
        }
      }
    } catch (e) {
      if (e is AttendanceApiException) rethrow;
      debugPrint('[AttendanceApiClient] ❌ Decide suggestion error: $e');
      throw AttendanceApiException('Network error: ${e.toString()}');
    }
  }

  /// Admin: get attendance history for a user for last N days (max 30)
  /// GET /attendance/history?days=15&userId=...
  Future<List<AttendanceHistoryDay>> getAttendanceHistory({
    required String userId,
    int days = 15,
  }) async {
    if (days < 1) days = 1;
    if (days > 30) days = 30;

    final url = '$baseUrl/attendance/history?days=$days&userId=$userId';
    final uri = Uri.parse(url);

    try {
      final headers = await _buildHeaders();

      debugPrint('[AttendanceApiClient] 🔵 Get attendance history API call');
      debugPrint('[AttendanceApiClient] URL: $url');

      final response = await _httpClient
          .get(
            uri,
            headers: headers,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw AttendanceApiException('Attendance history timeout'),
          );

      final responsePreview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      debugPrint('[AttendanceApiClient] ✅ Attendance history response');
      debugPrint('[AttendanceApiClient] Status: ${response.statusCode}');
      debugPrint('[AttendanceApiClient] Response preview: $responsePreview');

      if (response.statusCode == 200) {
        final data = SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: url,
          statusCode: response.statusCode,
        );

        final list = (data['data'] as List<dynamic>? ?? [])
            .map((e) => AttendanceHistoryDay.fromJson(
                  e as Map<String, dynamic>,
                ))
            .toList();
        return list;
      } else if (response.statusCode == 401) {
        throw AttendanceApiException('Authentication failed');
      } else {
        try {
          final error = SafeJsonDecoder.safeJsonDecode(
            response.body,
            url: url,
            statusCode: response.statusCode,
          );
          throw AttendanceApiException(
            error['message'] as String? ??
                error['error'] as String? ??
                'Failed to fetch attendance history',
          );
        } on FormatException catch (e) {
          throw AttendanceApiException(
            'Failed to fetch attendance history (Status: ${response.statusCode}): ${e.message}',
          );
        }
      }
    } catch (e) {
      if (e is AttendanceApiException) rethrow;
      debugPrint('[AttendanceApiClient] ❌ Attendance history error: $e');
      throw AttendanceApiException('Network error: ${e.toString()}');
    }
  }

  /// Save location to backend
  /// Returns saved location or throws AttendanceApiException
  Future<WorkLocation> saveLocation({
    required String name,
    required double latitude,
    required double longitude,
    required double radius,
    String? locationId, // For update
  }) async {
    final url = locationId != null
        ? '$baseUrl/work-locations/$locationId'
        : '$baseUrl/work-locations';
    final uri = Uri.parse(url);
    
    try {
      final headers = await _buildHeaders();
      final body = jsonEncode({
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
      });

      // Deep logging before API call
      debugPrint('[AttendanceApiClient] 🔵 Save location API call');
      debugPrint('[AttendanceApiClient] URL: $url');
      debugPrint('[AttendanceApiClient] Method: ${locationId != null ? 'PUT' : 'POST'}');
      debugPrint('[AttendanceApiClient] Headers: ${headers.keys.join(", ")}');
      debugPrint('[AttendanceApiClient] Body: $body');

      final response = await (locationId != null
          ? _httpClient.put(uri, headers: headers, body: body)
          : _httpClient.post(uri, headers: headers, body: body)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw AttendanceApiException('Save location request timeout'),
      );

      // Deep logging after response
      final responsePreview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      debugPrint('[AttendanceApiClient] ✅ Save location response received');
      debugPrint('[AttendanceApiClient] Status: ${response.statusCode}');
      debugPrint('[AttendanceApiClient] Response preview: $responsePreview');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: url,
          statusCode: response.statusCode,
        );
        
        // Handle response format: {success: true, data: {...}}
        final locationData = data['data'] as Map<String, dynamic>? ?? data;
        
        return WorkLocation(
          id: locationData['id']?.toString() ?? '',
          name: locationData['name']?.toString() ?? name,
          latitude: (locationData['latitude'] as num?)?.toDouble() ?? latitude,
          longitude: (locationData['longitude'] as num?)?.toDouble() ?? longitude,
          radius: (locationData['radius'] as num?)?.toDouble() ?? radius,
        );
      } else if (response.statusCode == 401) {
        throw AttendanceApiException('Authentication failed');
      } else {
        try {
          final error = SafeJsonDecoder.safeJsonDecode(
            response.body,
            url: url,
            statusCode: response.statusCode,
          );
          throw AttendanceApiException(
            error['message'] as String? ?? error['error'] as String? ?? 'Failed to save location',
          );
        } on FormatException catch (e) {
          throw AttendanceApiException(
            'Failed to save location (Status: ${response.statusCode}): ${e.message}',
          );
        }
      }
    } catch (e) {
      if (e is AttendanceApiException) rethrow;
      debugPrint('[AttendanceApiClient] ❌ Save location error: $e');
      throw AttendanceApiException('Network error: ${e.toString()}');
    }
  }

  /// Delete location from backend
  /// Returns true if successful or throws AttendanceApiException
  Future<bool> deleteLocation(String locationId) async {
    final url = '$baseUrl/work-locations/$locationId';
    final uri = Uri.parse(url);
    
    try {
      final headers = await _buildHeaders();

      // Deep logging before API call
      debugPrint('[AttendanceApiClient] 🔴 Delete location API call');
      debugPrint('[AttendanceApiClient] URL: $url');
      debugPrint('[AttendanceApiClient] Method: DELETE');
      debugPrint('[AttendanceApiClient] Headers: ${headers.keys.join(", ")}');

      final response = await _httpClient.delete(
        uri,
        headers: headers,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw AttendanceApiException('Delete location request timeout'),
      );

      // Deep logging after response
      final responsePreview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      debugPrint('[AttendanceApiClient] ✅ Delete location response received');
      debugPrint('[AttendanceApiClient] Status: ${response.statusCode}');
      debugPrint('[AttendanceApiClient] Response preview: $responsePreview');

      if (response.statusCode == 200 || response.statusCode == 204) {
        // Check if response has success field
        if (response.body.isNotEmpty) {
          try {
            final data = SafeJsonDecoder.safeJsonDecode(
              response.body,
              url: url,
              statusCode: response.statusCode,
            );
            final success = data['success'] as bool? ?? true;
            return success;
          } catch (e) {
            // If parsing fails, assume success for 200/204 status
            return true;
          }
        }
        return true;
      } else if (response.statusCode == 401) {
        throw AttendanceApiException('Authentication failed');
      } else if (response.statusCode == 404) {
        throw AttendanceApiException('Location not found');
      } else {
        try {
          final error = SafeJsonDecoder.safeJsonDecode(
            response.body,
            url: url,
            statusCode: response.statusCode,
          );
          throw AttendanceApiException(
            error['message'] as String? ?? error['error'] as String? ?? 'Failed to delete location',
          );
        } on FormatException catch (e) {
          throw AttendanceApiException(
            'Failed to delete location (Status: ${response.statusCode}): ${e.message}',
          );
        }
      }
    } catch (e) {
      if (e is AttendanceApiException) rethrow;
      debugPrint('[AttendanceApiClient] ❌ Delete location error: $e');
      throw AttendanceApiException('Network error: ${e.toString()}');
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

/// Work location suggestion model (for admin)
class LocationSuggestion {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radius;
  final String? notes;
  final String status;
  final String? createdByName;
  final String? createdByEmail;

  LocationSuggestion({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.status,
    this.notes,
    this.createdByName,
    this.createdByEmail,
  });

  factory LocationSuggestion.fromJson(Map<String, dynamic> json) {
    final createdBy = json['createdBy'] as Map<String, dynamic>? ?? {};
    return LocationSuggestion(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      radius: (json['radius'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      createdByName: createdBy['name']?.toString(),
      createdByEmail: createdBy['email']?.toString(),
    );
  }
}

/// Result of admin decision on suggestion
class LocationSuggestionDecisionResult {
  final LocationSuggestion suggestion;
  final WorkLocation? createdLocation;

  LocationSuggestionDecisionResult({
    required this.suggestion,
    required this.createdLocation,
  });

  factory LocationSuggestionDecisionResult.fromJson(
      Map<String, dynamic> json) {
    return LocationSuggestionDecisionResult(
      suggestion: LocationSuggestion.fromJson(
        json['suggestion'] as Map<String, dynamic>? ?? {},
      ),
      createdLocation: json['createdLocation'] != null
          ? WorkLocation.fromJson(
              json['createdLocation'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

/// One day's attendance history for a user (admin view)
class AttendanceHistoryDay {
  final DateTime date;
  final int totalCheckIns;
  final int totalCheckOuts;
  final String userId;
  final String userName;
  final String userEmail;
  final List<AttendanceHistoryLocationSummary> locations;

  AttendanceHistoryDay({
    required this.date,
    required this.totalCheckIns,
    required this.totalCheckOuts,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.locations,
  });

  factory AttendanceHistoryDay.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    final locationsJson = json['locations'] as List<dynamic>? ?? [];

    return AttendanceHistoryDay(
      date: DateTime.parse(json['date'].toString()),
      totalCheckIns: (json['totalCheckIns'] as num?)?.toInt() ?? 0,
      totalCheckOuts: (json['totalCheckOuts'] as num?)?.toInt() ?? 0,
      userId: user['id']?.toString() ?? '',
      userName: user['name']?.toString() ?? '',
      userEmail: user['email']?.toString() ?? '',
      locations: locationsJson
          .map((e) => AttendanceHistoryLocationSummary.fromJson(
                e as Map<String, dynamic>,
              ))
          .toList(),
    );
  }
}

/// Per-location summary inside a day's history
class AttendanceHistoryLocationSummary {
  final double? latitude;
  final double? longitude;
  final int checkIns;
  final int checkOuts;

  AttendanceHistoryLocationSummary({
    required this.latitude,
    required this.longitude,
    required this.checkIns,
    required this.checkOuts,
  });

  factory AttendanceHistoryLocationSummary.fromJson(
      Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>?;
    return AttendanceHistoryLocationSummary(
      latitude: (location?['latitude'] as num?)?.toDouble(),
      longitude: (location?['longitude'] as num?)?.toDouble(),
      checkIns: (json['checkIns'] as num?)?.toInt() ?? 0,
      checkOuts: (json['checkOuts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Work location model
class WorkLocation {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radius; // in meters

  WorkLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radius,
  });

  factory WorkLocation.fromJson(Map<String, dynamic> json) {
    return WorkLocation(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      radius: (json['radius'] as num?)?.toDouble() ?? 100.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
    };
  }
}

/// Check-in response model
class CheckInResponse {
  final String id;
  final DateTime checkInAt;
  final String? locationId;
  final String status;

  CheckInResponse({
    required this.id,
    required this.checkInAt,
    this.locationId,
    required this.status,
  });

  factory CheckInResponse.fromJson(Map<String, dynamic> json) {
    return CheckInResponse(
      id: json['id']?.toString() ?? json['eventId']?.toString() ?? '',
      checkInAt: json['checkInAt'] != null
          ? DateTime.parse(json['checkInAt'].toString()).toLocal()
          : DateTime.now(),
      locationId: json['locationId']?.toString(),
      status: json['status']?.toString() ?? 'PRESENT',
    );
  }
}

/// Check-out response model
class CheckOutResponse {
  final String id;
  final DateTime checkOutAt;
  final int workDurationMinutes;
  final int? totalCheckOutsToday;

  CheckOutResponse({
    required this.id,
    required this.checkOutAt,
    required this.workDurationMinutes,
    this.totalCheckOutsToday,
  });

  factory CheckOutResponse.fromJson(Map<String, dynamic> json) {
    return CheckOutResponse(
      id: json['eventId']?.toString() ?? json['id']?.toString() ?? '',
      checkOutAt: json['checkOutAt'] != null
          ? DateTime.parse(json['checkOutAt'].toString()).toLocal()
          : DateTime.now(),
      workDurationMinutes: (json['workDurationMinutes'] as num?)?.toInt() ?? 0,
      totalCheckOutsToday: (json['totalCheckOutsToday'] as num?)?.toInt(),
    );
  }
}

/// Custom exception for attendance API errors
class AttendanceApiException implements Exception {
  final String message;
  AttendanceApiException(this.message);

  @override
  String toString() => 'AttendanceApiException: $message';
}

