import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';

/// Handles device power management for reliable background execution
/// Requests battery optimization exemption and manages foreground service
class DevicePowerManager {
  static const MethodChannel _channel = MethodChannel('com.example.demoapp/power');

  /// Request to ignore battery optimizations
  /// This is critical for background location checks on real devices
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (kIsWeb || !Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return result ?? false;
    } catch (e) {
      debugPrint('[DevicePowerManager] Battery optimization request failed: $e');
      return false;
    }
  }

  /// Check if battery optimizations are ignored
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb || !Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Start foreground service for reliable location tracking
  static Future<bool> startForegroundService() async {
    if (kIsWeb || !Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('startForegroundService');
      return result ?? false;
    } catch (e) {
      debugPrint('[DevicePowerManager] Failed to start foreground service: $e');
      return false;
    }
  }

  /// Stop foreground service
  static Future<bool> stopForegroundService() async {
    if (kIsWeb || !Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('stopForegroundService');
      return result ?? false;
    } catch (e) {
      debugPrint('[DevicePowerManager] Failed to stop foreground service: $e');
      return false;
    }
  }
}

