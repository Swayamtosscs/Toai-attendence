import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'services/location_config.dart';
import 'services/attendance_service_factory.dart';
import 'services/attendance_service.dart';
import 'services/attendance_api_client.dart';
import 'services/storage_service.dart';

class LocationManagementScreen extends StatefulWidget {
  const LocationManagementScreen({super.key});

  @override
  State<LocationManagementScreen> createState() => _LocationManagementScreenState();
}

class _LocationManagementScreenState extends State<LocationManagementScreen> {
  List<WorkLocation> _locations = [];
  bool _isLoading = true;
  AttendanceService? _attendanceService;
  String? _userRole;
  bool _canManageLocations = false;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _loadLocations();
  }

  Future<void> _checkUserRole() async {
    final user = await StorageService.getUserData();
    if (user != null) {
      final role = user.role.toLowerCase();
      setState(() {
        _userRole = role;
        // Only HR and Admin can manage locations
        _canManageLocations = role == 'admin' || role == 'hr';
      });
    }
  }

  Future<void> _loadLocations() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get locations from service
      final service = await AttendanceServiceFactory.getInstance();
      setState(() {
        _attendanceService = service;
      });

      // Try to get locations from backend
      try {
        final apiClient = AttendanceApiClient(
          baseUrl: 'http://103.14.120.163:8092/api',
        );
        final locations = await apiClient.getWorkLocations();
        setState(() {
          _locations = locations;
        });
        apiClient.dispose();
      } catch (e) {
        // If backend fails, check for custom location
        final customLocation = await LocationConfig.getCustomLocation();
        if (customLocation != null) {
          setState(() {
            _locations = [customLocation];
          });
        } else {
          // Use default location
          setState(() {
            _locations = [LocationConfig.getDefaultLocation()];
          });
        }
      }
    } catch (e) {
      print('Error loading locations: $e');
      // Use default location as fallback
      setState(() {
        _locations = [LocationConfig.getDefaultLocation()];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddEditLocationScreen(),
      ),
    );

    if (result == true) {
      _loadLocations();
      // Refresh attendance service with new locations
      if (_attendanceService != null) {
        await _attendanceService!.refreshWorkLocations();
      }
    }
  }

  Future<void> _requestLocationSuggestion() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RequestLocationSuggestionScreen(),
      ),
    );

    if (result == true) {
      // Reload locations list in case admin has already approved something
      _loadLocations();
    }
  }

  Future<void> _openAdminSuggestions() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AdminLocationSuggestionsScreen(),
      ),
    );

    if (result == true) {
      // If any suggestion was approved, refresh work locations
      _loadLocations();
      if (_attendanceService != null) {
        await _attendanceService!.refreshWorkLocations();
      }
    }
  }

  Future<void> _editLocation(WorkLocation location) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditLocationScreen(location: location),
      ),
    );

    if (result == true) {
      _loadLocations();
      // Refresh attendance service with updated locations
      if (_attendanceService != null) {
        await _attendanceService!.refreshWorkLocations();
      }
    }
  }

  Future<void> _deleteLocation(WorkLocation location) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Location'),
        content: Text('Are you sure you want to delete "${location.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deleting location...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      try {
        // Try to delete from backend API first
        // Only delete from backend if location has a valid ID (not custom/default)
        if (location.id.isNotEmpty && 
            location.id != 'custom_location' && 
            location.id != 'default_office') {
          try {
            final apiClient = AttendanceApiClient(
              baseUrl: 'http://103.14.120.163:8092/api',
            );
            
            await apiClient.deleteLocation(location.id);
            apiClient.dispose();
            
            print('[LocationManagement] Location deleted from backend: ${location.id}');
          } catch (apiError) {
            print('API delete failed, continuing with local delete: $apiError');
            // Continue with local delete even if API fails
          }
        }

        // If it's custom location, clear it from local storage
        if (location.id == 'custom_location') {
          await LocationConfig.clearCustomLocation();
        }

        // Remove from local list
        setState(() {
          _locations.removeWhere((loc) => loc.id == location.id);
        });

        // Refresh attendance service
        if (_attendanceService != null) {
          await _attendanceService!.refreshWorkLocations();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting location: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Manage Locations',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF2563EB),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info Card
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _canManageLocations
                              ? 'When you reach any of these locations, automatic check-in will happen. You can add, edit, or delete locations.'
                              : 'When you reach any of these locations, automatic check-in will happen. Only HR and Admin can manage locations.',
                          style: TextStyle(
                            color: Colors.blue[900],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Location List
                Expanded(
                  child: _locations.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_off,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No locations added',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add a location to enable auto attendance',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _locations.length,
                          itemBuilder: (context, index) {
                            final location = _locations[index];
                            return _buildLocationCard(location);
                          },
                        ),
                ),

                // Add Location Button (Only for HR and Admin)
                if (_canManageLocations)
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: _addLocation,
                                icon: const Icon(Icons.add_location),
                                label: const Text(
                                  'Add New Location',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _openAdminSuggestions,
                                icon: const Icon(
                                  Icons.list_alt,
                                  size: 18,
                                ),
                                label: const Text('View Location Suggestions'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                // Suggest Location Button (Only for Employees)
                if (!_canManageLocations)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _requestLocationSuggestion,
                        icon: const Icon(Icons.add_location_alt),
                        label: const Text(
                          'Suggest New Location',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildLocationCard(WorkLocation location) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: _canManageLocations ? () => _editLocation(location) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                        Text(
                          location.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_canManageLocations)
                    PopupMenuButton(
                      icon: const Icon(Icons.more_vert, color: Colors.grey),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 20),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editLocation(location);
                      } else if (value == 'delete') {
                        _deleteLocation(location);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.radio_button_checked,
                      size: 16, color: Colors.green[600]),
                  const SizedBox(width: 6),
                  Text(
                    'Radius: ${location.radius.toStringAsFixed(0)} meters',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RequestLocationSuggestionScreen extends StatefulWidget {
  const RequestLocationSuggestionScreen({super.key});

  @override
  State<RequestLocationSuggestionScreen> createState() =>
      _RequestLocationSuggestionScreenState();
}

class _RequestLocationSuggestionScreenState
    extends State<RequestLocationSuggestionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _radiusController = TextEditingController(text: '100');
  final _notesController = TextEditingController();
  bool _isLoading = false;
  bool _isGettingCurrentLocation = false;

  @override
  void dispose() {
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingCurrentLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Location services are disabled. Please enable them.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permissions are denied.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Location permissions are permanently denied. Please enable in settings.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _latitudeController.text = position.latitude.toStringAsFixed(6);
        _longitudeController.text = position.longitude.toStringAsFixed(6);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Current location captured!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isGettingCurrentLocation = false;
      });
    }
  }

  Future<void> _submitSuggestion() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final name = _nameController.text.trim();
      final latitude = double.parse(_latitudeController.text);
      final longitude = double.parse(_longitudeController.text);
      final radius = double.parse(_radiusController.text);
      final notes = _notesController.text.trim();

      if (latitude < -90 || latitude > 90) {
        throw 'Latitude must be between -90 and 90';
      }
      if (longitude < -180 || longitude > 180) {
        throw 'Longitude must be between -180 and 180';
      }
      if (radius <= 0 || radius > 10000) {
        throw 'Radius must be between 1 and 10000 meters';
      }

      final apiClient = AttendanceApiClient(
        baseUrl: 'http://103.14.120.163:8092/api',
      );

      final message = await apiClient.suggestWorkLocation(
        name: name,
        latitude: latitude,
        longitude: longitude,
        radius: radius,
        notes: notes.isEmpty ? null : notes,
      );

      apiClient.dispose();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
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
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Suggest New Location',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF2563EB),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Yaha se aap nayi location suggest kar sakte ho. '
                        'Request admin ke paas jayegi, woh approve / reject karega.',
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Location Name',
                  hintText: 'e.g., Client Office - Sector 62',
                  prefixIcon: const Icon(Icons.business),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter location name';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed:
                      _isGettingCurrentLocation ? null : _getCurrentLocation,
                  icon: _isGettingCurrentLocation
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: Text(
                    _isGettingCurrentLocation
                        ? 'Getting Location...'
                        : 'Use Current Location',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    side: const BorderSide(color: Color(0xFF2563EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _latitudeController,
                decoration: InputDecoration(
                  labelText: 'Latitude',
                  hintText: 'e.g., 28.6201',
                  prefixIcon: const Icon(Icons.navigation),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter latitude';
                  }
                  final lat = double.tryParse(value);
                  if (lat == null) {
                    return 'Please enter a valid number';
                  }
                  if (lat < -90 || lat > 90) {
                    return 'Latitude must be between -90 and 90';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _longitudeController,
                decoration: InputDecoration(
                  labelText: 'Longitude',
                  hintText: 'e.g., 77.3822',
                  prefixIcon: const Icon(Icons.navigation),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter longitude';
                  }
                  final lng = double.tryParse(value);
                  if (lng == null) {
                    return 'Please enter a valid number';
                  }
                  if (lng < -180 || lng > 180) {
                    return 'Longitude must be between -180 and 180';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _radiusController,
                decoration: InputDecoration(
                  labelText: 'Radius (meters)',
                  hintText: 'e.g., 100',
                  prefixIcon: const Icon(Icons.radio_button_checked),
                  suffixText: 'meters',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  helperText:
                      'Distance from location center for auto check-in',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter radius';
                  }
                  final r = double.tryParse(value);
                  if (r == null) {
                    return 'Please enter a valid number';
                  }
                  if (r <= 0 || r > 10000) {
                    return 'Radius must be between 1 and 10000 meters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText:
                      'Yaha se daily kaam karta hu, please isko official location bana do.',
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.notes),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),

              const SizedBox(height: 32),

              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitSuggestion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Submit Suggestion',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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
}

class AdminLocationSuggestionsScreen extends StatefulWidget {
  const AdminLocationSuggestionsScreen({super.key});

  @override
  State<AdminLocationSuggestionsScreen> createState() =>
      _AdminLocationSuggestionsScreenState();
}

class _AdminLocationSuggestionsScreenState
    extends State<AdminLocationSuggestionsScreen> {
  bool _isLoading = true;
  bool _isActionLoading = false;
  List<LocationSuggestion> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final apiClient = AttendanceApiClient(
        baseUrl: 'http://103.14.120.163:8092/api',
      );
      final result = await apiClient.getLocationSuggestions(status: 'pending');
      apiClient.dispose();

      setState(() {
        _suggestions = result;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading suggestions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleDecision(
    LocationSuggestion suggestion,
    String status,
  ) async {
    final reasonController = TextEditingController();
    final isApprove = status == 'approved';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isApprove ? 'Approve Suggestion' : 'Reject Suggestion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isApprove
                  ? 'Is location ko approve karna hai?'
                  : 'Is location ko reject karna hai?'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  hintText: isApprove
                      ? 'Valid client site, official location me add kar rahe hai.'
                      : 'Location bahut door hai, abhi isko allow nahi karenge.',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(isApprove ? 'Approve' : 'Reject'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isActionLoading = true;
    });

    try {
      final apiClient = AttendanceApiClient(
        baseUrl: 'http://103.14.120.163:8092/api',
      );

      final result = await apiClient.decideLocationSuggestion(
        suggestionId: suggestion.id,
        status: status,
        reason: reasonController.text.trim().isEmpty
            ? null
            : reasonController.text.trim(),
      );

      apiClient.dispose();

      if (mounted) {
        final msg = result.createdLocation != null
            ? 'Suggestion approved and location created'
            : (status == 'rejected'
                ? 'Suggestion rejected'
                : 'Suggestion updated');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Remove processed suggestion from list
      setState(() {
        _suggestions.removeWhere((s) => s.id == suggestion.id);
      });

      // If list empty after action, pop with success so parent can refresh
      if (_suggestions.isEmpty && mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating suggestion: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActionLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Location Suggestions (Admin)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF2563EB),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _suggestions.isEmpty
              ? const Center(
                  child: Text('No pending suggestions'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final s = _suggestions[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563EB)
                                        .withOpacity(0.1),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.name,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1F2937),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${s.latitude.toStringAsFixed(6)}, ${s.longitude.toStringAsFixed(6)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      if (s.createdByName != null ||
                                          s.createdByEmail != null)
                                        Text(
                                          'By: ${s.createdByName ?? ''} (${s.createdByEmail ?? ''})',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Radius: ${s.radius.toStringAsFixed(0)} meters',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (s.notes != null && s.notes!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                s.notes!,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: _isActionLoading
                                      ? null
                                      : () => _handleDecision(
                                            s,
                                            'rejected',
                                          ),
                                  child: const Text(
                                    'Reject',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _isActionLoading
                                      ? null
                                      : () => _handleDecision(
                                            s,
                                            'approved',
                                          ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Approve'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class AddEditLocationScreen extends StatefulWidget {
  final WorkLocation? location;

  const AddEditLocationScreen({super.key, this.location});

  @override
  State<AddEditLocationScreen> createState() => _AddEditLocationScreenState();
}

class _AddEditLocationScreenState extends State<AddEditLocationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _radiusController = TextEditingController();
  bool _isLoading = false;
  bool _isGettingCurrentLocation = false;

  @override
  void initState() {
    super.initState();
    if (widget.location != null) {
      _nameController.text = widget.location!.name;
      _latitudeController.text = widget.location!.latitude.toStringAsFixed(6);
      _longitudeController.text = widget.location!.longitude.toStringAsFixed(6);
      _radiusController.text = widget.location!.radius.toStringAsFixed(0);
    } else {
      _radiusController.text = '100';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingCurrentLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled. Please enable them.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permissions are denied.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are permanently denied. Please enable in settings.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _latitudeController.text = position.latitude.toStringAsFixed(6);
        _longitudeController.text = position.longitude.toStringAsFixed(6);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Current location captured!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isGettingCurrentLocation = false;
      });
    }
  }

  Future<void> _saveLocation() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final name = _nameController.text.trim();
      final latitude = double.parse(_latitudeController.text);
      final longitude = double.parse(_longitudeController.text);
      final radius = double.parse(_radiusController.text);

      // Validate coordinates
      if (latitude < -90 || latitude > 90) {
        throw 'Latitude must be between -90 and 90';
      }
      if (longitude < -180 || longitude > 180) {
        throw 'Longitude must be between -180 and 180';
      }
      if (radius <= 0 || radius > 10000) {
        throw 'Radius must be between 1 and 10000 meters';
      }

      // Try to save to backend API first
      try {
        final apiClient = AttendanceApiClient(
          baseUrl: 'http://103.14.120.163:8092/api',
        );
        
        // Check if updating existing location
        final isUpdate = widget.location != null && widget.location!.id.isNotEmpty;
        final locationId = isUpdate ? widget.location!.id : null;
        
        print('[LocationManagement] Saving location - isUpdate: $isUpdate, locationId: $locationId');
        
        final savedLocation = await apiClient.saveLocation(
          name: name,
          latitude: latitude,
          longitude: longitude,
          radius: radius,
          locationId: locationId, // For update - will use PUT if provided
        );
        
        apiClient.dispose();

        // Also save to local storage as backup
        await LocationConfig.saveCustomLocation(
          latitude: savedLocation.latitude,
          longitude: savedLocation.longitude,
          radius: savedLocation.radius,
          name: savedLocation.name,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.location != null
                    ? 'Location updated successfully!'
                    : 'Location saved successfully!',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } catch (apiError) {
        // If API fails, still save locally as fallback
        print('API save failed, saving locally: $apiError');
        
        await LocationConfig.saveCustomLocation(
          latitude: latitude,
          longitude: longitude,
          radius: radius,
          name: name,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Location saved locally (API unavailable). ${apiError.toString()}',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          Navigator.pop(context, true);
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
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          widget.location != null ? 'Edit Location' : 'Add Location',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF2563EB),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Set your office location. When you reach within the radius, automatic check-in will happen.',
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Location Name
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Location Name',
                  hintText: 'e.g., Main Office, Branch Office',
                  prefixIcon: const Icon(Icons.business),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter location name';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Get Current Location Button
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _isGettingCurrentLocation ? null : _getCurrentLocation,
                  icon: _isGettingCurrentLocation
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: Text(_isGettingCurrentLocation
                      ? 'Getting Location...'
                      : 'Use Current Location'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    side: const BorderSide(color: Color(0xFF2563EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Latitude
              TextFormField(
                controller: _latitudeController,
                decoration: InputDecoration(
                  labelText: 'Latitude',
                  hintText: 'e.g., 22.3072',
                  prefixIcon: const Icon(Icons.navigation),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter latitude';
                  }
                  final lat = double.tryParse(value);
                  if (lat == null) {
                    return 'Please enter a valid number';
                  }
                  if (lat < -90 || lat > 90) {
                    return 'Latitude must be between -90 and 90';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Longitude
              TextFormField(
                controller: _longitudeController,
                decoration: InputDecoration(
                  labelText: 'Longitude',
                  hintText: 'e.g., 73.1812',
                  prefixIcon: const Icon(Icons.navigation),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter longitude';
                  }
                  final lng = double.tryParse(value);
                  if (lng == null) {
                    return 'Please enter a valid number';
                  }
                  if (lng < -180 || lng > 180) {
                    return 'Longitude must be between -180 and 180';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Radius
              TextFormField(
                controller: _radiusController,
                decoration: InputDecoration(
                  labelText: 'Radius (meters)',
                  hintText: 'e.g., 100',
                  prefixIcon: const Icon(Icons.radio_button_checked),
                  suffixText: 'meters',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  helperText: 'Distance from location center for auto check-in',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter radius';
                  }
                  final radius = double.tryParse(value);
                  if (radius == null) {
                    return 'Please enter a valid number';
                  }
                  if (radius <= 0 || radius > 10000) {
                    return 'Radius must be between 1 and 10000 meters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 32),

              // Save Button
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveLocation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          widget.location != null ? 'Update Location' : 'Save Location',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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
}

