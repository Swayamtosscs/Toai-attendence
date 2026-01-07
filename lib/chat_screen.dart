import 'package:flutter/material.dart';

import 'services/auth_api_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final AuthApiService _authApiService = AuthApiService();
  final TextEditingController _recipientController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  String? _errorMessage;
  String? _autoDetectedRecipientId; // Auto-detected recipient from conversation

  @override
  void initState() {
    super.initState();
    // Auto-load messages when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMessages();
    });
  }

  @override
  void dispose() {
    _authApiService.dispose();
    _recipientController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load all messages (userId is optional - if empty, fetch all)
      final userId = _recipientController.text.trim();
      final messages = await _authApiService.getChatMessages(
        userId: userId.isEmpty ? null : userId,
      );
      if (!mounted) return;
      // Sort messages by createdAt (oldest first for chat UI)
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      
      // Auto-detect recipient from conversation
      _autoDetectRecipient(messages);
      
      setState(() {
        _messages = messages;
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
        _errorMessage = 'Failed to load messages: $error';
        _isLoading = false;
      });
    }
  }

  // Auto-detect recipient from existing messages
  void _autoDetectRecipient(List<ChatMessage> messages) {
    final currentUser = AuthApiService.currentUser;
    if (currentUser == null || messages.isEmpty) {
      _autoDetectedRecipientId = null;
      return;
    }

    // Find the most recent conversation partner
    // If user sent a message, use recipient ID
    // If user received a message, use sender ID
    for (var message in messages.reversed) {
      if (message.sender.id == currentUser.id) {
        // User sent this message, so recipient is the other person
        _autoDetectedRecipientId = message.recipient.id;
        // Auto-populate recipient field
        if (_recipientController.text.trim().isEmpty) {
          _recipientController.text = message.recipient.id;
        }
        return;
      } else if (message.recipient.id == currentUser.id) {
        // User received this message, so sender is the other person
        _autoDetectedRecipientId = message.sender.id;
        // Auto-populate recipient field
        if (_recipientController.text.trim().isEmpty) {
          _recipientController.text = message.sender.id;
        }
        return;
      }
    }
    
    // If no conversation found, try to get recipient from filter field
    final filterRecipient = _recipientController.text.trim();
    if (filterRecipient.isNotEmpty) {
      _autoDetectedRecipientId = filterRecipient;
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a message')),
      );
      return;
    }

    // Auto-detect recipient: use manual input, auto-detected, or try to find from messages
    String? recipientId = _recipientController.text.trim();
    
    // If no manual recipient, use auto-detected one
    if ((recipientId.isEmpty) && _autoDetectedRecipientId != null) {
      recipientId = _autoDetectedRecipientId;
      _recipientController.text = recipientId!; // Update UI
    }
    
    // If still no recipient, try to find from existing messages
    if ((recipientId.isEmpty) && _messages.isNotEmpty) {
      final currentUser = AuthApiService.currentUser;
      if (currentUser != null) {
        // Find the most recent conversation partner
        for (var message in _messages.reversed) {
          if (message.sender.id == currentUser.id) {
            recipientId = message.recipient.id;
            break;
          } else if (message.recipient.id == currentUser.id) {
            recipientId = message.sender.id;
            break;
          }
        }
        if (recipientId != null && recipientId.isNotEmpty) {
          _autoDetectedRecipientId = recipientId;
          _recipientController.text = recipientId; // Update UI
        }
      }
    }

    // If still no recipient found, show error
    if (recipientId == null || recipientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to determine recipient. Please enter recipient ID or start a conversation first.')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final newMessage = await _authApiService.sendChatMessage(
        recipientId: recipientId,
        content: content,
      );
      if (!mounted) return;
      // Add new message and sort by date
      final updatedMessages = [..._messages, newMessage];
      updatedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      
      // Ensure recipient is set for future messages
      _autoDetectedRecipientId = recipientId;
      if (_recipientController.text.trim().isEmpty) {
        _recipientController.text = recipientId;
      }
      
      setState(() {
        _messages = updatedMessages;
        _isSending = false;
        _messageController.clear();
      });
    } on AuthApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthApiService.currentUser;
    return Scaffold(
      backgroundColor: Colors.white, // Pure white background
      appBar: AppBar(
        backgroundColor: Colors.white, // Pure white
        elevation: 0,
        title: Text(
          'Messages',
          style: TextStyle(color: const Color(0xFF111827), fontWeight: FontWeight.bold), // Near-black text
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: const Color(0xFF111827)), // Near-black icon
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: const Color(0xFF111827)), // Near-black icon
            onPressed: _isLoading ? null : _loadMessages,
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
              Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _recipientController,
                            style: TextStyle(color: const Color(0xFF111827)), // Near-black text
                            decoration: InputDecoration(
                              labelText: 'User ID (optional)',
                              labelStyle: TextStyle(color: const Color(0xFF6B7280)), // Medium gray
                              hintText: _autoDetectedRecipientId != null 
                                  ? 'Auto-detected: ${_autoDetectedRecipientId!.substring(0, _autoDetectedRecipientId!.length > 8 ? 8 : _autoDetectedRecipientId!.length)}...'
                                  : 'Enter User ID to filter messages, or leave empty for all',
                              hintStyle: TextStyle(color: const Color(0xFF9CA3AF), fontSize: 12), // Light gray
                              prefixIcon:
                                  Icon(Icons.person_outline, color: const Color(0xFF111827)), // Near-black icon
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB), // Very light gray background
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (value) {
                              // Update auto-detected when user manually changes
                              if (value.trim().isNotEmpty) {
                                _autoDetectedRecipientId = value.trim();
                              }
                            },
                          ),
                        ),
                        SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _loadMessages,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          icon: _isLoading
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Icon(Icons.refresh),
                          label: Text(
                            _isLoading ? 'Loading...' : 'Load',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    if (_errorMessage != null) ...[
                      SizedBox(height: 10),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF2563EB)), // Blue indicator
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chat_bubble_outline, 
                                    color: const Color(0xFF9CA3AF), size: 64), // Light gray icon
                                SizedBox(height: 16),
                                Text(
                                  'No messages yet',
                                  style: TextStyle(
                                    color: const Color(0xFF374151), // Dark gray text
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Tap "Load" to fetch messages\nor send a new message below',
                                  style: TextStyle(color: const Color(0xFF6B7280), fontSize: 12), // Medium gray
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            reverse: false, // Show oldest first, scroll to bottom for newest
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              final isCurrentUser =
                                  currentUser?.id == message.sender.id;
                              final otherUser = isCurrentUser 
                                  ? message.recipient 
                                  : message.sender;
                              return Align(
                                alignment: isCurrentUser
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: EdgeInsets.symmetric(vertical: 6),
                                  padding: EdgeInsets.all(12),
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width * 0.75,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isCurrentUser
                                        ? const Color(0xFF2563EB) // Blue for current user
                                        : const Color(0xFFF3F4F6), // Light gray for other user
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              isCurrentUser
                                                  ? 'You → ${otherUser.name.isNotEmpty ? otherUser.name : "Unknown"}'
                                                  : '${message.sender.name.isNotEmpty ? message.sender.name : "Unknown"} → You',
                                              style: TextStyle(
                                                color: isCurrentUser ? Colors.white : const Color(0xFF374151), // White on blue, dark gray on light
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          if (!message.read && !isCurrentUser)
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF2563EB), // Blue dot
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        message.content,
                                        style: TextStyle(
                                          color: isCurrentUser ? Colors.white : const Color(0xFF111827), // White on blue, near-black on light
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        _formatTimestamp(message.createdAt),
                                        style: TextStyle(
                                          color: isCurrentUser ? Colors.white70 : const Color(0xFF6B7280), // White70 on blue, medium gray on light
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white, // Pure white
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05), // Subtle shadow
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        style: TextStyle(color: const Color(0xFF111827)), // Near-black text
                        decoration: InputDecoration(
                          hintText: 'Type your message...',
                          hintStyle: TextStyle(color: const Color(0xFF9CA3AF)), // Light gray hint
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB), // Very light gray background
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(color: Color(0xFFE5E7EB)), // Light gray border
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        minLines: 1,
                        maxLines: 4,
                      ),
                    ),
                    SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _isSending ? null : _sendMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB), // Blue button
                        foregroundColor: Colors.white,
                        shape: CircleBorder(),
                        padding: EdgeInsets.all(14),
                      ),
                      child: _isSending
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    final local = dateTime.toLocal();
    final date = '${local.day}/${local.month}/${local.year}';
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minutes = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$date · $hour:$minutes $period';
  }
}

