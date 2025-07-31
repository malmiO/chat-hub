import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:http/io_client.dart';
import 'dart:io';
import 'package:slt_chat/config/config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slt_chat/service/local_db_helper.dart';
import 'package:slt_chat/service/connectivity_service.dart';

class AuthController {
  Future<bool> sendOTP(String email) async {
    try {
      print("Sending OTP to: $email");
      final httpClient =
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true;

      final ioClient = IOClient(httpClient);
      final response = await ioClient.post(
        Uri.parse('${AppConfig.baseUrl}/send-otp'),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({"email": email}),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print("Error: ${response.statusCode}, Body: ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception: $e");
      return false;
    }
  }

  // **Verify OTP**
  Future<String?> verifyOTP(String email, String otp) async {
    final httpClient =
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;

    final ioClient = IOClient(httpClient);
    final response = await ioClient.post(
      Uri.parse('${AppConfig.baseUrl}/verify-otp'),
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode({"email": email, "otp": otp}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      if (data['token'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('userId', data['user']['id']);
        return data['token'];
      }
      return null;
    }
    return null;
  }

  // **Register New User**
  Future<bool> registerUser(
    String name,
    String email,
    String? profilePicBase64,
  ) async {
    final httpClient =
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;

    final ioClient = IOClient(httpClient);

    final response = await ioClient.post(
      Uri.parse('${AppConfig.baseUrl}/register'),
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode({
        "email": email,
        "name": name,
        "profile_pic": profilePicBase64,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      String userId = data['userId'];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['token'] ?? '');
      await prefs.setString('userId', userId);
      await prefs.setString(
        'username',
        data['user'] != null ? data['user']['name'] ?? '' : '',
      );
      await prefs.setString(
        'email',
        data['user'] != null ? data['user']['email'] ?? '' : '',
      );
      return true;
    }
    return false;
  }

  // **Auto-Login**
  /*   Future<bool> autoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final userId = prefs.getString('userId');

    if (token == null || userId == null) return false;
    final localDB = LocalDBHelper();
    final hasLocalData = await localDB.hasData();

    if (hasLocalData) return true;

    try {
      final httpClient =
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true;

      final ioClient = IOClient(httpClient);
      final response = await ioClient.get(
        Uri.parse('${AppConfig.baseUrl}/auto-login?token=$token'),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  } */

  Future<bool> autoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final userId = prefs.getString('userId');

    if (token == null || userId == null) return false;

    // Only check local data - defer network validation
    return await LocalDBHelper().hasData();
  }

  Future<void> validateToken(String token) async {
    try {
      final response = await IOClient(
            HttpClient()..badCertificateCallback = (cert, host, port) => true,
          )
          .get(Uri.parse('${AppConfig.baseUrl}/auto-login?token=$token'))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode != 200) {
        await logout();
      }
    } catch (e) {
      print("Token validation error: $e");
    }
  }

  // **Resend OTP**
  Future<bool> resendOTP(String email) async {
    try {
      final httpClient =
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true;

      final ioClient = IOClient(httpClient);

      final response = await ioClient.post(
        Uri.parse('${AppConfig.baseUrl}/send-otp'), // SAME AS sendOTP
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({"email": email}),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print("Resend OTP Failed: ${response.statusCode} - ${response.body}");
        return false;
      }
    } catch (e) {
      print("Error resending OTP: $e");
      return false;
    }
  }

  // **Logout**
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
