import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  Future<Map<String, double>?> getLocation(BuildContext context) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? hasDeniedLocation = prefs.getBool('hasDeniedLocation');

    PermissionStatus status = await Permission.location.status;

    if (status.isGranted) {
      return await _getCurrentLocation();
    } else if (hasDeniedLocation == true) {
      // If the user denied before, show the alert
      _showPermissionDeniedAlert(context);
      return null;
    } else {
      PermissionStatus newStatus = await Permission.location.request();

      if (newStatus.isGranted) {
        return await _getCurrentLocation();
      } else {
        prefs.setBool('hasDeniedLocation', true);
        _showPermissionDeniedAlert(context);
        return null;
      }
    }
  }

  void _showPermissionDeniedAlert(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Denied'),
        content: const Text(
          'Location permission is optional, but if you would like to help Wired track where health modules are being used, please enable location permissions in your settings. Thank you.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close alert
            },
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () async {
              // Open app settings to let user grant permission manually
              await openAppSettings();
            },
            child: const Text('Settings'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, double>?> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high),
      );
      return {'latitude': position.latitude, 'longitude': position.longitude};
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }
}
