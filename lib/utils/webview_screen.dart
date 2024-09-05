import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';

class WebViewScreen extends StatelessWidget {
  final URLRequest urlRequest;

  const WebViewScreen({required this.urlRequest});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Offline Module"),
      ),
      body: InAppWebView(
        initialUrlRequest: urlRequest,
        //url: Uri.parse("file:///storage/emulated/0/Android/data/com.example.wired_test/files/Flu - Influenza.htm"),
        initialOptions: InAppWebViewGroupOptions(
          crossPlatform: InAppWebViewOptions(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            useOnLoadResource: true,
            useOnDownloadStart: true,
          ),
          android: AndroidInAppWebViewOptions(
            allowFileAccess: true,
            useWideViewPort: true,
            useHybridComposition: true,
          ),
          ios: IOSInAppWebViewOptions(
            allowsInlineMediaPlayback: true,
          ),
        ),
        onDownloadStartRequest: (controller, downloadStartRequest) async {
          if (downloadStartRequest.mimeType == "application/pdf") {
            print("Download URL: ${downloadStartRequest.url}");
            // Check for local file existence
            await _openLocalPdf(downloadStartRequest.url.toString());
          }
        }
      ),
    );
  }

  Future<void> _openLocalPdf(String url) async {
    try {
      // Decode the URL if needed
      String filePath = Uri.parse(url).path;
      File file = File(filePath);

      print("Checking for file at: $filePath");

      if (await file.exists()) {
        print("Opening PDF file at: $filePath");
        await OpenFilex.open(filePath);
      } else {
        print("PDF file does not exist: $filePath");
      }
    } catch (e) {
      print("Error opening PDF file: $e");
    }
  }
}