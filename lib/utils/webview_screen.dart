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
  bool _isOpeningPdf = false;
  late InAppWebViewController _webViewController;
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: widget.urlRequest,
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                useOnLoadResource: true,
                useOnDownloadStart: true,
                allowFileAccess: true,
                allowContentAccess: true,
                allowFileAccessFromFileURLs: true,
                allowUniversalAccessFromFileURLs: true,
                useWideViewPort: true,
                useHybridComposition: true,
                hardwareAcceleration: true,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;

                controller.addJavaScriptHandler(
                  handlerName: "exitModule",
                  callback: (args) {
                    print("🚪 EXIT HANDLER TRIGGERED");

                    if (Navigator.canPop(context)) {
                      Navigator.pop(context); // go back to ModuleLibrary
                    } else {
                      print("⚠️ Cannot pop, no previous route");
                    }
                    return;
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: "openPdfResource",
                  callback: (args) async {
                    print("📂 openPdfResource handler triggered: $args");

                    try {
                      if (args.isEmpty) {
                        print("❌ No PDF data received.");
                        return;
                      }

                      final data = Map<String, dynamic>.from(args.first as Map);

                      final String fileName = data["file"]?.toString() ?? "";
                      final String url = data["url"]?.toString() ?? "";

                      print("📄 File: $fileName");
                      print("🔗 URL: $url");
                      print("📦 ModuleID: ${widget.moduleId}");

                      if (fileName.isEmpty) {
                        print("❌ PDF file name missing.");
                        return;
                      }

                      if (url.contains("assets/resources")) {
                        print("📂 Detected Compiler Module via URL");
                        final fullUrl = widget.urlRequest.url.toString();

                        // Extract folder name between /modules/ and /index.html
                        final match = RegExp(r'modules/(.+)/index\.html').firstMatch(fullUrl);

                        if (match != null) {
                          final moduleFolder = Uri.decodeComponent(match.group(1)!);

                          print("📂 Extracted module folder: $moduleFolder");

                          await _openLocalPdf(fileName, moduleFolder);
                        } else {
                          print("❌ Could not extract module folder from URL");
                        }
                      } else {
                        print("📂 Detected Storyline Module");
                        await _openLocalPdf(fileName, widget.moduleId);
                      }

                    } catch (e) {
                      print("❌ Error in openPdfResource handler: $e");
                    }

                    return;
                  },
                );
                controller.addJavaScriptHandler(
                  handlerName: "saveCmeScore",
                  callback: (args) async {
                    print("📥 saveCmeScore handler triggered: $args");

                    try {
                      if (args.isEmpty) {
                        print("❌ No score data received.");
                        return;
                      }

                      final data = Map<String, dynamic>.from(args.first as Map);

                      final String moduleId = data["module_id"]?.toString() ?? "unknown";
                      final String moduleName =
                          data["module_name"]?.toString() ?? "Unknown Module";
                      final double score =
                          double.tryParse(data["quiz_score"]?.toString() ?? "0") ?? 0.0;

                      print("💾 Saving score from Compiler Module:");
                      print("🔹 ID: $moduleId");
                      print("🔹 Name: $moduleName");
                      print("🔹 Score: $score");

                      // 🔥 Reuse your EXISTING storage function (no duplicate logic)
                      await _storeScoreInSecureStorage({
                        "module_id": moduleId,
                        "module_name": moduleName,
                        "quiz_score": score,
                      });

                      print("✅ Compiler score saved successfully");

                    } catch (e) {
                      print("❌ Error in saveCmeScore handler: $e");
                    }

                    return;
                  },
                );
              },
              onLoadStop: (controller, url) async {
                print("🚀 WebView attempting to load: ${widget.urlRequest.url}");
                print("✅ Page finished loading: $url");

                // Retrieve authentication details
                String? moduleId = await secureStorage.read(key: "module_id");
                String? moduleName = await secureStorage.read(key: "module_name");

                print("📌 Stored Data Before Injection:");
                print("🔹 ModuleID: $moduleId");
                print("🔹 ModuleName: $moduleName");

                if (moduleId != null && moduleName != null &&
                    moduleName.isNotEmpty) {
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
                String? checkInjectedModuleId = await _webViewController
                    .evaluateJavascript(source: "window.moduleId;");
                print("🔍 Post-Injection moduleId Check: $checkInjectedModuleId");

                String? checkInjectedModuleName = await _webViewController
                    .evaluateJavascript(source: "window.moduleName;");
                print(
                    "🔍 Post-Injection moduleName Check: $checkInjectedModuleName");

                // Inject JS to detect clicked links (even if Storyline opens PDFs via JavaScript)
                await _webViewController.evaluateJavascript(source: """
                  document.addEventListener('click', function(event) {
                    let target = event.target.closest('a');
                    if (target) {
                      const href = target.getAttribute('href');
                      console.log('🔗 Link clicked:', href);
                
                      if (href && href.endsWith('.pdf')) {
                        window.location.href = href;
                      }
                    }
                  });
                """);

                // -----------------------------
                // Samsung-safe video fix
                // -----------------------------
                await _webViewController.evaluateJavascript(source: """
                  const patchVideo = (v) => {
                    v.setAttribute('playsinline', '');
                    v.controls = true;
                    v.autoplay = false;
                    v.muted = false;
                    v.preload = 'auto';
                    console.log('🎥 Video patched for Android WebView:', v.src);
                  };
                
                  // Patch existing videos
                  document.querySelectorAll('video').forEach(patchVideo);
                
                  // Patch videos added later (Storyline / JS slides)
                  const observer = new MutationObserver(() => {
                    document.querySelectorAll('video').forEach(patchVideo);
                  });
                
                  observer.observe(document.body, { childList: true, subtree: true });
                """);

                // Inject JS to detect PDFs opened in iframes
                await _webViewController.evaluateJavascript(source: """
                  setTimeout(() => {
                    let iframes = document.getElementsByTagName('iframe');
                    for (let iframe of iframes) {
                      console.log('📂 PDF Loaded in iframe:', iframe.src);
                    }
                  }, 3000);
                """);

                // Override window.open to capture JavaScript-triggered PDFs
                await _webViewController.evaluateJavascript(source: """
                  window.open = function(url) {
                    console.log('📂 JavaScript opened:', url);
                    window.location.href = url;
                  };
                """);
              },
              onConsoleMessage: (controller, consoleMessage) async {
                print("📝 JavaScript console message: ${consoleMessage.message}");

                try {
                  String cleanMessage = consoleMessage.message.trim();

                  // Detect and print any message containing `module_id`
                  if (cleanMessage.contains("module_id")) {
                    print("📌 Debug: Storyline Sent Data - $cleanMessage");
                  }

                  // Detect and print any message containing `module_name`
                  if (cleanMessage.contains("module_name")) {
                    print("📌 Debug: Storyline Sent Data - $cleanMessage");
                  }

                  // Detect PDF Links opened via JavaScript
                  if (cleanMessage.contains(".pdf")) {
                    print("📂 Detected PDF link: $cleanMessage");

                    // Retrieve `moduleId` from WebView
                    String? moduleId = await _webViewController.evaluateJavascript(
                        source: "window.moduleId");
                    if (moduleId == null || moduleId.isEmpty) {
                      print("❌ ERROR: Module ID not found in WebView!");
                      return;
                    }

                    print("🔹 Retrieved moduleId from WebView: $moduleId");

                    // Extract actual file name
                    String fileName = cleanMessage
                        .split("/")
                        .last;
                    print("📂 Extracted PDF file name: $fileName");

                    // Get correct external storage path
                    Directory? externalDir = await getExternalStorageDirectory();
                    // if (externalDir == null) {
                    //   print("❌ ERROR: External storage directory not found.");
                    //   return;
                    // }

                    // Construct full file path
                    // String filePath = "${externalDir.path}/files/$moduleId/story_content/external_files/$fileName";
                    // print("📂 Constructed PDF file path: $filePath");

                    // Open PDF with correct path
                    await _openLocalPdf(cleanMessage, moduleId);
                    return;
                  }

                  // Extract and clean JSON message
                  final int jsonStartIndex = cleanMessage.indexOf("{");
                  if (jsonStartIndex != -1) {
                    cleanMessage = cleanMessage.substring(jsonStartIndex);
                  }

                  // Validate and parse JSON
                  if (cleanMessage.startsWith("{") && cleanMessage.endsWith("}")) {
                    final Map<String, dynamic> jsonData = json.decode(cleanMessage);

                    print("📥 Received Data from Storyline:");
                    print("🔹 ModuleID: ${jsonData['module_id']}");
                    print("🔹 ModuleName: ${jsonData['module_name']}");
                    print("🔹 Quiz Score: ${jsonData['quiz_score']}");

                    // If module_id is missing, retrieve it from WebView
                    if (!jsonData.containsKey("module_id") ||
                        jsonData["module_id"] == null) {
                      print(
                          "⚠️ Module ID missing in Storyline data! Attempting retrieval...");

                      // Retrieve moduleId from WebView
                      String? injectedModuleId = await _webViewController
                          .evaluateJavascript(source: "window.moduleId;");
                      if (injectedModuleId != null && injectedModuleId.isNotEmpty) {
                        jsonData["module_id"] = injectedModuleId;
                        print("✅ Injected missing module ID: $injectedModuleId");
                      } else {
                        print("❌ Failed to retrieve module ID from WebView!");
                      }
                    }

                    // If module_name is missing, retrieve it from WebView
                    if (!jsonData.containsKey("module_name") ||
                        jsonData["module_name"] == null) {
                      print(
                          "⚠️ Module Name missing in Storyline data! Attempting retrieval...");

                      // Retrieve moduleName from WebView
                      String? injectedModuleName = await _webViewController
                          .evaluateJavascript(source: "window.moduleName;");
                      if (injectedModuleName != null &&
                          injectedModuleName.isNotEmpty) {
                        jsonData["module_name"] = injectedModuleName;
                        print(
                            "✅ Injected missing module Name: $injectedModuleName");
                      } else {
                        print("❌ Failed to retrieve module Name from WebView!");
                      }
                    }

                    // Store the quiz score in Secure Storage
                    await _storeScoreInSecureStorage(jsonData);
                  } else {
                    print("⚠️ Warning: Message does not appear to be valid JSON.");
                  }
                } catch (e) {
                  print("❌ Error parsing WebView message: $e");
                }
              },

    // Handle downloads properly
              onDownloadStartRequest: (controller, downloadStartRequest) async {
                print("📥 Download Request Triggered: ${downloadStartRequest
                    .url} - MIME Type: ${downloadStartRequest.mimeType}");

                if (downloadStartRequest.mimeType == "application/pdf") {
                  // Retrieve `moduleId` from WebView
                  String? moduleId = await _webViewController.evaluateJavascript(
                      source: "window.moduleId");
                  if (moduleId == null || moduleId.isEmpty) {
                    print("❌ ERROR: Module ID not found in WebView!");
                    return;
                  }

                  print("🔹 Retrieved moduleId from WebView: $moduleId");

                  await _openLocalPdf(
                      downloadStartRequest.url.toString(), moduleId);
                }
              },

    // Override URL loading behavior
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final uri = navigationAction.request.url;
                if (uri != null) {
                  print("🔗 Intercepted Link: $uri");

                  if (uri.toString().endsWith(".pdf")) {
                    print("📂 PDF detected! Forcing download.");

                    // Retrieve `moduleId` from WebView
                    String? moduleId = await _webViewController.evaluateJavascript(
                        source: "window.moduleId");
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
              },

              shouldInterceptRequest: (controller, request) async {
                final uri = request.url;
                final path = uri.toString();

                if (path.endsWith(".mp3") && path.startsWith("file://")) {
                  try {
                    final file = File(uri.toFilePath());
                    final bytes = await file.readAsBytes();
                    return WebResourceResponse(
                      data: bytes,
                      statusCode: 200,
                      reasonPhrase: "OK",
                      headers: {
                        'Content-Type': 'audio/mpeg',
                        'Access-Control-Allow-Origin': '*',
                      },
                    );
                  } catch (e) {
                    print("❌ Error serving MP3: $e");
                    return null;
                  }
                }
                return null;
              },
            ),
            // 🔥 PDF Loading Overlay (NEW)
            if (_isOpeningPdf)
              Container(
                color: Colors.black.withOpacity(0.4),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        "Opening document...",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),

          ],
        ),
      ),
    );
  }

  // Function to store quiz scores in secure storage
  Future<void> _storeScoreInSecureStorage(dynamic data) async {
    try {
      // Normalize input (list or map)
      if (data is List && data.isNotEmpty && data.first is Map) {
        data = data.first;
      } else if (data is! Map<String, dynamic>) {
        print("⚠️ Unexpected data format: $data");
        return;
      }

      final String moduleId = data["module_id"]?.toString() ?? "unknown";
      final String moduleName = data["module_name"]?.toString() ??
          "Unknown Module";
      final double score = double.tryParse(
          data["quiz_score"]?.toString() ?? "0") ?? 0.0;

      // 1️⃣ Load any existing scores
      String? existing = await secureStorage.read(key: "pending_quiz_scores");
      Map<String, dynamic> storedScores = {};
      if (existing != null && existing.isNotEmpty) {
        final decoded = jsonDecode(existing);
        if (decoded is Map<String, dynamic>) storedScores = decoded;
      }

      // 2️⃣ Update the map
      storedScores[moduleId] = {
        "module_name": moduleName,
        "score": score,
        "date_saved": DateTime.now().toIso8601String(),
      };

      // 3️⃣ Write & confirm
      await secureStorage.write(
        key: "pending_quiz_scores",
        value: jsonEncode(storedScores),
      );

      // ✅ Force the OS to finish the write before continuing
      await Future.delayed(const Duration(milliseconds: 250));

      // 4️⃣ Read back once to confirm flush
      final verify = await secureStorage.read(key: "pending_quiz_scores");
      if (verify != null && verify.contains(moduleId)) {
        print("✅ Pending quiz score safely flushed for module $moduleId");
      } else {
        print("⚠️ Flush verification failed for module $moduleId");
      }
    } catch (e, st) {
      print("❌ Error storing offline quiz score: $e");
      print(st);
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _openLocalPdf(String url, String moduleId) async {
    setState(() {
      _isOpeningPdf = true;
    });

    try {
      if (moduleId.isEmpty) {
        print("❌ ERROR: moduleId is empty.");
        return;
      }

      String fileName = url;
      // ✅ NEW: Handle full file:// paths directly
      if (url.startsWith("file://")) {
        final filePath = Uri.parse(url).toFilePath();

        print("📂 Direct file path detected: $filePath");

        File file = File(filePath);

        if (await file.exists()) {
          final result = await OpenFile.open(filePath);

          print("📄 OpenFile result: ${result.type}");

          if (result.type != ResultType.done) {
            _showError("Could not open document.");
          }
        } else {
          print("❌ File not found at: $filePath");
          _showError("Document not found.");
        }

        return; // 🔥 IMPORTANT: stop here
      }

      Directory? externalDir = await getExternalStorageDirectory();

      if (externalDir == null) {
        print("❌ External storage directory not found.");
        return;
      }

      String filePath;

      // ✅ CASE 1: OLD STORYLINE MODULE (numeric ID)
      if (RegExp(r'^\d+$').hasMatch(moduleId)) {
        print("📂 Detected Storyline Module (numeric ID)");

        filePath =
        "${externalDir
            .path}/modules/files/$moduleId/story_content/external_files/$fileName";
      }

      // ✅ CASE 2: NEW COMPILER MODULE (folder name)
      else {
        print("📂 Detected Compiler Module (folder)");

        filePath =
        "${externalDir.path}/modules/$moduleId/assets/resources/$fileName";
      }

      print("📂 Constructed PDF file path: $filePath");

      File file = File(filePath);

      if (await file.exists()) {
        print("📂 File found! Opening PDF...");

        final result = await OpenFile.open(filePath);

        print("📄 OpenFile result: ${result.type}");

        if (result.type != ResultType.done) {
          _showError("Could not open document.");
        }
      } else {
        print("❌ PDF file not found at: $filePath");
        _showError("Document not found.");
      }
    } catch (e) {
      print("❌ Error opening PDF file: $e");
      _showError("Error opening document.");
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningPdf = false;
        });
      }
    }
  }
}