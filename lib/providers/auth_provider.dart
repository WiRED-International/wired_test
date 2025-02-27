import 'package:flutter/material.dart';
import 'dart:convert';
import '../pages/cme/cme_info.dart';
import '../pages/cme/login.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthProvider with ChangeNotifier {
  bool _isLoggedIn = false; // Tracks the authentication status
  String? _authToken;
  DateTime? _tokenExpiry;
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  bool get isLoggedIn => _isLoggedIn;
  String? get authToken => _authToken;

  // Load stored token & expiry on app startup
  Future<void> loadStoredAuthData() async {
    _authToken = await storage.read(key: 'authToken');
    final expiryString = await storage.read(key: 'tokenExpiry');

    if (_authToken != null && expiryString != null) {
      _tokenExpiry = DateTime.tryParse(expiryString);
      _isLoggedIn = _tokenExpiry != null && !isTokenExpired();
    }

    notifyListeners();
  }

  // Log in the user and store token securely
  Future<void> logIn(String authToken, DateTime expiry) async {
    _authToken = authToken;
    _tokenExpiry = expiry;
    _isLoggedIn = true;

    await storage.write(key: 'authToken', value: authToken);
    await storage.write(key: 'tokenExpiry', value: expiry.toIso8601String());

    notifyListeners();
    print('User logged in. Token: $_authToken, Expiry: $_tokenExpiry');
  }

  // Log out the user
  Future<void> logOut() async {
    print('logOut: Logging out user.');

    await storage.delete(key: 'authToken');
    await storage.delete(key: 'tokenExpiry');


    _authToken = null;
    _tokenExpiry = null;
    _isLoggedIn = false;
    notifyListeners();

    print('User logged out.');
  }

  // Decode JWT to extract user ID
  String? getUserIdFromToken() {
    if (_authToken == null) return null;
    try {
      final parts = _authToken!.split('.');
      if (parts.length != 3) return null;

      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payloadMap = json.decode(payload) as Map<String, dynamic>;

      print("Decoded JWT Payload: $payloadMap"); // Debugging: Check user ID field
      return payloadMap['id']?.toString();
    } catch (e) {
      print('Error decoding token: $e');
      return null;
    }
  }

  // Check if token is expired
  bool isTokenExpired() {
    if (_tokenExpiry == null) return true;

    final bufferDuration = Duration(minutes: 2);
    final expiryWithBuffer = _tokenExpiry!.subtract(bufferDuration);

    return DateTime.now().isAfter(expiryWithBuffer);
  }

  // Handle authentication status and redirect if needed
  void handleAuthentication(BuildContext context) {
    if (_authToken == null) {
      Future.microtask(() {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => CmeInfo()),
        );
      });
    } else if (isTokenExpired()) {
      print('Token expired. Logging out.');
      Future.microtask(() {
        logOut();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => Login()),
        );
      });
    }
  }
}