import '../models/quiz_result_validation.dart';
import 'package:provider/provider.dart';
import '../services/pending_quiz_score_repository.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;

class WebViewScreen extends StatefulWidget {
  final URLRequest urlRequest;
  final String moduleId;
  final String? moduleName;

  const WebViewScreen({
    required this.urlRequest,
    required this.moduleId,
    this.moduleName,
    Key? key,
  }) : super(key: key);

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final PendingQuizScoreRepository _pendingScores;

  @override
  void initState() {
    super.initState();
    _pendingScores = context.read<PendingQuizScoreRepository>();
  }

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

                      await _openLocalPdf(url.isNotEmpty ? url : fileName);
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
                      final saved = await _storeScoreInSecureStorage(
                        args.isEmpty ? null : args.first,
                      );

                      if (saved) print("✅ Compiler score saved successfully");
                    } catch (e) {
                      print("❌ Error in saveCmeScore handler: $e");
                    }

                    return;
                  },
                );
              },
              onLoadStop: (controller, url) async {
                print(
                    "🚀 WebView attempting to load: ${widget.urlRequest.url}");
                print("✅ Page finished loading: $url");

                // Retrieve authentication details
                String? moduleId = await secureStorage.read(key: "module_id");
                String? moduleName =
                    await secureStorage.read(key: "module_name");

                print("📌 Stored Data Before Injection:");
                print("🔹 ModuleID: $moduleId");
                print("🔹 ModuleName: $moduleName");

                if (moduleId != null &&
                    moduleName != null &&
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
                print(
                    "🔍 Post-Injection moduleId Check: $checkInjectedModuleId");

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
                print(
                    "📝 JavaScript console message: ${consoleMessage.message}");

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

                  // Valid score metadata can contain PDF filenames. Recognize
                  // score JSON before applying the broad PDF-link fallback.
                  Map<String, dynamic>? scoreMessage;
                  final jsonStart = cleanMessage.indexOf("{");
                  if (jsonStart != -1 && cleanMessage.endsWith("}")) {
                    try {
                      final decoded =
                          json.decode(cleanMessage.substring(jsonStart));
                      if (decoded is Map<String, dynamic> &&
                          validQuizModuleId(decoded['module_id']) != null &&
                          validQuizScore(decoded['quiz_score']) != null) {
                        scoreMessage = decoded;
                      }
                    } on FormatException {
                      // Non-score messages still use the existing PDF fallback.
                    }
                  }

                  // Detect PDF Links opened via JavaScript
                  if (scoreMessage == null && cleanMessage.contains(".pdf")) {
                    print("📂 Detected PDF link: $cleanMessage");

                    // Accept only the link prefix emitted by our click listener
                    // and its plain-text form used by existing modules.
                    final reference = cleanMessage.replaceFirst(
                        RegExp(r'^(?:🔗 )?Link clicked:\s*'), '');
                    await _openLocalPdf(reference);
                    return;
                  }

                  // Extract and clean JSON message
                  final int jsonStartIndex = cleanMessage.indexOf("{");
                  if (jsonStartIndex != -1) {
                    cleanMessage = cleanMessage.substring(jsonStartIndex);
                  }

                  // Validate and parse JSON
                  if (cleanMessage.startsWith("{") &&
                      cleanMessage.endsWith("}")) {
                    final Map<String, dynamic> jsonData =
                        scoreMessage ?? json.decode(cleanMessage);

                    print("📥 Received Data from Storyline:");
                    print("🔹 ModuleID: ${jsonData['module_id']}");
                    print("🔹 ModuleName: ${jsonData['module_name']}");
                    print("🔹 Quiz Score: ${jsonData['quiz_score']}");

                    if (validQuizModuleId(jsonData['module_id']) == null ||
                        validQuizScore(jsonData['quiz_score']) == null) {
                      await _storeScoreInSecureStorage(jsonData);
                      return;
                    }

                    // Queue results in arrival order; optional metadata must
                    // not delay a result behind a newer retake.
                    final messageName = jsonData['module_name'];
                    final launchName = widget.moduleName;
                    jsonData['module_name'] =
                        messageName is String && messageName.trim().isNotEmpty
                            ? messageName
                            : launchName != null && launchName.trim().isNotEmpty
                                ? launchName
                                : 'Unknown Module';

                    // Store the quiz score in Secure Storage
                    await _storeScoreInSecureStorage(jsonData);
                  } else {
                    print(
                        "⚠️ Warning: Message does not appear to be valid JSON.");
                  }
                } catch (e) {
                  print("❌ Error parsing WebView message: $e");
                }
              },

              // Handle downloads properly
              onDownloadStartRequest: (controller, downloadStartRequest) async {
                print(
                    "📥 Download Request Triggered: ${downloadStartRequest.url} - MIME Type: ${downloadStartRequest.mimeType}");

                if (downloadStartRequest.mimeType == "application/pdf") {
                  await _openLocalPdf(downloadStartRequest.url.toString());
                }
              },

              // Override URL loading behavior
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final uri = navigationAction.request.url;
                if (uri != null) {
                  print("🔗 Intercepted Link: $uri");

                  if (uri.toString().endsWith(".pdf")) {
                    print("📂 PDF detected! Forcing download.");

                    await _openLocalPdf(uri.toString());
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
  Future<bool> _storeScoreInSecureStorage(dynamic data) async {
    try {
      // Normalize input (list or map)
      if (data is List && data.isNotEmpty && data.first is Map) {
        data = data.first;
      } else if (data is! Map<String, dynamic>) {
        print("⚠️ Unexpected data format: $data");
        throw const FormatException('Invalid quiz result');
      }

      final moduleId = validQuizModuleId(data['module_id']);
      final score = validQuizScore(data['quiz_score']);
      if (moduleId == null || score == null) {
        throw const FormatException('Invalid quiz score or module identifier');
      }
      final moduleName = data['module_name']?.toString() ?? 'Unknown Module';

      await _pendingScores.save(
        moduleId: moduleId,
        moduleName: moduleName,
        score: score,
      );
      return true;
    } catch (e, st) {
      print("❌ Error storing offline quiz score: $e");
      print(st);
      _showError(
          'Your quiz result could not be saved on this device. Please keep this module open and try saving again.');
      return false;
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

  Future<void> _openLocalPdf(String url) async {
    if (!mounted) return;
    setState(() {
      _isOpeningPdf = true;
    });

    try {
      // ✅ NEW: Handle full file:// paths directly
      if (url.startsWith("file://")) {
        final filePath = Uri.parse(url).toFilePath();

        print("📂 Direct file path detected: $filePath");

        File file = File(filePath);

        if (await file.exists()) {
          if (!mounted) return;
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

      // getUrl reflects launcher redirects; the initial request may still name
      // a launcher in modules/ or packages/, rather than the content document.
      final loadedUrl = await _webViewController.getUrl();
      final document =
          loadedUrl == null ? null : Uri.tryParse(loadedUrl.toString());
      if (document == null || document.scheme != 'file') {
        _showError("Document location is unavailable. Please try again.");
        return;
      }
      final reference = Uri.parse(url.replaceAll('\\', '/'));
      final relativePath =
          Uri.decodeComponent(reference.path).replaceAll('\\', '/');
      if (reference.hasScheme ||
          reference.hasAuthority ||
          p.isAbsolute(relativePath) ||
          relativePath.isEmpty) {
        throw const FormatException('Expected a relative PDF resource path');
      }
      final documentPath =
          document.replace(query: '', fragment: '').toFilePath();
      final moduleDirectory = File(documentPath).parent;
      final moduleRoot = await moduleDirectory.resolveSymbolicLinks();
      final filePath = p.normalize(p.join(moduleRoot, relativePath));
      if (!p.isWithin(moduleRoot, filePath)) {
        throw const FormatException('PDF path escapes the module directory');
      }

      File file = File(filePath);
      // Bare filenames from older bridges have a format-specific resource
      // directory. Never discard path segments or search other installations.
      if (!await file.exists() && !relativePath.contains('/')) {
        final entry = p.basename(documentPath).toLowerCase();
        final resourceDirectory = switch (entry) {
          'story.html' => p.join('story_content', 'external_files'),
          'index.html' => p.join('assets', 'resources'),
          _ => null,
        };
        if (resourceDirectory != null) {
          file = File(p.join(moduleRoot, resourceDirectory, relativePath));
        }
      }

      print("📂 Constructed PDF file path: $filePath");

      if (await file.exists()) {
        final resolvedPath = await file.resolveSymbolicLinks();
        if (!p.isWithin(moduleRoot, resolvedPath)) {
          throw const FormatException('PDF link escapes the module directory');
        }
        print("📂 File found! Opening PDF...");

        if (!mounted) return;
        final result = await OpenFile.open(resolvedPath);

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
