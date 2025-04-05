import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pages/cme/cme_info.dart';
import '../providers/auth_provider.dart';

class AuthGuard extends StatelessWidget {
  final Widget child;

  const AuthGuard({required this.child, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    debugPrint("AuthGuard: isLoading=${authProvider.isLoading}, isLoggedIn=${authProvider.isLoggedIn}");

    if (authProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (authProvider.isLoggedIn && !authProvider.isTokenExpired()) {
      return child;
    }

    Future.microtask(() {
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => CmeInfo()),
        );
      }
    });

    return const SizedBox();
  }
}