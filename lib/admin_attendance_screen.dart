import 'package:flutter/material.dart';
import 'services/auth_api_service.dart';
import 'services/attendance_api_client.dart';
import 'package:geolocator/geolocator.dart';

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  final AuthApiService _authApiService = AuthApiService();
  List<AttendanceRecord> _attendanceRecords = [];
  bool _isLoading = true;
  String? _errorMessage;
  DateTime _selectedDate = DateTime.now();
  List<WorkLocation> _workLocations = [];

  Future<void> _showEmployeeCounts(AttendanceRecord record) async {
    try {
      final counts = await _authApiService.getAttendanceCounts(userId: record.user.id);
      AttendanceCount? selectedDateCount;
      
      try {
        selectedDateCount = counts.firstWhere(
          (count) {
            final countDate = count.date.toLocal();
            return countDate.year == _selectedDate.year &&
                countDate.month == _selectedDate.month &&
                countDate.day == _selectedDate.day;
          },
        );
      } catch (e) {
        selectedDateCount = null;
      }

      if (!mounted) return;

      if (selectedDateCount == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No attendance counts for this date')),
        );
        return;
      }

      // Store in non-nullable variable after null check
      final count = selectedDateCount!;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            '${record.user.name} - Attendance Details',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Date: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                if (count.location.isNotEmpty && count.location['latitude'] != null && count.location['longitude'] != null) ...[
                  SizedBox(height: 10),
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Location: ${_getLocationName((count.location['latitude'] as num?)?.toDouble(), (count.location['longitude'] as num?)?.toDouble())}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${count.checkIns}',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              'Check-ins',
                              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${count.checkOuts}',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            Text(
                              'Check-outs',
                              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (count.checkInTimestamps.isNotEmpty) ...[
                  SizedBox(height: 20),
                  Text(
                    'Check-in Times:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  SizedBox(height: 8),
                  ...count.checkInTimestamps.map((timestamp) {
                    final dt = DateTime.tryParse(timestamp);
                    if (dt == null) return SizedBox();
                    final local = dt.isUtc ? dt.toLocal() : dt;
                    final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.login, size: 16, color: Colors.green),
                          SizedBox(width: 8),
                          Text(time, style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    );
                  }),
                ],
                if (count.checkOutTimestamps.isNotEmpty) ...[
                  SizedBox(height: 15),
                  Text(
                    'Check-out Times:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  SizedBox(height: 8),
                  ...count.checkOutTimestamps.map((timestamp) {
                    final dt = DateTime.tryParse(timestamp);
                    if (dt == null) return SizedBox();
                    final local = dt.isUtc ? dt.toLocal() : dt;
                    final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.logout, size: 16, color: Colors.blue),
                          SizedBox(width: 8),
                          Text(time, style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load counts: $e')),
        );
      }
    }
  }

  Future<void> _showEmployeeHistory(AttendanceRecord record) async {
    int selectedDays = 15;
    List<AttendanceHistoryDay> history = [];
    bool isLoading = true;
    String? error;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> loadHistory() async {
              setState(() {
                isLoading = true;
                error = null;
              });
              try {
                final apiClient = AttendanceApiClient(
                  baseUrl: 'http://103.14.120.163:8092/api',
                );
                final result = await apiClient.getAttendanceHistory(
                  userId: record.user.id,
                  days: selectedDays,
                );
                apiClient.dispose();

                setState(() {
                  history = result;
                  isLoading = false;
                });
              } catch (e) {
                setState(() {
                  error = e.toString();
                  isLoading = false;
                });
              }
            }

            // Initial load when dialog opens
            if (isLoading && history.isEmpty && error == null) {
              // ignore: discarded_futures
              loadHistory();
            }

            return AlertDialog(
              title: Text(
                '${record.user.name} - Last $selectedDays Days',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Range:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: selectedDays,
                          items: const [
                            DropdownMenuItem(
                              value: 7,
                              child: Text('Last 7 days'),
                            ),
                            DropdownMenuItem(
                              value: 15,
                              child: Text('Last 15 days'),
                            ),
                            DropdownMenuItem(
                              value: 30,
                              child: Text('Last 30 days'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              selectedDays = value;
                            });
                            // ignore: discarded_futures
                            loadHistory();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (error != null)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'Error: $error',
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    else if (history.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('No history for this range'),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: history.length,
                          itemBuilder: (context, index) {
                            final day = history[index];
                            final date = day.date.toLocal();
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${date.day}/${date.month}/${date.year}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            const Icon(Icons.login,
                                                size: 16, color: Colors.green),
                                            const SizedBox(width: 4),
                                            Text('${day.totalCheckIns}'),
                                            const SizedBox(width: 12),
                                            const Icon(Icons.logout,
                                                size: 16, color: Colors.blue),
                                            const SizedBox(width: 4),
                                            Text('${day.totalCheckOuts}'),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ...day.locations.map((loc) {
                                      final name = _getLocationName(
                                        loc.latitude,
                                        loc.longitude,
                                      );
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(top: 4.0),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.location_on,
                                              size: 14,
                                              color: Colors.red,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'IN ${loc.checkIns} / OUT ${loc.checkOuts}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAttendance();
    _loadWorkLocations();
  }

  Future<void> _loadWorkLocations() async {
    try {
      final apiClient = AttendanceApiClient(
        baseUrl: 'http://103.14.120.163:8092/api',
      );
      final locations = await apiClient.getWorkLocations();
      if (mounted) {
        setState(() {
          _workLocations = locations;
        });
      }
      apiClient.dispose();
    } catch (e) {
      print('Error loading work locations: $e');
    }
  }

  String _getLocationName(double? lat, double? lng) {
    if (lat == null || lng == null) return 'Unknown Location';
    
    // Find matching location by checking if coordinates are within radius
    for (final location in _workLocations) {
      final distance = Geolocator.distanceBetween(
        lat,
        lng,
        location.latitude,
        location.longitude,
      );
      // If within radius, return location name
      if (distance <= location.radius) {
        return location.name;
      }
    }
    
    // If no match found, return coordinates
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }

  @override
  void dispose() {
    _authApiService.dispose();
    super.dispose();
  }

  Future<void> _loadAttendance() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get start and end of selected date
      final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final endOfDay = startOfDay.add(Duration(days: 1));

      // Fetch attendance records for today with status 'present'
      final records = await _authApiService.getAttendanceRecords(
        startDate: startOfDay,
        endDate: endOfDay,
        status: 'present',
      );

      if (!mounted) return;

      setState(() {
        _attendanceRecords = records;
        _isLoading = false;
      });
    } on AuthApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load attendance: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: const Color(0xFF2563EB), // Blue primary
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadAttendance();
    }
  }

  String _formatTime(DateTime? time) {
    if (time == null) return 'N/A';
    final local = time.isUtc ? time.toLocal() : time;
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minutes = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minutes $period';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDuration(int? minutes) {
    if (minutes == null) return 'N/A';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthApiService.currentUser;
    
    // STRICT CHECK: Only admin can access this screen
    // Employees (role: 'employee' or 'manager') cannot access this
    if (currentUser == null) {
      return Scaffold(
        backgroundColor: Colors.white, // White background
        appBar: AppBar(
          backgroundColor: Colors.white, // White background
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.black), // Black icon
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Admin Attendance',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold), // Black text
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block, color: Colors.red, size: 50),
              SizedBox(height: 20),
              Text(
                'Access Denied',
                style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold), // Black text
              ),
              SizedBox(height: 10),
              Text(
                'Only admin can access this screen',
                style: TextStyle(color: Colors.black87, fontSize: 14), // Dark gray text
              ),
            ],
          ),
        ),
      );
    }

    // Check if user is admin - if not, deny access
    final userRole = currentUser.role.toLowerCase();
    if (userRole != 'admin') {
      // User is employee or manager - show access denied
      return Scaffold(
        backgroundColor: Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Admin Attendance',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block, color: Colors.red, size: 50),
              SizedBox(height: 20),
              Text(
                'Access Denied',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Text(
                'Only admin can access this screen',
                style: TextStyle(color: Color(0xFF8b8b8b), fontSize: 14),
              ),
              SizedBox(height: 5),
              Text(
                'Your role: ${userRole.toUpperCase()}',
                style: TextStyle(color: Color(0xFF8b8b8b), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white, // Pure white background
      appBar: AppBar(
        backgroundColor: Colors.white, // White background
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black), // Black icon
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Present Employees',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold), // Black text
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.black), // Black icon
            onPressed: _loadAttendance,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.white, // Pure white - no gradient
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Date Selector
              Container(
                margin: EdgeInsets.all(20),
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white, // White background
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFE5E7EB)), // Light gray border
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05), // Subtle shadow
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: Colors.black87, size: 20), // Black icon
                    SizedBox(width: 10),
                    Text(
                      'Date: ',
                      style: TextStyle(
                        color: Colors.black87, // Dark gray text
                        fontSize: 14,
                      ),
                    ),
                    TextButton(
                      onPressed: _selectDate,
                      child: Text(
                        _formatDate(_selectedDate),
                        style: TextStyle(
                          color: Colors.black, // Black text
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Spacer(),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Text(
                        '${_attendanceRecords.length} Present',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Attendance List
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF2563EB)), // Blue indicator
                        ),
                      )
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, color: Colors.red, size: 50),
                                SizedBox(height: 20),
                                Text(
                                  _errorMessage!,
                                  style: TextStyle(color: Colors.black), // Black text
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 20),
                                ElevatedButton(
                                  onPressed: _loadAttendance,
                                  child: Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : _attendanceRecords.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.person_off, color: Colors.grey, size: 50),
                                    SizedBox(height: 20),
                                    Text(
                                      'No employees present on this date',
                                      style: TextStyle(color: Colors.black87), // Dark gray text
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _loadAttendance,
                                color: const Color(0xFF2563EB), // Blue refresh indicator
                                child: ListView.builder(
                                  padding: EdgeInsets.symmetric(horizontal: 20),
                                  itemCount: _attendanceRecords.length,
                                  itemBuilder: (context, index) {
                                    final record = _attendanceRecords[index];
                                    return GestureDetector(
                                      onTap: () => _showEmployeeCounts(record),
                                      child: Container(
                                        margin: EdgeInsets.only(bottom: 15),
                                        padding: EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          color: Colors.white, // White background
                                          borderRadius: BorderRadius.circular(15),
                                          border: Border.all(color: const Color(0xFFE5E7EB)), // Light gray border
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.05), // Subtle shadow
                                              blurRadius: 8,
                                              spreadRadius: 1,
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
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      const Color(0xFF2563EB),
                                                      const Color(0xFF3B82F6),
                                                    ],
                                                  ),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons.person,
                                                  color: Colors.white, // White icon on blue background
                                                  size: 25,
                                                ),
                                              ),
                                              SizedBox(width: 15),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      record.user.name,
                                                      style: TextStyle(
                                                        fontSize: 18,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.black, // Black text
                                                      ),
                                                    ),
                                                    SizedBox(height: 5),
                                                    Text(
                                                      record.user.email,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: Colors.black87, // Dark gray text
                                                      ),
                                                    ),
                                                    if (record.user.department != null) ...[
                                                      SizedBox(height: 3),
                                                      Text(
                                                        record.user.department!,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.black87, // Dark gray text
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(20),
                                                  border: Border.all(color: Colors.green),
                                                ),
                                                child: Text(
                                                  'PRESENT',
                                                  style: TextStyle(
                                                    color: Colors.green,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 20),
                                          Divider(color: const Color(0xFFE5E7EB)), // Light gray divider
                                          SizedBox(height: 15),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _buildInfoRow(
                                                  Icons.login,
                                                  'Check In',
                                                  _formatTime(record.checkInAt),
                                                  Colors.green,
                                                ),
                                              ),
                                              SizedBox(width: 15),
                                              Expanded(
                                                child: _buildInfoRow(
                                                  Icons.logout,
                                                  'Check Out',
                                                  record.checkOutAt != null
                                                      ? _formatTime(
                                                          record.checkOutAt)
                                                      : 'Not checked out',
                                                  record.checkOutAt != null
                                                      ? Colors.orange
                                                      : Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (record.workDurationMinutes != null &&
                                              record.checkOutAt != null) ...[
                                            SizedBox(height: 15),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: _buildInfoRow(
                                                    Icons.timer,
                                                    'Work Duration',
                                                    _formatDuration(record.workDurationMinutes),
                                                    Colors.blue,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          if (record.notes != null &&
                                              record.notes!.isNotEmpty) ...[
                                            SizedBox(height: 15),
                                            Container(
                                              padding: EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF9FAFB), // Very light gray background
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: const Color(0xFFE5E7EB)), // Light gray border
                                              ),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Icon(Icons.note, color: Colors.black87, size: 18), // Black icon
                                                  SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      record.notes!,
                                                      style: TextStyle(
                                                        color: Colors.black87, // Dark gray text
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 10),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton.icon(
                                              onPressed: () =>
                                                  _showEmployeeHistory(record),
                                              icon: const Icon(
                                                Icons.history,
                                                size: 18,
                                              ),
                                              label: const Text(
                                                'Last days history',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  },
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB), // Very light gray background
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)), // Light gray border
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16), // Colored icon (green/orange/blue)
              SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: Colors.black87, // Dark gray text
                  fontSize: 12,
                ),
              ),
            ],
          ),
          SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              color: Colors.black, // Black text
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

