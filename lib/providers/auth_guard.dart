import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/pages/cme/cme_info.dart';
import '../providers/auth_provider.dart';

class AuthGuard extends StatelessWidget {
  final Widget child;

  const AuthGuard({required this.child});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    // Check if the user is logged in
    if (!authProvider.isLoggedIn) {
      Future.microtask(() {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => CmeInfo()),
        );
      });
      return SizedBox(); // Return an empty widget temporarily
    }

    // If logged in, show the protected page
    return child;
  }
}

// class AuthGuard extends StatelessWidget {
//   final Widget child;
//
//   const AuthGuard({required this.child});
//
//   @override
//   Widget build(BuildContext context) {
//     final authProvider = Provider.of<AuthProvider>(context);
//
//     // Check if the token is expired
//     if (authProvider.isTokenExpired()) {
//       Future.microtask(() async {
//         final renewed = await authProvider.renewToken();
//         if (!renewed) {
//           Navigator.pushReplacement(
//             context,
//             MaterialPageRoute(builder: (context) => CmeInfo()),
//           );
//         }
//       });
//       return SizedBox(); // Return an empty widget temporarily
//     }
//
//     // If logged in and token is valid, show the protected page
//     return child;
//   }
// }