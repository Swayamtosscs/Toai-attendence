import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'services/auth_api_service.dart';
import 'services/storage_service.dart';
import 'app_routes.dart';

class ProfileScreen extends StatefulWidget {
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthApiService _authApiService = AuthApiService();
  File? _profileImageFile;
  String? _profilePictureUrl;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadProfilePicture();
  }

  void _loadProfilePicture() {
    // Load profile picture from user data if available
    // Note: You may need to add profilePicture field to RegisteredUser model
    // For now, we'll check if there's a stored profile picture URL
    // The profile picture will be loaded after upload
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthApiService.currentUser;
    final userName = user?.name ?? 'User';
    final userEmail = user?.email ?? '';
    final userDepartment = user?.department ?? 'Not specified';
    final userDesignation = user?.designation ?? 'Not specified';
    final userRole = user?.role ?? '';
    final userId = user?.id ?? '';
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
                      'Profile',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Spacer(),
                    IconButton(
                      onPressed: () => _showEditProfileDialog(context),
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
                              Stack(
                                children: [
                                  ClipOval(
                                    child: _profileImageFile != null
                                        ? Image.file(
                                            _profileImageFile!,
                                            width: 120,
                                            height: 120,
                                            fit: BoxFit.cover,
                                          )
                                        : _profilePictureUrl != null && _profilePictureUrl!.isNotEmpty
                                            ? Image.network(
                                                _profilePictureUrl!.startsWith('http')
                                                    ? _profilePictureUrl!
                                                    : 'http://103.14.120.163:8092$_profilePictureUrl',
                                                width: 120,
                                                height: 120,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return Container(
                                                    width: 120,
                                                    height: 120,
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [Colors.blue, Colors.blueAccent],
                                                      ),
                                                    ),
                                                    child: Icon(
                                                      Icons.person,
                                                      size: 60,
                                                      color: Colors.white,
                                                    ),
                                                  );
                                                },
                                              )
                                            : Container(
                                                width: 120,
                                                height: 120,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [Colors.blue, Colors.blueAccent],
                                                  ),
                                                ),
                                                child: Icon(
                                                  Icons.person,
                                                  size: 60,
                                                  color: Colors.white,
                                                ),
                                              ),
                                  ),
                                  Positioned(
                                    bottom: 5,
                                    right: 5,
                                    child: GestureDetector(
                                      onTap: _isUploading ? null : () => _showImageSourceDialog(context),
                                      child: Container(
                                        width: 35,
                                        height: 35,
                                        decoration: BoxDecoration(
                                          color: _isUploading ? Colors.grey[300] : Colors.grey[100],
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.blue, width: 2),
                                        ),
                                        child: _isUploading
                                            ? SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              )
                                            : Icon(
                                                Icons.camera_alt,
                                                size: 18,
                                                color: Colors.white,
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 20),
                              Text(
                                userName,
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black, // Black text
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                userDesignation,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[700],
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                userDepartment,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              SizedBox(height: 15),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.green),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Active Employee',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.blue),
                                    ),
                                    child: Text(
                                      'ID: ${userId.isNotEmpty ? userId.substring(0, userId.length > 12 ? 12 : userId.length) : 'N/A'}',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
                                  color: Colors.black, // Black text
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

                        // Personal Information
                        _buildInfoSection(
                          title: 'Personal Information',
                          icon: Icons.person_outline,
                          items: [
                            _buildInfoItem('Full Name', userName),
                            _buildInfoItem('Employee ID', userId.isNotEmpty ? userId : 'N/A'),
                            _buildInfoItem('Email', userEmail.isNotEmpty ? userEmail : 'Not provided'),
                            _buildInfoItem('Phone Number', 'Not provided'),
                            _buildInfoItem('Date of Birth', 'Not provided'),
                            _buildInfoItem('Gender', 'Not provided'),
                            _buildInfoItem('Blood Group', 'Not provided'),
                            _buildInfoItem('Address', 'Not provided'),
                          ],
                        ),

                        SizedBox(height: 25),

                        // Work Information
                        _buildInfoSection(
                          title: 'Work Information',
                          icon: Icons.work_outline,
                          items: [
                            _buildInfoItem('Department', userDepartment),
                            _buildInfoItem('Designation', userDesignation),
                            _buildInfoItem('Role', userRole.isNotEmpty ? userRole.toUpperCase() : 'Not specified'),
                            _buildInfoItem('Employee Type', 'Full-time'),
                            _buildInfoItem('Reporting Manager', 'Not provided'),
                            _buildInfoItem('Join Date', 'Not provided'),
                            _buildInfoItem('Work Location', 'Not provided'),
                            _buildInfoItem('Shift Timing', 'Not provided'),
                            _buildInfoItem('Team', 'Not provided'),
                          ],
                        ),

                        SizedBox(height: 25),

                        // Emergency Contact
                        _buildInfoSection(
                          title: 'Emergency Contact',
                          icon: Icons.emergency,
                          items: [
                            _buildInfoItem('Contact Name', 'Jane Doe'),
                            _buildInfoItem('Relationship', 'Spouse'),
                            _buildInfoItem('Phone Number', '+91 98765 43211'),
                            _buildInfoItem('Address', '123 Tech Street, Vadodara, Gujarat'),
                          ],
                        ),

                        SizedBox(height: 25),

                        // Bank Details
                        _buildInfoSection(
                          title: 'Bank Details',
                          icon: Icons.account_balance,
                          items: [
                            _buildInfoItem('Bank Name', 'State Bank of India'),
                            _buildInfoItem('Account Number', '****-****-****-1234'),
                            _buildInfoItem('IFSC Code', 'SBIN0001234'),
                            _buildInfoItem('Branch', 'Vadodara Main Branch'),
                          ],
                        ),

                        SizedBox(height: 25),

                        // Settings and Actions
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
                                onTap: () => _showNotificationSettings(context),
                              ),
                              _buildSettingItem(
                                icon: Icons.security_outlined,
                                title: 'Privacy & Security',
                                subtitle: 'Password and security settings',
                                onTap: () => _showSecuritySettings(context),
                              ),
                              _buildSettingItem(
                                icon: Icons.language_outlined,
                                title: 'Language',
                                subtitle: 'Choose your preferred language',
                                onTap: () => _showLanguageSettings(context),
                              ),
                              _buildSettingItem(
                                icon: Icons.download_outlined,
                                title: 'Download Data',
                                subtitle: 'Export your personal data',
                                onTap: () => _showDownloadDialog(context),
                              ),
                              _buildSettingItem(
                                icon: Icons.help_outline,
                                title: 'Help & Support',
                                subtitle: 'Get help and support',
                                onTap: () => _showHelpDialog(context),
                              ),
                              _buildSettingItem(
                                icon: Icons.info_outline,
                                title: 'About',
                                subtitle: 'App version and information',
                                onTap: () => _showAboutDialog(context),
                              ),
                              _buildSettingItem(
                                icon: Icons.logout,
                                title: 'Logout',
                                subtitle: 'Sign out of your account',
                                onTap: () => _showLogoutDialog(context),
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
    required IconData icon,
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
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6), // Light gray background
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.black87, size: 20), // Black icon
              ),
              SizedBox(width: 15),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black, // Black text
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          ...items,
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black87, // Dark gray text
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
                color: Colors.black, // Black text
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
        color: const Color(0xFFF9FAFB), // Very light gray background
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)), // Light gray border
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black, // Black text
            ),
          ),
          SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
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
            bottom: BorderSide(color: const Color(0xFFE5E7EB), width: 1), // Light gray border
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6), // Light gray background
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: textColor ?? Colors.black87, // Black icon (or red for logout)
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
                      color: textColor ?? Colors.black, // Black text (or red for logout)
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black87, // Dark gray text
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.black87, // Dark gray arrow
            ),
          ],
        ),
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Edit Profile', style: TextStyle(color: Colors.black87)),
        content: Text(
          'Profile editing functionality will be available in the next update. Contact HR for any changes.',
          style: TextStyle(color: Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _showImageSourceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Change Profile Picture', style: TextStyle(color: Colors.black87)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt, color: Colors.black87), // Black icon
              title: Text('Take Photo', style: TextStyle(color: Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: Colors.black87), // Black icon
              title: Text('Choose from Gallery', style: TextStyle(color: Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_profileImageFile != null || (_profilePictureUrl != null && _profilePictureUrl!.isNotEmpty))
              ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('Remove Photo', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _removeProfilePicture();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // Check if image_picker is available
      if (kIsWeb && source == ImageSource.camera) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Camera is not supported on web. Please use gallery.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final ImagePicker picker = ImagePicker();
      // Allow all image formats - JPEG, PNG, WebP, GIF, etc.
      final XFile? image = await picker.pickImage(
        source: source,
        // Remove maxWidth/maxHeight to preserve original quality
        // Remove imageQuality to avoid format conversion issues
        // Let server handle image processing if needed
      );

      if (image != null) {
        final imageFile = File(image.path);
        final fileName = imageFile.path.toLowerCase();
        
        // Validate file extension (allow all common image formats)
        final validExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic', '.heif'];
        final hasValidExtension = validExtensions.any((ext) => fileName.endsWith(ext));
        
        if (!hasValidExtension) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Please select a valid image file (JPEG, PNG, WebP, GIF, etc.)'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }

        setState(() {
          _profileImageFile = imageFile;
        });
        await _uploadProfilePicture(_profileImageFile!);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to pick image';
        if (e.toString().contains('MissingPluginException')) {
          errorMessage = 'Image picker plugin not initialized. Please restart the app completely (stop and restart, not just hot reload).';
        } else {
          errorMessage = 'Failed to pick image: ${e.toString()}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _uploadProfilePicture(File imageFile) async {
    setState(() {
      _isUploading = true;
    });

    try {
      final profilePictureUrl = await _authApiService.uploadAvatar(imageFile);
      if (mounted) {
        setState(() {
          _profilePictureUrl = profilePictureUrl;
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile picture uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on AuthApiException catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload profile picture: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeProfilePicture() {
    setState(() {
      _profileImageFile = null;
      _profilePictureUrl = null;
    });
    // Note: You may want to call an API to remove the profile picture from server
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Profile picture removed'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _showNotificationSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Notification Settings', style: TextStyle(color: Colors.black87)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSwitchTile('Push Notifications', true),
            _buildSwitchTile('Email Notifications', true),
            _buildSwitchTile('SMS Alerts', false),
            _buildSwitchTile('Meeting Reminders', true),
            _buildSwitchTile('Leave Approvals', true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Save', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile(String title, bool value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: Colors.black87)),
          Switch(
            value: value,
            onChanged: (newValue) {
              // Handle switch change
            },
            activeColor: Colors.green,
          ),
        ],
      ),
    );
  }

  void _showSecuritySettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Security Settings', style: TextStyle(color: Colors.black87)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.lock_outline, color: Colors.black87), // Black icon
              title: Text('Change Password', style: TextStyle(color: Colors.black87)),
              subtitle: Text('Update your account password', style: TextStyle(color: Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _showChangePasswordDialog(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.fingerprint, color: Colors.black87), // Black icon
              title: Text('Biometric Login', style: TextStyle(color: Colors.black87)),
              subtitle: Text('Enable fingerprint/face unlock', style: TextStyle(color: Colors.black87)),
              trailing: Switch(
                value: true,
                onChanged: (value) {},
                activeColor: Colors.green,
              ),
            ),
            ListTile(
              leading: Icon(Icons.security, color: Colors.black87), // Black icon
              title: Text('Two-Factor Authentication', style: TextStyle(color: Colors.black87)),
              subtitle: Text('Add extra security to your account', style: TextStyle(color: Colors.black87)),
              trailing: Switch(
                value: false,
                onChanged: (value) {},
                activeColor: Colors.green,
              ),
            ),
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

  void _showChangePasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Change Password', style: TextStyle(color: Colors.black87)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              obscureText: true,
              style: TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'Current Password',
                labelStyle: TextStyle(color: Color(0xFF8b8b8b)),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: const Color(0xFF2563EB)), // Blue border when focused
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            SizedBox(height: 15),
            TextField(
              obscureText: true,
              style: TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'New Password',
                labelStyle: TextStyle(color: Color(0xFF8b8b8b)),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: const Color(0xFF2563EB)), // Blue border when focused
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            SizedBox(height: 15),
            TextField(
              obscureText: true,
              style: TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'Confirm New Password',
                labelStyle: TextStyle(color: Color(0xFF8b8b8b)),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: const Color(0xFF2563EB)), // Blue border when focused
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showSuccessDialog(context, 'Password Changed', 'Your password has been updated successfully.');
            },
            child: Text('Update', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _showLanguageSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Language Settings', style: TextStyle(color: Colors.black87)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageOption('English', true),
            _buildLanguageOption('Hindi', false),
            _buildLanguageOption('Gujarati', false),
            _buildLanguageOption('Spanish', false),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Save', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageOption(String language, bool selected) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Radio(
            value: selected,
            groupValue: true,
            onChanged: (value) {},
            activeColor: Colors.green,
          ),
          Text(language, style: TextStyle(color: Colors.black87)),
        ],
      ),
    );
  }

  void _showDownloadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Download Data', style: TextStyle(color: Colors.black87)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select the data you want to download:',
              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 15),
            _buildCheckboxTile('Personal Information', true),
            _buildCheckboxTile('Attendance Records', true),
            _buildCheckboxTile('Leave History', false),
            _buildCheckboxTile('Performance Data', false),
            SizedBox(height: 15),
            Text(
              'Data will be exported as PDF format and sent to your registered email.',
              style: TextStyle(color: Color(0xFF8b8b8b), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showSuccessDialog(context, 'Download Initiated', 'Your data export has been initiated. You will receive an email shortly.');
            },
            child: Text('Download', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxTile(String title, bool value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: (newValue) {},
            activeColor: Colors.green,
          ),
          Text(title, style: TextStyle(color: Colors.black87)),
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
        title: Text('Help & Support', style: TextStyle(color: Colors.black87)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Need assistance? We\'re here to help!', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
            SizedBox(height: 15),
            _buildContactItem(Icons.email, 'Email Support', 'support@workflowpro.com'),
            _buildContactItem(Icons.phone, 'Phone Support', '+91 98765 43210'),
            _buildContactItem(Icons.chat, 'Live Chat', 'Available 9 AM - 6 PM'),
            _buildContactItem(Icons.help_center, 'Help Center', 'Visit our FAQ section'),
            SizedBox(height: 15),
            Text(
              'Response time: Usually within 24 hours',
              style: TextStyle(color: Color(0xFF8b8b8b), fontSize: 12),
            ),
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

  Widget _buildContactItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6), // Light gray background
              shape: BoxShape.circle,
            ),
              child: Icon(icon, color: Colors.black87, size: 18), // Black icon
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 14)),
                Text(subtitle, style: TextStyle(color: Color(0xFF8b8b8b), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF575757), Color(0xFF3f3f3f)]),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.work_outline, color: Colors.white, size: 30),
            ),
            SizedBox(height: 10),
            Text('WorkFlow Pro', style: TextStyle(color: Colors.black87)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Version 2.1.0', style: TextStyle(color: Color(0xFF8b8b8b))),
            SizedBox(height: 15),
            Text(
              'Smart Attendance Solution for modern workplaces. Track time, manage attendance, and boost productivity.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black87, fontSize: 14),
            ),
            SizedBox(height: 15),
            Text('© 2025 WorkFlow Pro. All rights reserved.',
                style: TextStyle(color: Color(0xFF8b8b8b), fontSize: 12)),
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

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text('Logout', style: TextStyle(color: Colors.black87)),
        content: Text(
          'Are you sure you want to logout from your account?',
          style: TextStyle(color: Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Logout using auth service
              final authService = AuthApiService();
              try {
                await authService.logout();
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    AppRoutes.login,
                    (route) => false,
                  );
                }
              } catch (e) {
                // Even if logout fails, navigate to login
                if (context.mounted) {
                  await StorageService.clearLoginState();
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    AppRoutes.login,
                    (route) => false,
                  );
                }
              }
            },
            child: Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Column(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 50),
            SizedBox(height: 10),
            Text(title, style: TextStyle(color: Colors.black87)),
          ],
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }
}