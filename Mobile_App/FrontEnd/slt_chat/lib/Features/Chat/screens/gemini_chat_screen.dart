/* import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '/common/widgets/colors.dart';
import '../../../service/local_db_helper.dart';

class GeminiChatScreen extends StatefulWidget {
  const GeminiChatScreen({Key? key}) : super(key: key);

  @override
  _GeminiChatScreenState createState() => _GeminiChatScreenState();
}

class _GeminiChatScreenState extends State<GeminiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, String>> messages = [];
  final LocalDBHelper _dbHelper = LocalDBHelper();
  bool _isOnline = true;
  final List<Map<String, String>> _pendingMessages = [];

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _loadCachedMessages();
  }

  Future<void> _checkConnectivity() async {
    // You might want to use connectivity_plus package for more robust checks
    try {
      final response = await http.get(Uri.parse('https://www.google.com'));
      setState(() {
        _isOnline = response.statusCode == 200;
      });
    } catch (e) {
      setState(() {
        _isOnline = false;
      });
    }
  }

  Future<void> _loadCachedMessages() async {
    try {
      // Load cached AI responses
      final cachedMessages = await _dbHelper.getCachedAIMessages();
      setState(() {
        messages.addAll(cachedMessages);
      });

      // Load any pending messages that failed to send
      final pending = await _dbHelper.getPendingAIMessages();
      setState(() {
        _pendingMessages.addAll(pending);
      });
    } catch (e) {
      debugPrint('Error loading cached messages: $e');
    }
  }

  Future<void> sendMessage(String userMessage) async {
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();

    // Add message to UI immediately
    setState(() {
      messages.add({
        "role": "user",
        "text": userMessage,
        "id": messageId,
        "status": _isOnline ? "sent" : "pending",
      });
    });

    // Save to local DB
    await _dbHelper.saveAIMessage({
      "id": messageId,
      "role": "user",
      "text": userMessage,
      "timestamp": DateTime.now().toIso8601String(),
      "status": _isOnline ? "sent" : "pending",
    });

    if (_isOnline) {
      await _sendToAPI(userMessage, messageId);
    } else {
      // Store for later sync
      setState(() {
        _pendingMessages.add({
          "id": messageId,
          "text": userMessage,
          "role": "user",
        });
      });

      // Show offline response
      _showOfflineResponse(messageId);
    }
  }

  Future<void> _sendToAPI(String userMessage, String messageId) async {
    const String apiKey = "AIzaSyCkrrWwz61WqRghasmSF-kita-nWQwINH0";
    const String endpoint =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey";

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": userMessage},
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String aiResponse =
            data["candidates"]?[0]?["content"]?["parts"]?[0]?["text"] ??
            "No response from AI";

        // Update message status to delivered
        await _dbHelper.updateAIMessageStatus(messageId, "delivered");

        // Save AI response
        final aiMessageId = 'ai_${DateTime.now().millisecondsSinceEpoch}';
        await _dbHelper.saveAIMessage({
          "id": aiMessageId,
          "role": "ai",
          "text": aiResponse,
          "timestamp": DateTime.now().toIso8601String(),
          "status": "delivered",
          "related_message_id": messageId,
        });

        setState(() {
          messages.add({
            "role": "ai",
            "text": aiResponse,
            "id": aiMessageId,
            "status": "delivered",
          });
        });
      } else {
        await _dbHelper.updateAIMessageStatus(messageId, "failed");
        setState(() {
          messages.add({
            "role": "ai",
            "text": "API Error: ${response.statusCode}",
            "id": "error_${DateTime.now().millisecondsSinceEpoch}",
            "status": "failed",
          });
        });
      }
    } catch (e) {
      await _dbHelper.updateAIMessageStatus(messageId, "failed");
      setState(() {
        messages.add({
          "role": "ai",
          "text": "Error: $e",
          "id": "error_${DateTime.now().millisecondsSinceEpoch}",
          "status": "failed",
        });
      });
    }
  }

  Future<void> _showOfflineResponse(String messageId) async {
    // Simple offline responses
    final offlineResponses = [
      "I'll respond when you're back online.",
      "I've saved your message for when you reconnect.",
      "You're offline right now - I'll help when you're back online.",
      "Message saved. I'll respond when internet is available.",
    ];

    final randomResponse =
        offlineResponses[DateTime.now().second % offlineResponses.length];

    final aiMessageId = 'offline_${DateTime.now().millisecondsSinceEpoch}';
    await _dbHelper.saveAIMessage({
      "id": aiMessageId,
      "role": "ai",
      "text": randomResponse,
      "timestamp": DateTime.now().toIso8601String(),
      "status": "offline",
      "related_message_id": messageId,
    });

    setState(() {
      messages.add({
        "role": "ai",
        "text": randomResponse,
        "id": aiMessageId,
        "status": "offline",
      });
    });
  }

  Future<void> _retryPendingMessages() async {
    if (_pendingMessages.isEmpty) return;

    setState(() {
      _isOnline = true;
    });

    for (var message in _pendingMessages) {
      await _sendToAPI(message["text"]!, message["id"]!);
    }

    setState(() {
      _pendingMessages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
        backgroundColor: backgroundColor,
        actions: [
          IconButton(
            icon: Icon(_isOnline ? Icons.cloud : Icons.cloud_off),
            onPressed: _checkConnectivity,
            tooltip: _isOnline ? 'Online' : 'Offline',
          ),
          if (!_isOnline && _pendingMessages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _retryPendingMessages,
              tooltip: 'Retry sending',
            ),
        ],
      ),
      body: Container(
        color: backgroundColor,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final isUser = message["role"] == "user";
                  final isPending = message["status"] == "pending";
                  final isFailed = message["status"] == "failed";
                  final isOffline = message["status"] == "offline";

                  return Column(
                    children: [
                      Align(
                        alignment:
                            isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.symmetric(
                            vertical: 5,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isUser
                                    ? (isPending
                                        ? Colors.blue[200]
                                        : isFailed
                                        ? Colors.orange[300]
                                        : Colors.blue[300])
                                    : const Color.fromARGB(255, 72, 72, 72),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                isUser
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                            children: [
                              Text(
                                message["text"] ?? "",
                                style: const TextStyle(color: Colors.white),
                              ),
                              if (isPending || isFailed || isOffline)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    isPending
                                        ? 'Sending...'
                                        : isFailed
                                        ? 'Failed to send'
                                        : 'Offline',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              decoration: const InputDecoration(
                                hintText: "Ask Anything",
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              maxLines: null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: _isOnline ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_upward, color: Colors.white),
                      onPressed: () {
                        if (_controller.text.isNotEmpty) {
                          sendMessage(_controller.text);
                          _controller.clear();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
 */

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart'; // Import intl package for date formatting
import '/common/widgets/colors.dart';
import '../../../service/local_db_helper.dart';

class GeminiChatScreen extends StatefulWidget {
  const GeminiChatScreen({Key? key}) : super(key: key);

  @override
  _GeminiChatScreenState createState() => _GeminiChatScreenState();
}

class _GeminiChatScreenState extends State<GeminiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> messages =
      []; // Changed to dynamic to hold timestamp
  final LocalDBHelper _dbHelper = LocalDBHelper();
  bool _isOnline = true;
  final List<Map<String, String>> _pendingMessages = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _loadCachedMessages();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _checkConnectivity() async {
    // You might want to use connectivity_plus package for more robust checks
    try {
      final response = await http.get(Uri.parse('https://www.google.com'));
      setState(() {
        _isOnline = response.statusCode == 200;
      });
    } catch (e) {
      setState(() {
        _isOnline = false;
      });
    }
  }

  Future<void> _loadCachedMessages() async {
    try {
      // Load cached AI responses
      final cachedMessages = await _dbHelper.getCachedAIMessages();
      setState(() {
        messages.addAll(
          cachedMessages.map(
            (message) =>
                message..addAll({'timestamp': message['timestamp'] ?? ''}),
          ),
        );
      });
      _scrollToBottom(); // Scroll to the bottom after loading initial messages

      // Load any pending messages that failed to send
      final pending = await _dbHelper.getPendingAIMessages();
      setState(() {
        _pendingMessages.addAll(pending);
      });
    } catch (e) {
      debugPrint('Error loading cached messages: $e');
    }
  }

  Future<void> sendMessage(String userMessage) async {
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    final timestamp = DateTime.now().toIso8601String();

    // Add message to UI immediately
    setState(() {
      messages.add({
        "role": "user",
        "text": userMessage,
        "id": messageId,
        "status": _isOnline ? "sent" : "pending",
        "timestamp": timestamp,
      });
    });
    _scrollToBottom();
    // Save to local DB
    await _dbHelper.saveAIMessage({
      "id": messageId,
      "role": "user",
      "text": userMessage,
      "timestamp": timestamp,
      "status": _isOnline ? "sent" : "pending",
    });

    if (_isOnline) {
      await _sendToAPI(userMessage, messageId);
    } else {
      // Store for later sync
      setState(() {
        _pendingMessages.add({
          "id": messageId,
          "text": userMessage,
          "role": "user",
        });
      });

      // Show offline response
      _showOfflineResponse(messageId);
    }
  }

  Future<void> _sendToAPI(String userMessage, String messageId) async {
    const String apiKey = "AIzaSyCkrrWwz61WqRghasmSF-kita-nWQwINH0";
    const String endpoint =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey";

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": userMessage},
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String aiResponse =
            data["candidates"]?[0]?["content"]?["parts"]?[0]?["text"] ??
            "No response from AI";
        final aiTimestamp = DateTime.now().toIso8601String();

        // Update message status to delivered
        await _dbHelper.updateAIMessageStatus(messageId, "delivered");

        // Save AI response
        final aiMessageId = 'ai_${DateTime.now().millisecondsSinceEpoch}';
        await _dbHelper.saveAIMessage({
          "id": aiMessageId,
          "role": "ai",
          "text": aiResponse,
          "timestamp": aiTimestamp,
          "status": "delivered",
          "related_message_id": messageId,
        });

        setState(() {
          messages.add({
            "role": "ai",
            "text": aiResponse,
            "id": aiMessageId,
            "status": "delivered",
            "timestamp": aiTimestamp,
          });
        });
      } else {
        await _dbHelper.updateAIMessageStatus(messageId, "failed");
        final errorTimestamp = DateTime.now().toIso8601String();
        setState(() {
          messages.add({
            "role": "ai",
            "text": "API Error: ${response.statusCode}",
            "id": "error_${DateTime.now().millisecondsSinceEpoch}",
            "status": "failed",
            "timestamp": errorTimestamp,
          });
        });
      }
    } catch (e) {
      await _dbHelper.updateAIMessageStatus(messageId, "failed");
      final errorTimestamp = DateTime.now().toIso8601String();
      setState(() {
        messages.add({
          "role": "ai",
          "text": "Error: $e",
          "id": "error_${DateTime.now().millisecondsSinceEpoch}",
          "status": "failed",
          "timestamp": errorTimestamp,
        });
      });
    }
  }

  Future<void> _showOfflineResponse(String messageId) async {
    // Simple offline responses
    final offlineResponses = [
      "I'll respond when you're back online.",
      "I've saved your message for when you reconnect.",
      "You're offline right now - I'll help when you're back online.",
      "Message saved. I'll respond when internet is available.",
    ];

    final randomResponse =
        offlineResponses[DateTime.now().second % offlineResponses.length];
    final offlineTimestamp = DateTime.now().toIso8601String();

    final aiMessageId = 'offline_${DateTime.now().millisecondsSinceEpoch}';
    await _dbHelper.saveAIMessage({
      "id": aiMessageId,
      "role": "ai",
      "text": randomResponse,
      "timestamp": offlineTimestamp,
      "status": "offline",
      "related_message_id": messageId,
    });

    setState(() {
      messages.add({
        "role": "ai",
        "text": randomResponse,
        "id": aiMessageId,
        "status": "offline",
        "timestamp": offlineTimestamp,
      });
    });
  }

  Future<void> _retryPendingMessages() async {
    if (_pendingMessages.isEmpty) return;

    setState(() {
      _isOnline = true;
    });

    for (var message in _pendingMessages) {
      await _sendToAPI(message["text"]!, message["id"]!);
    }

    setState(() {
      _pendingMessages.clear();
    });
  }

  String _getMessageTime(String timestamp) {
    final dateTime = DateTime.parse(timestamp).toLocal();
    return DateFormat('hh:mm a').format(dateTime);
  }

  String _getMessageDayLabel(String timestamp) {
    final messageDate = DateTime.parse(timestamp).toLocal().toLocal();
    final now = DateTime.now().toLocal();
    final yesterday = now.subtract(const Duration(days: 1));

    if (messageDate.year == now.year &&
        messageDate.month == now.month &&
        messageDate.day == now.day) {
      return 'Today';
    } else if (messageDate.year == yesterday.year &&
        messageDate.month == yesterday.month &&
        messageDate.day == yesterday.day) {
      return 'Yesterday';
    } else {
      return DateFormat('dd MMM yyyy').format(messageDate);
    }
  }

  bool _isSameDay(int index) {
    if (index == 0) return false;
    final currentDate = DateTime.parse(messages[index]['timestamp']).toLocal();
    final previousDate =
        DateTime.parse(messages[index - 1]['timestamp']).toLocal();
    return currentDate.year == previousDate.year &&
        currentDate.month == previousDate.month &&
        currentDate.day == previousDate.day;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI Assistant',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 28,
          ),
        ),
        backgroundColor: backgroundColor,
        actions: [
          IconButton(
            icon: Icon(_isOnline ? Icons.cloud : Icons.cloud_off),
            onPressed: _checkConnectivity,
            tooltip: _isOnline ? 'Online' : 'Offline',
          ),
          if (!_isOnline && _pendingMessages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _retryPendingMessages,
              tooltip: 'Retry sending',
            ),
        ],
      ),
      body: Container(
        color: backgroundColor,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final isUser = message["role"] == "user";
                  final isPending = message["status"] == "pending";
                  final isFailed = message["status"] == "failed";
                  final isOffline = message["status"] == "offline";
                  final timestamp = message["timestamp"] as String;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (index == 0 || !_isSameDay(index))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Center(
                            child: Container(
                              decoration: BoxDecoration(
                                color:
                                    Colors
                                        .grey[300], // Choose your desired background color
                                borderRadius: BorderRadius.circular(
                                  10.0,
                                ), // Adjust the radius for desired roundness
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                                vertical: 4.0,
                              ), // Add some padding
                              child: Text(
                                _getMessageDayLabel(timestamp),
                                style: TextStyle(
                                  color:
                                      Colors
                                          .black87, // Adjust text color for better visibility
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Align(
                        alignment:
                            isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.symmetric(
                            vertical: 5,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isUser
                                    ? (isPending
                                        ? Colors.blue[200]
                                        : isFailed
                                        ? Colors.orange[300]
                                        : Colors.blue[300])
                                    : const Color.fromARGB(255, 72, 72, 72),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                isUser
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                            children: [
                              Text(
                                message["text"] ?? "",
                                style: const TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isPending || isFailed || isOffline)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        right: 4.0,
                                      ),
                                      child: Icon(
                                        isPending
                                            ? Icons.schedule
                                            : isFailed
                                            ? Icons.error_outline
                                            : Icons.cloud_off_outlined,
                                        color: Colors.white.withOpacity(0.7),
                                        size: 12,
                                      ),
                                    ),
                                  Text(
                                    _getMessageTime(timestamp),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              decoration: const InputDecoration(
                                hintText: "Ask Anything",
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              maxLines: null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: _isOnline ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_upward, color: Colors.white),
                      onPressed: () {
                        if (_controller.text.isNotEmpty) {
                          sendMessage(_controller.text);
                          _controller.clear();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
