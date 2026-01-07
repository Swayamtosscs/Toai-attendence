import 'package:flutter/material.dart';
import 'services/auth_api_service.dart';

class LeaveListScreen extends StatefulWidget {
  const LeaveListScreen({super.key});

  @override
  State<LeaveListScreen> createState() => _LeaveListScreenState();
}

class _LeaveListScreenState extends State<LeaveListScreen> {
  final AuthApiService _authApiService = AuthApiService();
  List<LeaveListItem> _leaves = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLeaves();
  }

  @override
  void dispose() {
    _authApiService.dispose();
    super.dispose();
  }

  Future<void> _loadLeaves() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final leaves = await _authApiService.getLeaveList();
      if (!mounted) return;
      setState(() {
        _leaves = leaves;
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
        _errorMessage = 'Failed to load leaves: $error';
        _isLoading = false;
      });
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'casual':
        return Colors.blue;
      case 'sick':
        return Colors.red;
      case 'vacation':
        return Colors.purple;
      case 'personal':
        return Colors.orange;
      case 'emergency':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  bool _canManageLeave(LeaveListItem leave) {
    final currentUser = AuthApiService.currentUser;
    if (currentUser == null) return false;
    
    // Check if leave is pending
    final isPending = leave.status.toLowerCase() == 'pending';
    if (!isPending) return false;
    
    // Only admin can manage (approve/reject) leaves
    return currentUser.role.toLowerCase() == 'admin';
  }

  Future<void> _approveLeave(LeaveListItem leave) async {
    // Ensure only admin can approve leaves
    final currentUser = AuthApiService.currentUser;
    if (currentUser == null || currentUser.role.toLowerCase() != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Only admin can approve leaves'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final reply = await _showReplyDialog(context, 'Approve Leave');
    if (reply == null) return; // User cancelled

    try {
      await _authApiService.updateLeaveStatus(
        leaveId: leave.id,
        status: 'approved',
        reply: reply.isEmpty ? null : reply,
      );
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Leave approved successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
      _loadLeaves();
    } on AuthApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to approve leave: $error')),
      );
    }
  }

  Future<void> _rejectLeave(LeaveListItem leave) async {
    // Ensure only admin can reject leaves
    final currentUser = AuthApiService.currentUser;
    if (currentUser == null || currentUser.role.toLowerCase() != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Only admin can reject leaves'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final reply = await _showReplyDialog(context, 'Reject Leave');
    if (reply == null) return; // User cancelled

    try {
      await _authApiService.updateLeaveStatus(
        leaveId: leave.id,
        status: 'rejected',
        reply: reply.isEmpty ? null : reply,
      );
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Leave rejected'),
          backgroundColor: Colors.red,
        ),
      );
      
      _loadLeaves();
    } on AuthApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reject leave: $error')),
      );
    }
  }

  Future<String?> _showReplyDialog(BuildContext context, String title) async {
    final replyController = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
        backgroundColor: Colors.white, // White background
        title: Text(
          title,
          style: TextStyle(color: Colors.black), // Black text
        ),
        content: TextField(
          controller: replyController,
          style: TextStyle(color: Colors.black), // Black text
          decoration: InputDecoration(
            labelText: 'Reply (optional)',
            labelStyle: TextStyle(color: Colors.black54), // Dark gray label
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: const Color(0xFF2563EB)), // Blue border when focused
            ),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.black87)), // Dark gray text
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, replyController.text.trim());
            },
            child: Text('Confirm', style: TextStyle(color: const Color(0xFF2563EB))), // Blue text
          ),
        ],
      );
      },
    ).then((value) {
      replyController.dispose();
      return value;
    });
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
          'My Leaves',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold), // Black text
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.black), // Black icon
            onPressed: _loadLeaves,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.white, // Pure white - no gradient
        ),
        child: SafeArea(
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
                            onPressed: _loadLeaves,
                            child: Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _leaves.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.event_busy, color: Colors.grey, size: 50),
                              SizedBox(height: 20),
                              Text(
                                'No leave requests found',
                                style: TextStyle(color: Colors.black87), // Dark gray text
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadLeaves,
                          color: const Color(0xFF2563EB), // Blue refresh indicator
                          child: ListView.builder(
                            padding: EdgeInsets.all(20),
                            itemCount: _leaves.length,
                            itemBuilder: (context, index) {
                              final leave = _leaves[index];
                              final days = leave.endDate.difference(leave.startDate).inDays + 1;
                              
                              return Container(
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
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${_formatDate(leave.startDate)} - ${_formatDate(leave.endDate)}',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black, // Black text
                                                ),
                                              ),
                                              SizedBox(height: 5),
                                              Text(
                                                '$days ${days == 1 ? 'day' : 'days'}',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.black87, // Dark gray text
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(leave.status).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: _getStatusColor(leave.status),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            leave.status.toUpperCase(),
                                            style: TextStyle(
                                              color: _getStatusColor(leave.status),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 15),
                                    Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: _getTypeColor(leave.type).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            leave.type.toUpperCase(),
                                            style: TextStyle(
                                              color: _getTypeColor(leave.type),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        if (leave.manager.name.isNotEmpty)
                                          Container(
                                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF3F4F6), // Light gray background
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.person, color: Colors.black87, size: 14), // Black icon
                                                SizedBox(width: 5),
                                                Text(
                                                  'Manager: ${leave.manager.name}',
                                                  style: TextStyle(
                                                    color: Colors.black87, // Dark gray text
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (leave.reason.isNotEmpty) ...[
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
                                            Icon(Icons.description, color: Colors.black87, size: 18), // Black icon
                                            SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                leave.reason,
                                                style: TextStyle(
                                                  color: Colors.black87, // Dark gray text
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (_canManageLeave(leave)) ...[
                                      SizedBox(height: 15),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: () => _approveLeave(leave),
                                              icon: Icon(Icons.check, size: 18),
                                              label: Text('Approve'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                foregroundColor: Colors.white,
                                                padding: EdgeInsets.symmetric(vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: () => _rejectLeave(leave),
                                              icon: Icon(Icons.close, size: 18),
                                              label: Text('Reject'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                foregroundColor: Colors.white,
                                                padding: EdgeInsets.symmetric(vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    SizedBox(height: 10),
                                    Text(
                                      'Requested on ${_formatDate(leave.createdAt)}',
                                      style: TextStyle(
                                        color: Colors.black87, // Dark gray text
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ),
    );
  }
}

