import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'reports_screen.dart';
import 'services/attendance_service_factory.dart';
import 'services/foreground_attendance_service.dart';

// Main Screen with Bottom Navigation
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    ReportsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    // Rely on the dedicated foreground service + engine to manage
    // background execution. The UI should NOT start/stop services.
    final service = await AttendanceServiceFactory.getInstance();
    final currentState = service.getCurrentState();

    // Only react if auto attendance is enabled
    if (!currentState.isEnabled) return;

    if (state == AppLifecycleState.resumed) {
      // When app returns to foreground, just validate location and state.
      // ForegroundAttendanceService continues running independently.
      service.validateCurrentLocation();
    }
    // For paused/inactive/detached, do nothing here:
    // - ForegroundAttendanceService is START_STICKY and restarted by BootReceiver
    // - Native LocationService keeps location stream alive
    // This avoids UI-driven stopping/starting that can differ between
    // debug and release or between emulator and real devices.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey[700],
          backgroundColor: Colors.white,
          elevation: 0,
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.analytics_outlined),
              activeIcon: Icon(Icons.analytics),
              label: 'Reports',
            ),
          ],
        ),
      ),
    );
  }
}