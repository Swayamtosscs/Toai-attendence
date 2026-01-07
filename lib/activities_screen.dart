import 'package:flutter/material.dart';
import 'leave_request_screen.dart';
import 'leave_list_screen.dart';
import 'chat_screen.dart';

// Activities Screen
class ActivitiesScreen extends StatelessWidget {
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
                      'Activities',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
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
                      child: IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ProfileScreen()),
                          );
                        },
                        icon: Icon(
                          Icons.person,
                          color: Colors.black87,
                          size: 25,
                        ),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Banner Slider
                        Container(
                          height: 180,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.blue, Colors.blueAccent],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.2),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.campaign, color: Colors.white, size: 40),
                                SizedBox(height: 10),
                                Text(
                                  'Company Updates',
                                  style: TextStyle(
                                    color: Colors.white, // White text on blue background
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Stay informed with latest news',
                                  style: TextStyle(
                                    color: Colors.white70, // Light white text on blue background
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                                icon: Icons.help_outline,
                                title: 'Help Line',
                                color: Colors.red[400]!,
                              ),
                            ),
                            SizedBox(width: 15),
                            Expanded(
                              child: _buildQuickActionCard(
                                icon: Icons.event_available,
                                title: 'Regularize Attendance',
                                color: Colors.blue[400]!,
                              ),
                            ),
                            SizedBox(width: 15),
                            Expanded(
                              child: _buildQuickActionCard(
                                icon: Icons.exit_to_app,
                                title: 'Apply Leave',
                                color: Colors.orange[400]!,
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
                          ],
                        ),

                        SizedBox(height: 30),

                        // My Activities
                        Text(
                          'My Activities',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 15),
                        GridView.count(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          crossAxisSpacing: 15,
                          mainAxisSpacing: 15,
                          childAspectRatio: 1.1,
                          children: [
                            _buildActivityCard(
                              icon: Icons.calendar_today,
                              title: 'Attendance',
                              subtitle: 'View records',
                              color: Colors.green,
                            ),
                            _buildActivityCard(
                              icon: Icons.holiday_village,
                              title: 'My Leaves',
                              subtitle: 'View leave requests',
                              color: Colors.purple,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const LeaveListScreen(),
                                  ),
                                );
                              },
                            ),
                            _buildActivityCard(
                              icon: Icons.upload_file,
                              title: 'Document Upload',
                              subtitle: 'Upload files',
                              color: Colors.orange,
                            ),
                            _buildActivityCard(
                              icon: Icons.track_changes,
                              title: 'Target',
                              subtitle: 'View goals',
                              color: Colors.blue,
                            ),
                            _buildActivityCard(
                              icon: Icons.videocam,
                              title: 'Input Sales',
                              subtitle: 'Record sales',
                              color: Colors.red,
                            ),
                            _buildActivityCard(
                              icon: Icons.message,
                              title: 'Messages',
                              subtitle: 'Company chat',
                              color: Colors.teal,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ChatScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
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

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black54,
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
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 25),
            ),
            SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black, // Black text on white background
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 25),
            ),
            SizedBox(height: 15),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black, // Black text on white background
              ),
            ),
            SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Profile Screen
class ProfileScreen extends StatelessWidget {
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
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                    Text(
                      'Profile',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Spacer(),
                    IconButton(
                      onPressed: () {},
                      icon: Icon(Icons.edit, color: Colors.black87),
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
                        // Profile Picture and Basic Info
                        Container(
                          padding: EdgeInsets.all(25),
                          decoration: BoxDecoration(
                            color: Colors.white, // White background
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE5E7EB)), // Light gray border
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05), // Subtle shadow
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Stack(
                                children: [
                                  Container(
                                    width: 100,
                                    height: 100,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.blue, Colors.blueAccent],
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.withOpacity(0.2),
                                          blurRadius: 15,
                                          spreadRadius: 3,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.person,
                                      size: 50,
                                      color: Colors.white, // White icon on blue gradient
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.blue),
                                      ),
                                      child: Icon(
                                        Icons.camera_alt,
                                        size: 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 20),
                              Text(
                                'John Doe',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black, // Black text on white background
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Senior Software Developer',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87, // Dark gray text
                                ),
                              ),
                              SizedBox(height: 15),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.green),
                                ),
                                child: Text(
                                  'Active Employee',
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

                        SizedBox(height: 25),

                        // Personal Information
                        _buildInfoSection(
                          title: 'Personal Information',
                          items: [
                            _buildInfoItem('Employee ID', 'GS10035997'),
                            _buildInfoItem('Email', 'john.doe@company.com'),
                            _buildInfoItem('Phone', '+91 98765 43210'),
                            _buildInfoItem('Date of Birth', '15 January 1990'),
                            _buildInfoItem('Address', '123 Tech Street, Vadodara, Gujarat'),
                          ],
                        ),

                        SizedBox(height: 25),

                        // Work Information
                        _buildInfoSection(
                          title: 'Work Information',
                          items: [
                            _buildInfoItem('Department', 'Information Technology'),
                            _buildInfoItem('Designation', 'Senior Software Developer'),
                            _buildInfoItem('Reporting Manager', 'Jane Smith'),
                            _buildInfoItem('Join Date', '01 March 2020'),
                            _buildInfoItem('Work Location', 'Vadodara Office'),
                            _buildInfoItem('Shift Timing', '09:00 AM - 06:00 PM'),
                          ],
                        ),

                        SizedBox(height: 25),

                        // Quick Stats
                        Container(
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
                              Text(
                                'Quick Stats',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black, // Black text on white background
                                ),
                              ),
                              SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatItem(
                                      icon: Icons.calendar_today,
                                      value: '5.2',
                                      label: 'Years with Company',
                                      color: Colors.blue,
                                    ),
                                  ),
                                  SizedBox(width: 15),
                                  Expanded(
                                    child: _buildStatItem(
                                      icon: Icons.trending_up,
                                      value: '96%',
                                      label: 'Attendance Rate',
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 15),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatItem(
                                      icon: Icons.schedule,
                                      value: '8.5',
                                      label: 'Avg Daily Hours',
                                      color: Colors.orange,
                                    ),
                                  ),
                                  SizedBox(width: 15),
                                  Expanded(
                                    child: _buildStatItem(
                                      icon: Icons.star,
                                      value: '4.8',
                                      label: 'Performance Rating',
                                      color: Colors.purple,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 25),

                        // Settings Options
                        Container(
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
                            children: [
                              _buildSettingItem(
                                icon: Icons.notifications_outlined,
                                title: 'Notifications',
                                subtitle: 'Manage notification preferences',
                                onTap: () {},
                              ),
                              _buildSettingItem(
                                icon: Icons.security_outlined,
                                title: 'Privacy & Security',
                                subtitle: 'Password and security settings',
                                onTap: () {},
                              ),
                              _buildSettingItem(
                                icon: Icons.help_outline,
                                title: 'Help & Support',
                                subtitle: 'Get help and support',
                                onTap: () {},
                              ),
                              _buildSettingItem(
                                icon: Icons.logout,
                                title: 'Logout',
                                subtitle: 'Sign out of your account',
                                onTap: () {},
                                isLast: true,
                                textColor: Colors.red,
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 30),
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

  Widget _buildInfoSection({
    required String title,
    required List<Widget> items,
  }) {
    return Container(
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
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black, // Black text on white background
            ),
          ),
          SizedBox(height: 15),
          ...items,
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black, // Black text on white background
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 25),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black, // Black text on white background
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black87, // Dark gray text
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLast = false,
    Color? textColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: isLast ? null : Border(
            bottom: BorderSide(color: Colors.grey[300]!, width: 1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: textColor ?? Colors.black87,
                size: 22,
              ),
            ),
            SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor ?? Colors.black87,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Color(0xFF8b8b8b),
            ),
          ],
        ),
      ),
    );
  }
}