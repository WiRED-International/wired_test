import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../pages/cme/cme_info.dart';
import '../providers/auth_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class AuthGuard extends StatelessWidget {
  final Widget child;

  const AuthGuard({required this.child, Key? key}) : super(key: key);

  Future<bool> _hasInternet() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    debugPrint("AuthGuard: isLoading=${authProvider.isLoading}, isLoggedIn=${authProvider.isLoggedIn}");

    if (authProvider.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 🔹 2️⃣ User is logged in & token valid → check connectivity
    if (authProvider.isLoggedIn && !authProvider.isTokenExpired()) {
      return FutureBuilder<bool>(
        future: _hasInternet(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // 🚫 No Internet
          if (snapshot.hasData && !snapshot.data!) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off,
                          size: 80, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'No Internet Connection',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This page requires an internet connection to load your CME data.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context); // Go back to previous screen
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          // ✅ Online → show protected child page (e.g. CMETracker)
          return child;
        },
      );
    }

    // 🔹 3️⃣ Not logged in → redirect to CME Info
    Future.microtask(() {
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => CmeInfo()),
        );
      }
    });

    return const SizedBox();
  }
}