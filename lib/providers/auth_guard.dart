import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class AuthGuard extends StatelessWidget {
  final Widget child;

  const AuthGuard({required this.child, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Delegate authentication checks to AuthProvider's handleAuthentication method
    Future.microtask(() => authProvider.handleAuthentication(context));

    // Return the protected child if the user is logged in and token is valid
    if (authProvider.isLoggedIn && !authProvider.isTokenExpired()) {
      return child;
    }

    // Return an empty widget temporarily during navigation
    return const SizedBox();
  }
}