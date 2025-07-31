import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '/common/widgets/colors.dart';
import 'package:slt_chat/config/config.dart';

class CreateGroupScreen extends StatefulWidget {
  final String userId;
  const CreateGroupScreen({super.key, required this.userId});

  @override
  _CreateGroupScreenState createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  List<Map<String, dynamic>> _connections = [];
  final List<String> _selectedMembers = [];
  List<Map<String, dynamic>> _filteredConnections = [];
  final TextEditingController _searchController = TextEditingController();
  File? _groupImage;
  bool _isLoading = false;

  final String baseUrl = AppConfig.baseUrl;
  late IOClient httpClient;

  @override
  void initState() {
    super.initState();
    final HttpClient client =
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;
    httpClient = IOClient(client);

    _searchController.addListener(_filterConnections);
    _fetchConnections();
  }

  @override
  void dispose() {
    httpClient.close();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchConnections() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await httpClient.get(
        Uri.parse('$baseUrl/connections/${widget.userId}'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _connections = List<Map<String, dynamic>>.from(data['connections']);
          _filteredConnections = _connections;
        });
      } else {
        print('Failed to load connections');
      }
    } catch (e) {
      print('Error fetching connections: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterConnections() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredConnections =
          _connections
              .where(
                (connection) =>
                    connection['name'].toLowerCase().contains(query),
              )
              .toList();
    });
  }

  // Pick group image from gallery
  Future<void> _pickGroupImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile != null) {
      setState(() {
        _groupImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/create-group'),
      );

      // Use the custom client for the request
      request.headers['content-type'] = 'application/json';

      request.fields['name'] = _groupNameController.text;
      request.fields['creator_id'] = widget.userId;
      request.fields['member_ids'] = json.encode(_selectedMembers);

      // Comment out the file upload part to test
      // if (_groupImage != null) {
      //   request.files.add(
      //     await http.MultipartFile.fromPath('profile_pic', _groupImage!.path),
      //   );
      // }

      var response = await httpClient.send(request);
      var responseData = await response.stream.bytesToString();

      if (response.statusCode == 201) {
        final data = json.decode(responseData);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created successfully!')),
        );
        Navigator.of(context).pop(true);
      } else {
        final errorData = json.decode(responseData);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create group: ${errorData['error']}'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creating group: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Toggle member selection for group
  void _toggleMemberSelection(String memberId) {
    setState(() {
      if (_selectedMembers.contains(memberId)) {
        _selectedMembers.remove(memberId);
      } else {
        _selectedMembers.add(memberId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Create Group',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: backgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context); // Go back to the previous screen
          },
        ),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // Group Name Input
                    TextField(
                      controller: _groupNameController,
                      decoration: const InputDecoration(
                        labelText: 'Group Name',
                        labelStyle: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        border: OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.green),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    // Group Image Selection
                    GestureDetector(
                      onTap: _pickGroupImage,
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey[300],
                        child:
                            _groupImage != null
                                ? ClipOval(
                                  child: Image.file(
                                    _groupImage!,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  ),
                                )
                                : const Icon(Icons.camera_alt, size: 40),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Search Contacts Input
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search Connections',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: const BorderSide(color: Colors.white),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.green),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    // Connection List Display
                    Expanded(
                      child: ListView.builder(
                        itemCount:
                            _filteredConnections.isEmpty
                                ? _connections.length
                                : _filteredConnections.length,
                        itemBuilder: (context, index) {
                          final connection =
                              _filteredConnections.isEmpty
                                  ? _connections[index]
                                  : _filteredConnections[index];
                          bool isSelected = _selectedMembers.contains(
                            connection['id'],
                          );

                          return Card(
                            color: backgroundColor.withOpacity(0.8),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: ListTile(
                              title: Text(
                                connection['name'] ?? 'Unknown',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              leading: CircleAvatar(
                                backgroundColor: Colors.grey[300],
                                child: Text(
                                  connection['name'][0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              trailing: Checkbox(
                                value: isSelected,
                                onChanged:
                                    (value) => _toggleMemberSelection(
                                      connection['id'],
                                    ),
                              ),
                              onTap:
                                  () =>
                                      _toggleMemberSelection(connection['id']),
                            ),
                          );
                        },
                      ),
                    ),
                    // Create Group Button
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _createGroup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 12,
                          ),
                        ),
                        child:
                            _isLoading
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Text(
                                  'Create Group',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}
