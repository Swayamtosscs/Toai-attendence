import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_api_service.dart';

class StorageService {
  static const String _keyAuthToken = 'auth_token';
  static const String _keyUserData = 'user_data';
  static const String _keyIsLoggedIn = 'is_logged_in';

  // Save login state
  static Future<void> saveLoginState({
    required String token,
    required RegisteredUser user,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAuthToken, token);
    await prefs.setString(_keyUserData, jsonEncode({
      'id': user.id,
      'name': user.name,
      'email': user.email,
      'role': user.role,
      'department': user.department,
      'designation': user.designation,
    }));
    await prefs.setBool(_keyIsLoggedIn, true);
  }

  // Save user data (alias for saveLoginState without token)
  static Future<void> saveUserData(RegisteredUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserData, jsonEncode({
      'id': user.id,
      'name': user.name,
      'email': user.email,
      'role': user.role,
      'department': user.department,
      'designation': user.designation,
    }));
  }

  // Get auth token
  static Future<String?> getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAuthToken);
  }

  // Get user data
  static Future<RegisteredUser?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString(_keyUserData);
    if (userDataString == null) return null;
    
    try {
      final userData = jsonDecode(userDataString) as Map<String, dynamic>;
      return RegisteredUser.fromJson(userData);
    } catch (e) {
      return null;
    }
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  // Clear login state (logout)
  static Future<void> clearLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAuthToken);
    await prefs.remove(_keyUserData);
    await prefs.setBool(_keyIsLoggedIn, false);
  }

  // Clear user (alias for clearLoginState)
  static Future<void> clearUser() async {
    await clearLoginState();
  }
}


