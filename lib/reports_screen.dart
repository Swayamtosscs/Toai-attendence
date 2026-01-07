import 'package:flutter/material.dart';
import 'services/auth_api_service.dart';
import 'services/attendance_api_client.dart';
import 'package:geolocator/geolocator.dart';

// Reports Screen with Dummy Data
class ReportsScreen extends StatefulWidget {
  @override
  _ReportsScreenState createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int selectedTabIndex = 0;
  DateTime _selectedMonth = DateTime.now();
  final AuthApiService _authApiService = AuthApiService();
  List<AttendanceCount> _attendanceCounts = [];
  bool _isLoadingCounts = false;
  List<WorkLocation> _workLocations = [];

  // Dummy attendance data
  final List<Map<String, dynamic>> attendanceData = [
    {
      'date': '2025-05-29',
      'checkIn': '10:09 AM',
      'checkOut': '08:34 PM',
      'duration': '10h 24m',
      'status': 'Present',
      'overtimeHours': '2h 24m',
    },
    {
      'date': '2025-05-28',
      'checkIn': '09:15 AM',
      'checkOut': '06:30 PM',
      'duration': '9h 15m',
      'status': 'Present',
      'overtimeHours': '1h 15m',
    },
    {
      'date': '2025-05-27',
      'checkIn': '09:30 AM',
      'checkOut': '06:45 PM',
      'duration': '9h 15m',
      'status': 'Present',
      'overtimeHours': '1h 15m',
    },
    {
      'date': '2025-05-26',
      'checkIn': '--',
      'checkOut': '--',
      'duration': '--',
      'status': 'Weekend',
      'overtimeHours': '--',
    },
    {
      'date': '2025-05-25',
      'checkIn': '--',
      'checkOut': '--',
      'duration': '--',
      'status': 'Weekend',
      'overtimeHours': '--',
    },
    {
      'date': '2025-05-24',
      'checkIn': '08:45 AM',
      'checkOut': '05:50 PM',
      'duration': '9h 05m',
      'status': 'Present',
      'overtimeHours': '1h 05m',
    },
    {
      'date': '2025-05-23',
      'checkIn': '09:00 AM',
      'checkOut': '06:15 PM',
      'duration': '9h 15m',
      'status': 'Present',
      'overtimeHours': '1h 15m',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadAttendanceCounts();
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

  Future<void> _loadAttendanceCounts() async {
    setState(() {
      _isLoadingCounts = true;
    });
    try {
      final currentUser = AuthApiService.currentUser;
      if (currentUser == null) {
        if (mounted) {
          setState(() {
            _isLoadingCounts = false;
          });
        }
        return;
      }
      // Use attendance history API to build counts for the calendar
      final apiClient = AttendanceApiClient(
        baseUrl: 'http://103.14.120.163:8092/api',
      );
      // Last 30 days for this employee
      final history = await apiClient.getAttendanceHistory(
        userId: currentUser.id,
        days: 30,
      );
      apiClient.dispose();

      // Convert history response into AttendanceCount list
      final List<AttendanceCount> counts = [];
      for (final day in history) {
        if (day.locations.isEmpty) {
          // No per-location data, still add one aggregate record
          counts.add(
            AttendanceCount(
              location: <String, dynamic>{},
              checkIns: day.totalCheckIns,
              checkOuts: day.totalCheckOuts,
              date: day.date.toLocal(),
              checkInTimestamps: const [],
              checkOutTimestamps: const [],
              user: {
                'id': day.userId,
                'name': day.userName,
                'email': day.userEmail,
              },
            ),
          );
        } else {
          for (final loc in day.locations) {
            final locationMap = <String, dynamic>{};
            if (loc.latitude != null && loc.longitude != null) {
              locationMap['latitude'] = loc.latitude;
              locationMap['longitude'] = loc.longitude;
            }

            counts.add(
              AttendanceCount(
                location: locationMap,
                checkIns: loc.checkIns,
                checkOuts: loc.checkOuts,
                date: day.date.toLocal(),
                checkInTimestamps: const [],
                checkOutTimestamps: const [],
                user: {
                  'id': day.userId,
                  'name': day.userName,
                  'email': day.userEmail,
                },
              ),
            );
          }
        }
      }

      if (mounted) {
        setState(() {
          _attendanceCounts = counts;
          _isLoadingCounts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCounts = false;
        });
        print('Error loading attendance counts: $e');
      }
    }
  }

  AttendanceCount? _getCountForDate(DateTime date) {
    // Normalize the input date (remove time component)
    final normalizedDate = DateTime(date.year, date.month, date.day);

    // Collect ALL records that belong to this date (some APIs can return
    // multiple rows for same day – different locations / sessions, etc.)
    final matching = _attendanceCounts.where((count) {
      final countDate = count.date.toLocal();
      final normalizedCountDate =
          DateTime(countDate.year, countDate.month, countDate.day);

      return normalizedCountDate.year == normalizedDate.year &&
          normalizedCountDate.month == normalizedDate.month &&
          normalizedCountDate.day == normalizedDate.day;
    }).toList();

    if (matching.isEmpty) return null;

    // Aggregate to get a **stable, real** number per day
    final totalCheckIns =
        matching.fold<int>(0, (sum, c) => sum + (c.checkIns));
    final totalCheckOuts =
        matching.fold<int>(0, (sum, c) => sum + (c.checkOuts));

    // Merge timestamps (optional but useful for details popup)
    final allCheckInTimestamps = <String>[
      for (final c in matching) ...c.checkInTimestamps,
    ];
    final allCheckOutTimestamps = <String>[
      for (final c in matching) ...c.checkOutTimestamps,
    ];

    // Use first record as base for location / user metadata
    final base = matching.first;

    return AttendanceCount(
      location: base.location,
      checkIns: totalCheckIns,
      checkOuts: totalCheckOuts,
      date: normalizedDate,
      checkInTimestamps: allCheckInTimestamps,
      checkOutTimestamps: allCheckOutTimestamps,
      user: base.user,
    );
  }

  void _showDateDetailsPopup(DateTime date) {
    final count = _getCountForDate(date);
    if (count == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No attendance data for this date')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Attendance Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Date: ${date.day}/${date.month}/${date.year}',
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.white, // Pure white - no gradient
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
                    Text(
                      'Reports',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black, // Pure black text
                      ),
                    ),
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.filter_alt,
                        color: Colors.black, // Pure black text
                        size: 25,
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(top: 20),
                  decoration: const BoxDecoration(
                    color: Colors.white, // Pure white background
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Tab Bar
                      Container(
                        margin: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white, // White background
                          border: Border.all(color: const Color(0xFFE5E7EB)), // Light gray border
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => selectedTabIndex = 0),
                                child: Container(
                                  padding: EdgeInsets.symmetric(vertical: 15),
                                  decoration: BoxDecoration(
                                    color: selectedTabIndex == 0
                                        ? const Color(0xFF2563EB) // Blue when selected
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: Text(
                                    'Overview',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: selectedTabIndex == 0
                                          ? Colors.white // White text on blue
                                          : Colors.black, // Black text when not selected
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => selectedTabIndex = 1),
                                child: Container(
                                  padding: EdgeInsets.symmetric(vertical: 15),
                                  decoration: BoxDecoration(
                                    color: selectedTabIndex == 1
                                        ? const Color(0xFF2563EB) // Blue when selected
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: Text(
                                    'Attendance',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: selectedTabIndex == 1
                                          ? Colors.white // White text on blue
                                          : Colors.black, // Black text when not selected
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Tab Content
                      Expanded(
                        child: selectedTabIndex == 0
                            ? _buildOverviewTab()
                            : _buildAttendanceTab(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Cards
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'This Month',
                  value: '22',
                  subtitle: 'Days Present',
                  icon: Icons.calendar_today,
                  color: Colors.green,
                ),
              ),
              SizedBox(width: 15),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Total Hours',
                  value: '176',
                  subtitle: 'This Month',
                  icon: Icons.schedule,
                  color: Colors.blue,
                ),
              ),
            ],
          ),

          SizedBox(height: 15),

          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'Overtime',
                  value: '28h',
                  subtitle: 'This Month',
                  icon: Icons.timer,
                  color: Colors.orange,
                ),
              ),
              SizedBox(width: 15),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Leaves',
                  value: '2',
                  subtitle: 'Days Taken',
                  icon: Icons.event_busy,
                  color: Colors.red,
                ),
              ),
            ],
          ),

          SizedBox(height: 30),

          // Monthly Performance Chart
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
                            color: Colors.white, // White background
              borderRadius: BorderRadius.circular(15),
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
                Text(
                  'Monthly Performance',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black, // Pure black text
                  ),
                ),
                SizedBox(height: 20),
                Container(
                  height: 200,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(7, (index) {
                            List<double> heights = [0.8, 0.6, 0.9, 0.7, 0.85, 0.75, 0.95];
                            List<String> days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  width: 30,
                                  height: 150 * heights[index],
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [Colors.blue, Colors.blueAccent],
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  days[index],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black, // Pure black text
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 30),

          // Recent Activity
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
                            color: Colors.white, // White background
              borderRadius: BorderRadius.circular(15),
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
                Text(
                  'Recent Activity',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black, // Pure black text
                  ),
                ),
                SizedBox(height: 15),
                ...attendanceData.take(3).map((record) => _buildActivityItem(record)),
              ],
            ),
          ),

          SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildAttendanceTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month Navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Attendance Records',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left, color: Colors.black),
                      padding: EdgeInsets.all(4),
                      constraints: BoxConstraints(),
                      onPressed: () {
                        setState(() {
                          _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                        });
                        _loadAttendanceCounts();
                      },
                    ),
                    Flexible(
                      child: Text(
                        '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.chevron_right, color: Colors.black),
                      padding: EdgeInsets.all(4),
                      constraints: BoxConstraints(),
                      onPressed: () {
                        setState(() {
                          _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                        });
                        _loadAttendanceCounts();
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh, color: Colors.black, size: 20),
                      padding: EdgeInsets.all(4),
                      constraints: BoxConstraints(),
                      onPressed: _loadAttendanceCounts,
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          
          // Calendar View
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _buildCalendar();
              },
            ),
          ),
          
          SizedBox(height: 20),
          
          // Legend
          Container(
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLegendItem('Full', Colors.green),
                _buildLegendItem('Half', Colors.orange),
                _buildLegendItem('Absent', Colors.red),
                _buildLegendItem('Weekend', Colors.blue),
              ],
            ),
          ),
          
          SizedBox(height: 20),
        ],
      ),
    );
  }
  
  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
  
  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
  
  Widget _buildCalendar() {
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final firstDayOfWeek = firstDay.weekday; // 1 = Monday, 7 = Sunday
    final daysInMonth = lastDay.day;
    
    // Week day headers
    final weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Week day headers
        Row(
          children: weekDays.map((day) => Expanded(
            child: Center(
              child: Text(
                day,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          )).toList(),
        ),
        SizedBox(height: 8),
        // Calendar days
        ...List.generate((daysInMonth + firstDayOfWeek - 1) ~/ 7 + 1, (weekIndex) {
          return Row(
            children: List.generate(7, (dayIndex) {
              final dayNumber = weekIndex * 7 + dayIndex - firstDayOfWeek + 2;
              
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return Expanded(child: SizedBox());
              }
              
              final currentDate = DateTime(_selectedMonth.year, _selectedMonth.month, dayNumber);
              final attendanceStatus = _getAttendanceStatus(currentDate);
              final count = _getCountForDate(currentDate);
              
              return Expanded(
                child: GestureDetector(
                  onTap: () => _showDateDetailsPopup(currentDate),
                  child: Container(
                    margin: EdgeInsets.all(1.5),
                    constraints: BoxConstraints(
                      minHeight: 45,
                      maxHeight: 55,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          SizedBox(height: 1),
                          if (count != null)
                            Flexible(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (count.checkIns > 0)
                                    Flexible(
                                      child: Container(
                                        margin: EdgeInsets.only(right: 1),
                                        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                        child: Text(
                                          '${count.checkIns}',
                                          style: TextStyle(
                                            fontSize: 7,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            height: 1.0,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  if (count.checkOuts > 0)
                                    Flexible(
                                      child: Container(
                                        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
                                        decoration: BoxDecoration(
                                          color: Colors.blue,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                        child: Text(
                                          '${count.checkOuts}',
                                          style: TextStyle(
                                            fontSize: 7,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            height: 1.0,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          else
                            _buildStatusDot(attendanceStatus),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        }),
      ],
    );
  }
  
  Widget _buildStatusDot(String status) {
    Color dotColor;
    switch (status) {
      case 'full':
        dotColor = Colors.green;
        break;
      case 'half':
        dotColor = Colors.orange;
        break;
      case 'absent':
        dotColor = Colors.red;
        break;
      case 'weekend':
        dotColor = Colors.blue;
        break;
      default:
        dotColor = Colors.transparent;
    }
    
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
      ),
    );
  }
  
  String _getAttendanceStatus(DateTime date) {
    // Check if weekend (Saturday = 6, Sunday = 7)
    if (date.weekday == 6 || date.weekday == 7) {
      return 'weekend';
    }
    
    // Use real attendance count data instead of dummy data
    final count = _getCountForDate(date);
    if (count == null) {
      return 'absent';
    }
    
    // If there are check-ins, determine status
    if (count.checkIns > 0) {
      // Check if there's a check-out for the same day
      if (count.checkOuts > 0) {
        // Full day if both check-in and check-out exist
        return 'full';
      } else {
        // Only check-in, might be half day or still working
        return 'full';
      }
    }
    
    return 'absent';
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
                            color: Colors.white, // White background
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
                                color: Colors.black.withOpacity(0.05), // Subtle shadow
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
                            color: color.withOpacity(0.1), // Light colored background
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 25),
          ),
          SizedBox(height: 15),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black, // Black text
            ),
          ),
          SizedBox(height: 5),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black, // Black text
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: Colors.black87, // Dark gray text
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> record) {
    Color statusColor = record['status'] == 'Present' ? Colors.green : Colors.grey[700]!;

    return Container(
      margin: EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                            color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              record['status'] == 'Present' ? Icons.check : Icons.weekend,
              color: statusColor,
              size: 20,
            ),
          ),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record['date'],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black, // Pure black text
                  ),
                ),
                Text(
                  record['status'] == 'Present'
                      ? '${record['checkIn']} - ${record['checkOut']}'
                      : record['status'],
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black87, // Dark gray text
                  ),
                ),
              ],
            ),
          ),
          Text(
            record['duration'],
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black, // Pure black text
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceRow(Map<String, dynamic> record) {
    Color statusColor = record['status'] == 'Present'
        ? Colors.green
        : record['status'] == 'Weekend'
        ? Colors.blue
        : Colors.grey[700]!;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white, // White background for rows
        border: Border(
          bottom: BorderSide(color: const Color(0xFFE5E7EB), width: 1), // Light gray border
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              record['date'],
              style: TextStyle(
                fontSize: 12,
                color: Colors.black, // Black text
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              record['checkIn'],
              style: TextStyle(
                fontSize: 12,
                color: Colors.black, // Black text
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              record['checkOut'],
              style: TextStyle(
                fontSize: 12,
                color: Colors.black, // Black text
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Text(
                  record['duration'],
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black, // Pure black text
                  ),
                ),
                SizedBox(width: 5),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}