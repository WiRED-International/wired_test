import 'package:flutter/material.dart';
import 'dart:convert';
import '../pages/cme/cme_info.dart';
import '../pages/cme/login.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthProvider with ChangeNotifier {
  bool _isLoading = true;
  bool _isLoggedIn = false; // Tracks the authentication status
  String? _authToken;
  DateTime? _tokenExpiry;
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  bool get isLoggedIn => _isLoggedIn;
  String? get authToken => _authToken;
  bool get isLoading => _isLoading;

  // Load stored token & expiry on app startup
  Future<void> loadStoredAuthData() async {
    _isLoading = true;
    notifyListeners();

    try {
      _authToken = await storage.read(key: 'authToken');
      debugPrint("🔑 Retrieved authToken: $_authToken");

      final expiryString = await storage.read(key: 'tokenExpiry');

      if (_authToken != null && expiryString != null) {
        _tokenExpiry = DateTime.tryParse(expiryString);
        _isLoggedIn = _tokenExpiry != null && !isTokenExpired();
      } else {
        _isLoggedIn = false;
      }
    } catch (e) {
      print("Error loading stored auth data: $e");
      _isLoggedIn = false;
    } finally {
      _isLoading = false;  // ✅ Ensure loading completes even if an error occurs
      notifyListeners();
    }
  }

  // Log in the user and store token securely
  Future<void> logIn(String authToken, DateTime expiry) async {

    // Convert expiry to UTC before storing
    expiry = expiry.toUtc();

    _authToken = authToken;
    _tokenExpiry = expiry;
    _isLoggedIn = true;

    await storage.write(key: 'authToken', value: authToken);
    await storage.write(key: 'tokenExpiry', value: expiry.toIso8601String());

    notifyListeners();
  }

  // Log out the user
  Future<void> logOut() async {

    await storage.delete(key: 'authToken');
    await storage.delete(key: 'tokenExpiry');

    _authToken = null;
    _tokenExpiry = null;
    _isLoggedIn = false;
    notifyListeners();
  }

  // Decode JWT to extract user ID
  String? getUserIdFromToken() {
    if (_authToken == null) return null;
    try {
      final parts = _authToken!.split('.');
      if (parts.length != 3) return null;

      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payloadMap = json.decode(payload) as Map<String, dynamic>;

      return payloadMap['id']?.toString();
    } catch (e) {
      return null;
    }
  }

  // Check if token is expired
  bool isTokenExpired() {
    if (_tokenExpiry == null) {
      return true;
    }
    final now = DateTime.now().toUtc();
    final expiryUtc = _tokenExpiry!.toUtc();

    return now.isAfter(expiryUtc);
  }

  // Handle authentication status and redirect if needed
  void handleAuthentication(BuildContext context) {

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await loadStoredAuthData();
      if (_authToken == null) {
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => CmeInfo()),
          );
        }
      } else if (isTokenExpired()) {
        await logOut();
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => Login()),
          );
        }
      }
    });
  }
}