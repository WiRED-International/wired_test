import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Function to check if the device is a tablet
bool isTablet(BuildContext context) {
  var shortestSide = MediaQuery.of(context).size.shortestSide;
  return shortestSide > 600;
}

// Function to get responsive text style
TextStyle responsiveTextStyle(BuildContext context, double baseSize) {
  return TextStyle(
    fontSize: isTablet(context)
        ? baseSize * 1.5
        : baseSize, // Adjust font size for tablets
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
  return base64String.padRight(
      base64String.length + (4 - base64String.length % 4) % 4, '=');
}

// Function to help with scaling in portrait
double getScalingFactor(BuildContext context) {
  Size screenSize = MediaQuery.of(context).size;
  double baseWidth = 360.0; // Reference width for portrait mode
  double baseHeight = 640.0; // Reference height for portrait mode

  if (screenSize.width > screenSize.height) {
    return ((screenSize.width / baseWidth) + (screenSize.height / baseHeight)) /
        2;
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
        await secureStorage.write(
            key: "quiz_scores", value: jsonEncode(storedScores));
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

int calculateCredits(List<dynamic>? quizScores) {
  final int currentYear = DateTime.now().year;

  if (quizScores == null) return 0;

  int totalCredits = 0;

  for (var score in quizScores) {
    if (score is Map<String, dynamic>) {
      final rawScore = score['score'];
      final double scoreValue = (rawScore is num)
          ? rawScore.toDouble()
          : double.tryParse(rawScore.toString()) ?? 0.0;

      final rawDate = score['date_taken'];
      final DateTime? dateTaken =
          rawDate != null ? DateTime.tryParse(rawDate.toString()) : null;

      // 🧠 Handle both flattened and nested credit_type
      final String creditType =
          (score['credit_type'] ?? score['module']?['credit_type'] ?? 'none')
              .toString()
              .toLowerCase();

      // ✅ Debug
      debugPrint(
          '🧮 Evaluating: score=$scoreValue, creditType=$creditType, date=${dateTaken?.year}');

      if (creditType == 'cme' &&
          scoreValue >= 80.0 &&
          dateTaken != null &&
          dateTaken.year == currentYear) {
        totalCredits += 5;
        debugPrint('✅ Counted: $scoreValue (${dateTaken.year})');
      } else {
        debugPrint(
            '❌ Skipped: score=$scoreValue, creditType=$creditType, date=${dateTaken?.year}');
      }
    }
  }

  debugPrint('📊 Total CME credits counted: $totalCredits');
  return totalCredits;
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
              final scoreValue = quiz['score'];
              final double score = (scoreValue is num)
                  ? scoreValue.toDouble()
                  : double.tryParse(scoreValue.toString()) ?? 0.0;

              return [
                module?['name'] ?? 'Unknown',
                module?['module_id']?.toString() ?? 'N/A',
                '${score.toStringAsFixed(2)}%\n',
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
