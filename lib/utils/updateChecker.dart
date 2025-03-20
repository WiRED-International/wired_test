import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateChecker {
  static const String playStoreUrl = "https://play.google.com/store/apps/details?id=com.wiredInternational.wired_app";

  /// Get the installed version of the app
  static Future<String?> getInstalledVersion() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  /// Fetch the latest version from the Play Store
  static Future<String?> getLatestVersion() async {
    try {
      final response = await http.get(Uri.parse(playStoreUrl));
      if (response.statusCode == 200) {
        final regex = RegExp(r'\[\[\["([0-9]+(?:\.[0-9]+)*)"\]\]');
        final match = regex.firstMatch(response.body);
        if (match != null) {
          return match.group(1); // Extract version number
        }
      }
    } catch (e) {
      print("Error fetching Play Store version: $e");
    }
    return null;
  }

  /// Compare versions and show alert if needed
  static Future<void> checkForUpdate(BuildContext context) async {
    String? installedVersion = await getInstalledVersion();
    String? latestVersion = await getLatestVersion();

    if (installedVersion != null &&
        latestVersion != null &&
        installedVersion != latestVersion) {
      showUpdateDialog(context);
    }
  }

  /// Show the update alert dialog
  static void showUpdateDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Update Available"),
          content: Text("A new version of the app is available. Please update for the best experience."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("Later"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openPlayStore();
              },
              child: Text("Update Now"),
            ),
          ],
        );
      },
    );
  }

  /// Function to open Google Play Store
  static Future<void> _openPlayStore() async {
    final Uri url = Uri.parse(playStoreUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      print("Could not launch $playStoreUrl");
    }
  }
}
