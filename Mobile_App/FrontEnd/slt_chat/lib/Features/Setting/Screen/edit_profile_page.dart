import 'dart:io';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:image_picker/image_picker.dart';
import 'package:slt_chat/config/config.dart';
import '/common/widgets/colors.dart';

class EditProfilePage extends StatefulWidget {
  final String userId;
  final String currentName;
  final String currentEmail;
  final String currentPhone;
  final String currentProfilePic;

  const EditProfilePage({
    required this.userId,
    required this.currentName,
    required this.currentEmail,
    required this.currentPhone,
    required this.currentProfilePic,
  });

  @override
  _EditProfilePageState createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  String? _profilePic;
  bool _isLoading = false;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _emailController = TextEditingController(text: widget.currentEmail);
    _phoneController = TextEditingController(text: widget.currentPhone);
    _profilePic = widget.currentProfilePic;
  }

  Future<void> _updateProfile() async {
    if (!_validateForm()) return;

    setState(() => _isLoading = true);

    try {
      // Upload image if selected
      String? newProfilePicUrl;
      if (_selectedImage != null) {
        final uri = Uri.parse('${AppConfig.baseUrl}/upload-profile-pic');
        final request =
            http.MultipartRequest('POST', uri)
              ..files.add(
                await http.MultipartFile.fromPath(
                  'profile_pic',
                  _selectedImage!.path,
                ),
              )
              ..fields['user_id'] = widget.userId;

        final response = await request.send();
        if (response.statusCode != 200) {
          throw Exception('Failed to upload profile picture');
        }

        final responseData = await response.stream.bytesToString();
        newProfilePicUrl = json.decode(responseData)['profile_pic'];
      }

      // Prepare update payload
      final payload = {
        'name': _nameController.text,
        'email': _emailController.text,
        'phone': _phoneController.text,
        if (newProfilePicUrl != null) 'profile_pic': newProfilePicUrl,
      };

      // Send update request
      final client =
          HttpClient()..badCertificateCallback = (cert, host, port) => true;
      final ioClient = IOClient(client);

      final response = await ioClient.put(
        Uri.parse('${AppConfig.baseUrl}/user/${widget.userId}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        throw Exception('Failed to update profile: ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _validateForm() {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter your name',
            style: TextStyle(color: textColor),
          ),
        ),
      );
      return false;
    }
    return true;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
      return 'Please enter a valid email';
    }
    return null;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Widget _buildProfilePicture() {
    return Center(
      child: Stack(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: tabColor, width: 2),
            ),
            child: ClipOval(
              child:
                  _selectedImage != null
                      ? Image.file(_selectedImage!, fit: BoxFit.cover)
                      : (_profilePic?.isNotEmpty ?? false)
                      ? CachedNetworkImage(
                        imageUrl:
                            _profilePic!.startsWith('/uploads')
                                ? '${AppConfig.baseUrl}$_profilePic'
                                : _profilePic!,
                        placeholder:
                            (context, url) =>
                                CircularProgressIndicator(color: tabColor),
                        errorWidget:
                            (context, url, error) =>
                                Icon(Icons.person, size: 60, color: greyColor),
                      )
                      : Icon(Icons.person, size: 60, color: greyColor),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: appBarColor,
                shape: BoxShape.circle,
                border: Border.all(color: backgroundColor, width: 2),
              ),
              child: Icon(Icons.camera_alt, size: 20, color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    bool readOnly = false,
    String? Function(String?)? validator,
    IconData? icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor)),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        readOnly: readOnly,
        style: TextStyle(color: textColor, fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon) : null,
          labelStyle: TextStyle(color: greyColor),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text('Edit profile', style: TextStyle(color: textColor)),
        backgroundColor: backgroundColor,
        elevation: 0,
        automaticallyImplyLeading: true,
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon:
                _isLoading
                    ? CircularProgressIndicator(color: tabColor)
                    : Icon(Icons.check, color: tabColor),
            onPressed: _isLoading ? null : _updateProfile,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: 30),
            GestureDetector(onTap: _pickImage, child: _buildProfilePicture()),
            SizedBox(height: 30),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildInputField(
                    label: 'Name',
                    controller: _nameController,
                    icon: Icons.person,
                  ),
                  SizedBox(height: 20),
                  _buildInputField(
                    label: 'Email',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                    readOnly: true,
                    icon: Icons.email,
                  ),
                  SizedBox(height: 20),
                  _buildInputField(
                    label: 'Phone number',
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    icon: Icons.phone,
                  ),

                  SizedBox(height: 20),
                  _buildInputField(
                    label: 'About',
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    icon: Icons.info,
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Your name is not your username or pin. This name will be visible to your contacts.',
                style: TextStyle(color: greyColor, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
