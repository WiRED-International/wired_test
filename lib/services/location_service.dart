import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'download_event_outbox.dart';
import 'download_installation_reporting.dart';

class LocationService {
  /// Select exactly one reporting path. Queue failure must never fall back to
  /// legacy POST: the queued event may already have reached durable storage.
  Future<void> reportSuccessfulInstallation(
      int moduleId, Map<String, double?>? location,
      {required String publicationKey}) async {
    if (downloadEventOutboxEnabled ||
        DownloadEventOutbox.current?.enabled == true) {
      await queueInstalledDownload(moduleId, location,
          publicationKey: publicationKey);
    } else {
      await saveDownload(moduleId, location);
    }
  }

  Future<Map<String, double?>?> getLocation(BuildContext context) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? hasDeniedLocation = prefs.getBool('hasDeniedLocation');

    PermissionStatus status = await Permission.location.status;

    if (status.isGranted) {
      return await _getCurrentLocation();
    } else if (hasDeniedLocation == true) {
      return null;
    } else {
      PermissionStatus newStatus = await Permission.location.request();
      if (newStatus.isGranted) {
        return await _getCurrentLocation();
      } else {
        if (context.mounted) await _showPermissionDeniedAlert(context);
        prefs.setBool('hasDeniedLocation', true);

        return null;
      }
    }
  }

  Future<void> _showPermissionDeniedAlert(BuildContext context) {
    // Await the dialog to make sure the code doesn't continue until the user closes it
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) {
        return AlertDialog(
          title: const Text('Location Permission'),
          content: const Text(
            'Location permission is optional, but if you would like to help Wired track where health modules are being used, please enable location permissions in your settings. Thank you.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close the dialog
              },
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () async {
                await openAppSettings(); // Open app settings to let user grant permission manually
              },
              child: const Text('Settings'),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, double?>?> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high),
      );
      return {'latitude': position.latitude, 'longitude': position.longitude};
    } catch (e) {
      debugPrint('Error getting location: $e');
      return {'latitude': null, 'longitude': null};
    }
  }

  Future<void> saveDownload(
      int moduleId, Map<String, double?>? location) async {
    try {
      final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
      // final localServer = dotenv.env['LOCAL_SERVER']!;
      // If location is null, set it to an object with null values
      location ??= {'latitude': null, 'longitude': null};

      var requestBody = {
        'module_id': moduleId,
        'latitude': location['latitude'],
        'longitude': location['longitude'],
      };

      debugPrint('requestBody: $requestBody');

      var response = await http.post(
        Uri.parse('$apiBaseUrl/api/downloads'),
        body: jsonEncode(requestBody),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      debugPrint('Response code: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');
    } catch (e) {
      debugPrint('Error occurred in save download: $e');
    }
  }
}
