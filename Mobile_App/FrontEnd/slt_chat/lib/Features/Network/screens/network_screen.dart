/* import 'package:chat_app/common/widgets/colors.dart';
import 'package:flutter/material.dart';
import '../controller/network_conteroller.dart';

class NetworkScreen extends StatefulWidget {
  final String userId;

  const NetworkScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _NetworkScreenState createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  List<dynamic> suggestedUsers = [];
  List<dynamic> friendRequests = [];

  final NetworkConteroller _networkConteroller = NetworkConteroller();

  @override
  void initState() {
    super.initState();
    fetchSuggestedUsers();
    fetchFriendRequests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Network', style: TextStyle(color: Colors.white)),
        backgroundColor: backgroundColor,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Debug UID: ${widget.userId}",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _sectionTitle("Invitations"),
            ...friendRequests.map((user) => _invitationCard(user)),

            _sectionTitle("People You May Know"),
            ...suggestedUsers.map((user) => _suggestedConnection(user)),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                suggestedUsers.toString(),
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _invitationCard(dynamic request) {
    final user = request['requester'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: ListTile(
        leading: CircleAvatar(
          /* backgroundImage:
              user['profile_pic'] != null
                  ? NetworkImage(
                    'http://192.168.1.104:8000/${user['profile_pic']}',
                  )
                  : null, */
          backgroundColor: Colors.blueAccent,
          child:
              user['profile_pic'] == null
                  ? Icon(Icons.person, color: Colors.white)
                  : null,
        ),
        title: Text(
          user['name'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(user['email']),
        trailing: ElevatedButton(
          onPressed: () => acceptFriendRequest(request['request_id']),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: const Text("Accept"),
        ),
      ),
    );
  }

  Widget _suggestedConnection(dynamic user) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green,
          child:
              user['profile_pic'] != null
                  ? Icon(Icons.person, color: Colors.white)
                  : null,
        ),
        title: Text(
          user['id'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(user['email']),
        trailing: ElevatedButton(
          onPressed: () => sendFriendRequest(user['id']),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: const Text("Connect"),
        ),
      ),
    );
  }

  void fetchSuggestedUsers() {
    _networkConteroller.fetchSuggestedUsers(widget.userId).then((users) {
      setState(() {
        suggestedUsers = users;
      });
    });
  }

  void fetchFriendRequests() {
    _networkConteroller.fetchFriendRequests(widget.userId).then((response) {
      setState(() {
        friendRequests = response['requests']; // Extract 'requests' list
      });
    });
  }

  void sendFriendRequest(String receiverId) {
    _networkConteroller.sendFriendRequest(widget.userId, receiverId).then((_) {
      fetchSuggestedUsers(); // Refresh suggested users
    });
  }

  void acceptFriendRequest(String senderId) {
    _networkConteroller.acceptFriendRequest(senderId, widget.userId).then((_) {
      fetchFriendRequests(); // Refresh friend requests
    });
  }
}
 */
/* 
import '/common/widgets/colors.dart';
import 'package:flutter/material.dart';
import '../controller/network_conteroller.dart';

class NetworkScreen extends StatefulWidget {
  final String userId;

  const NetworkScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _NetworkScreenState createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  List<dynamic> suggestedUsers = [];
  List<dynamic> friendRequests = [];

  final NetworkConteroller _networkConteroller = NetworkConteroller();

  @override
  void initState() {
    super.initState();
    fetchSuggestedUsers();
    fetchFriendRequests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Network', style: TextStyle(color: Colors.white)),
        backgroundColor: backgroundColor,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Debug UID: ${widget.userId}",
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _sectionTitle("Invitations"),
            ...friendRequests.map((user) => _invitationCard(user)),

            _sectionTitle("People You May Know"),
            ...suggestedUsers.map((user) => _suggestedConnection(user)),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                suggestedUsers.toString(),
                style: TextStyle(
                  fontSize: 12,
                  color: const Color.fromARGB(255, 225, 225, 225),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white, // Text color for dark background
        ),
      ),
    );
  }

  Widget _invitationCard(dynamic request) {
    final user = request['requester'];

    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: ListTile(
        tileColor: backgroundColor,
        leading: CircleAvatar(
          backgroundColor: Colors.blueAccent,
          child:
              user['profile_pic'] == null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
        ),
        title: Text(
          user['name'],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          user['email'],
          style: TextStyle(color: Colors.grey[300]),
        ),
        trailing: ElevatedButton(
          onPressed: () => acceptFriendRequest(request['request_id']),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: const Text("Accept"),
        ),
      ),
    );
  }

  Widget _suggestedConnection(dynamic user) {
    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: ListTile(
        tileColor: backgroundColor,
        leading: CircleAvatar(
          backgroundColor: Colors.green,
          child:
              user['profile_pic'] != null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
        ),
        title: Text(
          user['name'],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          user['email'],
          style: TextStyle(color: Colors.grey[300]),
        ),
        trailing: ElevatedButton(
          onPressed: () => sendFriendRequest(user['id']),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: const Text("Connect"),
        ),
      ),
    );
  }

  void fetchSuggestedUsers() {
    _networkConteroller.fetchSuggestedUsers(widget.userId).then((users) {
      setState(() {
        suggestedUsers = users;
      });
    });
  }

  void fetchFriendRequests() {
    _networkConteroller.fetchFriendRequests(widget.userId).then((response) {
      setState(() {
        friendRequests = response['requests'];
      });
    });
  }

  void sendFriendRequest(String receiverId) {
    _networkConteroller.sendFriendRequest(widget.userId, receiverId).then((_) {
      fetchSuggestedUsers();
    });
  }

  void acceptFriendRequest(String senderId) {
    _networkConteroller.acceptFriendRequest(senderId, widget.userId).then((_) {
      fetchFriendRequests();
    });
  }
}
 */
/* 
import '/common/widgets/colors.dart';
import 'package:flutter/material.dart';
import '../controller/network_conteroller.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkScreen extends StatefulWidget {
  final String userId;

  const NetworkScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _NetworkScreenState createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  List<dynamic> suggestedUsers = [];
  List<dynamic> friendRequests = [];
  bool _isLoading = true;
  bool _hasInternet = true;

  final NetworkConteroller _networkConteroller = NetworkConteroller();
  final Connectivity _connectivity = Connectivity();

  @override
  void initState() {
    super.initState();
    _checkInternetAndFetchData();
    // Listen for connectivity changes
    _connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none && !_hasInternet) {
        _checkInternetAndFetchData();
      }
    });
  }

  Future<void> _checkInternetAndFetchData() async {
    var connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      setState(() {
        _hasInternet = false;
        _isLoading = false;
      });
    } else {
      setState(() {
        _hasInternet = true;
        _isLoading = true;
      });
      await fetchSuggestedUsers();
      await fetchFriendRequests();
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });
    await _checkInternetAndFetchData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Network', style: TextStyle(color: Colors.white)),
        backgroundColor: backgroundColor,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshData),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_hasInternet) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No Internet Connection',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check your connection and try again',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refreshData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue, // Background color
                foregroundColor: Colors.white, // Text color
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Debug UID: ${widget.userId}",
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _sectionTitle("Invitations"),
            ...friendRequests.map((user) => _invitationCard(user)),

            _sectionTitle("People You May Know"),
            ...suggestedUsers.map((user) => _suggestedConnection(user)),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                suggestedUsers.toString(),
                style: TextStyle(
                  fontSize: 12,
                  color: const Color.fromARGB(255, 225, 225, 225),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _invitationCard(dynamic request) {
    final user = request['requester'];

    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: ListTile(
        tileColor: backgroundColor,
        leading: CircleAvatar(
          backgroundColor: Colors.blueAccent,
          child:
              user['profile_pic'] == null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
        ),
        title: Text(
          user['name'],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          user['email'],
          style: TextStyle(color: Colors.grey[300]),
        ),
        trailing: ElevatedButton(
          onPressed: () => acceptFriendRequest(request['request_id']),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: const Text("Accept"),
        ),
      ),
    );
  }

  // ... [Keep all your existing helper methods (_sectionTitle, _invitationCard, etc.)] ...

  Future<void> fetchSuggestedUsers() async {
    try {
      final users = await _networkConteroller.fetchSuggestedUsers(
        widget.userId,
      );
      setState(() {
        suggestedUsers = users;
      });
    } catch (e) {
      // Handle error if needed
    }
  }

  Future<void> fetchFriendRequests() async {
    try {
      final response = await _networkConteroller.fetchFriendRequests(
        widget.userId,
      );
      setState(() {
        friendRequests = response['requests'];
      });
    } catch (e) {
      // Handle error if needed
    }
  }

  Widget _suggestedConnection(dynamic user) {
    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: ListTile(
        tileColor: backgroundColor,
        leading: CircleAvatar(
          backgroundColor: Colors.green,
          child:
              user['profile_pic'] != null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
        ),
        title: Text(
          user['name'],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          user['email'],
          style: TextStyle(color: Colors.grey[300]),
        ),
        trailing: ElevatedButton(
          onPressed: () => sendFriendRequest(user['id']),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: const Text("Connect"),
        ),
      ),
    );
  }

  void sendFriendRequest(String receiverId) {
    _networkConteroller.sendFriendRequest(widget.userId, receiverId).then((_) {
      fetchSuggestedUsers();
    });
  }

  void acceptFriendRequest(String senderId) {
    _networkConteroller.acceptFriendRequest(senderId, widget.userId).then((_) {
      fetchFriendRequests();
    });
  }

  // ... [Keep all your existing methods for sendFriendRequest, acceptFriendRequest] ...
}
 */
import '/common/widgets/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controller/network_conteroller.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkScreen extends StatefulWidget {
  final String userId;

  const NetworkScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _NetworkScreenState createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  List<dynamic> suggestedUsers = [];
  List<dynamic> friendRequests = [];
  List<dynamic> connections = [];
  List<dynamic> pendingConnections = [];
  bool _isLoading = true;
  bool _hasInternet = true;
  bool _connectionStatusInitialized = false;

  final NetworkConteroller _networkConteroller = NetworkConteroller();
  final Connectivity _connectivity = Connectivity();

  Set<String> pendingRequests = {};

  @override
  void initState() {
    super.initState();
    initConnectivity();
    _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      _updateConnectionStatus(results);
    });
  }

  Future<void> initConnectivity() async {
    try {
      var result = await _connectivity.checkConnectivity();
      if (!mounted) return;
      await _updateConnectionStatus(result);
    } on PlatformException catch (e) {
      debugPrint('Couldn\'t check connectivity: $e');
      if (!mounted) return;
      setState(() {
        _hasInternet = false;
        _isLoading = false;
        _connectionStatusInitialized = true;
      });
    }
  }

  Future<void> _updateConnectionStatus(List<ConnectivityResult> results) async {
    final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
    debugPrint('Connection status: $result');

    if (!mounted) return;

    setState(() {
      _hasInternet = result != ConnectivityResult.none;
      _connectionStatusInitialized = true;
    });

    if (_hasInternet) {
      await _fetchAllData();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> fetchSentRequests() async {
    try {
      final response = await _networkConteroller.fetchSentRequests(
        widget.userId,
      );
      if (!mounted) return;
      setState(() {
        pendingRequests = Set<String>.from(
          (response['sent_requests'] as List).map(
            (request) => request['receiver_id'].toString(),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load sent requests: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> fetchSuggestedUsers() async {
    try {
      final users = await _networkConteroller.fetchSuggestedUsers(
        widget.userId,
      );
      if (!mounted) return;

      // Filter out current user, pending requests AND existing connections
      final filteredUsers =
          users.where((user) {
            return user['id'] != widget.userId &&
                !pendingRequests.contains(user['id']) &&
                !connections.any((conn) => conn['id'] == user['id']);
          }).toList();

      setState(() => suggestedUsers = filteredUsers);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load suggestions: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> fetchConnections() async {
    try {
      final response = await _networkConteroller.fetchConnections(
        widget.userId,
      );
      if (!mounted) return;
      setState(() => connections = response['connections']);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load connections: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> fetchPendingConnections() async {
    try {
      final response = await _networkConteroller.fetchPendingRequests(
        widget.userId,
      );
      if (!mounted) return;
      setState(() => pendingConnections = response['pending_requests']);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load pending connections: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _fetchAllData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      await Future.wait([
        fetchSentRequests(),
        fetchFriendRequests(),
        fetchPendingConnections(),
        fetchSuggestedUsers(),
      ]);
    } catch (e) {
      debugPrint('Error fetching data: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading data: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshData() async {
    await initConnectivity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Network',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 28,
          ),
        ),
        backgroundColor: backgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshData,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_connectionStatusInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasInternet) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No Internet Connection',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check your connection and try again',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refreshData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: Colors.blue,
      backgroundColor: backgroundColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle("Invitations"),
            if (friendRequests.isEmpty)
              _buildEmptyState("No pending invitations"),
            ...friendRequests.map((user) => _invitationCard(user)),

            _sectionTitle("Your Pending Requests"),
            if (pendingConnections
                .where((request) => request['type'] == 'sent')
                .isEmpty)
              _buildEmptyState("No pending requests"),
            ...pendingConnections
                .where((request) => request['type'] == 'sent')
                .map((request) => _pendingConnectionCard(request)),

            _sectionTitle("People You May Know"),
            if (suggestedUsers.isEmpty)
              _buildEmptyState("No suggestions available"),
            ...suggestedUsers.map((user) => _suggestedConnection(user)),
          ],
        ),
      ),
    );
  }

  Widget _pendingConnectionCard(dynamic request) {
    final user = request['user'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: backgroundColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color.fromARGB(255, 100, 100, 100),
          backgroundImage:
              user['profile_pic'] != null
                  ? NetworkImage(user['profile_pic'])
                  : null,
          child:
              user['profile_pic'] == null
                  ? Icon(Icons.person, color: Colors.grey[600])
                  : null,
        ),
        title: Text(
          user['name'],
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          'Request sent',
          style: TextStyle(color: Colors.grey[400]),
        ),
        trailing: OutlinedButton(
          onPressed: null, // Disabled button
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.grey),
            backgroundColor: Colors.grey.withOpacity(0.2),
            foregroundColor: Colors.grey,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: const Text(
            'Pending',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            color: Colors.grey[400],
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _invitationCard(dynamic request) {
    final user = request['requester'];

    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: ListTile(
        tileColor: backgroundColor,
        leading: CircleAvatar(
          backgroundColor: Colors.blueAccent,
          child:
              user['profile_pic'] == null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
        ),
        title: Text(
          user['name'],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          user['email'],
          style: TextStyle(color: Colors.grey[300]),
        ),
        trailing: ElevatedButton(
          onPressed: () => acceptFriendRequest(request['request_id']),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: const Text("Accept"),
        ),
      ),
    );
  }

  Widget _suggestedConnection(dynamic user) {
    final isPending = pendingRequests.contains(user['id']);
    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: ListTile(
        tileColor: backgroundColor,
        leading: CircleAvatar(
          backgroundColor: Colors.green,
          child:
              user['profile_pic'] != null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
        ),
        title: Text(
          user['name'],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          user['email'],
          style: TextStyle(color: Colors.grey[300]),
        ),
        trailing:
            isPending
                ? ElevatedButton(
                  onPressed: null, // Disabled
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Pending"),
                )
                : ElevatedButton(
                  onPressed: () => sendFriendRequest(user['id']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Connect"),
                ),
      ),
    );
  }

  Future<void> fetchFriendRequests() async {
    try {
      final response = await _networkConteroller.fetchFriendRequests(
        widget.userId,
      );
      if (!mounted) return;
      setState(() => friendRequests = response['requests']);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load friend requests: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void sendFriendRequest(String receiverId) {
    setState(() {
      // Add the receiverId to the pendingRequests list
      pendingRequests.add(receiverId);
    });
    _networkConteroller
        .sendFriendRequest(widget.userId, receiverId)
        .then((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Friend request sent!'),
              backgroundColor: Colors.green,
            ),
          );
          fetchSuggestedUsers();
        })
        .catchError((e) {
          if (!mounted) return;

          setState(() {
            pendingRequests.remove(receiverId);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to send request: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        });
  }

  void acceptFriendRequest(String requestId) {
    _networkConteroller
        .acceptFriendRequest(requestId, widget.userId)
        .then((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Friend request accepted!'),
              backgroundColor: Colors.green,
            ),
          );
          fetchFriendRequests();
        })
        .catchError((e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to accept request: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        });
  }
}
