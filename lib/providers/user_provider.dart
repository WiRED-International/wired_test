import 'package:flutter/material.dart';

class UserProvider with ChangeNotifier {
  String? firstName;
  String? lastName;
  String? email;
  String? dateJoined;

  // Update user data
  void setUser(String firstName, String lastName, String email, String dateJoined) {
    this.firstName = firstName;
    this.lastName = lastName;
    this.email = email;
    this.dateJoined = dateJoined;
    notifyListeners(); // Notify listeners of changes
  }
}