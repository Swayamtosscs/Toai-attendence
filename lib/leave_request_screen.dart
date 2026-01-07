import 'package:flutter/material.dart';
import 'services/auth_api_service.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final AuthApiService _authApiService = AuthApiService();
  
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedType = 'casual';
  bool _isSubmitting = false;
  
  final List<String> _leaveTypes = ['casual', 'sick', 'personal', 'vacation', 'emergency'];

  @override
  void dispose() {
    _authApiService.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 365)),
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
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          _endDate = null;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select start date first')),
      );
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate!,
      firstDate: _startDate!,
      lastDate: DateTime.now().add(Duration(days: 365)),
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
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.black54), // Dark gray label
      prefixIcon: Icon(icon, color: Colors.black87), // Black icon
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: const Color(0xFFE5E7EB)), // Light gray border
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: const Color(0xFFE5E7EB)), // Light gray border
      ),
      filled: true,
      fillColor: Colors.white, // White background
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: const Color(0xFF2563EB), width: 2), // Blue border when focused
      ),
    );
  }

  Future<void> _submitLeaveRequest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select both start and end dates')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final request = LeaveRequest(
        startDate: _startDate!,
        endDate: _endDate!,
        type: _selectedType,
        reason: _reasonController.text.trim(),
      );

      final response = await _authApiService.submitLeaveRequest(request);
      
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Leave request submitted successfully! Status: ${response.status.toUpperCase()}'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } on AuthApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit leave request: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          'Request Leave',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold), // Black text
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.white, // Pure white - no gradient
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fill in the details to request leave',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black87, // Dark gray text
                    ),
                  ),
                  SizedBox(height: 25),
                  
                  // Start Date
                  Text(
                    'Start Date',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87, // Dark gray text
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  InkWell(
                    onTap: _selectStartDate,
                    child: Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white, // White background
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: const Color(0xFFE5E7EB)), // Light gray border
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: Colors.black87), // Black icon
                          SizedBox(width: 12),
                          Text(
                            _startDate == null
                                ? 'Select start date'
                                : '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}',
                            style: TextStyle(
                              color: Colors.black, // Black text
                              fontSize: 16,
                            ),
                          ),
                          Spacer(),
                          Icon(Icons.arrow_forward_ios, color: Colors.black87, size: 16), // Black icon
                        ],
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  // End Date
                  Text(
                    'End Date',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87, // Dark gray text
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  InkWell(
                    onTap: _selectEndDate,
                    child: Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white, // White background
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: const Color(0xFFE5E7EB)), // Light gray border
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: Colors.black87), // Black icon
                          SizedBox(width: 12),
                          Text(
                            _endDate == null
                                ? 'Select end date'
                                : '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}',
                            style: TextStyle(
                              color: Colors.black, // Black text
                              fontSize: 16,
                            ),
                          ),
                          Spacer(),
                          Icon(Icons.arrow_forward_ios, color: Colors.black87, size: 16), // Black icon
                        ],
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Leave Type
                  Text(
                    'Leave Type',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87, // Dark gray text
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedType,
                    dropdownColor: Colors.white, // White dropdown background
                    decoration: _inputDecoration('Select leave type', Icons.category_outlined),
                    items: _leaveTypes
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(
                              type.toUpperCase(),
                              style: TextStyle(color: Colors.black), // Black text
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedType = value);
                      }
                    },
                    style: TextStyle(color: Colors.black), // Black text
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Reason
                  TextFormField(
                    controller: _reasonController,
                    maxLines: 4,
                    style: TextStyle(color: Colors.black), // Black text
                    decoration: _inputDecoration('Reason for leave', Icons.description_outlined),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please provide a reason';
                      }
                      return null;
                    },
                  ),
                  
                  SizedBox(height: 30),
                  
                  // Submit Button
                  Container(
                    width: double.infinity,
                    height: 55,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [const Color(0xFF2563EB), const Color(0xFF3B82F6)], // Blue gradient
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withOpacity(0.3), // Blue shadow
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitLeaveRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _isSubmitting
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white), // White spinner
                              ),
                            )
                          : Text(
                              'Submit Leave Request',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white, // White text on blue button
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

