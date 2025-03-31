import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

class WebViewScreen extends StatefulWidget {
  final URLRequest urlRequest;
  final String moduleId;

  const WebViewScreen({required this.urlRequest, required this.moduleId, Key? key}) : super(key: key);


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
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              useOnLoadResource: true,
              useOnDownloadStart: true,
              allowFileAccess: true,
              allowContentAccess: true,
              useWideViewPort: true,
              useHybridComposition: true,
              hardwareAcceleration: true,
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            onLoadStop: (controller, url) async {
              print("✅ Page finished loading: $url");

              // Retrieve authentication details
              String? moduleId = await secureStorage.read(key: "module_id");
              String? moduleName = await secureStorage.read(key: "module_name");

              print("📌 Stored Data Before Injection:");
              print("🔹 ModuleID: $moduleId");
              print("🔹 ModuleName: $moduleName");

              if (moduleId != null && moduleName != null && moduleName.isNotEmpty) {
                // Inject JavaScript into WebView
                await _webViewController.evaluateJavascript(source: """
                  window.moduleId = "$moduleId"; // ✅ Make sure it is window.moduleId
                  window.moduleName = "$moduleName";
                  console.log("✅ Injected moduleId: " + window.moduleId);
                  console.log("✅ Injected moduleName: " + window.moduleName);
                """);
              } else {
                print("❌ ERROR: Module ID or Name missing before injection.");
              }

              // Verify if the injection worked
              String? checkInjectedModuleId = await _webViewController.evaluateJavascript(source: "window.moduleId;");
              print("🔍 Post-Injection moduleId Check: $checkInjectedModuleId");

              String? checkInjectedModuleName = await _webViewController.evaluateJavascript(source: "window.moduleName;");
              print("🔍 Post-Injection moduleName Check: $checkInjectedModuleName");

              // ✅ Inject JS to detect clicked links (even if Storyline opens PDFs via JavaScript)
              await _webViewController.evaluateJavascript(source: """
              document.addEventListener('click', function(event) {
                let target = event.target.closest('a');
                if (target) {
                  console.log('🔗 Link clicked:', target.href);
                }
              });
            """);

              // ✅ Inject JS to detect PDFs opened in iframes
              await _webViewController.evaluateJavascript(source: """
              setTimeout(() => {
                let iframes = document.getElementsByTagName('iframe');
                for (let iframe of iframes) {
                  console.log('📂 PDF Loaded in iframe:', iframe.src);
                }
              }, 3000);
            """);

              // ✅ Override window.open to capture JavaScript-triggered PDFs
              await _webViewController.evaluateJavascript(source: """
              window.open = function(url) {
                console.log('📂 JavaScript opened:', url);
              };
            """);
            },
            onConsoleMessage: (controller, consoleMessage) async {
              print("📝 JavaScript console message: ${consoleMessage.message}");

              try {
                String cleanMessage = consoleMessage.message.trim();

                // ✅ Detect and print any message containing `module_id`
                if (cleanMessage.contains("module_id")) {
                  print("📌 Debug: Storyline Sent Data - $cleanMessage");
                }

                // ✅ Detect and print any message containing `module_name`
                if (cleanMessage.contains("module_name")) {
                  print("📌 Debug: Storyline Sent Data - $cleanMessage");
                }

                // ✅ Detect PDF Links opened via JavaScript
                if (cleanMessage.contains(".pdf")) {
                  print("📂 Detected PDF link: $cleanMessage");

                  // ✅ Retrieve `moduleId` from WebView
                  String? moduleId = await _webViewController.evaluateJavascript(source: "window.moduleId");
                  if (moduleId == null || moduleId.isEmpty) {
                    print("❌ ERROR: Module ID not found in WebView!");
                    return;
                  }

                  print("🔹 Retrieved moduleId from WebView: $moduleId");

                  // ✅ Extract actual file name
                  String fileName = cleanMessage.split("/").last;
                  print("📂 Extracted PDF file name: $fileName");

                  // ✅ Get correct external storage path
                  Directory? externalDir = await getExternalStorageDirectory();
                  // if (externalDir == null) {
                  //   print("❌ ERROR: External storage directory not found.");
                  //   return;
                  // }

                  // ✅ Construct full file path
                  // String filePath = "${externalDir.path}/files/$moduleId/story_content/external_files/$fileName";
                  // print("📂 Constructed PDF file path: $filePath");

                  // ✅ Open PDF with correct path
                  await _openLocalPdf(cleanMessage, moduleId);
                  return;
                }

                // ✅ Extract and clean JSON message
                final int jsonStartIndex = cleanMessage.indexOf("{");
                if (jsonStartIndex != -1) {
                  cleanMessage = cleanMessage.substring(jsonStartIndex);
                }

                // ✅ Validate and parse JSON
                if (cleanMessage.startsWith("{") && cleanMessage.endsWith("}")) {
                  final Map<String, dynamic> jsonData = json.decode(cleanMessage);

                  print("📥 Received Data from Storyline:");
                  print("🔹 ModuleID: ${jsonData['module_id']}");
                  print("🔹 ModuleName: ${jsonData['module_name']}");
                  print("🔹 Quiz Score: ${jsonData['quiz_score']}");

                  // ✅ If module_id is missing, retrieve it from WebView
                  if (!jsonData.containsKey("module_id") || jsonData["module_id"] == null) {
                    print("⚠️ Module ID missing in Storyline data! Attempting retrieval...");

                    // Retrieve moduleId from WebView
                    String? injectedModuleId = await _webViewController.evaluateJavascript(source: "window.moduleId;");
                    if (injectedModuleId != null && injectedModuleId.isNotEmpty) {
                      jsonData["module_id"] = injectedModuleId;
                      print("✅ Injected missing module ID: $injectedModuleId");
                    } else {
                      print("❌ Failed to retrieve module ID from WebView!");
                    }
                  }

                  // ✅ If module_name is missing, retrieve it from WebView
                  if (!jsonData.containsKey("module_name") || jsonData["module_name"] == null) {
                    print("⚠️ Module Name missing in Storyline data! Attempting retrieval...");

                    // Retrieve moduleName from WebView
                    String? injectedModuleName = await _webViewController.evaluateJavascript(source: "window.moduleName;");
                    if (injectedModuleName != null && injectedModuleName.isNotEmpty) {
                      jsonData["module_name"] = injectedModuleName;
                      print("✅ Injected missing module Name: $injectedModuleName");
                    } else {
                      print("❌ Failed to retrieve module Name from WebView!");
                    }
                  }

                  // ✅ Store the quiz score in Secure Storage
                  await _storeScoreInSecureStorage(jsonData);
                } else {
                  print("⚠️ Warning: Message does not appear to be valid JSON.");
                }
              } catch (e) {
                print("❌ Error parsing WebView message: $e");
              }
            },

// ✅ Handle downloads properly
            onDownloadStartRequest: (controller, downloadStartRequest) async {
              print("📥 Download Request Triggered: ${downloadStartRequest.url} - MIME Type: ${downloadStartRequest.mimeType}");

              if (downloadStartRequest.mimeType == "application/pdf") {
                // ✅ Retrieve `moduleId` from WebView
                String? moduleId = await _webViewController.evaluateJavascript(source: "window.moduleId");
                if (moduleId == null || moduleId.isEmpty) {
                  print("❌ ERROR: Module ID not found in WebView!");
                  return;
                }

                print("🔹 Retrieved moduleId from WebView: $moduleId");

                await _openLocalPdf(downloadStartRequest.url.toString(), moduleId);
              }
            },

// ✅ Override URL loading behavior
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              if (uri != null) {
                print("🔗 Intercepted Link: $uri");

                if (uri.toString().endsWith(".pdf")) {
                  print("📂 PDF detected! Forcing download.");

                  // ✅ Retrieve `moduleId` from WebView
                  String? moduleId = await _webViewController.evaluateJavascript(source: "window.moduleId");
                  if (moduleId == null || moduleId.isEmpty) {
                    print("❌ ERROR: Module ID not found in WebView!");
                    return NavigationActionPolicy.CANCEL;
                  }

                  await _openLocalPdf(uri.toString(), moduleId);
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              }
              return NavigationActionPolicy.CANCEL;
            }
        ),
      ),
    );
  }

  // Function to store quiz scores in secure storage
  Future<void> _storeScoreInSecureStorage(Map<String, dynamic> data) async {
    try {
      String moduleId = data["module_id"].toString();
      String moduleName = data["module_name"] ?? "Unknown Module";
      double score = double.tryParse(data["quiz_score"].toString()) ?? 0.0;

      // Retrieve existing stored scores
      String? storedScoresJson = await secureStorage.read(key: "quiz_scores");
      Map<String, dynamic> storedScores = storedScoresJson != null ? jsonDecode(
          storedScoresJson) : {};

      // Update the score and module name for the current module
      storedScores[moduleId] = {
        "score": score,
        "module_name": moduleName
      };

      // Save updated scores back to Secure Storage
      await secureStorage.write(
          key: "quiz_scores", value: jsonEncode(storedScores));

      print(
          "✅ Successfully stored quiz score: Module ID: $moduleId, Score: $score");
    } catch (e) {
      print("❌ Error storing quiz score: $e");
    }
  }

  Future<void> _openLocalPdf(String url, String moduleId) async {
    try {
      if (moduleId == null || moduleId.isEmpty) {
        print("❌ ERROR: moduleId is null or empty. Cannot open PDF.");
        return;
      }

      String fileName = url.split("/").last;
      Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        print("❌ External storage directory not found.");
        return;
      }

      // ✅ Determine the correct directory based on moduleId length
      String basePath;
      if (moduleId.length == 4) {
        basePath = "${externalDir.path}/modules/files"; // Individual module
        print("📂 Detected Individual Module (4-digit ID)");
      } else if (moduleId.length == 8) {
        basePath = "${externalDir.path}/packages/files"; // Package of modules
        print("📂 Detected Package (8-digit ID)");
      } else {
        print("❌ ERROR: Invalid moduleId length (${moduleId.length})!");
        return;
      }

      // ✅ Construct the final PDF file path
      String filePath = "$basePath/$moduleId/story_content/external_files/$fileName";
      print("📂 Constructed PDF file path: $filePath");

      // ✅ Check if the file exists and open it
      File file = File(filePath);
      if (await file.exists()) {
        print("📂 File found! Opening PDF...");
        await OpenFile.open(filePath);
      } else {
        print("❌ PDF file not found at: $filePath");
      }
    } catch (e) {
      print("❌ Error opening PDF file: $e");
    }
  }
}
