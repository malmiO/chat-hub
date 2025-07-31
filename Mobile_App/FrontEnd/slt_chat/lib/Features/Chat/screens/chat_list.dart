/* import 'package:provider/provider.dart';
import '/common/widgets/colors.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'chat_screen.dart';
import 'package:slt_chat/config/config.dart';
import 'package:http/io_client.dart';
import 'dart:io';
import 'package:slt_chat/service/connectivity_service.dart';
import 'package:slt_chat/service/local_db_helper.dart';

class ChatList extends StatefulWidget {
  final String userId;

  const ChatList({Key? key, required this.userId}) : super(key: key);

  @override
  _ChatListState createState() => _ChatListState();
}

class _ChatListState extends State<ChatList> {
  List<Map<String, dynamic>> chats = [];
  bool isLoading = true;
  late LocalDBHelper localDB;
  late ConnectivityService connectivityService;
  Set<int> selectedChats = {};
  bool isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    localDB = LocalDBHelper();
    final connectivity = Provider.of<ConnectivityService>(
      context,
      listen: false,
    );
    connectivityService = Provider.of<ConnectivityService>(
      context,
      listen: false,
    );
    _loadChats();
  }

  /*   Future<void> _loadChats() async {
    // First try to load from local DB
    final localChats = await localDB.getChats();

    if (localChats.isNotEmpty) {
      setState(() {
        chats = localChats;
        isLoading = false;
      });
    }

    // Then try to fetch from server if online
    if (connectivityService.isOnline) {
      await _fetchChats();
    } else {
      setState(() => isLoading = false);
    }
  } */

  Future<void> _loadChats() async {
    // Always load from local DB first for instant display
    final localChats = await localDB.getChats();
    if (mounted) {
      setState(() {
        chats = localChats;
        isLoading = false;
      });
    }

    // Then try to fetch from server if online (silent update)
    if (connectivityService.isOnline) {
      await _fetchChats();
    }
  }

  Future<void> _fetchChats() async {
    try {
      final httpClient =
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true;

      final ioClient = IOClient(httpClient);
      final response = await ioClient.get(
        Uri.parse('${AppConfig.baseUrl}/chats/${widget.userId}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final serverChats = List<Map<String, dynamic>>.from(data['chats']);

        // Enhance with online status if available
        for (var chat in serverChats) {
          chat['is_online'] = chat['is_online'] ?? false;
          chat['last_seen'] =
              chat['last_seen'] ?? DateTime.now().toIso8601String();
        }

        // Only update UI if data has changed
        if (!_areListsEqual(chats, serverChats) && mounted) {
          setState(() {
            chats = serverChats;
          });
        }

        // Always save to local DB
        await localDB.saveChats(serverChats);
      }
    } catch (e) {
      print("Error fetching chats: $e");
    }
  }

  Future<void> _deleteChats() async {
    if (selectedChats.isEmpty) return;

    try {
      if (connectivityService.isOnline) {
        final httpClient =
            HttpClient()
              ..badCertificateCallback =
                  (X509Certificate cert, String host, int port) => true;
        final ioClient = IOClient(httpClient);

        for (int index in selectedChats) {
          final chat = chats[index];
          final response = await ioClient.delete(
            Uri.parse(
              '${AppConfig.baseUrl}/chats/${widget.userId}/${chat['partner_id']}',
            ),
          );

          if (response.statusCode != 200) {
            throw Exception('Failed to delete chat on server');
          }
        }
      }

      // Delete locally
      for (int index in selectedChats) {
        final chat = chats[index];
        await localDB.deleteChat(chat['chat_id']);
      }

      // Refresh chats
      setState(() {
        chats =
            chats
                .asMap()
                .entries
                .where((entry) => !selectedChats.contains(entry.key))
                .map((entry) => entry.value)
                .toList();
        selectedChats.clear();
        isSelectionMode = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chats deleted successfully')),
      );
    } catch (e) {
      print("Error deleting chats: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to delete chats')));
    }
  }

  bool _areListsEqual(
    List<Map<String, dynamic>> list1,
    List<Map<String, dynamic>> list2,
  ) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (!_areMapsEqual(list1[i], list2[i])) return false;
    }
    return true;
  }

  bool _areMapsEqual(Map<String, dynamic> map1, Map<String, dynamic> map2) {
    if (map1.length != map2.length) return false;
    for (final key in map1.keys) {
      if (map1[key] != map2[key]) return false;
    }
    return true;
  }

  String _formatTime(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(now.year, now.month, now.day - 1);

      final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

      if (messageDate == today) {
        return '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
      } else if (messageDate == yesterday) {
        return 'Yesterday';
      } else {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      }
    } catch (e) {
      return timestamp;
    }
  }

  String _formatLastSeen(String timestamp) {
    try {
      final lastSeen = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(lastSeen);

      if (difference.inMinutes < 1) return 'just now';
      if (difference.inHours < 1) return '${difference.inMinutes} min ago';
      if (difference.inDays < 1) return '${difference.inHours} hours ago';
      return '${difference.inDays} days ago';
    } catch (e) {
      return timestamp;
    }
  }

  String getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length > 1) {
      return parts[0][0].toUpperCase() + parts[1][0].toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '';
  }

  Widget _buildOnlineStatus(Map<String, dynamic> chat) {
    final isOnline = chat['is_online'] == true || chat['is_online'] == 1;
    final lastSeen = chat['last_seen'];

    if (isOnline) {
      return const Text(
        'Online',
        style: TextStyle(color: Colors.green, fontSize: 12),
      );
    } else if (lastSeen != null) {
      return Text(
        'Last seen ${_formatLastSeen(lastSeen)}',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      );
    }
    return const SizedBox.shrink();
  }

  String _capitalizeEachWord(String text) {
    return text
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  void _toggleSelection(int index) {
    setState(() {
      if (selectedChats.contains(index)) {
        selectedChats.remove(index);
        if (selectedChats.isEmpty) isSelectionMode = false;
      } else {
        selectedChats.add(index);
        isSelectionMode = true;
      }
    });
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: backgroundColor,
            title: Text(
              'Delete ${selectedChats.length} chat${selectedChats.length > 1 ? 's' : ''}?',
              style: const TextStyle(color: Colors.white),
            ),
            content: const Text(
              'This will delete the selected chats and their messages.',
              style: TextStyle(color: Colors.grey),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteChats();
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Chats', style: TextStyle(color: Colors.white)),
        backgroundColor: backgroundColor,
        actions: [
          if (isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _showDeleteConfirmation,
            ),
          IconButton(
            icon: Icon(
              connectivityService.isOnline ? Icons.wifi : Icons.wifi_off,
              color: connectivityService.isOnline ? Colors.green : Colors.grey,
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    connectivityService.isOnline
                        ? 'You are online'
                        : 'You are offline. Messages will be sent when connected',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        color: backgroundColor,
        child:
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : chats.isEmpty
                ? const Center(
                  child: Text(
                    'No Chats Yet',
                    style: TextStyle(color: Colors.white),
                  ),
                )
                : RefreshIndicator(
                  onRefresh: _fetchChats,
                  child: ListView.builder(
                    itemCount: chats.length,
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      final isSelected = selectedChats.contains(index);
                      return GestureDetector(
                        onLongPress: () => _toggleSelection(index),
                        onTap:
                            isSelectionMode
                                ? () => _toggleSelection(index)
                                : () async {
                                  await Navigator.push(
                                    context,
                                    PageRouteBuilder(
                                      transitionDuration: const Duration(
                                        milliseconds: 1200,
                                      ),
                                      pageBuilder:
                                          (
                                            context,
                                            animation,
                                            secondaryAnimation,
                                          ) => ChatScreen(
                                            userId: widget.userId,
                                            receiverId: chat['partner_id'],
                                            receiverName: chat['name'],
                                          ),
                                      transitionsBuilder: (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                        child,
                                      ) {
                                        const begin = Offset(1.0, 0.0);
                                        const end = Offset.zero;
                                        const curve = Curves.ease;

                                        var tween = Tween(
                                          begin: begin,
                                          end: end,
                                        ).chain(CurveTween(curve: curve));
                                        var offsetAnimation = animation.drive(
                                          tween,
                                        );

                                        return SlideTransition(
                                          position: offsetAnimation,
                                          child: child,
                                        );
                                      },
                                    ),
                                  );
                                  _fetchChats();
                                },
                        child: Card(
                          color:
                              isSelected
                                  ? Colors.blue.withOpacity(0.3)
                                  : backgroundColor.withOpacity(0.8),
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: ListTile(
                            tileColor: Colors.transparent,
                            leading: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.grey[300],
                                  child:
                                      chat['profile_pic'] != null &&
                                              chat['profile_pic'] !=
                                                  'default.jpg'
                                          ? ClipOval(
                                            child: Image.network(
                                              '${AppConfig.baseUrl}/${chat['profile_pic']}',
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                              errorBuilder: (
                                                context,
                                                error,
                                                stackTrace,
                                              ) {
                                                return Text(
                                                  getInitials(
                                                    chat['name'] ?? '',
                                                  ),
                                                  style: const TextStyle(
                                                    color: Colors.black,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                );
                                              },
                                            ),
                                          )
                                          : Text(
                                            getInitials(chat['name'] ?? ''),
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                ),
                                if (isSelectionMode)
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    child: Checkbox(
                                      value: isSelected,
                                      onChanged: (_) => _toggleSelection(index),
                                      activeColor: Colors.blue,
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(
                              _capitalizeEachWord(chat['name'] ?? 'Unknown'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Check if the last message type is 'image'
                                if (chat['last_message_type'] == 'image')
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.camera_alt,
                                        size: 16,
                                        color: Colors.grey[300],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        chat['last_message'] ??
                                            'Image', // Use the 'last_message' which is now "Image"
                                        style: TextStyle(
                                          color: Colors.grey[300],
                                          fontWeight:
                                              chat['unread_count'] > 0
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  )
                                else if (chat['last_message_type'] == 'voice')
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.mic,
                                        size: 16,
                                        color: Colors.grey[300],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        chat['last_message'] ?? 'Voice message',
                                        style: TextStyle(
                                          color: Colors.grey[300],
                                          fontWeight:
                                              chat['unread_count'] > 0
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.done_all,
                                        size: 18,
                                        color:
                                            chat['is_delivered'] == true
                                                ? Colors.blue
                                                : Colors.grey,
                                      ),

                                      const SizedBox(
                                        width: 4,
                                      ), // Small space between icon and text
                                      Expanded(
                                        child: Text(
                                          chat['last_message'] ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.grey[300],
                                            fontWeight:
                                                chat['unread_count'] > 0
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 2),
                                _buildOnlineStatus(chat),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _formatTime(chat['last_message_time'] ?? ''),
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),

                                if (chat['unread_count'] > 0)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      chat['unread_count'].toString(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: backgroundColor,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (context) => ConnectionsBottomSheet(userId: widget.userId),
          );
          _fetchChats();
        },
        backgroundColor: Colors.green,
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }
}

class ConnectionsBottomSheet extends StatefulWidget {
  final String userId;

  const ConnectionsBottomSheet({Key? key, required this.userId})
    : super(key: key);

  @override
  _ConnectionsBottomSheetState createState() => _ConnectionsBottomSheetState();
}

class _ConnectionsBottomSheetState extends State<ConnectionsBottomSheet> {
  List<Map<String, dynamic>> connections = [];
  bool isLoading = true;
  late LocalDBHelper localDB;

  @override
  void initState() {
    super.initState();
    localDB = LocalDBHelper();
    _fetchConnections();

    final connectivity = Provider.of<ConnectivityService>(
      context,
      listen: false,
    );
    connectivity.addListener(() {
      if (connectivity.isOnline) {
        _fetchConnections();
      }
    });
  }

  Future<void> _fetchConnections() async {
    setState(() => isLoading = true);

    try {
      // Always load from local DB first for instant display
      final localConnections = await localDB.getConnections();
      if (mounted) {
        setState(() {
          connections = localConnections;
        });
      }

      // Then try to fetch from server if online (silent update)
      final connectivity = Provider.of<ConnectivityService>(
        context,
        listen: false,
      );
      if (connectivity.isOnline) {
        final httpClient =
            HttpClient()
              ..badCertificateCallback =
                  (X509Certificate cert, String host, int port) => true;
        final ioClient = IOClient(httpClient);

        final response = await ioClient.get(
          Uri.parse('${AppConfig.baseUrl}/connections/${widget.userId}'),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final serverConnections = List<Map<String, dynamic>>.from(
            data['connections'],
          );

          if (mounted) {
            setState(() {
              connections = serverConnections;
            });
          }

          // Save to local DB
          await localDB.saveConnections(serverConnections);
        }
      }
    } catch (e) {
      print("Error fetching connections: $e");
      // If there's an error, we'll just keep showing the local data if available
      final localConnections = await localDB.getConnections();
      if (mounted) {
        setState(() {
          connections = localConnections.isNotEmpty ? localConnections : [];
        });
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  bool _areListsEqual(
    List<Map<String, dynamic>> list1,
    List<Map<String, dynamic>> list2,
  ) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (!_areMapsEqual(list1[i], list2[i])) return false;
    }
    return true;
  }

  bool _areMapsEqual(Map<String, dynamic> map1, Map<String, dynamic> map2) {
    if (map1.length != map2.length) return false;
    for (final key in map1.keys) {
      if (map1[key] != map2[key]) return false;
    }
    return true;
  }

  String getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length > 1) {
      return parts[0][0].toUpperCase() + parts[1][0].toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '';
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = Provider.of<ConnectivityService>(context);
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return Container(
                width: constraints.maxWidth * 0.5,
                height: 4,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(10),
                    bottom: Radius.circular(10),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Your Connections',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          if (!connectivity.isOnline)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Showing offline data',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          Expanded(
            child:
                isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : connections.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'No Connections Found',
                            style: TextStyle(color: Colors.white),
                          ),
                          if (!connectivity.isOnline)
                            Text(
                              'Connect to the internet to refresh',
                              style: TextStyle(color: Colors.grey),
                            ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      itemCount: connections.length,
                      itemBuilder: (context, index) {
                        final connection = connections[index];
                        return ListTile(
                          tileColor: backgroundColor,
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey[300],
                            child: Text(
                              getInitials(connection['name'] ?? ''),
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            connection['name'] ?? 'Unknown',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            connection['id'] ?? '',
                            style: TextStyle(color: Colors.grey[300]),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => ChatScreen(
                                      userId: widget.userId,
                                      receiverId: connection['id'],
                                      receiverName: connection['name'],
                                    ),
                              ),
                            );
                          },
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
 */

import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '/common/widgets/colors.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'chat_screen.dart';
import 'package:slt_chat/config/config.dart';
import 'package:http/io_client.dart';
import 'dart:io';
import 'package:slt_chat/service/connectivity_service.dart';
import 'package:slt_chat/service/local_db_helper.dart';

class ChatList extends StatefulWidget {
  final String userId;

  const ChatList({Key? key, required this.userId}) : super(key: key);

  @override
  _ChatListState createState() => _ChatListState();
}

class ConnectionsBottomSheet extends StatefulWidget {
  final String userId;

  const ConnectionsBottomSheet({Key? key, required this.userId})
    : super(key: key);

  @override
  _ConnectionsBottomSheetState createState() => _ConnectionsBottomSheetState();
}

class _ChatListState extends State<ChatList> {
  List<Map<String, dynamic>> chats = [];
  List<Map<String, dynamic>> filteredChats = [];
  bool isLoading = true;
  late LocalDBHelper localDB;
  late ConnectivityService connectivityService;
  Set<int> selectedChats = {};
  bool isSelectionMode = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    localDB = LocalDBHelper();
    final connectivity = Provider.of<ConnectivityService>(
      context,
      listen: false,
    );
    connectivityService = Provider.of<ConnectivityService>(
      context,
      listen: false,
    );
    _loadChats();
    _searchController.addListener(_filterChats);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    final localChats = await localDB.getChats();
    if (mounted) {
      setState(() {
        chats = localChats;
        filteredChats = localChats;
        isLoading = false;
      });
    }

    if (connectivityService.isOnline) {
      await _fetchChats();
    }
  }

  Future<void> _fetchChats() async {
    try {
      final httpClient =
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true;
      final ioClient = IOClient(httpClient);
      final response = await ioClient.get(
        Uri.parse('${AppConfig.baseUrl}/chats/${widget.userId}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final serverChats = List<Map<String, dynamic>>.from(data['chats']);

        for (var chat in serverChats) {
          chat['is_online'] = chat['is_online'] ?? false;
          chat['last_seen'] =
              chat['last_seen'] ?? DateTime.now().toIso8601String();
          chat['chat_id'] =
              chat['chat_id'] ?? '${widget.userId}_${chat['partner_id']}';
        }

        if (!_areListsEqual(chats, serverChats) && mounted) {
          setState(() {
            chats = serverChats;
            filteredChats = serverChats;
            _filterChats();
          });
        }

        await localDB.saveChats(serverChats);
      }
    } catch (e) {
      print("Error fetching chats: $e");
    }
  }

  void _filterChats() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredChats =
          chats.where((chat) {
            final name = chat['name']?.toLowerCase() ?? '';
            return name.contains(query);
          }).toList();
    });
  }

  Future<void> _deleteChats() async {
    if (selectedChats.isEmpty) return;

    try {
      // Store chats to delete for rollback in case of failure
      final chatsToDelete =
          selectedChats.map((index) => filteredChats[index]).toList();
      final httpClient =
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true;
      final ioClient = IOClient(httpClient);

      // Delete on server if online
      if (connectivityService.isOnline) {
        for (var chat in chatsToDelete) {
          final response = await ioClient.delete(
            Uri.parse(
              '${AppConfig.baseUrl}/chats/${widget.userId}/${chat['partner_id']}',
            ),
          );

          if (response.statusCode != 200) {
            throw Exception(
              'Failed to delete chat ${chat['partner_id']} on server',
            );
          }
        }
      }

      final db = await localDB.database;
      await db.transaction((txn) async {
        for (var chat in chatsToDelete) {
          await txn.delete(
            'chats',
            where: 'chat_id = ?',
            whereArgs: [chat['chat_id']],
          );
          await txn.delete(
            'messages',
            where: 'chat_id = ?',
            whereArgs: [chat['chat_id']],
          );
        }
      });

      // Update UI
      setState(() {
        chats.removeWhere(
          (chat) => chatsToDelete.any((c) => c['chat_id'] == chat['chat_id']),
        );
        filteredChats = List.from(chats);
        selectedChats.clear();
        isSelectionMode = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chats deleted successfully')),
      );
    } catch (e) {
      print("Error deleting chats: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to delete chats')));
    } finally {
      // Refresh chats to ensure sync
      if (connectivityService.isOnline) {
        await _fetchChats();
      }
    }
  }

  bool _areListsEqual(
    List<Map<String, dynamic>> list1,
    List<Map<String, dynamic>> list2,
  ) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (!_areMapsEqual(list1[i], list2[i])) return false;
    }
    return true;
  }

  bool _areMapsEqual(Map<String, dynamic> map1, Map<String, dynamic> map2) {
    if (map1.length != map2.length) return false;
    for (final key in map1.keys) {
      if (map1[key] != map2[key]) return false;
    }
    return true;
  }

  String _formatTime(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

      if (messageDate == today) {
        return '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
      } else if (messageDate == yesterday) {
        return 'Yesterday';
      } else {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      }
    } catch (e) {
      return timestamp;
    }
  }

  String _formatLastSeen(String timestamp) {
    try {
      final lastSeen = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(lastSeen);

      if (difference.inMinutes < 1) return 'just now';
      if (difference.inHours < 1) return '${difference.inMinutes} min ago';
      if (difference.inDays < 1) return '${difference.inHours} hours ago';
      return '${difference.inDays} days ago';
    } catch (e) {
      return timestamp;
    }
  }

  String getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length > 1) {
      return parts[0][0].toUpperCase() + parts[1][0].toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '';
  }

  Widget _buildOnlineStatus(Map<String, dynamic> chat) {
    final isOnline = chat['is_online'] == true || chat['is_online'] == 1;
    final lastSeen = chat['last_seen'];

    if (isOnline) {
      return const Text(
        'Online',
        style: TextStyle(color: Colors.green, fontSize: 12),
      );
    } else if (lastSeen != null) {
      return Text(
        'Last seen ${_formatLastSeen(lastSeen)}',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      );
    }
    return const SizedBox.shrink();
  }

  String _capitalizeEachWord(String text) {
    return text
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  void _toggleSelection(int index) {
    setState(() {
      if (selectedChats.contains(index)) {
        selectedChats.remove(index);
        if (selectedChats.isEmpty) isSelectionMode = false;
      } else {
        selectedChats.add(index);
        isSelectionMode = true;
      }
    });
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: backgroundColor,
            title: Text(
              'Delete ${selectedChats.length} chat${selectedChats.length > 1 ? 's' : ''}?',
              style: const TextStyle(color: Colors.white),
            ),
            content: const Text(
              'This will delete the selected chats and their messages.',
              style: TextStyle(color: Colors.grey),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteChats();
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text(
          'Chats',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 28,
          ),
        ),
        backgroundColor: backgroundColor,
        actions: [
          if (isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.white),
              onPressed: _showDeleteConfirmation,
            ),
          IconButton(
            icon: Icon(
              connectivityService.isOnline ? Icons.wifi : Icons.wifi_off,
              color: Colors.white,
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    connectivityService.isOnline
                        ? 'You are online'
                        : 'You are offline. Messages will be sent when connected',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: backgroundColor,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(color: Colors.white, fontSize: 18),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Color.fromARGB(255, 209, 206, 206),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),

                filled: true,
                fillColor: const Color.fromARGB(255, 68, 62, 62),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: backgroundColor,
              child:
                  isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : filteredChats.isEmpty
                      ? const Center(
                        child: Text(
                          'No Chats Yet',
                          style: TextStyle(
                            color: Color.fromARGB(137, 233, 233, 233),
                          ),
                        ),
                      )
                      : RefreshIndicator(
                        onRefresh: _fetchChats,
                        child: ListView.separated(
                          itemCount: filteredChats.length,
                          separatorBuilder:
                              (context, index) => const Divider(
                                height: 1,
                                color: Color.fromARGB(255, 53, 53, 53),
                                indent: 72,
                              ),
                          itemBuilder: (context, index) {
                            final chat = filteredChats[index];
                            final isSelected = selectedChats.contains(index);
                            return GestureDetector(
                              onLongPress: () => _toggleSelection(index),
                              onTap:
                                  isSelectionMode
                                      ? () => _toggleSelection(index)
                                      : () async {
                                        await Navigator.push(
                                          context,
                                          PageRouteBuilder(
                                            transitionDuration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            pageBuilder:
                                                (
                                                  context,
                                                  animation,
                                                  secondaryAnimation,
                                                ) => ChatScreen(
                                                  userId: widget.userId,
                                                  receiverId:
                                                      chat['partner_id'],
                                                  receiverName: chat['name'],
                                                  profileImage:
                                                      chat['profile_pic'],
                                                ),
                                            transitionsBuilder: (
                                              context,
                                              animation,
                                              secondaryAnimation,
                                              child,
                                            ) {
                                              const begin = Offset(1.0, 0.0);
                                              const end = Offset.zero;
                                              const curve = Curves.ease;

                                              var tween = Tween(
                                                begin: begin,
                                                end: end,
                                              ).chain(CurveTween(curve: curve));
                                              var offsetAnimation = animation
                                                  .drive(tween);

                                              return SlideTransition(
                                                position: offsetAnimation,
                                                child: child,
                                              );
                                            },
                                          ),
                                        );
                                        _fetchChats();
                                      },
                              child: Container(
                                color:
                                    isSelected
                                        ? Colors.blue.withOpacity(0.2)
                                        : Colors.transparent,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: Stack(
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.blue,
                                            width: 2, // Border thickness
                                          ),
                                        ),
                                        child: CircleAvatar(
                                          radius: 26,
                                          backgroundColor: Colors.grey[300],
                                          child:
                                              (chat['profile_pic'] != null &&
                                                      chat['profile_pic'] !=
                                                          'default.jpg')
                                                  ? ClipOval(
                                                    child: CachedNetworkImage(
                                                      imageUrl:
                                                          '${AppConfig.baseUrl}/${chat['profile_pic']}',
                                                      width: 52,
                                                      height: 52,
                                                      fit: BoxFit.cover,
                                                      placeholder:
                                                          (context, url) =>
                                                              const CircularProgressIndicator(),
                                                      errorWidget:
                                                          (
                                                            context,
                                                            url,
                                                            error,
                                                          ) => Center(
                                                            child: Text(
                                                              getInitials(
                                                                chat['name'] ??
                                                                    '',
                                                              ),
                                                              style: const TextStyle(
                                                                color:
                                                                    Color.fromARGB(
                                                                      255,
                                                                      67,
                                                                      66,
                                                                      66,
                                                                    ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                    ),
                                                  )
                                                  : Center(
                                                    child: Text(
                                                      getInitials(
                                                        chat['name'] ?? '',
                                                      ),
                                                      style: const TextStyle(
                                                        color: Color.fromARGB(
                                                          255,
                                                          67,
                                                          66,
                                                          66,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 20,
                                                      ),
                                                    ),
                                                  ),
                                        ),
                                      ),
                                      if (isSelectionMode)
                                        Positioned(
                                          top: 0,
                                          left: 0,
                                          child: Checkbox(
                                            value: isSelected,
                                            onChanged:
                                                (_) => _toggleSelection(index),
                                            activeColor: Colors.blue,
                                          ),
                                        ),
                                    ],
                                  ),
                                  title: Text(
                                    _capitalizeEachWord(
                                      chat['name'] ?? 'Unknown',
                                    ),
                                    style: const TextStyle(
                                      color: Color.fromARGB(221, 232, 232, 232),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (chat['last_message_type'] == 'image')
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.camera_alt,
                                              size: 16,
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              chat['last_message'] ?? 'Image',
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontWeight:
                                                    chat['unread_count'] > 0
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        )
                                      else if (chat['last_message_type'] ==
                                          'voice')
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.mic,
                                              size: 16,
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              chat['last_message'] ??
                                                  'Voice message',
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontWeight:
                                                    chat['unread_count'] > 0
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        )
                                      else if (chat['last_message_type'] ==
                                          'video')
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.videocam,
                                              size: 16,
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              chat['last_message'] ??
                                                  'Voice message',
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontWeight:
                                                    chat['unread_count'] > 0
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        )
                                      else if (chat['last_message_type'] ==
                                          'pdf')
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.picture_as_pdf_sharp,
                                              size: 16,
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              chat['last_message'] ??
                                                  'Voice message',
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontWeight:
                                                    chat['unread_count'] > 0
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.done_all,
                                              size: 18,
                                              color:
                                                  chat['is_delivered'] == true
                                                      ? Colors.blue
                                                      : Colors.grey,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                chat['last_message'] ?? '',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontWeight:
                                                      chat['unread_count'] > 0
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      const SizedBox(height: 2),
                                      _buildOnlineStatus(chat),
                                    ],
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _formatTime(
                                          chat['last_message_time'] ?? '',
                                        ),
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (chat['unread_count'] > 0)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF25D366),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            chat['unread_count'].toString(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: backgroundColor,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (context) => ConnectionsBottomSheet(userId: widget.userId),
          );
          _fetchChats();
        },
        backgroundColor: const Color(0xFF25D366),
        child: const Icon(Icons.message, color: Colors.white),
      ),
    );
  }
}

class _ConnectionsBottomSheetState extends State<ConnectionsBottomSheet> {
  List<Map<String, dynamic>> connections = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchConnections();
  }

  Future<void> _fetchConnections() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final connectivity = Provider.of<ConnectivityService>(
        context,
        listen: false,
      );
      if (!connectivity.isOnline) {
        setState(() {
          errorMessage =
              'No internet connection. Please connect and try again.';
          isLoading = false;
        });
        return;
      }

      final httpClient =
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true;
      final ioClient = IOClient(httpClient);

      final response = await ioClient.get(
        Uri.parse('${AppConfig.baseUrl}/connections/${widget.userId}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Debug: Print the raw response to verify structure
        print('Connections API response: $data');

        if (data['connections'] is List) {
          final serverConnections = List<Map<String, dynamic>>.from(
            data['connections'],
          );
          if (mounted) {
            setState(() {
              connections = serverConnections;
              isLoading = false;
            });
          }
        } else {
          throw Exception(
            'Invalid response format: "connections" is not a list',
          );
        }
      } else {
        throw Exception('Failed to fetch connections: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching connections: $e');
      if (mounted) {
        setState(() {
          errorMessage = 'Failed to load connections. Please try again.';
          isLoading = false;
        });
      }
    }
  }

  String getInitials(String? name) {
    if (name == null || name.isEmpty) return '';
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return parts[0][0].toUpperCase() + parts[1][0].toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 181, 181, 181),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'New Chat',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color.fromARGB(221, 255, 255, 255),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child:
                isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : errorMessage != null
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            errorMessage!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _fetchConnections,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                    : connections.isEmpty
                    ? const Center(
                      child: Text(
                        'No Connections Found',
                        style: TextStyle(
                          color: Color.fromARGB(221, 255, 255, 255),
                        ),
                      ),
                    )
                    : ListView.separated(
                      itemCount: connections.length,
                      separatorBuilder:
                          (context, index) => const Divider(
                            height: 1,
                            color: Color.fromARGB(255, 123, 121, 121),
                          ),
                      itemBuilder: (context, index) {
                        final connection = connections[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            radius: 26,
                            backgroundColor: Colors.grey[300],
                            child:
                                (connection['profile_pic'] != null &&
                                        connection['profile_pic'] !=
                                            'default.jpg')
                                    ? ClipOval(
                                      child: CachedNetworkImage(
                                        imageUrl:
                                            '${AppConfig.baseUrl}/${connection['profile_pic']}',
                                        width: 52,
                                        height: 52,
                                        fit: BoxFit.cover,
                                        placeholder:
                                            (context, url) =>
                                                const CircularProgressIndicator(),
                                        errorWidget:
                                            (context, url, error) => Center(
                                              child: Text(
                                                getInitials(
                                                  connection['name'] ?? '',
                                                ),
                                                style: const TextStyle(
                                                  color: Color.fromARGB(
                                                    255,
                                                    67,
                                                    66,
                                                    66,
                                                  ),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                      ),
                                    )
                                    : Center(
                                      child: Text(
                                        getInitials(connection['name'] ?? ''),
                                        style: const TextStyle(
                                          color: Color.fromARGB(
                                            255,
                                            67,
                                            66,
                                            66,
                                          ),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20,
                                        ),
                                      ),
                                    ),
                          ),

                          title: Text(
                            connection['name'] ?? 'Unknown',
                            style: const TextStyle(
                              color: Color.fromARGB(221, 255, 255, 255),
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            connection['email']?.toString() ?? '',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => ChatScreen(
                                      userId: widget.userId,
                                      receiverId: connection['id'],
                                      receiverName:
                                          connection['name'] ?? 'Unknown',
                                      profileImage: connection['profile_pic'],
                                    ),
                              ),
                            );
                          },
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
