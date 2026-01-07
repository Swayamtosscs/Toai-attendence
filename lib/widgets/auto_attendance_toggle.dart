import 'dart:async';
import 'package:flutter/material.dart';
import '../services/attendance_service.dart' show AttendanceService, ServiceAttendanceState;
import '../services/attendance_service_factory.dart';
import '../services/attendance_api_client.dart';
import '../services/intelligent_attendance/attendance_controller.dart' show AttendanceController, IntelligentAttendanceState;

/// UI Widget for Auto Attendance Toggle
/// Add this to your settings screen or home screen
class AutoAttendanceToggle extends StatefulWidget {
  const AutoAttendanceToggle({super.key});

  @override
  State<AutoAttendanceToggle> createState() => _AutoAttendanceToggleState();
}

class _AutoAttendanceToggleState extends State<AutoAttendanceToggle> {
  AttendanceService? _attendanceService;
  AttendanceController? _attendanceController;
  ServiceAttendanceState _currentState = ServiceAttendanceState.initial();
  StreamSubscription<ServiceAttendanceState>? _stateSubscription;
  StreamSubscription<IntelligentAttendanceState>? _controllerStateSubscription;
  bool _isLoading = false;
  List<WorkLocation> _workLocations = [];

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    try {
      // Initialize new attendance controller
      try {
        final controller = await AttendanceServiceFactory.initializeController();
        setState(() {
          _attendanceController = controller;
        });

        // Listen to controller state
        _controllerStateSubscription = controller.stateStream.listen((state) {
          if (mounted) {
            setState(() {
              // Map controller state to service state for UI
              _currentState = ServiceAttendanceState(
                isEnabled: !state.isManuallyDisabled,
                isCheckedIn: state.isCheckedIn,
                currentLocationId: null,
                checkInTimestamp: state.checkInTime,
              );
            });
          }
        });

        // Load current state
        final controllerState = controller.getCurrentState();
        setState(() {
          _currentState = ServiceAttendanceState(
            isEnabled: !controllerState.isManuallyDisabled,
            isCheckedIn: controllerState.isCheckedIn,
            currentLocationId: null,
            checkInTimestamp: controllerState.checkInTime,
          );
        });
      } catch (e) {
        print('Controller initialization failed: $e');
      }

      // Also keep service for backward compatibility
      final service = await AttendanceServiceFactory.getInstance();
      setState(() {
        _attendanceService = service;
      });

      // Load work locations
      try {
        final apiClient = AttendanceApiClient(
          baseUrl: 'http://103.14.120.163:8092/api',
        );
        final locations = await apiClient.getWorkLocations();
        setState(() {
          _workLocations = locations;
        });
        apiClient.dispose();
      } catch (e) {
        print('Failed to load locations: $e');
      }

      // Listen to service state changes (backward compatibility)
      _stateSubscription = service.stateStream.listen((state) {
        if (mounted && _attendanceController == null) {
          setState(() {
            _currentState = state;
          });
        }
      });

      // Load current state
      if (_attendanceController == null) {
        setState(() {
          _currentState = service.getCurrentState();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize: $e')),
        );
      }
    }
  }

  String _getLocationName(String? locationId) {
    if (locationId == null) return '';
    try {
      final location = _workLocations.firstWhere(
        (loc) => loc.id == locationId,
        orElse: () => WorkLocation(
          id: locationId,
          name: locationId,
          latitude: 0,
          longitude: 0,
          radius: 100,
        ),
      );
      return location.name;
    } catch (e) {
      return locationId;
    }
  }

  Future<void> _toggleAutoAttendance(bool value) async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (value) {
        // Enable - use controller if available
        if (_attendanceController != null) {
          // Controller handles auto enable when location detected
          // Just clear manual disable flag
          setState(() {
            _currentState = ServiceAttendanceState(
              isEnabled: true,
              isCheckedIn: _currentState.isCheckedIn,
              currentLocationId: _currentState.currentLocationId,
              checkInTimestamp: _currentState.checkInTimestamp,
            );
          });
        } else if (_attendanceService != null) {
          await _attendanceService!.enable();
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Auto attendance enabled'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Manual toggle OFF - treat as final check-out
        if (_attendanceController != null) {
          await _attendanceController!.manualToggleOff();
        } else if (_attendanceService != null) {
          final wasCheckedIn = _attendanceService!.getCurrentState().isCheckedIn;
          final checkoutTime = DateTime.now();
          await _attendanceService!.disable();
          
          if (mounted && wasCheckedIn) {
            final hour = checkoutTime.hour % 12 == 0 ? 12 : checkoutTime.hour % 12;
            final minute = checkoutTime.minute.toString().padLeft(2, '0');
            final period = checkoutTime.hour >= 12 ? 'PM' : 'AM';
            final timeStr = '$hour:$minute $period';
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Manual check-out completed at $timeStr'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _controllerStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Auto Attendance',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentState.isEnabled
                          ? 'Automatically tracks your attendance'
                          : 'Manual attendance only',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: _currentState.isEnabled,
                    onChanged: _toggleAutoAttendance,
                    activeColor: const Color(0xFF2563EB),
                  ),
              ],
            ),
            if (_currentState.isEnabled) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _currentState.isCheckedIn
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: _currentState.isCheckedIn
                              ? Colors.green
                              : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _currentState.isCheckedIn
                                ? (_currentState.checkInTimestamp != null
                                    ? 'Checked In at ${_formatTime(_currentState.checkInTimestamp!)}'
                                    : 'Checked In')
                                : 'Waiting for check-in',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _currentState.isCheckedIn
                                  ? Colors.green[700]
                                  : Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_currentState.currentLocationId != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Location: ${_getLocationName(_currentState.currentLocationId)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                    // Removed duplicate check-in time display - now shown in main status text
                  ],
                ),
              ),
            ],
            if (_currentState.error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentState.error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final local = dateTime.isUtc ? dateTime.toLocal() : dateTime;
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

