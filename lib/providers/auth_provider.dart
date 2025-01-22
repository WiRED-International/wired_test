import 'package:flutter/material.dart';

class AuthProvider with ChangeNotifier {
  bool _isLoggedIn = false; // Tracks the authentication status

  bool get isLoggedIn => _isLoggedIn;

  void logIn() {
    _isLoggedIn = true;
    notifyListeners(); // Notify listeners when authentication state changes
  }

  void logOut() {
    _isLoggedIn = false;
    notifyListeners(); // Notify listeners when authentication state changes
  }
}

// class AuthProvider with ChangeNotifier {
//   bool _isLoggedIn = false; // Tracks the authentication status
//   String? _authToken;
//   DateTime? _tokenExpiry;
//
//   bool get isLoggedIn => _isLoggedIn;
//
//   // Log in the user and set the token
//   void logIn(String authToken, DateTime expiry) {
//     _authToken = authToken;
//     _tokenExpiry = expiry;
//     _isLoggedIn = true;
//     notifyListeners(); // Notify listeners when authentication state changes
//   }
//
//   // Log out the user
//   void logOut() {
//     _authToken = null;
//     _tokenExpiry = null;
//     _isLoggedIn = false;
//     notifyListeners(); // Notify listeners when authentication state changes
//   }
//
//   // Check if the token is expired
//   bool isTokenExpired() {
//     if (_tokenExpiry == null) return true;
//     return DateTime.now().isAfter(_tokenExpiry!);
//   }
//
//   // Attempt to renew the token
//   Future<bool> renewToken() async {
//     // Replace this with your token refresh API call logic
//     try {
//       final newToken = await fetchNewToken(_authToken); // Example API call
//       if (newToken != null) {
//         logIn(newToken.token, newToken.expiry); // Update token and expiry
//         return true;
//       }
//     } catch (e) {
//       print('Error renewing token: $e');
//     }
//     logOut(); // Log out if token cannot be renewed
//     return false;
//   }
// }
//
// // Example function for token renewal (replace with actual API call)
// Future<TokenResponse?> fetchNewToken(String? currentToken) async {
//   // Call your backend to get a new token
//   // Return null if renewal fails
//   return null;
// }
//
// class TokenResponse {
//   final String token;
//   final DateTime expiry;
//
//   TokenResponse(this.token, this.expiry);
// }