import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class ConnectivityService with ChangeNotifier {
  bool _isOnline = true;

  bool get isOnline => _isOnline;

  ConnectivityService() {
    _init();
  }

  Future<void> _init() async {
    final connectivity = Connectivity();
    var results = await connectivity.checkConnectivity();
    _updateStatus(
      results.isNotEmpty && results.any((r) => r != ConnectivityResult.none),
    );

    connectivity.onConnectivityChanged.listen((results) {
      // Check if at least one connection is active
      _updateStatus(
        results.isNotEmpty && results.any((r) => r != ConnectivityResult.none),
      );
    });
  }

  void _updateStatus(bool isNowOnline) {
    if (_isOnline != isNowOnline) {
      _isOnline = isNowOnline;
      notifyListeners();
    }
  }
}
