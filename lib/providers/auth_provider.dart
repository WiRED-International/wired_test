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
    print("🔄 Starting loadStoredAuthData...");
    _isLoading = true;
    notifyListeners();

    try {
      print("📂 Reading authToken from storage...");
      _authToken = await storage.read(key: 'authToken');
      print("🔑 Retrieved authToken: $_authToken");

      print("📂 Reading tokenExpiry from storage...");
      final expiryString = await storage.read(key: 'tokenExpiry');
      print("🕒 Retrieved expiryString: $expiryString");

      print("Stored Token: $_authToken");
      print("Stored Expiry String: $expiryString");

      if (_authToken != null && expiryString != null) {
        _tokenExpiry = DateTime.tryParse(expiryString);
        print("📅 Parsed expiry date: $_tokenExpiry");
        _isLoggedIn = _tokenExpiry != null && !isTokenExpired();
        print("✅ Authenticated status: $_isLoggedIn");
      } else {
        print("⚠️ No valid token found. User is NOT logged in.");
        _isLoggedIn = false;
      }
    } catch (e) {
      print("Error loading stored auth data: $e");
      _isLoggedIn = false;
    } finally {
      print("🏁 Before setting isLoading=false");
      _isLoading = false;  // ✅ Ensure loading completes even if an error occurs
      notifyListeners();
      print("🏁 Finished loading. isLoading: $_isLoading");
    }

    print("Finished loading auth data. isLoggedIn: $_isLoggedIn, isLoading: $_isLoading");
  }

  // Log in the user and store token securely
  Future<void> logIn(String authToken, DateTime expiry) async {
    print('Logging in user...');
    print('Received Token: $authToken');
    print('Received Expiry: $expiry');

    // Convert expiry to UTC before storing
    expiry = expiry.toUtc();

    print('Converted Expiry to UTC: $expiry');

    _authToken = authToken;
    _tokenExpiry = expiry;
    _isLoggedIn = true;

    await storage.write(key: 'authToken', value: authToken);
    await storage.write(key: 'tokenExpiry', value: expiry.toIso8601String());

    print('Token stored successfully.');
    print('Expiry stored successfully.');

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
    if (_tokenExpiry == null) {
      print('Token expiry is null, considering it expired.');
      return true;
    }
    final now = DateTime.now().toUtc();
    final expiryUtc = _tokenExpiry!.toUtc();

    print('Checking token expiry: Now = $now, Expiry = $expiryUtc');

    return now.isAfter(expiryUtc);
  }

  // Handle authentication status and redirect if needed
  void handleAuthentication(BuildContext context) {
    // if (_authToken == null) {
    //   Future.microtask(() {
    //     Navigator.pushReplacement(
    //       context,
    //       MaterialPageRoute(builder: (context) => CmeInfo()),
    //     );
    //   });
    // } else if (isTokenExpired()) {
    //   print('Token expired. Logging out.');
    //   Future.microtask(() {
    //     logOut();
    //     Navigator.pushReplacement(
    //       context,
    //       MaterialPageRoute(builder: (context) => Login()),
    //     );
    //   });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await loadStoredAuthData();

      if (_authToken == null) {
        print('No token found, redirecting to CmeInfo.');
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => CmeInfo()),
          );
        }
      } else if (isTokenExpired()) {
        print('Token expired. Logging out.');
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