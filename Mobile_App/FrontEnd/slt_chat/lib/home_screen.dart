import '/common/widgets/colors.dart';
import 'package:flutter/material.dart';
import 'Features/Auth/controller/auth_controller.dart';
import 'Features/Auth/screens/login_screen.dart';
import 'mobile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatelessWidget {
  final AuthController authController = AuthController();

  void logout(BuildContext context) async {
    await authController.logout(); // Handle logout
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => LoginScreen(),
      ), // Navigate to login screen
    );
  }

  Future<String?> _getUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('userId');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: backgroundColor,
        title: RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: "SLT",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: " ChatHub",
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey),
            onPressed: () {},
          ),
          /*  IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => logout(context),
          ), */
        ],
      ),
      body: FutureBuilder<String?>(
        future: _getUserId(), // Fetch userId from SharedPreferences
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          } else if (snapshot.hasData) {
            // Pass the userId to MobileLayoutScreen
            String? userId = snapshot.data;
            return MobileLayoutScreen(userId: userId);
          } else {
            return const Center(child: Text("User not found"));
          }
        },
      ),
    );
  }
}
