import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class LocationService {
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
        await _showPermissionDeniedAlert(context);
        prefs.setBool('hasDeniedLocation', true);
        
        return null;
      }
    }
  }

  Future<void> _showPermissionDeniedAlert(BuildContext context) {
    // Await the dialog to make sure the code doesn't continue until the user closes it
    return showDialog<void>(
      context: context,
      barrierDismissible: false,  // Prevent dismissing by tapping outside
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
      print('Error getting location: $e');
      return {'latitude': null, 'longitude': null};
    }
  }

 Future<void> saveDownload(int moduleId, Map<String, double?>? location) async {
  try {
    // If location is null, set it to an object with null values
    location ??= {'latitude': null, 'longitude': null};

    var requestBody = {
      'module_id': moduleId,
      'latitude': location['latitude'],
      'longitude': location['longitude'],
    };

    debugPrint('requestBody: $requestBody');

    var response = await http.post(
      Uri.parse('http://10.0.2.2:3000/api/downloads'),
      body: jsonEncode(requestBody),
      headers: {'Content-Type': 'application/json'},
    );

    debugPrint('Response code: ${response.statusCode}');
    debugPrint('Response body: ${response.body}');

  } catch (e) {
    debugPrint('Error occurred in save download: $e');
  }
}

}
