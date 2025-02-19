import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:open_filex/open_filex.dart';

// class WebViewScreen extends StatefulWidget {
//   final URLRequest urlRequest;
//
//   const WebViewScreen({required this.urlRequest, Key? key}) : super(key: key);
//
//   @override
//   State<WebViewScreen> createState() => _WebViewScreenState();
// }
//
// class _WebViewScreenState extends State<WebViewScreen> {
//   late InAppWebViewController _webViewController;
//   final FlutterSecureStorage secureStorage = FlutterSecureStorage();
//
//   @override
//   void initState() {
//     super.initState();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: SafeArea(
//         child: InAppWebView(
//           initialUrlRequest: widget.urlRequest,
//           initialOptions: InAppWebViewGroupOptions(
//             crossPlatform: InAppWebViewOptions(
//               javaScriptEnabled: true,
//               mediaPlaybackRequiresUserGesture: false,
//               useOnLoadResource: true,
//               useOnDownloadStart: true,
//             ),
//             android: AndroidInAppWebViewOptions(
//               allowFileAccess: true,
//               allowContentAccess: true,
//               useWideViewPort: true,
//               useHybridComposition: true,
//             ),
//             ios: IOSInAppWebViewOptions(
//               allowsInlineMediaPlayback: true,
//             ),
//           ),
//           onWebViewCreated: (controller) {
//             _webViewController = controller;
//           },
//           onLoadStop: (controller, url) async {
//             print("✅ Page finished loading: $url");
//
//             // Retrieve authentication details
//             String? authToken = await secureStorage.read(key: "authToken");
//             String? userId = await secureStorage.read(key: "user_id");
//             String? moduleId = await secureStorage.read(key: "module_id");
//
//             print("📌 Stored Data Before Injection:");
//             print("🔹 AuthToken: $authToken");
//             print("🔹 UserID: $userId");
//             print("🔹 ModuleID: $moduleId");
//
//             if (authToken != null && userId != null && moduleId != null) {
//               // Inject JavaScript into WebView
//               await _webViewController.evaluateJavascript(source: """
//                 window.storylineAuthToken = '$authToken';
//                 window.storylineUserId = '$userId';
//                 window.storylineModuleId = '$moduleId';
//                 console.log('🔹 Injected Auth Data:', window.storylineAuthToken, window.storylineUserId, window.storylineModuleId);
//               """);
//
//               print("✅ JavaScript Injection Complete: Data sent to Storyline.");
//             } else {
//               print("❌ ERROR: Authentication data is missing before injection.");
//             }
//           },
//           onConsoleMessage: (controller, consoleMessage) {
//             print("JavaScript console message: ${consoleMessage.message}");
//           },
//           onDownloadStartRequest: (controller, downloadStartRequest) async {
//             if (downloadStartRequest.mimeType == "application/pdf") {
//               // Check for local file existence
//               await _openLocalPdf(downloadStartRequest.url.toString());
//             }
//           },
//           shouldOverrideUrlLoading: (controller, navigationAction) async {
//             // Force all links to open inside WebView instead of external browsers
//             final uri = navigationAction.request.url;
//             if (uri != null) {
//               return NavigationActionPolicy.ALLOW;
//             }
//               return NavigationActionPolicy.CANCEL;
//           },
//         ),
//       ),
//     );
//   }
// }
//
//
//   Future<void> _openLocalPdf(String url) async {
//     try {
//       // Decode the URL if needed
//       String filePath = Uri.parse(url).path;
//       File file = File(filePath);
//
//       print("Checking for file at: $filePath");
//
//       if (await file.exists()) {
//         print("Opening PDF file at: $filePath");
//         await OpenFilex.open(filePath);
//       } else {
//         print("PDF file does not exist: $filePath");
//       }
//     } catch (e) {
//       print("Error opening PDF file: $e");
//     }
//   }

class WebViewScreen extends StatefulWidget {
  final URLRequest urlRequest;

  const WebViewScreen({required this.urlRequest, Key? key}) : super(key: key);

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late InAppWebViewController _webViewController;
  final FlutterSecureStorage secureStorage = FlutterSecureStorage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              allowContentAccess: true,
              useWideViewPort: true,
              useHybridComposition: true,
            ),
            ios: IOSInAppWebViewOptions(
              allowsInlineMediaPlayback: true,
            ),
          ),
          onWebViewCreated: (controller) {
            _webViewController = controller;
          },
          onLoadStop: (controller, url) async {
            print("✅ Page finished loading: $url");

            // Retrieve authentication details
            String? authToken = await secureStorage.read(key: "authToken");
            String? userId = await secureStorage.read(key: "user_id");
            String? moduleId = await secureStorage.read(key: "module_id");

            print("📌 Stored Data Before Injection:");
            print("🔹 AuthToken: $authToken");
            print("🔹 UserID: $userId");
            print("🔹 ModuleID: $moduleId");

            if (authToken != null && userId != null && moduleId != null) {
              // Inject JavaScript into WebView
              await _webViewController.evaluateJavascript(source: """
                window.storylineAuthToken = '$authToken';
                window.storylineUserId = '$userId';
                window.storylineModuleId = '$moduleId';
                console.log('🔹 Injected Auth Data:', window.storylineAuthToken, window.storylineUserId, window.storylineModuleId);
              """);

              print("✅ JavaScript Injection Complete: Data sent to Storyline.");
            } else {
              print("❌ ERROR: Authentication data is missing before injection.");
            }
          },
          onConsoleMessage: (controller, consoleMessage) async {
            print("📢 JavaScript Console Message: ${consoleMessage.message}");

            try {
              final message = consoleMessage.message;
              if (message.contains("quiz_score")) {
                final Map<String, dynamic> receivedData = _parseJavaScriptMessage(message);
                await _storeScoreInSecureStorage(receivedData);
              }
            } catch (e) {
              print("❌ Error processing JavaScript message: $e");
            }
          },
          onDownloadStartRequest: (controller, downloadStartRequest) async {
            if (downloadStartRequest.mimeType == "application/pdf") {
              await _openLocalPdf(downloadStartRequest.url.toString());
            }
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final uri = navigationAction.request.url;
            if (uri != null) {
              return NavigationActionPolicy.ALLOW;
            }
            return NavigationActionPolicy.CANCEL;
          },
        ),
      ),
    );
  }

  // Function to parse JavaScript message
  Map<String, dynamic> _parseJavaScriptMessage(String message) {
    try {
      return {
        "auth_token": _extractValue(message, "auth_token"),
        "user_id": _extractValue(message, "user_id"),
        "module_id": _extractValue(message, "module_id"),
        "quiz_score": double.tryParse(_extractValue(message, "quiz_score") ?? "0") ?? 0.0
      };
    } catch (e) {
      print("❌ Error parsing JavaScript message: $e");
      return {};
    }
  }

  // Function to extract values from JavaScript message
  String? _extractValue(String message, String key) {
    final regex = RegExp(r'"' + key + r'":"?([^",]+)"?');
    final match = regex.firstMatch(message);
    return match?.group(1);
  }

  // Function to store quiz score in secure storage
  Future<void> _storeScoreInSecureStorage(Map<String, dynamic> data) async {
    try {
      final String userId = data["user_id"];
      final String moduleId = data["module_id"];
      final double score = data["quiz_score"];

      // Create a map object and store it in Secure Storage
      Map<String, dynamic> quizData = {
        "user_id": userId,
        "module_id": moduleId,
        "score": score,
        "date_taken": DateTime.now().toIso8601String()
      };

      await secureStorage.write(key: "quiz_score", value: quizData.toString());
      print("✅ Successfully stored quiz score in Secure Storage: $quizData");
    } catch (e) {
      print("❌ Error storing quiz score: $e");
    }
  }

  // Function to open local PDF files
  Future<void> _openLocalPdf(String url) async {
    try {
      String filePath = Uri.parse(url).path;
      File file = File(filePath);

      print("📂 Checking for file at: $filePath");

      if (await file.exists()) {
        print("📂 Opening PDF file at: $filePath");
        await OpenFilex.open(filePath);
      } else {
        print("❌ PDF file does not exist: $filePath");
      }
    } catch (e) {
      print("❌ Error opening PDF file: $e");
    }
  }
}