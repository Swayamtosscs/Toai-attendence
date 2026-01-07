import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show PlatformDispatcher;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_screens.dart';
import 'app_routes.dart';
import 'main_navigation.dart';
import 'services/background_location_worker.dart';

void main() async {
  // Add comprehensive error handling to prevent crashes
  FlutterError.onError = (FlutterErrorDetails details) {
    // Log error but don't crash
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exception}');
    debugPrint('Stack: ${details.stack}');
  };
  
  // Handle platform errors (async errors)
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Platform Error: $error');
    debugPrint('Stack: $stack');
    return true; // Prevent crash - return true means error is handled
  };
  
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Initialize background worker only on mobile platforms (Android/iOS)
    // workmanager doesn't support Windows/Web
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await BackgroundLocationWorker.initialize();
      } catch (e) {
        // Silent fail if workmanager not available
        debugPrint('Background worker initialization skipped: $e');
      }
    }
    
    // Store API base URL for background worker
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_base_url', 'http://103.14.120.163:8092/api');
    } catch (e) {
      debugPrint('Failed to store API URL: $e');
      // Continue anyway
    }
    
    runApp(const AttendanceApp());
  } catch (e, stackTrace) {
    debugPrint('Fatal error in main: $e');
    debugPrint('Stack trace: $stackTrace');
    // Still run app even if initialization fails
    runApp(const AttendanceApp());
  }
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ToAI Attendance',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: Colors.white, // Pure white background
        visualDensity: VisualDensity.adaptivePlatformDensity,
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF2563EB), // Professional blue
          secondary: const Color(0xFF6366F1), // Soft purple-blue accent
          surface: Colors.white, // Pure white
          background: Colors.white, // Pure white background
          error: const Color(0xFFEF4444), // Red for errors
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: const Color(0xFF111827), // Near-black for primary text
          onBackground: const Color(0xFF111827), // Near-black for text on background
          onError: Colors.white,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shadowColor: Colors.black.withOpacity(0.05), // Subtle shadow
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white, // Pure white
          elevation: 0,
          iconTheme: const IconThemeData(color: Color(0xFF111827)), // Near-black icons
          titleTextStyle: const TextStyle(
            color: Color(0xFF111827), // Near-black text
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF111827)), // Near-black
          bodyMedium: TextStyle(color: Color(0xFF374151)), // Dark gray
          bodySmall: TextStyle(color: Color(0xFF6B7280)), // Medium gray
          titleLarge: TextStyle(color: Color(0xFF111827)), // Near-black
          titleMedium: TextStyle(color: Color(0xFF111827)), // Near-black
          titleSmall: TextStyle(color: Color(0xFF374151)), // Dark gray
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF9FAFB), // Very light gray for inputs
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)), // Light gray border
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
          ),
        ),
      ),
      initialRoute: AppRoutes.splash,
      routes: {
        AppRoutes.splash: (context) => const SplashScreen(),
        AppRoutes.login: (context) => const LoginScreen(),
        AppRoutes.main: (context) => MainScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}