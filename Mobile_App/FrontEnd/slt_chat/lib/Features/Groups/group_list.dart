import 'package:connectivity_plus/connectivity_plus.dart';
import '/common/widgets/colors.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '/Features/Groups/create_new_group.dart';
import '/config/config.dart';
import '/Features/Groups/group_chat_screen.dart';
import '/Features/Groups/group_list_local_db.dart';
import 'package:cached_network_image/cached_network_image.dart';

class GroupListScreen extends StatefulWidget {
  final String userId;

  const GroupListScreen({super.key, required this.userId});

  @override
  _GroupListScreenState createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  List<Map<String, dynamic>> groups = [];
  List<Map<String, dynamic>> filteredGroups = [];
  bool isLoading = true;
  late IOClient httpClient;
  final String baseUrl = AppConfig.baseUrl;
  final TextEditingController searchController = TextEditingController();
  late IO.Socket socket;
  late GroupListLocalDB localDB;

  @override
  void initState() {
    super.initState();
    localDB = GroupListLocalDB();
    final HttpClient client =
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;
    httpClient = IOClient(client);
    _initWithLocalData();
    _initSocket();
    searchController.addListener(_filterGroups);
  }

  void _initSocket() {
    socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    socket.connect();

    socket.onConnect((_) {
      print('Connected to socket server');
      socket.emit('join', widget.userId);
    });

    socket.on('group_updated', (_) {
      print('Group list changed, refetching...');
      _fetchGroups();
    });

    socket.onDisconnect((_) => print('Disconnected from socket'));
  }

  @override
  void dispose() {
    localDB.close();
    socket.dispose();
    httpClient.close();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _initWithLocalData() async {
    try {
      final localGroups = await localDB.getGroups();
      setState(() {
        groups = localGroups;
        filteredGroups = localGroups;
        isLoading = false;
      });
    } catch (e) {
      print("Error loading local groups: $e");
      setState(() => isLoading = false);
    }

    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        _fetchGroups();
      }
    } on SocketException catch (_) {
      print("No internet connection, using local data only");
    }
  }

  Future<void> _fetchGroups() async {
    try {
      final response = await httpClient.get(
        Uri.parse('$baseUrl/user-groups/${widget.userId}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final serverGroups = List<Map<String, dynamic>>.from(data['groups']);
        await localDB.upsertGroups(serverGroups);

        setState(() {
          groups = serverGroups;
          filteredGroups = serverGroups;
          _filterGroups();
        });
      }
    } catch (e) {
      print("Network fetch error: $e");
      if (groups.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error fetching groups: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _filterGroups() {
    final query = searchController.text.toLowerCase();
    setState(() {
      filteredGroups =
          groups.where((group) {
            final name = group['name']?.toLowerCase() ?? '';
            return name.contains(query);
          }).toList();
    });
  }

  String getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length > 1) {
      return parts[0][0].toUpperCase() + parts[1][0].toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Groups',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 28,
          ),
        ),
        backgroundColor: backgroundColor,
        actions: [
          IconButton(
            icon: FutureBuilder<List<ConnectivityResult>>(
              future: Connectivity().checkConnectivity(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData &&
                    snapshot.data!.contains(ConnectivityResult.none)) {
                  return const Icon(Icons.wifi_off, color: Colors.white);
                }
                return const Icon(Icons.wifi, color: Colors.white);
              },
            ),
            onPressed: () async {
              final result = await Connectivity().checkConnectivity();
              final message =
                  result.contains(ConnectivityResult.none)
                      ? 'You are offline'
                      : 'You are online';
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(message)));
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
              controller: searchController,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                hintText: 'Search groups',
                hintStyle: const TextStyle(color: Colors.white, fontSize: 18),
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
                      : filteredGroups.isEmpty
                      ? const Center(
                        child: Text(
                          'No Groups Yet',
                          style: TextStyle(
                            color: Color.fromARGB(137, 233, 233, 233),
                            fontSize: 18,
                          ),
                        ),
                      )
                      : RefreshIndicator(
                        onRefresh: _fetchGroups,
                        child: ListView.separated(
                          itemCount: filteredGroups.length,
                          separatorBuilder:
                              (context, index) => const Divider(
                                height: 1,
                                color: Color.fromARGB(255, 53, 53, 53),
                                indent: 72,
                              ),
                          itemBuilder: (context, index) {
                            final group = filteredGroups[index];
                            final groupName = group['name'] ?? 'Unnamed Group';
                            final unreadCount = group['unread_count'] ?? 0;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.grey[700]!,
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 26,
                                  backgroundColor: Colors.grey[300],
                                  child: ClipOval(
                                    child:
                                        group['profile_pic'] != null &&
                                                !group['profile_pic'].contains(
                                                  'default',
                                                )
                                            ? CachedNetworkImage(
                                              imageUrl:
                                                  '$baseUrl/${group['profile_pic']}',
                                              width: 52,
                                              height: 52,
                                              fit: BoxFit.cover,
                                              errorWidget:
                                                  (
                                                    context,
                                                    url,
                                                    error,
                                                  ) => Center(
                                                    child: Text(
                                                      getInitials(groupName),
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
                                            )
                                            : Container(
                                              width: 52,
                                              height: 52,
                                              color: Colors.grey[300],
                                              child: Center(
                                                child: Text(
                                                  getInitials(groupName),
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
                                  ),
                                ),
                              ),
                              title: Text(
                                groupName,
                                style: const TextStyle(
                                  color: Color.fromARGB(221, 232, 232, 232),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (group['is_typing'] == true)
                                    Text(
                                      'Typing...',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontStyle: FontStyle.italic,
                                        fontWeight:
                                            unreadCount > 0
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                      ),
                                    )
                                  else if (group['last_message_type'] ==
                                      'image')
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.camera_alt,
                                          size: 16,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          group['last_message'] ?? 'Image',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontWeight:
                                                unreadCount > 0
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    )
                                  else if (group['last_message_type'] ==
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
                                          group['last_message'] ??
                                              'Voice message',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontWeight:
                                                unreadCount > 0
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Text(
                                      group['last_message'] ??
                                          'No messages yet',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontWeight:
                                            unreadCount > 0
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                      ),
                                    ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${group['member_count'] ?? 0} members',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    group['last_message_time'] != null
                                        ? _formatTime(
                                          group['last_message_time'],
                                        )
                                        : '',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (unreadCount > 0)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF25D366),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '$unreadCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              onTap: () async {
                                final groupId = group['group_id']?.toString();
                                final groupProfilePic =
                                    group['profile_pic'] != null
                                        ? '$baseUrl/${group['profile_pic']}'
                                        : 'default';

                                if (groupId == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Error: Group ID is missing',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => GroupChatScreen(
                                          groupId: groupId,
                                          groupName: groupName,
                                          userId: widget.userId,
                                          groupProfilePic: groupProfilePic,
                                        ),
                                  ),
                                );
                                _fetchGroups();
                              },
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
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateGroupScreen(userId: widget.userId),
            ),
          );
          if (result == true) {
            _fetchGroups();
          }
        },
        backgroundColor: const Color(0xFF25D366),
        child: const Icon(Icons.group_add, color: Colors.white),
      ),
    );
  }
}
