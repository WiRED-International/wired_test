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