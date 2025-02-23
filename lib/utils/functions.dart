import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:url_launcher/url_launcher.dart';


Future<void> unzipFile(String zipFilePath) async {
  // Get the application documents directory
  final appDocDir = await getApplicationDocumentsDirectory();
  print('appDocDir1: ${appDocDir.path}');
  final outputDir = Directory('${appDocDir.path}/unzipped_module');

  // Ensure the output directory exists
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  // Open the ZIP file
  final bytes = File(zipFilePath).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);

  // Extract the contents of the ZIP file to the output directory
  for (final file in archive) {
    final filename = file.name;
    final filePath = '${outputDir.path}/$filename';
    if (file.isFile) {
      final data = file.content as List<int>;
      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(data);
    } else {
      Directory(filePath).createSync(recursive: true);
    }
  }
}

Future<void> openHtmlFile(String htmlFilePath) async {
  final uri = Uri.file(htmlFilePath);
  if (await canLaunch(uri.toString())) {
    await launch(uri.toString(), forceSafariVC: false, forceWebView: false);
  } else {
    throw 'Could not launch $htmlFilePath';
  }
}

// Function to check if the device is a tablet
bool isTablet(BuildContext context) {
  var shortestSide = MediaQuery.of(context).size.shortestSide;
  return shortestSide > 600;
}

// Function to get responsive text style
TextStyle responsiveTextStyle(BuildContext context, double baseSize) {
  return TextStyle(
    fontSize: isTablet(context) ? baseSize * 1.5 : baseSize, // Adjust font size for tablets
  );
}

// Function to format timestamp
String formatDate(String timestamp) {
  try {
    final DateTime date = DateTime.parse(timestamp); // Parse the timestamp
    return DateFormat('MMMM yyyy').format(date); // Format to "Month Year"
  } catch (e) {
    return 'Invalid date'; // Handle invalid timestamps
  }
}

// Function to pad base64 string
String normalizeBase64(String base64String) {
  return base64String.padRight(base64String.length + (4 - base64String.length % 4) % 4, '=');
}

// Function to help with scaling in portrait
double getScalingFactor(BuildContext context) {
  Size screenSize = MediaQuery.of(context).size;
  double baseWidth = 360.0;  // Reference width for portrait mode
  double baseHeight = 640.0; // Reference height for portrait mode

  if (screenSize.width > screenSize.height) {
    return ((screenSize.width / baseWidth) + (screenSize.height / baseHeight)) / 2;
  } else {
    return screenSize.width / baseWidth;
  }
}

// Function to check if user is logged in
Future<bool> checkIfUserIsLoggedIn() async {
  final _storage = const FlutterSecureStorage();
  final token = await _storage.read(key: 'authToken');
  print("🔑 Retrieved Token: $token"); // Debugging output

  bool isLoggedIn = token != null && token.isNotEmpty;
  print("✅ User is logged in: $isLoggedIn"); // Debugging output

  return isLoggedIn;
}

// Remove flutter secure storage entry by module id
const FlutterSecureStorage secureStorage = FlutterSecureStorage();

Future<void> deleteStoredScore(String moduleId) async {
  try {
    String? storedScoresJson = await secureStorage.read(key: "quiz_scores");

    if (storedScoresJson != null) {
      Map<String, dynamic> storedScores = jsonDecode(storedScoresJson);

      if (storedScores.containsKey(moduleId)) {
        storedScores.remove(moduleId); // Remove the specific module ID
        await secureStorage.write(key: "quiz_scores", value: jsonEncode(storedScores));
        print("✅ Successfully deleted score for Module ID: $moduleId");
      } else {
        print("⚠️ No score found for Module ID: $moduleId");
      }
    } else {
      print("ℹ️ No stored scores found.");
    }
  } catch (e) {
    print("❌ Error deleting score: $e");
  }
}

// Function to get the badge image based on the number of credits earned
String getBadgeImage(int creditsEarned) {
  if (creditsEarned >= 200) {
    return "assets/images/supreme_badge.png";
  } else if (creditsEarned >= 150) {
    return "assets/images/diamond_badge.png";
  } else if (creditsEarned >= 110) {
    return "assets/images/platinum_badge.png";
  } else if (creditsEarned >= 80) {
    return "assets/images/gold_badge.png";
  } else if (creditsEarned >= 60) {
    return "assets/images/silver_badge.png";
  } else if (creditsEarned >= 50) {
    return "assets/images/circular_bronze_badge.png";
  } else {
    return "assets/images/no_badge.png"; // Default badge or placeholder
  }
}

// Function to get the max credits based on the number of credits earned
int getMaxCredits(int creditsEarned) {
  if (creditsEarned >= 200) {
    return 200; // Supreme
  } else if (creditsEarned >= 150) {
    return 200; // Still aiming for Supreme
  } else if (creditsEarned >= 110) {
    return 150; // Diamond goal
  } else if (creditsEarned >= 80) {
    return 110; // Platinum goal
  } else if (creditsEarned >= 60) {
    return 80; // Gold goal
  } else if (creditsEarned >= 50) {
    return 60; // Silver goal
  } else {
    return 50; // Bronze goal
  }
}

// Function to get the text message for the badge
String getNextBadgeMessage(int creditsEarned, int creditsRemaining) {
  if (creditsEarned >= 200) {
    return "Congratulations! You've reached the highest rank: Supreme! You've earned $creditsEarned credits and your current position is x";
  } else if (creditsEarned >= 150) {
    return "Congratulations! You've completed the necessary CME credits for this year. You've earned $creditsEarned credits, and you have $creditsRemaining more credits to go before reaching Supreme rank. Keep going!";
  } else if (creditsEarned >= 110) {
    return "Congratulations! You've completed the necessary CME credits for this year. You've earned $creditsEarned credits, and you have $creditsRemaining more credits to go before reaching Diamond rank. You're doing great!";
  } else if (creditsEarned >= 80) {
    return "Congratulations! You've completed the necessary CME credits for this year. You've earned $creditsEarned credits, and you have $creditsRemaining more credits to go before reaching Platinum rank. Almost there!";
  } else if (creditsEarned >= 60) {
    return "Congratulations! You've completed the necessary CME credits for this year. You've earned $creditsEarned credits, and you have $creditsRemaining more credits to go before reaching Gold rank. Keep up the momentum!";
  } else if (creditsEarned >= 50) {
    return "Congratulations! You've completed the necessary CME credits for this year. You've earned $creditsEarned credits, and you have $creditsRemaining more credits to go before reaching Silver rank. Good luck!";
  } else {
    return "You have earned $creditsEarned credits this year, and you have $creditsRemaining more credits to go before Dec. 31.";
    return "Congratulations! You've reached the highest rank: Supreme! You've earned $creditsEarned credits and your current position is x";
  }
}

// String getNextBadgeMessage(int creditsEarned, int creditsRemaining) {
//   if (creditsEarned >= 200) {
//     return "Supreme";
//   } else if (creditsEarned >= 150) {
//     return "Supreme";
//   } else if (creditsEarned >= 110) {
//     return "Diamond";
//   } else if (creditsEarned >= 80) {
//     return "Platinum";
//   } else if (creditsEarned >= 60) {
//     return "Gold";
//   } else if (creditsEarned >= 50) {
//     return "Silver";
//   } else {
//     return "Bronze";
//   }
// }
