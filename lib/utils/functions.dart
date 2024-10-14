import 'package:flutter/material.dart';
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

