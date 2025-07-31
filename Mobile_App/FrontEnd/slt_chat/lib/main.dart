import 'package:flutter/material.dart';
import 'package:slt_chat/SplashScreen.dart';
import 'Features/Auth/screens/login_screen.dart';
import 'home_screen.dart';
import 'Features/Auth/controller/auth_controller.dart';
import 'service/local_db_helper.dart';
import 'service/connectivity_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize critical services first
  await LocalDBHelper().database; // Initialize DB before UI

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ConnectivityService(),
          lazy: false, // Initialize immediately
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SLT Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: FutureBuilder<bool>(
        future: _initializeApp(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SplashScreen();
          }
          return snapshot.data == true ? HomeScreen() : LoginScreen();
        },
      ),
    );
  }

  Future<bool> _initializeApp() async {
    // Only check local data for initial routing
    final hasLocalData = await LocalDBHelper().hasData();
    if (!hasLocalData) return false;

    // Start token validation in background without waiting
    _validateTokenInBackground();
    return true;
  }

  void _validateTokenInBackground() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      try {
        await AuthController().validateToken(token);
      } catch (e) {
        print("Background token validation error: $e");
      }
    }
  }
}
