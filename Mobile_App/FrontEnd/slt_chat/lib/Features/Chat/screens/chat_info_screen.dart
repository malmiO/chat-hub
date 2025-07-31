import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:slt_chat/config/config.dart';

class ChatInfoScreen extends StatelessWidget {
  final String userId;
  final String receiverId;
  final String receiverName;
  final bool isOnline;
  final String lastSeen;
  final String profile;

  const ChatInfoScreen({
    Key? key,
    required this.userId,
    required this.receiverId,
    required this.receiverName,
    required this.isOnline,
    required this.lastSeen,
    required this.profile,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121B22),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2C34),
        title: const Text(
          'Contact info',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile Header
            Container(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blueAccent, width: 3),
                    ),
                    child: ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: '${AppConfig.baseUrl}/${profile}',
                        placeholder:
                            (context, url) => CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.grey.shade300,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                        errorWidget:
                            (context, url, error) => CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.grey.shade400,
                              child: Text(
                                receiverName[0],
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                        fit: BoxFit.cover,
                        width: 120,
                        height: 120,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Text(
                    receiverName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '+94 123 456 6785',
                    style: const TextStyle(
                      color: Color(0xFF8696A0),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              color: const Color(0xFF182229),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'About and Phone Number',
                        style: TextStyle(
                          color: Color(0xFF00A884),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Hey there! I am using SLT ChatHub.',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      subtitle: const Text(
                        'Status',
                        style: TextStyle(
                          color: Color(0xFF8696A0),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    _divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '+1 ${receiverId.substring(0, 3)} ${receiverId.substring(3, 6)}-${receiverId.substring(6)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: const Text(
                        'Mobile',
                        style: TextStyle(
                          color: Color(0xFF8696A0),
                          fontSize: 12,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.message, color: Color(0xFF00A884)),
                          SizedBox(width: 20),
                          Icon(Icons.call, color: Color(0xFF00A884)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Media Section
            Container(
              color: const Color(0xFF182229),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text(
                      'Media, links, and docs',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Color(0xFF8696A0),
                    ),
                    onTap: () {},
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        _buildMediaItem(Icons.image, '0 Photos'),
                        const SizedBox(width: 24),
                        _buildMediaItem(Icons.videocam, '0 Videos'),
                        const SizedBox(width: 24),
                        _buildMediaItem(Icons.insert_drive_file, '0 Docs'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Settings Section
            Container(
              color: const Color(0xFF182229),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text(
                      'Disappearing messages',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    subtitle: const Text(
                      'Off',
                      style: TextStyle(color: Color(0xFF8696A0), fontSize: 14),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Color(0xFF8696A0),
                    ),
                    onTap: () {},
                  ),
                  _divider(),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      'Block ${receiverName.split(' ').first}',
                      style: const TextStyle(
                        color: Color(0xFFFF5757),
                        fontSize: 16,
                      ),
                    ),
                    onTap: () {},
                  ),
                  _divider(),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      'Report ${receiverName.split(' ').first}',
                      style: const TextStyle(
                        color: Color(0xFFFF5757),
                        fontSize: 16,
                      ),
                    ),
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaItem(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF8696A0), size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF8696A0), fontSize: 12),
        ),
      ],
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: const Color(0xFF2A3942),
      indent: 16,
      endIndent: 16,
    );
  }
}
