import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '/common/widgets/colors.dart';
import '/config/config.dart';
import 'package:slt_chat/Features/Groups/group_info_db.dart';

class GroupInfoScreen extends StatefulWidget {
  final String groupId;
  final String userId;
  final Map<String, dynamic> groupDetails;
  final Function(String)? onGroupImageUpdated;

  const GroupInfoScreen({
    super.key,
    required this.groupId,
    required this.userId,
    required this.groupDetails,
    this.onGroupImageUpdated,
  });

  @override
  _GroupInfoScreenState createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late Map<String, dynamic> _groupDetails;
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;
  bool _isEditingDescription = false;
  final TextEditingController _descriptionController = TextEditingController();
  final String baseUrl = AppConfig.baseUrl;
  List<Map<String, dynamic>> _connections = [];
  List<String> _selectedConnections = [];
  late IOClient httpClient;

  @override
  void initState() {
    super.initState();
    final HttpClient client =
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;
    httpClient = IOClient(client);

    _groupDetails = widget.groupDetails;
    _descriptionController.text =
        _groupDetails['description'] ?? 'No description provided';
    _loadLocalData();
    _fetchMembers();
  }

  @override
  void dispose() {
    httpClient.close();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalData() async {
    final localGroup = await GroupInfoDB.getGroupDetails(widget.groupId);
    final localMembers = await GroupInfoDB.getGroupMembers(widget.groupId);

    if (localGroup != null) {
      setState(() {
        _groupDetails = {...widget.groupDetails, ...localGroup};
        _descriptionController.text =
            _groupDetails['description'] ?? 'No description provided';
      });
    }

    if (localMembers.isNotEmpty) {
      setState(() {
        _members =
            localMembers
                .map(
                  (m) => {
                    'id': m['id'],
                    'name': m['name'],
                    'profile_pic': m['profile_pic'],
                    'isAdmin': m['is_admin'] == 1,
                  },
                )
                .toList();
      });
    }
  }

  Future<void> _fetchMembers() async {
    setState(() => _isLoading = true);
    try {
      final memberIds = List<String>.from(_groupDetails['members'] ?? []);
      List<Map<String, dynamic>> members = [];
      for (String memberId in memberIds) {
        final response = await httpClient.get(
          Uri.parse('$baseUrl/user/$memberId'),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          members.add({
            'id': memberId,
            'name': data['name'] ?? 'Unknown',
            'profile_pic': data['profile_pic'] ?? 'assets/users.png',
            'isAdmin': _groupDetails['admins'].contains(memberId),
          });
        }
      }
      setState(() => _members = members);
      await GroupInfoDB.saveGroupMembers(widget.groupId, members);
    } catch (e) {
      print('Error fetching members: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error fetching members: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchConnections() async {
    try {
      final response = await httpClient.get(
        Uri.parse('$baseUrl/connections/${widget.userId}'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final connections = List<Map<String, dynamic>>.from(
          data['connections'],
        );
        final memberIds = List<String>.from(_groupDetails['members'] ?? []);
        setState(
          () =>
              _connections =
                  connections
                      .where((conn) => !memberIds.contains(conn['id']))
                      .toList(),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load connections')),
        );
      }
    } catch (e) {
      print('Error fetching connections: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error fetching connections: $e')));
    }
  }

  void _showAddMembersDialog() async {
    await _fetchConnections();
    setState(() => _selectedConnections = []);

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  backgroundColor: backgroundColor,
                  title: const Text(
                    'Add Members',
                    style: TextStyle(color: Colors.white),
                  ),
                  content:
                      _connections.isEmpty
                          ? const Text(
                            'No connections available to add.',
                            style: TextStyle(color: Colors.white),
                          )
                          : SizedBox(
                            width: double.maxFinite,
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _connections.length,
                              itemBuilder: (context, index) {
                                final connection = _connections[index];
                                final isSelected = _selectedConnections
                                    .contains(connection['id']);
                                return CheckboxListTile(
                                  title: Text(
                                    connection['name'] ?? 'Unknown',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  value: isSelected,
                                  onChanged: (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        _selectedConnections.add(
                                          connection['id'],
                                        );
                                      } else {
                                        _selectedConnections.remove(
                                          connection['id'],
                                        );
                                      }
                                    });
                                  },
                                  activeColor: Colors.green,
                                  checkColor: Colors.white,
                                  tileColor: Colors.grey[800],
                                  subtitle: Text(
                                    connection['email'] ?? '',
                                    style: TextStyle(color: Colors.grey[400]),
                                  ),
                                );
                              },
                            ),
                          ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    ElevatedButton(
                      onPressed:
                          _selectedConnections.isEmpty
                              ? null
                              : () async {
                                await _addMembers();
                                Navigator.pop(context);
                              },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      child: const Text(
                        'Add',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  Future<void> _addMembers() async {
    try {
      final updatedMembers = List<String>.from(_groupDetails['members'] ?? [])
        ..addAll(_selectedConnections);
      final response = await httpClient.put(
        Uri.parse('$baseUrl/update-group'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'group_id': widget.groupId,
          'updates': {'members': updatedMembers},
        }),
      );

      if (response.statusCode == 200) {
        setState(() => _groupDetails['members'] = updatedMembers);
        await _fetchMembers();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Members added successfully')),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to add members')));
      }
    } catch (e) {
      print('Error adding members: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error adding members: $e')));
    }
  }

  Future<void> _removeMember(String memberId) async {
    bool? confirm = await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: backgroundColor,
            title: const Text(
              'Remove Member',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Are you sure you want to remove this member?',
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Remove',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      final updatedMembers = List<String>.from(_groupDetails['members'] ?? [])
        ..remove(memberId);
      final response = await httpClient.put(
        Uri.parse('$baseUrl/update-group'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'group_id': widget.groupId,
          'updates': {'members': updatedMembers},
        }),
      );

      if (response.statusCode == 200) {
        setState(() => _groupDetails['members'] = updatedMembers);
        await _fetchMembers();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member removed successfully')),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to remove member')),
        );
      }
    } catch (e) {
      print('Error removing member: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error removing member: $e')));
    }
  }

  Future<void> _leaveGroup() async {
    final isAdmin = _groupDetails['admins'].contains(widget.userId);
    final isOnlyAdmin = isAdmin && _groupDetails['admins'].length == 1;

    if (isOnlyAdmin) {
      bool? confirmDelete = await showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              backgroundColor: backgroundColor,
              title: const Text(
                'Warning',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                "You can't leave the group as you are the only admin. Do you want to delete this group and leave?",
                style: TextStyle(color: Colors.white),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
      );

      if (confirmDelete == true) {
        try {
          final response = await httpClient.delete(
            Uri.parse('$baseUrl/delete-group/${widget.groupId}'),
            headers: {'Content-Type': 'application/json'},
          );
          if (response.statusCode == 200) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Group deleted successfully')),
            );
            Navigator.pop(context, true);
            Navigator.pop(context);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to delete group')),
            );
          }
        } catch (e) {
          print('Error deleting group: $e');
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error deleting group: $e')));
        }
      }
      return;
    }

    bool? confirm = await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: backgroundColor,
            title: const Text(
              'Leave Group',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Are you sure you want to leave this group?',
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      final updatedMembers = List<String>.from(_groupDetails['members'] ?? [])
        ..remove(widget.userId);
      final updatedAdmins = List<String>.from(_groupDetails['admins'] ?? [])
        ..remove(widget.userId);
      final response = await httpClient.put(
        Uri.parse('$baseUrl/update-group'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'group_id': widget.groupId,
          'updates': {'members': updatedMembers, 'admins': updatedAdmins},
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have left the group')),
        );
        Navigator.pop(context, true);
        //Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to leave group')));
      }
    } catch (e) {
      print('Error leaving group: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error leaving group: $e')));
    }
  }

  Future<void> _updateDescription() async {
    try {
      final response = await httpClient.put(
        Uri.parse('$baseUrl/update-group'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'group_id': widget.groupId,
          'updates': {'description': _descriptionController.text},
        }),
      );
      if (response.statusCode == 200) {
        setState(() {
          _groupDetails['description'] = _descriptionController.text;
          _isEditingDescription = false;
        });
        await GroupInfoDB.saveGroupDetails(_groupDetails);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Description updated successfully')),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update description')),
        );
      }
    } catch (e) {
      print('Error updating description: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating description: $e')));
    }
  }

  Future<void> _updateProfilePicture(XFile image) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/update-group-image'),
      );
      request.fields['group_id'] = widget.groupId;
      request.files.add(
        await http.MultipartFile.fromPath('profile_pic', image.path),
      );
      var streamedResponse = await httpClient.send(request);
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var jsonData = json.decode(response.body);
        final newImageUrl = jsonData['profile_pic'];
        setState(() => _groupDetails['profile_pic'] = newImageUrl);
        await GroupInfoDB.saveGroupDetails(_groupDetails);

        if (widget.onGroupImageUpdated != null) {
          widget.onGroupImageUpdated!(newImageUrl);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated successfully')),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update profile picture')),
        );
      }
    } catch (e) {
      print('Error updating profile picture: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating profile picture: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = DateTime.parse(_groupDetails['created_at']).toLocal();
    final formattedDate = DateFormat('MMM d, yyyy').format(createdAt);
    final isAdmin = _groupDetails['admins'].contains(widget.userId);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Group Info', style: TextStyle(color: Colors.white)),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundImage:
                                _groupDetails['profile_pic'] != "default"
                                    ? NetworkImage(
                                      '$baseUrl/${_groupDetails['profile_pic']}',
                                    )
                                    : const AssetImage(
                                          'assets/images/group_default.jpg',
                                        )
                                        as ImageProvider,
                          ),
                          if (isAdmin)
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.white),
                              onPressed: () async {
                                final ImagePicker picker = ImagePicker();
                                final XFile? image = await picker.pickImage(
                                  source: ImageSource.gallery,
                                );
                                if (image != null)
                                  await _updateProfilePicture(image);
                              },
                            ),
                        ],
                      ),
                    ),
                    Text(
                      _groupDetails['name'] ?? 'Unnamed Group',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Created on: $formattedDate',
                      style: TextStyle(color: Colors.grey[400], fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Description',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (isAdmin && !_isEditingDescription)
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                  ),
                                  onPressed:
                                      () => setState(
                                        () => _isEditingDescription = true,
                                      ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _isEditingDescription
                              ? Column(
                                children: [
                                  TextField(
                                    controller: _descriptionController,
                                    style: const TextStyle(color: Colors.white),
                                    maxLines: 3,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Colors.grey[800],
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                          8.0,
                                        ),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _isEditingDescription = false;
                                            _descriptionController.text =
                                                _groupDetails['description'] ??
                                                'No description provided';
                                          });
                                        },
                                        child: const Text(
                                          'Cancel',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                      ElevatedButton(
                                        onPressed: _updateDescription,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                        ),
                                        child: const Text(
                                          'Save',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                              : Text(
                                _groupDetails['description'] ??
                                    'No description provided',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 16,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Members (${_members.length})',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (isAdmin)
                                TextButton.icon(
                                  onPressed: _showAddMembersDialog,
                                  icon: const Icon(
                                    Icons.add,
                                    color: Colors.green,
                                  ),
                                  label: const Text(
                                    'Add Members',
                                    style: TextStyle(color: Colors.green),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _members.length,
                            itemBuilder: (context, index) {
                              final member = _members[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 24,
                                  backgroundImage:
                                      member['profile_pic'] != 'default.jpg'
                                          ? NetworkImage(
                                            '$baseUrl/${member['profile_pic']}',
                                          )
                                          : const AssetImage(
                                                'assets/images/default.jpg',
                                              )
                                              as ImageProvider,
                                ),
                                title: Text(
                                  member['name'],
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  member['isAdmin'] ? 'Admin' : 'Member',
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                                trailing:
                                    isAdmin && member['id'] != widget.userId
                                        ? IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle,
                                            color: Colors.red,
                                          ),
                                          onPressed:
                                              () => _removeMember(member['id']),
                                        )
                                        : null,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ElevatedButton(
                        onPressed: _leaveGroup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text(
                          'Leave Group',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}
