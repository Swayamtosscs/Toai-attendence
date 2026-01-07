import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Safe JSON decoder that handles HTML responses and other non-JSON content
/// Prevents FormatException crashes when backend returns HTML error pages
class SafeJsonDecoder {
  /// Safely decode JSON from response body
  /// Returns decoded JSON or throws a descriptive error
  static Map<String, dynamic> safeJsonDecode(
    String responseBody, {
    String? url,
    int? statusCode,
  }) {
    // Check if response is empty
    if (responseBody.trim().isEmpty) {
      throw FormatException(
        'Empty response body',
        url ?? 'unknown',
      );
    }

    // Check if response starts with HTML (common error page indicator)
    final trimmedBody = responseBody.trim();
    if (trimmedBody.startsWith('<!DOCTYPE') ||
        trimmedBody.startsWith('<!doctype') ||
        trimmedBody.startsWith('<html') ||
        trimmedBody.startsWith('<HTML')) {
      final preview = trimmedBody.length > 200
          ? '${trimmedBody.substring(0, 200)}...'
          : trimmedBody;
      
      debugPrint('[SafeJsonDecoder] ⚠️ HTML response detected (not JSON)');
      debugPrint('[SafeJsonDecoder] URL: $url');
      debugPrint('[SafeJsonDecoder] Status: $statusCode');
      debugPrint('[SafeJsonDecoder] Response preview: $preview');
      
      throw FormatException(
        'Server returned HTML instead of JSON. Status: $statusCode. '
        'This usually indicates an error page or server misconfiguration.',
        url ?? 'unknown',
      );
    }

    // Check if response starts with JSON-like content
    if (!trimmedBody.startsWith('{') && !trimmedBody.startsWith('[')) {
      final preview = trimmedBody.length > 200
          ? '${trimmedBody.substring(0, 200)}...'
          : trimmedBody;
      
      debugPrint('[SafeJsonDecoder] ⚠️ Non-JSON response detected');
      debugPrint('[SafeJsonDecoder] URL: $url');
      debugPrint('[SafeJsonDecoder] Status: $statusCode');
      debugPrint('[SafeJsonDecoder] Response preview: $preview');
      
      throw FormatException(
        'Response is not valid JSON. Status: $statusCode. '
        'Expected JSON object or array, got: ${preview.substring(0, 50)}...',
        url ?? 'unknown',
      );
    }

    try {
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } on FormatException catch (e) {
      final preview = responseBody.length > 200
          ? '${responseBody.substring(0, 200)}...'
          : responseBody;
      
      debugPrint('[SafeJsonDecoder] ❌ JSON decode failed');
      debugPrint('[SafeJsonDecoder] URL: $url');
      debugPrint('[SafeJsonDecoder] Status: $statusCode');
      debugPrint('[SafeJsonDecoder] Error: ${e.message}');
      debugPrint('[SafeJsonDecoder] Response preview: $preview');
      
      rethrow;
    } catch (e) {
      final preview = responseBody.length > 200
          ? '${responseBody.substring(0, 200)}...'
          : responseBody;
      
      debugPrint('[SafeJsonDecoder] ❌ Unexpected decode error');
      debugPrint('[SafeJsonDecoder] URL: $url');
      debugPrint('[SafeJsonDecoder] Status: $statusCode');
      debugPrint('[SafeJsonDecoder] Error: $e');
      debugPrint('[SafeJsonDecoder] Response preview: $preview');
      
      throw FormatException(
        'Failed to decode JSON: ${e.toString()}',
        url ?? 'unknown',
      );
    }
  }

  /// Safely decode JSON array from response body
  static List<dynamic> safeJsonDecodeList(
    String responseBody, {
    String? url,
    int? statusCode,
  }) {
    // Check if response is empty
    if (responseBody.trim().isEmpty) {
      throw FormatException('Empty response body', url ?? 'unknown');
    }

    // Check if response starts with HTML
    final trimmedBody = responseBody.trim();
    if (trimmedBody.startsWith('<!DOCTYPE') ||
        trimmedBody.startsWith('<!doctype') ||
        trimmedBody.startsWith('<html') ||
        trimmedBody.startsWith('<HTML')) {
      final preview = trimmedBody.length > 200
          ? '${trimmedBody.substring(0, 200)}...'
          : trimmedBody;
      
      debugPrint('[SafeJsonDecoder] ⚠️ HTML response detected (not JSON array)');
      debugPrint('[SafeJsonDecoder] URL: $url');
      debugPrint('[SafeJsonDecoder] Status: $statusCode');
      debugPrint('[SafeJsonDecoder] Response preview: $preview');
      
      throw FormatException(
        'Server returned HTML instead of JSON array. Status: $statusCode.',
        url ?? 'unknown',
      );
    }

    try {
      return jsonDecode(responseBody) as List<dynamic>;
    } on FormatException catch (e) {
      final preview = responseBody.length > 200
          ? '${responseBody.substring(0, 200)}...'
          : responseBody;
      
      debugPrint('[SafeJsonDecoder] ❌ JSON array decode failed');
      debugPrint('[SafeJsonDecoder] URL: $url');
      debugPrint('[SafeJsonDecoder] Status: $statusCode');
      debugPrint('[SafeJsonDecoder] Error: ${e.message}');
      debugPrint('[SafeJsonDecoder] Response preview: $preview');
      
      rethrow;
    } catch (e) {
      final preview = responseBody.length > 200
          ? '${responseBody.substring(0, 200)}...'
          : responseBody;
      
      debugPrint('[SafeJsonDecoder] ❌ Unexpected array decode error');
      debugPrint('[SafeJsonDecoder] URL: $url');
      debugPrint('[SafeJsonDecoder] Status: $statusCode');
      debugPrint('[SafeJsonDecoder] Error: $e');
      debugPrint('[SafeJsonDecoder] Response preview: $preview');
      
      throw FormatException(
        'Failed to decode JSON array: ${e.toString()}',
        url ?? 'unknown',
      );
    }
  }
}

