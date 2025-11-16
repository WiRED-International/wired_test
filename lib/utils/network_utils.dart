import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkUtils {
  /// 🚀 Reliable check:
  /// 1. Is any network available?
  /// 2. Can we reach the real internet?
  static Future<bool> isOnline() async {
    final status = await Connectivity().checkConnectivity();

    if (status == ConnectivityResult.none) {
      return false;
    }

    // Verify real internet
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));

      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}