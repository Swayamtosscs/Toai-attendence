import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'profile_screen.dart';
import 'app_routes.dart';
import 'services/auth_api_service.dart';
import 'services/attendance_service.dart' show AttendanceService, ServiceAttendanceState;
import 'services/attendance_service_factory.dart';
import 'services/intelligent_attendance/attendance_controller.dart';
import 'services/foreground_attendance_service.dart';
import 'services/safe_startup_manager.dart';
import 'leave_request_screen.dart';
import 'admin_attendance_screen.dart';
import 'location_management_screen.dart';
import 'widgets/auto_attendance_toggle.dart';
import 'dart:io' show Platform;

// Home Screen
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthApiService _authApiService = AuthApiService();
  AttendanceService? _attendanceService;
  AttendanceController? _attendanceController;
  StreamSubscription<ServiceAttendanceState>? _attendanceSubscription;
  StreamSubscription<IntelligentAttendanceState>? _controllerStateSubscription;
  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<int>? _countdownSubscription;
  bool _controllerInitialized = false;
  bool _isCheckingIn = false;
  bool _isCheckingOut = false;
  DateTime? _lastCheckInAt;
  DateTime? _lastCheckOutAt;
  int? _workDurationMinutes;
  String? _attendanceStatus;
  bool _hasCheckedInToday = false;
  bool _hasCheckedOutToday = false;
  bool _checkInInProgress = false; // Synchronous guard to prevent duplicate calls
  bool _checkOutInProgress = false; // Synchronous guard to prevent duplicate calls
  
  // UI message state
  String? _currentMessage;
  int? _countdownSeconds;

  @override
  void initState() {
    super.initState();
    // Load today's attendance status when screen initializes
    // This ensures check-in status persists even after app restart
    _loadTodayAttendance();
    _initializeAutoAttendance();
  }

  Future<void> _initializeAutoAttendance() async {
    if (_controllerInitialized) return;
    try {
      final startupResult = await SafeStartupManager.executeStartupPipeline();
      if (!startupResult.success || !startupResult.permissionsGranted) {
        if (mounted) {
          setState(() {
            _currentMessage = '⚠️ Some features may be limited. Please grant location permissions.';
          });
        }
        return;
      }
      final controller = await AttendanceServiceFactory.initializeController();
      if (mounted && !_controllerInitialized) {
        setState(() {
          _attendanceController = controller;
          _controllerInitialized = true;
        });
        _setupControllerListeners(controller);
        final currentState = controller.getCurrentState();
        setState(() {
          _hasCheckedInToday = currentState.isCheckedIn;
          _hasCheckedOutToday = !currentState.isCheckedIn;
          _attendanceStatus = currentState.status;
          if (currentState.checkInTime != null) {
            _lastCheckInAt = currentState.checkInTime;
          }
        });
      }
    } catch (e) {
      debugPrint('[HomeScreen] Auto attendance initialization failed: $e');
    }
  }

  void _setupControllerListeners(AttendanceController controller) {
    _controllerStateSubscription?.cancel();
    _messageSubscription?.cancel();
    _countdownSubscription?.cancel();

    _controllerStateSubscription = controller.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _hasCheckedInToday = state.isCheckedIn;
          _hasCheckedOutToday = !state.isCheckedIn;
          _attendanceStatus = state.status;
          if (state.checkInTime != null) {
            _lastCheckInAt = state.checkInTime;
          }
          if (state.checkOutTime != null) {
            _lastCheckOutAt = state.checkOutTime;
          }
          
          // UI Priority Rules
          if (state.entryTimerRunning) {
            _currentMessage = 'Stay inside for 1 minute — auto check-in in progress';
            _countdownSeconds = state.entrySecondsLeft;
          } else if (state.exitTimerRunning) {
            _currentMessage = 'Outside location — returning within 1 minute will cancel checkout';
            _countdownSeconds = state.exitSecondsLeft;
          } else if (state.isCheckedIn && state.checkInTime != null) {
            final localTime = state.checkInTime!.toLocal();
            final hour = localTime.hour % 12 == 0 ? 12 : localTime.hour % 12;
            final minutes = localTime.minute.toString().padLeft(2, '0');
            final period = localTime.hour >= 12 ? 'PM' : 'AM';
            _currentMessage = '✅ Checked in at $hour:$minutes $period';
            _countdownSeconds = null;
          } else {
            _currentMessage = 'Waiting for check-in';
            _countdownSeconds = null;
          }
        });
      }
    });

    _messageSubscription = controller.messageStream.listen((message) {
      if (mounted) {
        setState(() {
          _currentMessage = message;
        });
        try {
          if (mounted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                duration: const Duration(seconds: 4),
                backgroundColor: message.contains('✅') 
                    ? Colors.green 
                    : message.contains('❌') 
                        ? Colors.red 
                        : Colors.blue,
              ),
            );
          }
        } catch (e) {
          debugPrint('[HomeScreen] Error showing SnackBar: $e');
        }
      }
    });

    _countdownSubscription = controller.countdownStream.listen((seconds) {
      if (mounted) {
        setState(() {
          _countdownSeconds = seconds;
        });
      }
    });
  }

  /// Load checkout time from SharedPreferences (real-time when toggle is turned OFF)
  Future<void> _loadCheckoutTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final checkoutTimestamp = prefs.getString('check_out_timestamp');
      if (checkoutTimestamp != null && mounted) {
        final checkoutTime = DateTime.parse(checkoutTimestamp);
        setState(() {
          _lastCheckOutAt = checkoutTime;
          print('[HomeScreen] ✅ Real checkout time loaded: ${_formatCheckInTime(checkoutTime)}');
        });
      } else if (mounted) {
        // If no stored time, use current time (for immediate display)
        setState(() {
          _lastCheckOutAt = DateTime.now();
          print('[HomeScreen] ✅ Using current time as checkout time: ${_formatCheckInTime(_lastCheckOutAt!)}');
        });
      }
    } catch (e) {
      print('[HomeScreen] Error loading checkout time: $e');
      // On error, still set current time for immediate display
      if (mounted) {
        setState(() {
          _lastCheckOutAt = DateTime.now();
        });
      }
    }
  }

  @override
  void dispose() {
    _attendanceSubscription?.cancel();
    _controllerStateSubscription?.cancel();
    _messageSubscription?.cancel();
    _countdownSubscription?.cancel();
    _authApiService.dispose();
    // DO NOT shutdown controller here - it's managed by factory
    // UI rebuilds/disposes should not affect engine lifecycle
    super.dispose();
  }

  Future<void> _loadTodayAttendance() async {
    try {
      final user = AuthApiService.currentUser;
      if (user == null) return;

      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(Duration(days: 1));

      // Fetch today's attendance records
      final attendanceRecords = await _authApiService.getAttendanceRecords(
        userId: user.id,
        startDate: startOfDay,
        endDate: endOfDay,
      );

      if (!mounted) return;

      // Find today's record - check if checkInAt is today
      AttendanceRecord? todayRecord;
      
      // First, try to find record where checkInAt is today
      for (var record in attendanceRecords) {
        if (record.checkInAt != null) {
          final checkInDate = record.checkInAt!.toLocal();
          final checkInStartOfDay = DateTime(
            checkInDate.year,
            checkInDate.month,
            checkInDate.day,
          );
          
          // Compare with today's date
          final todayStartOfDay = DateTime(
            today.year,
            today.month,
            today.day,
          );
          
          // Check if checkInAt is today
          if (checkInStartOfDay == todayStartOfDay) {
            todayRecord = record;
            break;
          }
        }
      }
      
      // If no record found with checkInAt today, check the date field
      if (todayRecord == null && attendanceRecords.isNotEmpty) {
        try {
          todayRecord = attendanceRecords.firstWhere(
            (record) {
              // Check date field in local timezone
              final recordDate = record.date.toLocal();
              final recordStartOfDay = DateTime(
                recordDate.year,
                recordDate.month,
                recordDate.day,
              );
              final todayStartOfDay = DateTime(
                today.year,
                today.month,
                today.day,
              );
              return recordStartOfDay == todayStartOfDay;
            },
          );
        } catch (e) {
          // If still not found, try to use first record if it has checkInAt
          if (attendanceRecords.isNotEmpty && attendanceRecords.first.checkInAt != null) {
            // Use the first record if it has checkInAt (might be yesterday's check-in that's still active)
            todayRecord = attendanceRecords.first;
          }
        }
      }

      // If we found a record with checkInAt, use it (even if date doesn't match exactly)
      // This handles cases where check-in was done but date field is different due to timezone
      if (todayRecord == null && attendanceRecords.isNotEmpty) {
        // Get the most recent record with checkInAt
        final recordsWithCheckIn = attendanceRecords.where((r) => r.checkInAt != null).toList();
        if (recordsWithCheckIn.isNotEmpty) {
          // Sort by checkInAt descending and take the first one
          recordsWithCheckIn.sort((a, b) => b.checkInAt!.compareTo(a.checkInAt!));
          final mostRecent = recordsWithCheckIn.first;
          
          // Check if check-in was today (within last 24 hours or same day)
          final checkInDate = mostRecent.checkInAt!.toLocal();
          final checkInStartOfDay = DateTime(checkInDate.year, checkInDate.month, checkInDate.day);
          final todayStartOfDay = DateTime(today.year, today.month, today.day);
          
          // If check-in was today and check-out is null, use this record
          if (checkInStartOfDay == todayStartOfDay && mostRecent.checkOutAt == null) {
            todayRecord = mostRecent;
          }
        }
      }

      if (todayRecord != null && todayRecord.checkInAt != null) {
        // User has checked in today - restore the status
        setState(() {
          _lastCheckInAt = todayRecord!.checkInAt;
          _attendanceStatus = todayRecord!.status;
          _hasCheckedInToday = true;

          // COMPLETELY REMOVED: Check-out info display
          // Always clear check-out data when there's an active check-in
          // The check-out line has been completely removed from UI
          _hasCheckedOutToday = false;
          _lastCheckOutAt = null;
          _workDurationMinutes = null;
        });

        print('[HomeScreen] Loaded today attendance: Check-in at ${todayRecord.checkInAt}, Check-out: ${todayRecord.checkOutAt != null ? todayRecord.checkOutAt : "Not checked out"}');
      } else {
        // Check if there's any record with checkInAt but no checkOutAt (active check-in)
        if (attendanceRecords.isNotEmpty) {
          final activeCheckIn = attendanceRecords.firstWhere(
            (record) => record.checkInAt != null && record.checkOutAt == null,
            orElse: () => attendanceRecords.first,
          );
          
          if (activeCheckIn.checkInAt != null && activeCheckIn.checkOutAt == null) {
            // Found active check-in - restore it
            setState(() {
              _lastCheckInAt = activeCheckIn.checkInAt;
              _attendanceStatus = activeCheckIn.status;
              _hasCheckedInToday = true;
              _hasCheckedOutToday = false;
              _lastCheckOutAt = null;
              _workDurationMinutes = null;
            });
            print('[HomeScreen] Found active check-in: Check-in at ${activeCheckIn.checkInAt}, Date: ${activeCheckIn.date}');
            return;
          }
        }
        
        // No check-in for today
        // If auto attendance is active, clear any old check-out data
        final autoAttendanceActive = _attendanceService != null && _attendanceService!.getCurrentState().isEnabled;
        setState(() {
          _hasCheckedInToday = false;
          // If auto attendance is active, don't show old check-out data
          if (autoAttendanceActive) {
            _hasCheckedOutToday = false;
            _lastCheckOutAt = null;
            _workDurationMinutes = null;
          }
          _lastCheckInAt = null;
          _attendanceStatus = null;
        });
        print('[HomeScreen] No attendance found for today. Records received: ${attendanceRecords.length}');
        if (attendanceRecords.isNotEmpty) {
          print('[HomeScreen] First record: date=${attendanceRecords.first.date}, checkInAt=${attendanceRecords.first.checkInAt}, checkOutAt=${attendanceRecords.first.checkOutAt}');
        }
      }
    } catch (e) {
      // Error loading attendance - silently fail and let user check in fresh
      print('[HomeScreen] Error loading today attendance: $e');
      if (mounted) {
        setState(() {
          _hasCheckedInToday = false;
          _hasCheckedOutToday = false;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    try {
      await _authApiService.logout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logged out successfully')),
      );
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    } on AuthApiException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $error')),
      );
    }
  }

  Future<void> _handleCheckIn() async {
    // Allow multiple clicks - remove the guard that prevents clicking
    if (_isCheckingIn || _checkInInProgress) {
      // Already processing, ignore this click
      print('[HomeScreen] Check-in already in progress, ignoring duplicate click');
      return;
    }
    
    // Set synchronous guard IMMEDIATELY - before any async operations
    _checkInInProgress = true;
    _isCheckingIn = true;
    print('[HomeScreen] Starting check-in request...');
    
    // Schedule state update (but guard is already set synchronously)
    if (mounted) {
      setState(() {
        // State already updated above, just trigger rebuild
      });
    }
    
    try {
      // Get current location for intelligent engine
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (e) {
        print('[HomeScreen] Failed to get location: $e');
      }
      
      // Try auto attendance service first, fallback to manual API
      if (_attendanceService != null) {
        try {
          await _attendanceService!.manualCheckIn();
          if (!mounted) return;
          
          final state = _attendanceService!.getCurrentState();
          final checkInTime = state.checkInTimestamp ?? DateTime.now();
          setState(() {
            _lastCheckInAt = checkInTime;
            _attendanceStatus = 'PRESENT';
            _hasCheckedInToday = true;
            _hasCheckedOutToday = false;
            _checkInInProgress = false;
            _isCheckingIn = false;
          });
          
          
          // Reload attendance to get real-time data
          await _loadTodayAttendance();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Checked in at ${_formatCheckInTime(checkInTime)}'),
              backgroundColor: Colors.green,
            ),
          );
          return;
        } catch (e) {
          print('Auto attendance check-in failed, trying manual: $e');
        }
      }
      
      // Fallback to manual check-in
      // Multiple check-ins are now allowed, so no need to check for existing check-in
      final response = await _authApiService.checkIn(notes: 'Manual check-in');
      if (!mounted) return;
      
      
      // Always use real check-in data from server with real-time timestamp
      setState(() {
        _lastCheckInAt = response.checkInAt;
        _attendanceStatus = response.status;
        _hasCheckedInToday = true;  // Explicitly set to true
        _hasCheckedOutToday = false; // Explicitly set to false
        _checkInInProgress = false;
        _isCheckingIn = false;
      });
      
      print('[HomeScreen] Manual check-in completed: _hasCheckedInToday=$_hasCheckedInToday, _hasCheckedOutToday=$_hasCheckedOutToday');
      
      // Reload attendance to get real-time data
      await _loadTodayAttendance();
      
      print('[HomeScreen] Check-in: Success at ${response.checkInAt}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Checked in at ${_formatCheckInTime(response.checkInAt)}'),
          backgroundColor: Colors.green,
        ),
      );
    } on AuthApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _checkInInProgress = false;
        _isCheckingIn = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkInInProgress = false;
        _isCheckingIn = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Check-in failed: $error')),
      );
    }
  }

  Future<void> _handleCheckOut() async {
    // Allow multiple clicks - remove the guard that prevents clicking
    if (_isCheckingOut || _checkOutInProgress) {
      // Already processing, ignore this click
      print('[HomeScreen] Check-out already in progress, ignoring duplicate click');
      return;
    }
    
    // Set synchronous guard IMMEDIATELY - before any async operations
    _checkOutInProgress = true;
    _isCheckingOut = true;
    print('[HomeScreen] Starting check-out request...');
    
    // Schedule state update (but guard is already set synchronously)
    if (mounted) {
      setState(() {
        // State already updated above, just trigger rebuild
      });
    }
    
    // Always use manual API directly for check-out
    // Multiple check-outs are now allowed, so no need to check for existing check-out
    // Don't rely on auto attendance service for manual check-out
    
    // Get current location for intelligent engine
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      print('[HomeScreen] Failed to get location: $e');
    }
    
    try {
      final response = await _authApiService.checkOut(notes: 'Manual check-out');
      if (!mounted) return;
      
      
      // Always use real check-out data from server with real-time timestamp
      setState(() {
        _lastCheckOutAt = response.checkOutAt;
        _lastCheckInAt = response.checkInAt;
        _workDurationMinutes = response.workDurationMinutes;
        _hasCheckedOutToday = true;
        _hasCheckedInToday = false;
        _checkOutInProgress = false;
        _isCheckingOut = false;
      });
      
      // Reload attendance to get real-time data
      await _loadTodayAttendance();
      
      print('[HomeScreen] Check-out: Success at ${response.checkOutAt}');
      final checkoutMessage = response.totalCheckOutsToday != null
          ? 'Checked out at ${_formatTime(response.checkOutAt)} '
            '(${response.workDurationMinutes} mins worked, ${response.totalCheckOutsToday} check-outs today)'
          : 'Checked out at ${_formatTime(response.checkOutAt)} '
            '(${response.workDurationMinutes} mins worked)';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(checkoutMessage),
          backgroundColor: Colors.green,
        ),
      );
    } on AuthApiException catch (error) {
      // Handle specific error messages
      final errorMsg = error.message.toLowerCase();
      if (errorMsg.contains('no check-in found') || errorMsg.contains('check-in')) {
        // With multiple check-ins/check-outs, this error shouldn't block check-out
        // But if backend requires it, show a helpful message
        if (!mounted) return;
        setState(() {
          _checkOutInProgress = false;
          _isCheckingOut = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please check in first before checking out'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        if (!mounted) return;
        setState(() {
          _checkOutInProgress = false;
          _isCheckingOut = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkOutInProgress = false;
        _isCheckingOut = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Check-out failed: $error')),
      );
    }
  }

  String _formatCheckInTime([DateTime? time]) {
    final timestamp = (time ?? _lastCheckInAt);
    if (timestamp == null) {
      return 'Not checked in yet';
    }
    final local = timestamp.isUtc ? timestamp.toLocal() : timestamp;
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minutes = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minutes $period';
  }

  String _formatTime(DateTime time) {
    final local = time.isUtc ? time.toLocal() : time;
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minutes = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minutes $period';
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthApiService.currentUser;
    final userName = user?.name ?? 'User';
    final userEmail = user?.email ?? '';
    final userDepartment = user?.department ?? 'Not specified';
    final userDesignation = user?.designation ?? 'Not specified';
    final userId = user?.id ?? '';
    
    return Scaffold(
      backgroundColor: Colors.white, // Pure white background
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Colors.grey[50]!,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ToAI Attendance',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1F2937),
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Welcome Back',
                          style: TextStyle(
                            fontSize: 16,
                            color: const Color(0xFF6B7280),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.logout, color: Colors.black87),
                          tooltip: 'Logout',
                          onPressed: _handleLogout,
                        ),
                        Container(
                          width: 45,
                          height: 45,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withOpacity(0.1),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: () {
                              // Notification functionality
                              _showNotificationDialog(context);
                            },
                            icon: Icon(
                              Icons.notifications_outlined,
                              color: const Color(0xFF2563EB),
                              size: 22,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ProfileScreen()),
                            );
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2563EB).withOpacity(0.3),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Main Content
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(top: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // User Info Card
                        Container(
                          padding: EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white,
                                const Color(0xFFF8F9FA),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFE5E7EB),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 20,
                                spreadRadius: 0,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF2563EB).withOpacity(0.3),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                  SizedBox(width: 15),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          userName,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1F2937),
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        Text(
                                          'ID: ${userId.isNotEmpty ? userId.substring(0, userId.length > 12 ? 12 : userId.length) : 'N/A'}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF6B7280),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        SizedBox(height: 5),
                                        Text(
                                          userDesignation,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF9CA3AF),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD1FAE5),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(0xFF10B981),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: const Text(
                                      'Active',
                                      style: TextStyle(
                                        color: Color(0xFF059669),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 25),

                        // UI Message Display (from intelligent controller)
                        if (_currentMessage != null) ...[
                          Container(
                            padding: EdgeInsets.all(16),
                            margin: EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: _currentMessage!.contains('✅')
                                  ? Colors.green[50]
                                  : _currentMessage!.contains('❌')
                                      ? Colors.red[50]
                                      : Colors.blue[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _currentMessage!.contains('✅')
                                    ? Colors.green[200]!
                                    : _currentMessage!.contains('❌')
                                        ? Colors.red[200]!
                                        : Colors.blue[200]!,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _currentMessage!.contains('✅')
                                      ? Icons.check_circle
                                      : _currentMessage!.contains('❌')
                                          ? Icons.error
                                          : Icons.info,
                                  color: _currentMessage!.contains('✅')
                                      ? Colors.green[700]
                                      : _currentMessage!.contains('❌')
                                          ? Colors.red[700]
                                          : Colors.blue[700],
                                  size: 24,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _currentMessage!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: _currentMessage!.contains('✅')
                                              ? Colors.green[900]
                                              : _currentMessage!.contains('❌')
                                                  ? Colors.red[900]
                                                  : Colors.blue[900],
                                        ),
                                      ),
                                      if (_countdownSeconds != null && _countdownSeconds! > 0) ...[
                                        SizedBox(height: 8),
                                        Row(
                                          children: [
                                            CircularProgressIndicator(
                                              value: (60 - _countdownSeconds!) / 60,
                                              strokeWidth: 3,
                                              backgroundColor: Colors.grey[300],
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                _currentMessage!.contains('Outside')
                                                    ? Colors.orange
                                                    : Colors.green,
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Text(
                                              '${_countdownSeconds}s remaining',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        
                        // Auto Attendance Toggle Card
                        AutoAttendanceToggle(),

                        SizedBox(height: 16),

                        // Manage Locations Button
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFE5E7EB),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 12,
                                spreadRadius: 0,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LocationManagementScreen(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2563EB).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Color(0xFF2563EB),
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Manage Locations',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1F2937),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Add or edit office locations',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),


                        SizedBox(height: 25),

                        // Admin View Present Employees (ONLY ADMIN - NOT FOR EMPLOYEES)
                        // This section will ONLY show if user role is 'admin'
                        // Employees (role: 'employee' or 'manager') will NOT see this
                        if (user != null && user.role.toLowerCase() == 'admin') ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF7C3AED),
                                  Color(0xFF8B5CF6),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF7C3AED).withOpacity(0.3),
                                  blurRadius: 20,
                                  spreadRadius: 0,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.admin_panel_settings,
                                        color: Colors.white,
                                        size: 25,
                                      ),
                                    ),
                                    SizedBox(width: 15),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Admin Dashboard',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          SizedBox(height: 5),
                                          Text(
                                            'View present employees',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.white.withOpacity(0.9),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 20),
                                Container(
                                  width: double.infinity,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Colors.green[600]!, Colors.green[400]!],
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const AdminAttendanceScreen(),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.people, color: Colors.white, size: 20),
                                        SizedBox(width: 10),
                                        Text(
                                          'View Present Employees',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 25),
                        ],

                        // Today's Tasks
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Today\'s Tasks',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                _showTasksDialog(context);
                              },
                              child: Text(
                                'View All',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 15),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFE5E7EB),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 12,
                                spreadRadius: 0,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF10B981), Color(0xFF34D399)],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withOpacity(0.3),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: 25,
                                ),
                              ),
                              SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Great!',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1F2937),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const Text(
                                      'You don\'t have any pending tasks',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF6B7280),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD1FAE5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFF10B981),
                                    width: 1,
                                  ),
                                ),
                                child: const Text(
                                  '100%',
                                  style: TextStyle(
                                    color: Color(0xFF059669),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 25),

                        // Quick Stats
                        Text(
                          'Quick Stats',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.trending_up,
                                title: 'This Month',
                                value: '22 Days',
                                subtitle: 'Present',
                                color: Colors.green,
                              ),
                            ),
                            SizedBox(width: 15),
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.schedule,
                                title: 'Avg Hours',
                                value: '8.5 hrs',
                                subtitle: 'Daily',
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.timer,
                                title: 'Overtime',
                                value: '28h',
                                subtitle: 'This Month',
                                color: Colors.orange,
                              ),
                            ),
                            SizedBox(width: 15),
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.star,
                                title: 'Performance',
                                value: '96%',
                                subtitle: 'Rating',
                                color: Colors.purple,
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 30),

                        // Quick Actions
                        Text(
                          'Quick Actions',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: _buildQuickActionCard(
                                icon: Icons.event_available,
                                title: 'Apply Leave',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const LeaveRequestScreen(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: _buildQuickActionCard(
                                icon: Icons.schedule,
                                title: 'View Schedule',
                                onTap: () => _showScheduleDialog(context),
                              ),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: _buildQuickActionCard(
                                icon: Icons.help_outline,
                                title: 'Help & Support',
                                onTap: () => _showHelpDialog(context),
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.15),
                  color.withOpacity(0.1),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: color, size: 25),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
              letterSpacing: 0.2,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF2563EB).withOpacity(0.1),
                    const Color(0xFF3B82F6).withOpacity(0.05),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF2563EB).withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF2563EB),
                size: 22,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotificationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Notifications', style: TextStyle(color: Colors.black87)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildNotificationItem('Meeting Reminder', 'Team standup at 2:00 PM', Icons.event),
            _buildNotificationItem('Leave Approved', 'Your leave request has been approved', Icons.check_circle),
            _buildNotificationItem('System Update', 'New features available in the app', Icons.info),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(String title, String subtitle, IconData icon) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.black87, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)),
                Text(subtitle, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showTasksDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Today\'s Tasks', style: TextStyle(color: Colors.black87)),
        content: Text(
          'All tasks completed for today!\n\n✅ Code Review\n✅ Team Meeting\n✅ Documentation Update',
          style: TextStyle(color: Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _showLeaveDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Apply Leave', style: TextStyle(color: Colors.white)),
        content: Text(
          'Would you like to apply for leave? You will be redirected to the leave application form.',
          style: TextStyle(color: Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Apply', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _showScheduleDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('This Week\'s Schedule', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monday - Friday: 9:00 AM - 6:00 PM', style: TextStyle(color: Colors.grey[700])),
            Text('Saturday: 10:00 AM - 2:00 PM', style: TextStyle(color: Colors.grey[700])),
            Text('Sunday: Off', style: TextStyle(color: Colors.grey[700])),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Help & Support', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Need help? Contact us:', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text('📧 support@workflowpro.com', style: TextStyle(color: Colors.grey[700])),
            Text('📞 +91 98765 43210', style: TextStyle(color: Colors.grey[700])),
            Text('💬 Live Chat (9 AM - 6 PM)', style: TextStyle(color: Colors.grey[700])),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }
}

// Checkout Screen
class CheckoutScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Colors.grey[50]!,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                    Text(
                      'Check Out',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(top: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Current Time Display
                        Container(
                          padding: EdgeInsets.all(30),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.2),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.access_time,
                                color: Colors.green,
                                size: 40,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Current Time',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[700],
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                '08:34 PM',
                                style: TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              Text(
                                'May 29, 2025',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 25),

                        // Location Card
                        Container(
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.2),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.location_on,
                                      color: Colors.red,
                                      size: 25,
                                    ),
                                  ),
                                  SizedBox(width: 15),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Current Location',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          'Office Building, Vadodara',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Verified',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 15),
                              Container(
                                height: 120,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.grey[200]!, Colors.grey[300]!],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.map, color: Colors.black87, size: 30),
                                      SizedBox(height: 8),
                                      Text(
                                        'Location Map',
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 25),

                        // Work Summary Card
                        Container(
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.2),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Today\'s Work Summary',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildSummaryItem('Shift', 'Open Shift'),
                                  _buildSummaryItem('Duration', '10h 24min'),
                                ],
                              ),
                              SizedBox(height: 15),
                              Divider(color: Colors.grey[300]),
                              SizedBox(height: 15),
                              _buildTimelineItem('Check In', '10:09 AM', 'Started work', true),
                              SizedBox(height: 12),
                              _buildTimelineItem('Break', '1:00 PM - 2:00 PM', 'Lunch break', true),
                              SizedBox(height: 12),
                              _buildTimelineItem('Check Out', '8:34 PM', 'Ready to leave', false),
                              SizedBox(height: 20),
                              Container(
                                padding: EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Total overtime: 2h 24m',
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 40),

                        // Checkout Button
                        Container(
                          width: double.infinity,
                          height: 55,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green[400]!, Colors.green[600]!],
                            ),
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              _showCheckoutConfirmation(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.logout, color: Colors.white, size: 20),
                                SizedBox(width: 10),
                                Text(
                                  'Confirm Check Out',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineItem(String title, String time, String description, bool completed) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: completed ? Colors.green : Colors.orange,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showCheckoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Column(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 60),
            SizedBox(height: 10),
            Text('Check Out Successful!', style: TextStyle(color: Colors.black87)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You have successfully checked out at 8:34 PM',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700]),
            ),
            SizedBox(height: 15),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text('Today\'s Summary', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Total Hours: 10h 24m', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                  Text('Overtime: 2h 24m', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text('Continue', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }
}