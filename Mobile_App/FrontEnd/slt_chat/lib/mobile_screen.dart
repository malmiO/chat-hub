import 'package:slt_chat/Features/Groups/group_list.dart';
import '/Features/Chat/screens/chat_list.dart';
import '/Features/Setting/Screen/setting_screen.dart';
import 'package:flutter/material.dart';
import '/Features/Chat/screens/gemini_chat_screen.dart';
import '/Features/Network/screens/network_screen.dart';

class MobileLayoutScreen extends StatefulWidget {
  final String? userId;

  const MobileLayoutScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _MobileLayoutScreenState createState() => _MobileLayoutScreenState();
}

class _MobileLayoutScreenState extends State<MobileLayoutScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> _screens = [
      ChatList(userId: widget.userId ?? 'defaultUserId'),
      GroupListScreen(userId: widget.userId ?? 'defaultUserId'),
      NetworkScreen(userId: widget.userId ?? 'defaultUserId'),
      const GeminiChatScreen(),
      SettingsPage(userId: widget.userId ?? 'defaultUserId'),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index; // Update the selected index
          });
        },
        backgroundColor: const Color.fromARGB(255, 15, 34, 45),
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chats'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Groups'),
          BottomNavigationBarItem(icon: Icon(Icons.wifi), label: 'Network'),
          BottomNavigationBarItem(
            icon: Icon(Icons.psychology),
            label: 'AI-Assistant',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
