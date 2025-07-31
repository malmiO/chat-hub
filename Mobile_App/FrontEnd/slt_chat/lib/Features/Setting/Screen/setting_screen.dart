import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:slt_chat/Features/Setting/Screen/about_page.dart';
import 'package:slt_chat/Features/Setting/Screen/help_support_page.dart';
import 'dart:convert';
import '/common/widgets/colors.dart';
import 'package:http/io_client.dart';
import 'dart:io';
import 'package:slt_chat/config/config.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:slt_chat/Features/Setting/Screen/edit_profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  final String userId;

  const SettingsPage({Key? key, required this.userId}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _userName = "Loading...";
  String _phoneNumber = "Loading...";
  String _email = "Loading...";
  String _profilePic = "assets/user.jpg";
  bool _isLoading = true;
  bool _notificationsEnabled = false;
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadCachedData(); // Load cached data immediately
    _fetchUserData(); // Fetch fresh data
  }

  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name_${widget.userId}') ?? "Loading...";
      _phoneNumber =
          prefs.getString('user_phone_${widget.userId}') ?? "Loading...";
      _email = prefs.getString('user_email_${widget.userId}') ?? "Loading...";
      _profilePic =
          prefs.getString('user_profile_pic_${widget.userId}') ??
          "assets/user.jpg";
      _isLoading = false; // Show cached data immediately
    });
  }

  Future<void> _fetchUserData() async {
    setState(() => _isLoading = true);

    try {
      final httpClient =
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true;

      final ioClient = IOClient(httpClient);

      final response = await ioClient
          .get(Uri.parse('${AppConfig.baseUrl}/user/${widget.userId}'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          _userName = data['name'] ?? "No Name";
          _phoneNumber = data['phone'] ?? "No Phone";
          _email = data['email'] ?? "No Email";
          _profilePic = data['profile_pic'] ?? "assets/user.jpg";
          _isLoading = false;
        });
        // Save to shared_preferences
        await prefs.setString('user_name_${widget.userId}', _userName);
        await prefs.setString('user_phone_${widget.userId}', _phoneNumber);
        await prefs.setString('user_email_${widget.userId}', _email);
        await prefs.setString('user_profile_pic_${widget.userId}', _profilePic);
      } else {
        throw Exception('Failed to load user data: ${response.statusCode}');
      }
    } on SocketException {
      _showErrorSnackbar('No internet connection. Showing cached data.');
    } on TimeoutException {
      _showErrorSnackbar('Request timed out. Showing cached data.');
    } catch (e) {
      _showErrorSnackbar('Error loading user data. Showing cached data.');
      print('Error fetching user data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      // Clear cached data on logout
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_name_${widget.userId}');
      await prefs.remove('user_phone_${widget.userId}');
      await prefs.remove('user_email_${widget.userId}');
      await prefs.remove('user_profile_pic_${widget.userId}');
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  Widget _buildProfileHeader() {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.blueAccent, width: 3),
          ),
          child: CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey[300],
            child:
                _profilePic.startsWith('/uploads') ||
                        _profilePic.startsWith('http')
                    ? CachedNetworkImage(
                      imageUrl:
                          _profilePic.startsWith('/uploads')
                              ? '${AppConfig.baseUrl}$_profilePic'
                              : _profilePic,
                      imageBuilder:
                          (context, imageProvider) => CircleAvatar(
                            radius: 60,
                            backgroundImage: imageProvider,
                          ),
                      placeholder:
                          (context, url) => const CircularProgressIndicator(),
                      errorWidget:
                          (context, url, error) => Text(
                            _userName.isNotEmpty
                                ? _userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: backgroundColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                    )
                    : CircleAvatar(
                      radius: 60,
                      backgroundImage: AssetImage(_profilePic),
                      child:
                          _profilePic == "assets/user.jpg" ||
                                  _profilePic == "default.jpg"
                              ? Text(
                                _userName.isNotEmpty
                                    ? _userName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: backgroundColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 24,
                                ),
                              )
                              : null,
                    ),
          ),
        ),

        const SizedBox(height: 16),
        Text(
          _userName,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(_email, style: TextStyle(fontSize: 16, color: Colors.grey[400])),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => EditProfilePage(
                        userId: widget.userId,
                        currentName: _userName,
                        currentEmail: _email,
                        currentPhone: _phoneNumber,
                        currentProfilePic: _profilePic,
                      ),
                ),
              ).then((refresh) {
                if (refresh == true) {
                  _fetchUserData(); // Refresh data after update
                }
              }),
          child: Text('Edit Profile', style: TextStyle(color: Colors.blue)),
        ),
      ],
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? Colors.white),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      minLeadingWidth: 24,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 28,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildProfileHeader(),
                    ),
                    const Divider(height: 1, thickness: 1, color: Colors.grey),
                    _buildSettingsItem(
                      icon: Icons.notifications,
                      title: 'Notifications',
                      trailing: Switch(
                        value: _notificationsEnabled,
                        onChanged:
                            (value) =>
                                setState(() => _notificationsEnabled = value),
                        activeColor: Colors.blue,
                      ),
                    ),
                    _buildSettingsItem(
                      icon: Icons.help_outline,
                      title: 'Help & Support',
                      onTap:
                          () => Navigator.push(
                            context,
                            PageRouteBuilder(
                              transitionDuration: Duration(milliseconds: 900),
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      const HelpSupportPage(),
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
                                return SlideTransition(
                                  position: animation.drive(tween),
                                  child: child,
                                );
                              },
                            ),
                          ),
                    ),
                    _buildSettingsItem(
                      icon: Icons.info_outline,
                      title: 'About',
                      onTap:
                          () => Navigator.push(
                            context,
                            PageRouteBuilder(
                              transitionDuration: Duration(milliseconds: 900),
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      const AboutPage(),
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
                                return SlideTransition(
                                  position: animation.drive(tween),
                                  child: child,
                                );
                              },
                            ),
                          ),
                    ),
                    _buildSettingsItem(
                      icon: Icons.security,
                      title: 'Privacy Policy',
                      onTap: () => Navigator.pushNamed(context, '/privacy'),
                    ),
                    const Divider(height: 1, thickness: 1, color: Colors.grey),
                    _buildSettingsItem(
                      icon: Icons.logout,
                      title: 'Logout',
                      iconColor: Colors.red,
                      onTap: _logout,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
    );
  }
}
