import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:wired_test/pages/home_page.dart';
import '../providers/auth_guard.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'cme/cme_tracker.dart';
import 'creditsTracker/credits_tracker.dart';
import 'download_confirm.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
import 'module_library.dart';
import '../services/location_service.dart';
import '../utils/download_section.dart';
import 'dart:isolate';


class ModuleInfo extends StatefulWidget {
  final int moduleId;
  final String moduleName;
  final String moduleDescription;
  final String? downloadLink;

  LocationService locationService = LocationService();

  ModuleInfo({
    required this.moduleId,
    required this.moduleName,
    required this.moduleDescription,
    this.downloadLink
  });

  @override
  _ModuleInfoState createState() => _ModuleInfoState();
}

class Modules {
  String? name;
  String? description;
  String? downloadLink;
  List<String>? letters;

  Modules({
    this.name,
    this.description,
    this.downloadLink,
    this.letters,
  });

  Modules.fromJson(Map<String, dynamic> json)
      : name = json['name'] as String,
        description = json['description'] as String,
        downloadLink = json['downloadLink'] as String,
        letters = (json['letters'] as List<dynamic>?)?.map((e) => e as String).toList();


  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'downloadLink': downloadLink,
    'letters': letters,
  };
}

class _ModuleInfoState extends State<ModuleInfo> {
  late Future<Modules> futureModule;
  late List<Modules> moduleData = [];
  final GlobalKey _moduleNameKey = GlobalKey();
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  String _progressText = "";
  double topPadding = 0;
  bool _isLoading = false;
  Map<String, double?>? _location;

  // Get Permissions
  // Future<bool> checkAndRequestStoragePermission() async {
  //   var status = await Permission.storage.status;
  //   if (!status.isGranted) {
  //     status = await Permission.storage.request();
  //   }
  //   return status.isGranted;
  // }

  /// Attempts external first, falls back to internal if needed.
  Future<String> getStoragePath() async {
    // Try external app-private directory first (visible via Files app)
    Directory? baseDir;
    try {
      baseDir = await getExternalStorageDirectory();
    } catch (_) {}
    baseDir ??= await getApplicationDocumentsDirectory();

    // Always ensure /modules exists and is fully registered
    final modulesDir = Directory('${baseDir.path}/modules');
    if (!await modulesDir.exists()) {
      await modulesDir.create(recursive: true);
      // Give Android time to register directory before writing
      await Future.delayed(const Duration(milliseconds: 150));
    }

    return modulesDir.path;
  }

// ✅ STREAMED LARGE-FILE DOWNLOAD WITH PROGRESS + EXTRACTION
  Future<void> downloadModule(String url, String fileName) async {
    try {
      final storagePath = await getStoragePath();
      print('DEBUG: Storage path -> $storagePath');

      // ⚙️ Ensure target directory exists
      final modulesDir = Directory(storagePath);
      if (!modulesDir.existsSync()) {
        modulesDir.createSync(recursive: true);
        print('Created directory: ${modulesDir.path}');
      }

      final zipFile = File('${modulesDir.path}/$fileName');

      // ⚙️ Ensure parent directories exist (fixes PathNotFoundException)
      if (!await zipFile.parent.exists()) {
        await zipFile.parent.create(recursive: true);
        await Future.delayed(const Duration(milliseconds: 100));
      }

      print('DEBUG: Downloading to ${zipFile.path}');

      // 🔽 Streamed download (efficient for 100MB+ files)
      final request = await HttpClient().getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Download failed with ${response.statusCode}');
      }

      final sink = zipFile.openWrite();
      int received = 0;
      final total = response.contentLength;
      final startTime = DateTime.now();
      DateTime lastUpdate = DateTime.now();

      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);

        if (total > 0) {
          final now = DateTime.now();
          final elapsed = now.difference(startTime).inMilliseconds / 1000.0;
          final speed = received / elapsed; // bytes/sec
          final progress = received / total;
          final remainingBytes = total - received;
          final etaSeconds = remainingBytes / (speed > 0 ? speed : 1);
          final percent = (progress * 100).toStringAsFixed(1);
          final mbSpeed = (speed / (1024 * 1024)).toStringAsFixed(2);
          final eta = etaSeconds < 60
              ? '${etaSeconds.toStringAsFixed(0)}s'
              : '${(etaSeconds / 60).toStringAsFixed(1)}m';

          // 🔄 Throttle updates every 250ms
          if (now.difference(lastUpdate).inMilliseconds > 250) {
            lastUpdate = now;
            if (mounted) {
              setState(() {
                _downloadProgress = progress;
                _progressText = '$percent% • $mbSpeed MB/s • $eta left';
              });
            }
          }
        }
      }

      await sink.close();
      print('✅ Download complete: ${zipFile.path}');

      // 🧩 Prepare extraction
      final receivePort = ReceivePort();
      if (mounted) {
        setState(() {
          _progressText = "Download complete — extracting files…";
          _isDownloading = true;
          _downloadProgress = 1.0;
        });
      }

      // 🧠 Extract in background isolate (non-blocking)
      await Isolate.spawn(_extractZipWithProgress, {
        'zipPath': zipFile.path,
        'outputDir': modulesDir.path,
        'sendPort': receivePort.sendPort,
      });

      // 🧭 Listen for extraction progress
      await for (final message in receivePort) {
        if (message is double) {
          final percent = (message * 100).toStringAsFixed(1);
          if (mounted) {
            setState(() {
              _downloadProgress = message;
              _progressText = "Extracting… $percent%";
            });
          }
        } else if (message == 'done') {
          await zipFile.delete();
          print('🗑️ Deleted ZIP after extraction.');

          if (mounted) {
            setState(() {
              _isDownloading = false;
              _progressText = "Extraction complete!";
            });
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloaded and extracted $fileName')),
          );
          receivePort.close();
          break;
        }
      }
    } catch (e) {
      print('❌ Download error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading $fileName: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
  }

  Future<void> getLocationAndSaveDownload() async {
    var location = await widget.locationService.getLocation(context);
    setState(() {
      _location = location;  // Store the location in state
    });
    await widget.locationService.saveDownload(widget.moduleId, location);
  }

// Consider using AutoSizeText for the module name instead of RichText

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    var baseSize = MediaQuery.of(context).size.shortestSide;
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFF0DC),
                    Color(0xFFF9EBD9),
                    Color(0xFFFFC888),
                  ],
                ),
              ),
            ),
            Column(
              children: [
                // Custom AppBar
                CustomAppBar(
                  onBackPressed: () {
                    Navigator.pop(context);
                  },
                  requireAuth: false,
                ),
                // Expanded layout for the main content
                Expanded(
                  child: Row(
                    children: [
                      if (isLandscape)
                        CustomSideNavBar(
                          onHomeTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => ModuleLibrary()),
                            );
                          },
                          onTrackerTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AuthGuard(
                                  child: CreditsTracker(),
                                ),
                              ),
                            );
                          },
                          onMenuTap: () async {
                            bool isLoggedIn = await checkIfUserIsLoggedIn();
                            print("Navigating to menu. Logged in: $isLoggedIn");
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                              ),
                            );
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(screenWidth, screenHeight, baseSize)
                              : _buildPortraitLayout(screenWidth, screenHeight, baseSize),
                        ),
                      ),
                    ],
                  ),
                ),

                if (!isLandscape)
                  CustomBottomNavBar(
                    onHomeTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const MyHomePage()),
                      );
                    },
                    onLibraryTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => ModuleLibrary()),
                      );
                    },
                    onTrackerTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AuthGuard(
                            child: CreditsTracker(),
                          ),
                        ),
                      );
                    },
                    onMenuTap: () async {
                      bool isLoggedIn = await checkIfUserIsLoggedIn();
                      print("Navigating to menu. Logged in: $isLoggedIn");
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(screenWidth, screenHeight, baseSize) {
    return Stack(
      children: [
        // 🔹 Main content (your original layout)
        Column(
          children: [
            SizedBox(
              height: baseSize * (isTablet(context) ? 0.03 : 0.03),
            ),
            // 🟢 Module Description Container
            Flexible(
              flex: 6,
              child: Stack(
                children: [
                  Container(
                    height: baseSize * (isTablet(context) ? 60 : 60),
                    decoration: const BoxDecoration(color: Colors.transparent),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          bottom: 50,
                          left: 10,
                          right: 10,
                        ),
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '${widget.moduleName}\n',
                                style: TextStyle(
                                  fontSize: baseSize * (isTablet(context) ? 0.06 : 0.065),
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF0070C0),
                                ),
                              ),
                              WidgetSpan(
                                child: SizedBox(
                                  height: baseSize * (isTablet(context) ? 0.08 : 0.08),
                                ),
                              ),
                              TextSpan(
                                text: '${widget.moduleDescription}\n',
                                style: TextStyle(
                                  fontSize: baseSize * (isTablet(context) ? 0.04 : 0.045),
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 🟢 Gradient text fade
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 5.0],
                            colors: [
                              Color(0xFFFCDBB3).withOpacity(0.0),
                              Color(0xFFFDD8AD),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 🟢 Download Button
            Flexible(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: _isLoading || _isDownloading
                      ? null
                      : () async {
                    if (widget.downloadLink != null) {
                      setState(() {
                        _isLoading = true;
                        _isDownloading = true;
                      });

                      String fileName = "${widget.moduleName}.zip";
                      await downloadModule(widget.downloadLink!, fileName);
                      await getLocationAndSaveDownload();

                      setState(() {
                        _isLoading = false;
                        _isDownloading = false;
                      });

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              DownloadConfirm(moduleName: widget.moduleName),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'No download link found for ${widget.moduleName}',
                          ),
                        ),
                      );
                    }
                  },
                  child: Container(
                    width: baseSize * (isTablet(context) ? 0.5 : 0.55),
                    height: baseSize * (isTablet(context) ? 0.10 : 0.12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0070C0),
                          Color(0xFF00C1FF),
                          Color(0xFF0070C0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(35),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(1, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _isLoading || _isDownloading
                              ? const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          )
                              : Text(
                            "Download",
                            style: TextStyle(
                              fontSize: baseSize *
                                  (isTablet(context) ? 0.071 : 0.071),
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 7),
                          SvgPicture.asset(
                            'assets/icons/download_icon.svg',
                            height: baseSize *
                                (isTablet(context) ? 0.0675 : 0.0675),
                            width: baseSize *
                                (isTablet(context) ? 0.0675 : 0.0675),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // 🔹 Overlay progress bar in the center of the screen
        if (_isDownloading) ...[
          Container(
            color: Colors.black.withOpacity(0.4), // dim background
            child: Center(
              child: Container(
                width: screenWidth * 0.8,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Downloading...",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0070C0),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _downloadProgress,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF22C55E),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _progressText,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }


  Widget _buildLandscapeLayout(screenWidth, screenHeight, baseSize) {
    return Stack(
      children: [
        // 🔹 Main landscape content (your original layout)
        Column(
          children: [
            SizedBox(
              height: baseSize * (isTablet(context) ? 0.05 : 0.03),
            ),

            // 🟢 Module Description Container
            Flexible(
              flex: 6,
              child: Stack(
                children: [
                  Container(
                    height: baseSize * (isTablet(context) ? 0.65 : 0.65),
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          bottom: 50,
                          left: 20,
                          right: 20,
                        ),
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '${widget.moduleName}\n',
                                style: TextStyle(
                                  fontSize:
                                  baseSize * (isTablet(context) ? 0.06 : 0.065),
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF0070C0),
                                ),
                              ),
                              WidgetSpan(
                                child: SizedBox(
                                  height: baseSize *
                                      (isTablet(context) ? 0.08 : 0.08),
                                ),
                              ),
                              TextSpan(
                                text: '${widget.moduleDescription}\n',
                                style: TextStyle(
                                  fontSize: screenHeight *
                                      (isTablet(context) ? 0.04 : 0.045),
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 🟢 Gradient text fade
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 5.0],
                            colors: [
                              Color(0xFFFCDBB3).withOpacity(0.0),
                              Color(0xFFFDD8AD),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 🟢 Download Button
            Flexible(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: _isLoading || _isDownloading
                      ? null
                      : () async {
                    if (widget.downloadLink != null) {
                      setState(() {
                        _isLoading = true;
                        _isDownloading = true;
                      });

                      String fileName = "${widget.moduleName}.zip";
                      await downloadModule(widget.downloadLink!, fileName);
                      await getLocationAndSaveDownload();

                      setState(() {
                        _isLoading = false;
                        _isDownloading = false;
                      });

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              DownloadConfirm(moduleName: widget.moduleName),
                        ),
                      );
                      print("Module Id: ${widget.moduleId}");
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'No download link found for ${widget.moduleName}',
                          ),
                        ),
                      );
                    }
                  },
                  child: Container(
                    width: baseSize * (isTablet(context) ? 0.5 : 0.55),
                    height: baseSize * (isTablet(context) ? 0.10 : 0.12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0070C0),
                          Color(0xFF00C1FF),
                          Color(0xFF0070C0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(1, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _isLoading || _isDownloading
                              ? const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          )
                              : Text(
                            "Download",
                            style: TextStyle(
                              fontSize: baseSize *
                                  (isTablet(context) ? 0.07 : 0.07),
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 7),
                          SvgPicture.asset(
                            'assets/icons/download_icon.svg',
                            height: baseSize *
                                (isTablet(context) ? 0.0675 : 0.0675),
                            width: baseSize *
                                (isTablet(context) ? 0.0675 : 0.0675),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // 🔹 Overlay progress bar centered on screen (same as portrait)
        if (_isDownloading) ...[
          Container(
            color: Colors.black.withOpacity(0.4), // Dim background
            child: Center(
              child: Container(
                width: screenWidth * 0.6, // slightly narrower in landscape
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Downloading...",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0070C0),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _downloadProgress,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF22C55E),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _progressText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

Future<void> _extractZipWithProgress(Map<String, dynamic> args) async {
  final zipFile = File(args['zipPath']!);
  final outputDir = args['outputDir']!;
  final sendPort = args['sendPort'] as SendPort;

  print('📦 Background extraction started for ${zipFile.path}');
  final inputStream = InputFileStream(zipFile.path);
  final archive = ZipDecoder().decodeStream(inputStream);

  int extracted = 0;
  final total = archive.length;

  for (final file in archive) {
    final outPath = '$outputDir/${file.name}';

    if (file.isFile) {
      final output = OutputFileStream(outPath);
      file.writeContent(output);
      await output.close();
    } else {
      Directory(outPath).createSync(recursive: true);
    }

    extracted++;
    // Send progress every few files to avoid too many UI updates
    if (extracted % 5 == 0 || extracted == total) {
      final progress = extracted / total;
      sendPort.send(progress);
    }
  }

  await inputStream.close();
  print('✅ Extraction complete to $outputDir');
  sendPort.send('done');
}
