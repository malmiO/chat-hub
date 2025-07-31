import 'package:http/http.dart' as http;
import 'package:http/http.dart' as ioClient;
import 'dart:convert';
import 'package:slt_chat/config/config.dart';
import 'package:http/io_client.dart';
import 'dart:io';

/* import 'package:shared_preferences/shared_preferences.dart';
 */
class NetworkConteroller {
  // Fetch suggested users with the userId as a parameter
  Future<List<dynamic>> fetchSuggestedUsers(String userId) async {
    final httpClient =
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;

    final ioClient = IOClient(httpClient);

    final response = await ioClient.get(
      Uri.parse('${AppConfig.baseUrl}/suggested-users/$userId'),
    );
    print('Raw API response: ${response.body}');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data is! Map<String, dynamic>) {
        throw Exception('Invalid response format');
      }

      final users = data['suggested_users'] as List;
      print('Parsed users: $users');
      return users;
    } else if (response.statusCode >= 500) {
      throw Exception('Server error: ${response.statusCode}');
    } else {
      throw Exception('Failed with status: ${response.statusCode}');
    }
  }

  // Fetch friend requests with the userId as a parameter
  Future<Map<String, dynamic>> fetchFriendRequests(String userId) async {
    final httpClient =
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;

    final ioClient = IOClient(httpClient);

    final response = await ioClient.get(
      Uri.parse('${AppConfig.baseUrl}/friend-requests/$userId'),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load friend requests');
    }
  }

  Future<Map<String, dynamic>> fetchConnections(String userId) async {
    final httpClient =
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;

    final ioClient = IOClient(httpClient);

    final response = await ioClient.get(
      Uri.parse('${AppConfig.baseUrl}/connections/$userId'),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load connections');
    }
  }

  Future<Map<String, dynamic>> fetchSentRequests(String userId) async {
    final response = await ioClient.get(
      Uri.parse('${AppConfig.baseUrl}/sent-requests/$userId'),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load sent requests');
    }
  }

  // Fetch pending requests with the userId as a parameter
  Future<Map<String, dynamic>> fetchPendingRequests(String userId) async {
    final httpClient =
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;

    final ioClient = IOClient(httpClient);

    final response = await ioClient.get(
      Uri.parse('${AppConfig.baseUrl}/pending-requests/$userId'),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load pending requests');
    }
  }

  // Send a friend request
  Future<void> sendFriendRequest(String senderId, String receiverId) async {
    final httpClient =
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;

    final ioClient = IOClient(httpClient);

    final response = await ioClient.post(
      Uri.parse('${AppConfig.baseUrl}/send-request'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'senderId': senderId, 'receiverId': receiverId}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send friend request');
    }
  }

  // Accept a friend request
  Future<void> acceptFriendRequest(String senderId, String receiverId) async {
    final httpClient =
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;

    final ioClient = IOClient(httpClient);

    final response = await ioClient.post(
      Uri.parse('${AppConfig.baseUrl}/accept-request'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'senderId': senderId, 'receiverId': receiverId}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to accept friend request');
    }
  }
}
