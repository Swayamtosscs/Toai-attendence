import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/http.dart' show MultipartFile, MultipartRequest;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'storage_service.dart';
import 'safe_json_decoder.dart';

const String _baseApiUrl = 'http://103.14.120.163:8092/api';
const Duration _defaultTimeout = Duration(seconds: 20);
const String _attendanceCookie =
    String.fromEnvironment('ATTENDANCE_TOKEN', defaultValue: '');

class RegisterRequest {
  RegisterRequest({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    required this.department,
    required this.designation,
    required this.managerId,
  });

  final String name;
  final String email;
  final String password;
  final String role;
  final String department;
  final String designation;
  final String managerId;

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'password': password,
        'role': role,
        'department': department,
        'designation': designation,
        'managerId': managerId,
      };
}

class RegisteredUser {
  RegisteredUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.department,
    required this.designation,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String? department;
  final String? designation;

  factory RegisteredUser.fromJson(Map<String, dynamic> json) {
    return RegisteredUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      department: json['department']?.toString(),
      designation: json['designation']?.toString(),
    );
  }
}

class LoginRequest {
  LoginRequest({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
      };
}

class LoginResponse {
  LoginResponse({
    required this.user,
    required this.token,
  });

  final RegisteredUser user;
  final String token;

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      user: RegisteredUser.fromJson(
        json['data'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      token: json['token']?.toString() ?? '',
    );
  }
}

class CheckInResponse {
  CheckInResponse({
    required this.id,
    required this.checkInAt,
    required this.status,
  });

  final String id;
  final DateTime checkInAt;
  final String status;

  factory CheckInResponse.fromJson(Map<String, dynamic> json) {
    return CheckInResponse(
      id: json['id']?.toString() ?? '',
      checkInAt: json['checkInAt'] != null
          ? DateTime.parse(json['checkInAt'].toString()).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(0),
      status: json['status']?.toString() ?? '',
    );
  }
}

class CheckOutResponse {
  CheckOutResponse({
    required this.id,
    required this.checkInAt,
    required this.checkOutAt,
    required this.workDurationMinutes,
    this.eventId,
    this.totalCheckOutsToday,
  });

  final String id;
  final DateTime checkInAt;
  final DateTime checkOutAt;
  final int workDurationMinutes;
  final String? eventId;
  final int? totalCheckOutsToday;

  factory CheckOutResponse.fromJson(Map<String, dynamic> json) {
    // Use eventId as id if id is not present (for new API format)
    final idValue = json['id']?.toString() ?? json['eventId']?.toString() ?? '';
    return CheckOutResponse(
      id: idValue,
      checkInAt: json['checkInAt'] != null
          ? DateTime.parse(json['checkInAt'].toString()).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(0),
      checkOutAt: json['checkOutAt'] != null
          ? DateTime.parse(json['checkOutAt'].toString()).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(0),
      workDurationMinutes: int.tryParse(json['workDurationMinutes']?.toString() ?? '') ?? 0,
      eventId: json['eventId']?.toString(),
      totalCheckOutsToday: json['totalCheckOutsToday'] != null 
          ? int.tryParse(json['totalCheckOutsToday']?.toString() ?? '') 
          : null,
    );
  }
}

class LeaveRequest {
  LeaveRequest({
    required this.startDate,
    required this.endDate,
    required this.type,
    required this.reason,
  });

  final DateTime startDate;
  final DateTime endDate;
  final String type;
  final String reason;

  Map<String, dynamic> toJson() => {
        'startDate': startDate.toUtc().toIso8601String(),
        'endDate': endDate.toUtc().toIso8601String(),
        'type': type,
        'reason': reason,
      };
}

class LeaveResponse {
  LeaveResponse({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.type,
    required this.status,
  });

  final String id;
  final DateTime startDate;
  final DateTime endDate;
  final String type;
  final String status;

  factory LeaveResponse.fromJson(Map<String, dynamic> json) {
    return LeaveResponse(
      id: json['id']?.toString() ?? '',
      startDate: DateTime.parse(json['startDate']?.toString() ?? DateTime.now().toIso8601String()),
      endDate: DateTime.parse(json['endDate']?.toString() ?? DateTime.now().toIso8601String()),
      type: json['type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }
}

class LeaveListItem {
  LeaveListItem({
    required this.id,
    required this.user,
    required this.manager,
    required this.startDate,
    required this.endDate,
    required this.type,
    required this.status,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final LeaveUserInfo user;
  final LeaveUserInfo manager;
  final DateTime startDate;
  final DateTime endDate;
  final String type;
  final String status;
  final String reason;
  final DateTime createdAt;

  factory LeaveListItem.fromJson(Map<String, dynamic> json) {
    return LeaveListItem(
      id: json['id']?.toString() ?? '',
      user: LeaveUserInfo.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
      manager: LeaveUserInfo.fromJson(json['manager'] as Map<String, dynamic>? ?? {}),
      startDate: DateTime.parse(json['startDate']?.toString() ?? DateTime.now().toIso8601String()),
      endDate: DateTime.parse(json['endDate']?.toString() ?? DateTime.now().toIso8601String()),
      type: json['type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      createdAt: DateTime.parse(json['createdAt']?.toString() ?? DateTime.now().toIso8601String()),
    );
  }
}

class LeaveUserInfo {
  LeaveUserInfo({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.department,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String? department;

  factory LeaveUserInfo.fromJson(Map<String, dynamic> json) {
    return LeaveUserInfo(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      department: json['department']?.toString(),
    );
  }
}

class AttendanceRecord {
  AttendanceRecord({
    required this.id,
    required this.user,
    required this.date,
    this.checkInAt,
    this.checkOutAt,
    this.workDurationMinutes,
    required this.status,
    this.notes,
    this.lateByMinutes,
  });

  final String id;
  final AttendanceUserInfo user;
  final DateTime date;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final int? workDurationMinutes;
  final String status;
  final String? notes;
  final int? lateByMinutes;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id']?.toString() ?? '',
      user: AttendanceUserInfo.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
      date: DateTime.parse(json['date']?.toString() ?? DateTime.now().toIso8601String()).toLocal(),
      checkInAt: json['checkInAt'] != null
          ? DateTime.parse(json['checkInAt'].toString()).toLocal()
          : null,
      checkOutAt: json['checkOutAt'] != null
          ? DateTime.parse(json['checkOutAt'].toString()).toLocal()
          : null,
      workDurationMinutes: json['workDurationMinutes'] != null
          ? int.tryParse(json['workDurationMinutes'].toString())
          : null,
      status: json['status']?.toString() ?? '',
      notes: json['notes']?.toString(),
      lateByMinutes: json['lateByMinutes'] != null
          ? int.tryParse(json['lateByMinutes'].toString())
          : null,
    );
  }
}

class AttendanceUserInfo {
  AttendanceUserInfo({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.department,
    this.designation,
    this.manager,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String? department;
  final String? designation;
  final String? manager;

  factory AttendanceUserInfo.fromJson(Map<String, dynamic> json) {
    return AttendanceUserInfo(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      department: json['department']?.toString(),
      designation: json['designation']?.toString(),
      manager: json['manager']?.toString(),
    );
  }
}

class CreateAttendanceRequest {
  CreateAttendanceRequest({
    required this.userId,
    required this.date,
    required this.checkInAt,
    required this.checkOutAt,
    required this.status,
    this.notes,
  });

  final String userId;
  final DateTime date;
  final DateTime checkInAt;
  final DateTime checkOutAt;
  final String status;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'date': date.toUtc().toIso8601String(),
        'checkInAt': checkInAt.toUtc().toIso8601String(),
        'checkOutAt': checkOutAt.toUtc().toIso8601String(),
        'status': status,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

class UpdateAttendanceRequest {
  UpdateAttendanceRequest({
    this.date,
    this.checkInAt,
    this.checkOutAt,
    this.status,
    this.notes,
  });

  final DateTime? date;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final String? status;
  final String? notes;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {};
    if (date != null) {
      json['date'] = date!.toUtc().toIso8601String();
    }
    if (checkInAt != null) {
      json['checkInAt'] = checkInAt!.toUtc().toIso8601String();
    }
    if (checkOutAt != null) {
      json['checkOutAt'] = checkOutAt!.toUtc().toIso8601String();
    }
    if (status != null) {
      json['status'] = status;
    }
    if (notes != null && notes!.isNotEmpty) {
      json['notes'] = notes;
    }
    return json;
  }
}

class AttendanceCount {
  AttendanceCount({
    required this.location,
    required this.checkIns,
    required this.checkOuts,
    required this.date,
    required this.checkInTimestamps,
    required this.checkOutTimestamps,
    required this.user,
  });

  final Map<String, dynamic> location;
  final int checkIns;
  final int checkOuts;
  final DateTime date;
  final List<String> checkInTimestamps;
  final List<String> checkOutTimestamps;
  final Map<String, dynamic> user;

  factory AttendanceCount.fromJson(Map<String, dynamic> json) {
    return AttendanceCount(
      location: json['location'] as Map<String, dynamic>? ?? {},
      checkIns: int.tryParse(json['checkIns']?.toString() ?? '0') ?? 0,
      checkOuts: int.tryParse(json['checkOuts']?.toString() ?? '0') ?? 0,
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      checkInTimestamps: (json['checkInTimestamps'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      checkOutTimestamps: (json['checkOutTimestamps'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      user: json['user'] as Map<String, dynamic>? ?? {},
    );
  }
}

class AttendanceSummary {
  AttendanceSummary({
    required this.user,
    required this.presentDays,
    required this.absentDays,
    required this.halfDays,
    required this.onLeaveDays,
    required this.totalMinutes,
  });

  final AttendanceUserInfo user;
  final int presentDays;
  final int absentDays;
  final int halfDays;
  final int onLeaveDays;
  final int totalMinutes;

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    return AttendanceSummary(
      user: AttendanceUserInfo.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
      presentDays: int.tryParse(json['presentDays']?.toString() ?? '0') ?? 0,
      absentDays: int.tryParse(json['absentDays']?.toString() ?? '0') ?? 0,
      halfDays: int.tryParse(json['halfDays']?.toString() ?? '0') ?? 0,
      onLeaveDays: int.tryParse(json['onLeaveDays']?.toString() ?? '0') ?? 0,
      totalMinutes: int.tryParse(json['totalMinutes']?.toString() ?? '0') ?? 0,
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.sender,
    required this.recipient,
    required this.content,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final ChatUser sender;
  final ChatUser recipient;
  final String content;
  final bool read;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      sender: ChatUser.fromJson(json['sender'] as Map<String, dynamic>? ?? {}),
      recipient: ChatUser.fromJson(json['recipient'] as Map<String, dynamic>? ?? {}),
      content: json['content']?.toString() ?? '',
      read: json['read'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class ChatUser {
  ChatUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.department,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String? department;

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: json['id']?.toString() ??
          json['_id']?.toString() ??
          json['userId']?.toString() ??
          '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      department: json['department']?.toString(),
    );
  }
}

class AuthApiException implements Exception {
  AuthApiException(this.message);
  final String message;

  @override
  String toString() => 'AuthApiException: $message';
}

class AuthApiService {
  AuthApiService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  static String? _authToken;
  static RegisteredUser? _currentUser;

  static RegisteredUser? get currentUser => _currentUser;

  Future<RegisteredUser> registerUser(RegisterRequest request) async {
    final uri = Uri.parse('$_baseApiUrl/auth/register');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    try {
      final response = await _httpClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(_defaultTimeout);

      _logResponse('register', uri, response);

      final Map<String, dynamic> payload = SafeJsonDecoder.safeJsonDecode(
        response.body,
        url: uri.toString(),
        statusCode: response.statusCode,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = payload['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
        return RegisteredUser.fromJson(data);
      }

      final message = payload['message'] ?? payload['error'] ?? 'Registration failed';
      throw AuthApiException(message.toString());
    } on SocketException catch (e) {
      throw AuthApiException(
        'Network error: Unable to connect to server. Please check your internet connection.',
      );
    } on HttpException catch (e) {
      throw AuthApiException('HTTP error: ${e.message}');
    } on FormatException catch (e) {
      throw AuthApiException('Invalid server response format');
    } catch (e) {
      if (e is AuthApiException) {
        rethrow;
      }
      throw AuthApiException('Registration failed: ${e.toString()}');
    }
  }

  Future<LoginResponse> login(LoginRequest request) async {
    final uri = Uri.parse('$_baseApiUrl/auth/login');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    try {
      final response = await _httpClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(_defaultTimeout);

      _logResponse('login', uri, response);

      final Map<String, dynamic> payload = SafeJsonDecoder.safeJsonDecode(
        response.body,
        url: uri.toString(),
        statusCode: response.statusCode,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final loginResponse = LoginResponse.fromJson(payload);
        _authToken = loginResponse.token;
        _currentUser = loginResponse.user;
        return loginResponse;
      }

      final message = payload['message'] ?? payload['error'] ?? 'Login failed';
      throw AuthApiException(message.toString());
    } on SocketException catch (e) {
      throw AuthApiException(
        'Network error: Unable to connect to server. Please check your internet connection.',
      );
    } on HttpException catch (e) {
      throw AuthApiException('HTTP error: ${e.message}');
    } on FormatException catch (e) {
      throw AuthApiException('Invalid server response format');
    } catch (e) {
      if (e is AuthApiException) {
        rethrow;
      }
      throw AuthApiException('Login failed: ${e.toString()}');
    }
  }

  Future<LoginResponse> loginWithGoogle(String idToken) async {
    final uri = Uri.parse('$_baseApiUrl/auth/google');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    try {
      final response = await _httpClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode({'idToken': idToken}),
          )
          .timeout(_defaultTimeout);

      _logResponse('google-login', uri, response);

      final Map<String, dynamic> payload = SafeJsonDecoder.safeJsonDecode(
        response.body,
        url: uri.toString(),
        statusCode: response.statusCode,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final loginResponse = LoginResponse.fromJson(payload);
        _authToken = loginResponse.token;
        _currentUser = loginResponse.user;
        return loginResponse;
      }

      final message = payload['message'] ?? payload['error'] ?? 'Google login failed';
      throw AuthApiException(message.toString());
    } on SocketException catch (e) {
      throw AuthApiException(
        'Network error: Unable to connect to server. Please check your internet connection.',
      );
    } on HttpException catch (e) {
      throw AuthApiException('HTTP error: ${e.message}');
    } on FormatException catch (e) {
      throw AuthApiException('Invalid server response format');
    } catch (e) {
      if (e is AuthApiException) {
        rethrow;
      }
      throw AuthApiException('Google login failed: ${e.toString()}');
    }
  }

  Future<bool> logout() async {
    final uri = Uri.parse('$_baseApiUrl/auth/logout');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    }

    try {
      final response = await _httpClient
          .post(
            uri,
            headers: headers,
          )
          .timeout(_defaultTimeout);

      _logResponse('logout', uri, response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _authToken = null;
        _currentUser = null;
        // Clear persistent login state
        await _clearPersistentLoginState();
        return true;
      }

      final Map<String, dynamic>? payload =
          response.body.isNotEmpty
              ? SafeJsonDecoder.safeJsonDecode(
                  response.body,
                  url: uri.toString(),
                  statusCode: response.statusCode,
                )
              : null;
      final message = payload?['message'] ?? 'Logout failed';
      throw AuthApiException(message.toString());
    } catch (e) {
      // Even if logout API fails, clear local state
      _authToken = null;
      _currentUser = null;
      await _clearPersistentLoginState();
      if (e is AuthApiException) {
        rethrow;
      }
      throw AuthApiException('Logout failed: ${e.toString()}');
    }
  }

  // Clear persistent login state
  Future<void> _clearPersistentLoginState() async {
    try {
      await StorageService.clearLoginState();
    } catch (e) {
      // Ignore errors when clearing storage
      developer.log('Error clearing persistent login state: $e', name: 'AuthApiService');
    }
  }

  // Restore login state from storage
  static void restoreLoginState({required String token, required RegisteredUser user}) {
    _authToken = token;
    _currentUser = user;
  }

  Future<CheckInResponse> checkIn({String? notes}) async {
    // Get current location
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('[AuthApiService] ⚠️ Failed to get location: $e');
      // Continue without location if it fails
    }

    final uri = Uri.parse('$_baseApiUrl/attendance/check-in');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    // Build request body with notes, latitude, and longitude
    final body = <String, dynamic>{
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (position != null) 'latitude': position.latitude,
      if (position != null) 'longitude': position.longitude,
    };

    try {
      // Deep logging before API call
      debugPrint('[AuthApiService] 🔵 Check-in API call');
      debugPrint('[AuthApiService] URL: ${uri.toString()}');
      debugPrint('[AuthApiService] Method: POST');
      debugPrint('[AuthApiService] Headers: ${headers.keys.join(", ")}');
      debugPrint('[AuthApiService] Body: ${jsonEncode(body)}');

      final response = await _httpClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(_defaultTimeout);

      _logResponse('check-in', uri, response);

      // Deep logging after response
      final responsePreview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      debugPrint('[AuthApiService] ✅ Check-in response received');
      debugPrint('[AuthApiService] Status: ${response.statusCode}');
      debugPrint('[AuthApiService] Response preview: $responsePreview');

      final Map<String, dynamic> payload = SafeJsonDecoder.safeJsonDecode(
        response.body,
        url: uri.toString(),
        statusCode: response.statusCode,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = payload['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
        return CheckInResponse.fromJson(data);
      }

      // Multiple check-ins are now allowed, so no need to handle 409 conflict
      final message = payload['message'] ?? payload['error'] ?? 'Check-in failed';
      throw AuthApiException(message.toString());
    } on SocketException catch (e) {
      throw AuthApiException(
        'Network error: Unable to connect to server. Please check your internet connection.',
      );
    } on HttpException catch (e) {
      throw AuthApiException('HTTP error: ${e.message}');
    } on FormatException catch (e) {
      throw AuthApiException('Invalid server response format');
    } catch (e) {
      if (e is AuthApiException) {
        rethrow;
      }
      throw AuthApiException('Check-in failed: ${e.toString()}');
    }
  }

  Future<CheckOutResponse> checkOut({String? notes}) async {
    // Get current location
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('[AuthApiService] ⚠️ Failed to get location: $e');
      // Continue without location if it fails
    }

    final uri = Uri.parse('$_baseApiUrl/attendance/check-out');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    // Build request body with notes, latitude, and longitude
    final body = <String, dynamic>{
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (position != null) 'latitude': position.latitude,
      if (position != null) 'longitude': position.longitude,
    };

    try {
      // Deep logging before API call
      debugPrint('[AuthApiService] 🔵 Check-out API call');
      debugPrint('[AuthApiService] URL: ${uri.toString()}');
      debugPrint('[AuthApiService] Method: POST');
      debugPrint('[AuthApiService] Headers: ${headers.keys.join(", ")}');
      debugPrint('[AuthApiService] Body: ${jsonEncode(body)}');

      final response = await _httpClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(_defaultTimeout);

      _logResponse('check-out', uri, response);

      // Deep logging after response
      final responsePreview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      debugPrint('[AuthApiService] ✅ Check-out response received');
      debugPrint('[AuthApiService] Status: ${response.statusCode}');
      debugPrint('[AuthApiService] Response preview: $responsePreview');

      final Map<String, dynamic> payload = SafeJsonDecoder.safeJsonDecode(
        response.body,
        url: uri.toString(),
        statusCode: response.statusCode,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = payload['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
        return CheckOutResponse.fromJson(data);
      }

      // Multiple check-outs are now allowed, so no need to handle 409 conflict
      final message = payload['message'] ?? payload['error'] ?? 'Check-out failed';
      throw AuthApiException(message.toString());
    } on SocketException catch (e) {
      throw AuthApiException(
        'Network error: Unable to connect to server. Please check your internet connection.',
      );
    } on HttpException catch (e) {
      throw AuthApiException('HTTP error: ${e.message}');
    } on FormatException catch (e) {
      throw AuthApiException('Invalid server response format');
    } catch (e) {
      if (e is AuthApiException) {
        rethrow;
      }
      throw AuthApiException('Check-out failed: ${e.toString()}');
    }
  }

  Future<LeaveResponse> submitLeaveRequest(LeaveRequest request) async {
    final uri = Uri.parse('$_baseApiUrl/leave');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    final response = await _httpClient
        .post(
          uri,
          headers: headers,
          body: jsonEncode(request.toJson()),
        )
        .timeout(_defaultTimeout);

    _logResponse('leave-request', uri, response);

    final Map<String, dynamic> payload = SafeJsonDecoder.safeJsonDecode(
      response.body,
      url: uri.toString(),
      statusCode: response.statusCode,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = payload['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
      return LeaveResponse.fromJson(data);
    }

    final message = payload['message'] ?? payload['error'] ?? 'Leave request failed';
    throw AuthApiException(message.toString());
  }

  Future<List<LeaveListItem>> getLeaveList() async {
    final uri = Uri.parse('$_baseApiUrl/leave');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    final response = await _httpClient
        .get(
          uri,
          headers: headers,
        )
        .timeout(_defaultTimeout);

    _logResponse('get-leave-list', uri, response);

    final Map<String, dynamic> payload = SafeJsonDecoder.safeJsonDecode(
      response.body,
      url: uri.toString(),
      statusCode: response.statusCode,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final dataList = payload['data'] as List<dynamic>? ?? [];
      return dataList
          .map((item) => LeaveListItem.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    final message = payload['message'] ?? payload['error'] ?? 'Failed to fetch leave list';
    throw AuthApiException(message.toString());
  }

  Future<Map<String, dynamic>> updateLeaveStatus({
    required String leaveId,
    required String status,
    String? reply,
  }) async {
    final uri = Uri.parse('$_baseApiUrl/leave/$leaveId');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    final body = <String, dynamic>{
      'status': status,
    };
    if (reply != null && reply.isNotEmpty) {
      body['reply'] = reply;
    }

    final response = await _httpClient
        .patch(
          uri,
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(_defaultTimeout);

    _logResponse('update-leave-status', uri, response);

    final Map<String, dynamic> payload =
        SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: uri.toString(),
          statusCode: response.statusCode,
        );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = payload['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
      return data;
    }

    final message = payload['message'] ?? payload['error'] ?? 'Failed to update leave status';
    throw AuthApiException(message.toString());
  }

  Future<List<AttendanceRecord>> getAttendanceRecords({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
  }) async {
    final uriBuilder = Uri.parse('$_baseApiUrl/attendance').replace(queryParameters: {});
    final queryParams = <String, String>{};
    
    if (userId != null && userId.isNotEmpty) {
      queryParams['userId'] = userId;
    }
    if (startDate != null) {
      queryParams['startDate'] = startDate.toUtc().toIso8601String();
    }
    if (endDate != null) {
      queryParams['endDate'] = endDate.toUtc().toIso8601String();
    }
    if (status != null && status.isNotEmpty) {
      queryParams['status'] = status;
    }
    
    final uri = queryParams.isEmpty
        ? uriBuilder
        : uriBuilder.replace(queryParameters: queryParams);
    
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    final response = await _httpClient
        .get(
          uri,
          headers: headers,
        )
        .timeout(_defaultTimeout);

    _logResponse('get-attendance-records', uri, response);

    final Map<String, dynamic> payload =
        SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: uri.toString(),
          statusCode: response.statusCode,
        );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final dataList = payload['data'] as List<dynamic>? ?? [];
      return dataList
          .map((item) => AttendanceRecord.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    final message = payload['message'] ?? payload['error'] ?? 'Failed to fetch attendance records';
    throw AuthApiException(message.toString());
  }

  Future<AttendanceRecord> getAttendanceRecord(String attendanceId) async {
    final uri = Uri.parse('$_baseApiUrl/attendance/$attendanceId');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    final response = await _httpClient
        .get(
          uri,
          headers: headers,
        )
        .timeout(_defaultTimeout);

    _logResponse('get-attendance-record', uri, response);

    final Map<String, dynamic> payload =
        SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: uri.toString(),
          statusCode: response.statusCode,
        );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = payload['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
      return AttendanceRecord.fromJson(data);
    }

    final message = payload['message'] ?? payload['error'] ?? 'Failed to fetch attendance record';
    throw AuthApiException(message.toString());
  }

  Future<AttendanceRecord> createAttendanceRecord(CreateAttendanceRequest request) async {
    final uri = Uri.parse('$_baseApiUrl/attendance');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    final response = await _httpClient
        .post(
          uri,
          headers: headers,
          body: jsonEncode(request.toJson()),
        )
        .timeout(_defaultTimeout);

    _logResponse('create-attendance-record', uri, response);

    final Map<String, dynamic> payload =
        SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: uri.toString(),
          statusCode: response.statusCode,
        );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = payload['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
      return AttendanceRecord.fromJson(data);
    }

    final message = payload['message'] ?? payload['error'] ?? 'Failed to create attendance record';
    throw AuthApiException(message.toString());
  }

  Future<AttendanceRecord> updateAttendanceRecord(
    String attendanceId,
    UpdateAttendanceRequest request,
  ) async {
    final uri = Uri.parse('$_baseApiUrl/attendance/$attendanceId');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    final response = await _httpClient
        .patch(
          uri,
          headers: headers,
          body: jsonEncode(request.toJson()),
        )
        .timeout(_defaultTimeout);

    _logResponse('update-attendance-record', uri, response);

    final Map<String, dynamic> payload =
        SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: uri.toString(),
          statusCode: response.statusCode,
        );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = payload['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
      return AttendanceRecord.fromJson(data);
    }

    final message = payload['message'] ?? payload['error'] ?? 'Failed to update attendance record';
    throw AuthApiException(message.toString());
  }

  Future<bool> deleteAttendanceRecord(String attendanceId) async {
    final uri = Uri.parse('$_baseApiUrl/attendance/$attendanceId');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    final response = await _httpClient
        .delete(
          uri,
          headers: headers,
        )
        .timeout(_defaultTimeout);

    _logResponse('delete-attendance-record', uri, response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return true;
    }

    final Map<String, dynamic>? payload =
        response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic>? : null;
    final message = payload?['message'] ?? payload?['error'] ?? 'Failed to delete attendance record';
    throw AuthApiException(message.toString());
  }

  Future<List<AttendanceSummary>> getAttendanceSummary({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final uriBuilder = Uri.parse('$_baseApiUrl/attendance/summary').replace(queryParameters: {});
    final queryParams = <String, String>{};
    
    if (userId != null && userId.isNotEmpty) {
      queryParams['userId'] = userId;
    }
    if (startDate != null) {
      queryParams['startDate'] = startDate.toUtc().toIso8601String();
    }
    if (endDate != null) {
      queryParams['endDate'] = endDate.toUtc().toIso8601String();
    }
    
    final uri = queryParams.isEmpty
        ? uriBuilder
        : uriBuilder.replace(queryParameters: queryParams);
    
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    final response = await _httpClient
        .get(
          uri,
          headers: headers,
        )
        .timeout(_defaultTimeout);

    _logResponse('get-attendance-summary', uri, response);

    final Map<String, dynamic> payload =
        SafeJsonDecoder.safeJsonDecode(
          response.body,
          url: uri.toString(),
          statusCode: response.statusCode,
        );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final dataList = payload['data'] as List<dynamic>? ?? [];
      return dataList
          .map((item) => AttendanceSummary.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    final message = payload['message'] ?? payload['error'] ?? 'Failed to fetch attendance summary';
    throw AuthApiException(message.toString());
  }

  Future<List<AttendanceCount>> getAttendanceCounts({
    String? userId,
  }) async {
    final uriBuilder = Uri.parse('$_baseApiUrl/attendance/counts').replace(queryParameters: {});
    final queryParams = <String, String>{};
    
    if (userId != null && userId.isNotEmpty) {
      queryParams['userId'] = userId;
    }
    
    final uri = queryParams.isEmpty
        ? uriBuilder
        : uriBuilder.replace(queryParameters: queryParams);
    
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    try {
      final response = await _httpClient
          .get(
            uri,
            headers: headers,
          )
          .timeout(_defaultTimeout);

      _logResponse('get-attendance-counts', uri, response);

      final Map<String, dynamic> payload =
          SafeJsonDecoder.safeJsonDecode(
            response.body,
            url: uri.toString(),
            statusCode: response.statusCode,
          );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dataList = payload['data'] as List<dynamic>? ?? [];
        return dataList
            .map((item) => AttendanceCount.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      final message = payload['message'] ?? payload['error'] ?? 'Failed to fetch attendance counts';
      throw AuthApiException(message.toString());
    } catch (e) {
      if (e is AuthApiException) {
        rethrow;
      }
      throw AuthApiException('Failed to fetch attendance counts: ${e.toString()}');
    }
  }

  Future<List<ChatMessage>> getChatMessages({String? userId}) async {
    final baseUri = Uri.parse('$_baseApiUrl/chat/messages');
    final queryParams = <String, String>{};
    if (userId != null && userId.isNotEmpty) {
      queryParams['userId'] = userId;
    }
    final uri = queryParams.isEmpty ? baseUri : baseUri.replace(queryParameters: queryParams);

    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    try {
      final response = await _httpClient
          .get(
            uri,
            headers: headers,
          )
          .timeout(_defaultTimeout);

      _logResponse('get-chat-messages', uri, response);

      final Map<String, dynamic> payload = SafeJsonDecoder.safeJsonDecode(
        response.body,
        url: uri.toString(),
        statusCode: response.statusCode,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dataList = payload['data'] as List<dynamic>? ?? [];
        try {
          return dataList
              .map((item) {
                if (item is Map<String, dynamic>) {
                  return ChatMessage.fromJson(item);
                } else {
                  developer.log('Invalid message item format: $item', name: 'AuthApiService');
                  return null;
                }
              })
              .whereType<ChatMessage>()
              .toList();
        } catch (e) {
          developer.log('Error parsing chat messages: $e', name: 'AuthApiService');
          throw AuthApiException('Failed to parse messages: ${e.toString()}');
        }
      }

      final message = payload['message'] ?? payload['error'] ?? 'Failed to fetch messages';
      throw AuthApiException(message.toString());
    } on SocketException {
      throw AuthApiException(
        'Network error: Unable to connect to server. Please check your internet connection.',
      );
    } on HttpException catch (e) {
      throw AuthApiException('HTTP error: ${e.message}');
    } on FormatException catch (e) {
      developer.log('FormatException in getChatMessages: $e', name: 'AuthApiService');
      throw AuthApiException('Invalid server response format. Please try again.');
    } catch (e) {
      if (e is AuthApiException) rethrow;
      developer.log('Unexpected error in getChatMessages: $e', name: 'AuthApiService');
      throw AuthApiException('Failed to fetch messages: ${e.toString()}');
    }
  }

  Future<ChatMessage> sendChatMessage({
    required String recipientId,
    required String content,
  }) async {
    final uri = Uri.parse('$_baseApiUrl/chat/messages');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    final token = _authToken ?? _attendanceCookie;
    if (token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$token';
    } else if (_attendanceCookie.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = 'attendance_token=$_attendanceCookie';
    }

    final body = <String, dynamic>{
      'recipientId': recipientId,
      'content': content,
    };

    try {
      final response = await _httpClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(_defaultTimeout);

      _logResponse('send-chat-message', uri, response);

      final Map<String, dynamic> payload = SafeJsonDecoder.safeJsonDecode(
        response.body,
        url: uri.toString(),
        statusCode: response.statusCode,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = payload['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
        return ChatMessage.fromJson(data);
      }

      final message = payload['message'] ?? payload['error'] ?? 'Failed to send message';
      throw AuthApiException(message.toString());
    } on SocketException {
      throw AuthApiException(
        'Network error: Unable to connect to server. Please check your internet connection.',
      );
    } on HttpException catch (e) {
      throw AuthApiException('HTTP error: ${e.message}');
    } on FormatException {
      throw AuthApiException('Invalid server response format');
    } catch (e) {
      if (e is AuthApiException) rethrow;
      throw AuthApiException('Failed to send message: ${e.toString()}');
    }
  }

  void dispose() {
    _httpClient.close();
  }

  void _logResponse(String action, Uri uri, http.Response response) {
    final message =
        '[$action] ${response.statusCode} ${response.reasonPhrase} for ${uri.toString()} -> ${response.body}';

    developer.log(
      message,
      name: 'AuthApiService',
    );

    debugPrint('[AuthApiService] $message');
    // Ensure logs appear even in release/desktop shells.
    // ignore: avoid_print
    print('[AuthApiService] $message');
  }

  /// Upload profile picture/avatar
  /// Returns the profile picture URL
  Future<String> uploadAvatar(File imageFile) async {
    final uri = Uri.parse('$_baseApiUrl/users/me/avatar');

    final token = _authToken ?? _attendanceCookie;
    if (token.isEmpty) {
      throw AuthApiException('Not authenticated. Please login first.');
    }

    try {
      // Create multipart request
      final request = MultipartRequest('POST', uri);

      // Add headers
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Cookie'] = 'attendance_token=$token';

      // Add file with proper MIME type
      final fileStream = imageFile.openRead();
      final fileLength = await imageFile.length();
      final fileName = imageFile.path.split('/').last;
      final fileExtension = fileName.toLowerCase().split('.').last;
      
      // Determine MIME type based on file extension
      String? contentType;
      switch (fileExtension) {
        case 'jpg':
        case 'jpeg':
          contentType = 'image/jpeg';
          break;
        case 'png':
          contentType = 'image/png';
          break;
        case 'webp':
          contentType = 'image/webp';
          break;
        case 'gif':
          contentType = 'image/gif';
          break;
        case 'bmp':
          contentType = 'image/bmp';
          break;
        case 'heic':
        case 'heif':
          contentType = 'image/heic';
          break;
        default:
          contentType = 'image/jpeg'; // Default fallback
      }
      
      final multipartFile = MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: fileName,
        contentType: MediaType.parse(contentType),
      );
      request.files.add(multipartFile);

      developer.log(
        '[upload-avatar] POST ${uri.toString()}',
        name: 'AuthApiService',
      );

      // Send request
      final streamedResponse = await request.send().timeout(_defaultTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      _logResponse('upload-avatar', uri, response);

      final Map<String, dynamic> payload = SafeJsonDecoder.safeJsonDecode(
        response.body,
        url: uri.toString(),
        statusCode: response.statusCode,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = payload['data'] as Map<String, dynamic>? ?? {};
        final profilePicture = data['profilePicture']?.toString() ?? '';
        
        // Update current user's profile picture if available
        if (_currentUser != null && profilePicture.isNotEmpty) {
          // Note: You may need to add profilePicture field to RegisteredUser model
          // For now, we'll just return the URL
        }
        
        return profilePicture;
      }

      final message = payload['message'] ?? payload['error'] ?? 'Failed to upload avatar';
      throw AuthApiException(message.toString());
    } on SocketException {
      throw AuthApiException(
        'Network error: Unable to connect to server. Please check your internet connection.',
      );
    } on HttpException catch (e) {
      throw AuthApiException('HTTP error: ${e.message}');
    } on FormatException catch (e) {
      developer.log('FormatException in uploadAvatar: $e', name: 'AuthApiService');
      throw AuthApiException('Invalid server response format. Please try again.');
    } catch (e) {
      if (e is AuthApiException) rethrow;
      developer.log('Unexpected error in uploadAvatar: $e', name: 'AuthApiService');
      throw AuthApiException('Failed to upload avatar: ${e.toString()}');
    }
  }
}

