import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:open_filex/open_filex.dart';

class WebViewScreen extends StatefulWidget {
  final URLRequest urlRequest;

  const WebViewScreen({required this.urlRequest, Key? key}) : super(key: key);

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late InAppWebViewController _webViewController;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: Text("Offline Module"),
      // ),
      body: SafeArea(
        child: InAppWebView(
            initialUrlRequest: widget.urlRequest,
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
            // onLoadStop: (controller, url) async {
            //   print("Page finished loading: $url");
            // },
            // onConsoleMessage: (controller, consoleMessage) {
            //   print("JavaScript console message: ${consoleMessage.message}");
            // },
            onDownloadStartRequest: (controller, downloadStartRequest) async {
              if (downloadStartRequest.mimeType == "application/pdf") {
                print("Download URL: ${downloadStartRequest.url}");
                // Check for local file existence
                await _openLocalPdf(downloadStartRequest.url.toString());
              }
            }
        ),
      ),
    );
  }
  //     floatingActionButton: FloatingActionButton(
  //       onPressed: () async {
  //         // Example: Set a value in local storage
  //         await _setLocalStorage('key', 'value');
  //         // Example: Get a value from local storage
  //         String? value = await _getLocalStorage('key');
  //         print("Value from localStorage: $value");
  //       },
  //       child: Icon(Icons.storage),
  //     ),
  //   );
  // }

  // Future<void> _setLocalStorage(String key, String value) async {
  //   await _webViewController.evaluateJavascript(
  //     source: "localStorage.setItem('$key', '$value');",
  //   );
  //   print("Set localStorage: $key = $value");
  // }
  //
  // Future<String?> _getLocalStorage(String key) async {
  //   String? value = await _webViewController.evaluateJavascript(
  //     source: "localStorage.getItem('$key');",
  //   );
  //   return value?.replaceAll('"', ''); // Remove quotes from the returned string
  // }

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
