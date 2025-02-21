import 'dart:convert';
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
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

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
            print("📝 JavaScript console message: ${consoleMessage.message}");

            try {
              // Extract and clean the JSON message
              String cleanMessage = consoleMessage.message.trim();
              final int jsonStartIndex = cleanMessage.indexOf("{");
              if (jsonStartIndex != -1) {
                cleanMessage = cleanMessage.substring(jsonStartIndex);
              }

              // Validate JSON
              if (cleanMessage.startsWith("{") && cleanMessage.endsWith("}")) {
                final Map<String, dynamic> jsonData = json.decode(cleanMessage);

                print("📥 Received Data from Storyline:");
                print("🔹 AuthToken: ${jsonData['auth_token']}");
                print("🔹 UserID: ${jsonData['user_id']}");
                print("🔹 ModuleID: ${jsonData['module_id']}");
                print("🔹 Quiz Score: ${jsonData['quiz_score']}");

                // Store the quiz score in Secure Storage
                await _storeScoreInSecureStorage(jsonData);
              } else {
                print("⚠️ Warning: Message does not appear to be valid JSON.");
              }
            } catch (e) {
              print("❌ Error parsing WebView message: $e");
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

  // Function to store quiz scores in secure storage
  Future<void> _storeScoreInSecureStorage(Map<String, dynamic> data) async {
    try {
      String moduleId = data["module_id"].toString();
      double score = double.tryParse(data["quiz_score"].toString()) ?? 0.0;

      // Retrieve existing stored scores
      String? storedScoresJson = await secureStorage.read(key: "quiz_scores");
      Map<String, dynamic> storedScores = storedScoresJson != null ? jsonDecode(storedScoresJson) : {};

      // Update the score for the current module
      storedScores[moduleId] = score;

      // Save updated scores back to Secure Storage
      await secureStorage.write(key: "quiz_scores", value: jsonEncode(storedScores));

      print("✅ Successfully stored quiz score: Module ID: $moduleId, Score: $score");
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