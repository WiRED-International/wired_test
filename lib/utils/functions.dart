import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> unzipFile(String zipFilePath) async {
  // Get the application documents directory
  final appDocDir = await getApplicationDocumentsDirectory();
  debugPrint('appDocDir1: ${appDocDir.path}');
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

  if (await canLaunchUrl(uri)) {
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication, // or LaunchMode.platformDefault
    );
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
    return DateFormat('MMM dd, yyyy').format(date); // Format to "Month Year"
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
  debugPrint("Retrieved Token: $token"); // Debugging output

  bool isLoggedIn = token != null && token.isNotEmpty;
  debugPrint("User is logged in: $isLoggedIn"); // Debugging output

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
        debugPrint("Successfully deleted score for Module ID: $moduleId");
      } else {
        debugPrint("No score found for Module ID: $moduleId");
      }
    } else {
      debugPrint("No stored scores found.");
    }
  } catch (e) {
    debugPrint("Error deleting score: $e");
  }
}

// Function to get the rank text based on credits earned
String getRankText(int creditsEarned) {
  if (creditsEarned >= 200) {
    return "Rank: Supreme CHW";
  } else if (creditsEarned >= 150) {
    return "Rank: Diamond CHW";
  } else if (creditsEarned >= 110) {
    return "Rank: Platinum CHW";
  } else if (creditsEarned >= 80) {
    return "Rank: Gold CHW";
  } else if (creditsEarned >= 60) {
    return "Rank: Silver CHW";
  } else if (creditsEarned >= 50) {
    return "Rank: Bronze CHW";
  } else {
    return "Rank: Iron CHW";
  }
}


// Function to get the badge image based on the number of credits earned
String getBadgeImage(int creditsEarned) {
  if (creditsEarned >= 200) {
    return "assets/images/circular_supreme_badge.webp";
  } else if (creditsEarned >= 150) {
    return "assets/images/circular_diamond_badge.webp";
  } else if (creditsEarned >= 110) {
    return "assets/images/circular_platinum_badge.webp";
  } else if (creditsEarned >= 80) {
    return "assets/images/circular_gold_badge.webp";
  } else if (creditsEarned >= 60) {
    return "assets/images/circular_silver_badge.webp";
  } else if (creditsEarned >= 50) {
    return "assets/images/circular_bronze_badge.webp";
  } else {
    return "assets/images/circular_iron_badge.webp"; // Default badge or placeholder
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

int calculateCredits(List<dynamic>? quizScores) {
  final int currentYear = DateTime.now().year;

  if (quizScores == null) return 0;

  return quizScores.where((score) {
    if (score is Map<String, dynamic> &&
        score['score'] != null &&
        score['date_taken'] != null) {
      final scoreValue = double.tryParse(score['score'].toString()) ?? 0.0;
      final DateTime? dateTaken = DateTime.tryParse(score['date_taken'].toString());

      return scoreValue >= 80.0 &&
          dateTaken != null &&
          dateTaken.year == currentYear;
    }
    return false;
  }).length * 5;
}
// Get storage path based on platform
Future<Directory> getStoragePath() async {
  Directory directory;

  if (Platform.isAndroid) {
    directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();  
  } else if (Platform.isIOS || Platform.isMacOS) {
    directory = await getApplicationSupportDirectory();
  } else if (Platform.isWindows || Platform.isLinux) {
    directory = await getApplicationDocumentsDirectory();
  } else {
    throw Exception("Unsupported platform");
  }

  debugPrint("DEBUG: Returning Directory -> ${directory.path}");
  return directory;
}

// Generate PDF from CME data
Future<Uint8List> generateCMEPdf({
  required String firstName,
  required String lastName,
  required String email,
  required String role,
  required String country,
  required String organization,
  required List<dynamic> quizScores,
  required Set<int> selectedIndices,
}) async {
  final pdf = pw.Document();

  final logoData = await rootBundle.load('assets/images/watermark.png');
  final logoImage = pw.MemoryImage(logoData.buffer.asUint8List());

  final pageTheme = pw.PageTheme(
    margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 48),
    buildBackground: (context) => pw.Container(
      alignment: pw.Alignment.topCenter,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Opacity(
        opacity: 0.5,
        child: pw.Image(
          logoImage,
          width: 300,
          fit: pw.BoxFit.contain,
        ),
      ),
    ),
  );

  pdf.addPage(
    pw.MultiPage(
      pageTheme: pageTheme,
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
        ),
      ),
      build: (context) => [
        pw.Text(
          'Submitted CME History',
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 16),
        pw.Text('Name: $firstName $lastName'),
        pw.Text('Email: $email'),
        pw.Text('Role: $role'),
        pw.Text('Country: $country'),
        pw.Text('Organization: $organization'),
        pw.SizedBox(height: 24),

        // CME Table
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(),
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue800,
          ),
          headerDecoration: pw.BoxDecoration(
            color: PdfColors.white,
          ),
          cellAlignment: pw.Alignment.centerLeft,
          headerAlignment: pw.Alignment.center,
          columnWidths: {
            0: pw.FlexColumnWidth(2),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1),
            3: pw.FlexColumnWidth(2),
          },
          cellStyle: const pw.TextStyle(fontSize: 10),
          data: <List<String>>[
            ['Module Name', 'Module ID #', 'Score %', 'Date Submitted'],
            ...selectedIndices.map((index) {
              final quiz = quizScores[index];
              final module = quiz['module'];
              final formattedDate = formatDate(quiz['date_taken']);

              return [
                module?['name'] ?? 'Unknown',
                module?['module_id']?.toString() ?? 'N/A',
                '${double.parse(quiz['score']).toStringAsFixed(2)}%',
                formattedDate,
              ];
            }),
          ],
        ),
      ],
    ),
  );

  return pdf.save();
}