import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pub_semver/pub_semver.dart';

class UpdateChecker {
  static const _lookupTimeout = Duration(seconds: 15);
  static const String androidPackageName = "com.wiredInternational.wired_app";
  static const String playStoreUrl =
      "https://play.google.com/store/apps/details?id=com.wiredInternational.wired_app";

  static const String iosAppId = "6744303795"; // Replace with actual ID
  static const String appStoreUrl = "https://apps.apple.com/app/id$iosAppId";

  /// Get the installed version of the app
  static Future<String?> getInstalledVersion() async {
    try {
      final packageInfo =
          await PackageInfo.fromPlatform().timeout(_lookupTimeout);
      return packageInfo.version;
    } catch (error) {
      debugPrint('Unable to read installed app version: $error');
      return null;
    }
  }

  static Future<http.Response> _getStoreResponse(Uri url) async {
    final client = http.Client();
    try {
      return await client.get(url).timeout(_lookupTimeout);
    } finally {
      client.close();
    }
  }

  /// Fetch the latest version from the Play Store (Android)
  static Future<String?> _getLatestVersionFromPlayStore() async {
    try {
      final response = await _getStoreResponse(Uri.parse(playStoreUrl));
      if (response.statusCode == 200) {
        final regex = RegExp(r'\[\[\["([0-9]+(?:\.[0-9]+)*)"\]\]');
        final match = regex.firstMatch(response.body);
        if (match != null) {
          return match.group(1);
        }
      }
    } catch (e) {
      print("Error fetching Play Store version: $e");
    }
    return null;
  }

  /// Fetch the latest version from the App Store (iOS)
  static Future<String?> _getLatestVersionFromAppStore() async {
    try {
      final response = await _getStoreResponse(
          Uri.parse("https://itunes.apple.com/lookup?id=$iosAppId"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is! Map<String, dynamic>) return null;
        final count = data['resultCount'];
        final results = data['results'];
        if (count is! num ||
            count <= 0 ||
            results is! List ||
            results.isEmpty) {
          return null;
        }
        final first = results.first;
        if (first is! Map) return null;
        final version = first['version'];
        return version is String && version.isNotEmpty ? version : null;
      }
    } catch (e) {
      print("Error fetching App Store version: $e");
    }
    return null;
  }

  /// Public method to check for update
  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      final installedVersion = await getInstalledVersion();
      if (installedVersion == null || installedVersion.isEmpty) return;
      // Parse before looking up the store: malformed platform data is nonfatal.
      final installed = Version.parse(installedVersion);
      String? latestVersion;

      if (Platform.isAndroid) {
        latestVersion = await _getLatestVersionFromPlayStore();
      } else if (Platform.isIOS) {
        latestVersion = await _getLatestVersionFromAppStore();
      }

      if (latestVersion == null || latestVersion.isEmpty) return;
      final latest = Version.parse(latestVersion);
      print("Installed version: $installedVersion");
      print("Latest version from App Store: $latestVersion");

      if (installed < latest && context.mounted) {
        showUpdateDialog(context);
      }
    } catch (error) {
      // Update checks are optional; platform/response/parsing failures must not
      // interrupt Home or produce an unhandled asynchronous exception.
      debugPrint('Unable to check for app updates: $error');
    }
  }

  /// Show the update alert dialog
  static void showUpdateDialog(BuildContext context) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Update Available"),
          content: Text(
              "A new version of the app is available. Please update for the best experience."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("Later"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openStore();
              },
              child: Text("Update Now"),
            ),
          ],
        );
      },
    );
  }

  /// Open respective store
  static Future<void> _openStore() async {
    final Uri url = Uri.parse(Platform.isAndroid ? playStoreUrl : appStoreUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      print("Could not launch store URL");
    }
  }
}
