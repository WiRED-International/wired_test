import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_svg/svg.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wired_test/pages/animations/animation_info.dart';
import '../../providers/auth_guard.dart';
import '../../services/location_service.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../cme/cme_tracker.dart';
import '../download_confirm.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';

class AnimationInfo extends StatefulWidget {
  final int animationId;
  final String animationName;
  final String animationDescription;
  final String downloadLink;

  LocationService locationService = LocationService();

  AnimationInfo({
    Key? key,
    required this.animationId,
    required this.animationName,
    required this.animationDescription,
    required this.downloadLink,
  }) : super(key: key);

  @override
  State<AnimationInfo> createState() => _AnimationInfoState();
}

class Animations {
  String? name;
  String? description;
  String? downloadLink;

  Animations({
    this.name,
    this.description,
    this.downloadLink,
  });

  Animations.fromJson(Map<String, dynamic> json)
      : name = json['name'] as String,
        description = json['description'] as String,
        downloadLink = json['downloadLink'] as String;


  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'downloadLink': downloadLink,
  };
}

class _AnimationInfoState extends State<AnimationInfo> {
  late Future<List<Animation>> futureAnimations;
  double topPadding = 0;
  bool _isLoading = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _progressText = "";
  Map<String, double?>? _location;

  // Get Permissions
  Future<bool> checkAndRequestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }

  Future<String> getStoragePath() async {
    Directory? directory;
    if (Platform.isAndroid) {
      directory = await getExternalStorageDirectory(); // Android external storage
    } else if (Platform.isIOS || Platform.isMacOS) {
      directory = await getApplicationSupportDirectory(); // iOS/macOS safe location
    } else if (Platform.isWindows || Platform.isLinux) {
      directory = await getApplicationDocumentsDirectory(); // Windows/Linux
    }
    return directory?.path ?? "/default/path"; // Fallback path
  }
  // Download the Animation
  Future<void> downloadAnimation(String url, String fileName) async {
    final storagePath = await getStoragePath();
    final animationsDir = Directory('$storagePath/modules');
    if (!animationsDir.existsSync()) animationsDir.createSync(recursive: true);

    final zipFile = File('${animationsDir.path}/$fileName');
    final receivePort = ReceivePort();

    try {
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

      setState(() {
        _isDownloading = true;
        _progressText = "Starting download...";
      });

      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);

        if (total > 0) {
          final now = DateTime.now();
          if (now.difference(lastUpdate).inMilliseconds > 300) {
            final progress = received / total;
            final percent = (progress * 100).toStringAsFixed(1);
            final elapsed = now.difference(startTime).inSeconds;
            final speed = received / (elapsed > 0 ? elapsed : 1);
            final mbSpeed = (speed / (1024 * 1024)).toStringAsFixed(2);

            setState(() {
              _downloadProgress = progress;
              _progressText = "$percent% • $mbSpeed MB/s";
            });
            lastUpdate = now;
          }
        }
      }

      await sink.close();
      setState(() {
        _progressText = "Download complete — extracting...";
      });

      // ✅ Extract in background isolate
      await Isolate.spawn(_extractZipWithProgress, {
        'zipPath': zipFile.path,
        'outputDir': animationsDir.path,
        'sendPort': receivePort.sendPort,
      });

      await for (final message in receivePort) {
        if (message is double) {
          final percent = (message * 100).toStringAsFixed(0);
          setState(() {
            _downloadProgress = message;
            _progressText = "Extracting… $percent%";
          });
        } else if (message is String && message == 'done') {
          await zipFile.delete();
          setState(() {
            _isDownloading = false;
            _progressText = "Extraction complete!";
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloaded and extracted $fileName')),
          );
          receivePort.close();
          break;
        }
      }
    } catch (e) {
      setState(() => _isDownloading = false);
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
    await widget.locationService.saveDownload(widget.animationId, location);
  }

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
                                  child: CMETracker(),
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
                            child: CMETracker(),
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
            AnimatedOpacity(
              opacity: _isDownloading ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              child: IgnorePointer(
                ignoring: !_isDownloading,
                child: Container(
                  color: Colors.black.withOpacity(0.4),
                  child: Center(
                    child: Container(
                      width: isLandscape
                          ? screenWidth * 0.6
                          : screenWidth * 0.8,
                      padding: const EdgeInsets.all(20),
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
                          Text(
                            _progressText.startsWith("Extracting")
                                ? "Extracting..."
                                : "Downloading...",
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
                            valueColor:
                            const AlwaysStoppedAnimation<Color>(
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(screenWidth, screenHeight, baseSize) {
    return Stack(
      children: [
        // 🟢 Main vertical content
        Column(
          children: [
            SizedBox(
              height: baseSize * (isTablet(context) ? 0.03 : 0.03),
            ),

            // 📘 Animation description
            Flexible(
              flex: 6,
              child: Stack(
                children: [
                  Container(
                    height: baseSize * (isTablet(context) ? 60 : 60),
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                    ),
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
                                text: '${widget.animationName}\n',
                                style: TextStyle(
                                  fontSize: baseSize *
                                      (isTablet(context) ? 0.06 : 0.065),
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
                                text: '${widget.animationDescription}\n',
                                style: TextStyle(
                                  fontSize: baseSize *
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

                  // 🎨 Gradient fade at bottom of description
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
                              const Color(0xFFFCDBB3).withOpacity(0.0),
                              const Color(0xFFFDD8AD),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ⬇️ Download button
            Flexible(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: _isLoading
                      ? null
                      : () async {
                    if (widget.downloadLink.isNotEmpty) {
                      setState(() {
                        _isLoading = true;
                        _isDownloading = true;
                        _downloadProgress = 0;
                        _progressText = "Preparing download...";
                      });

                      String fileName = "${widget.animationName}.zip";
                      await downloadAnimation(
                          widget.downloadLink, fileName);
                      await getLocationAndSaveDownload();

                      setState(() {
                        _isLoading = false;
                        _isDownloading = false;
                      });

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DownloadConfirm(
                              packageName: widget.animationName),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'No download link found for ${widget.animationName}'),
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
                          _isLoading
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

        // 🔵 Smooth overlay progress (centered on screen)
        AnimatedOpacity(
          opacity: _isDownloading ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          child: IgnorePointer(
            ignoring: !_isDownloading,
            child: Container(
              color: Colors.black.withOpacity(0.45),
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
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _progressText.startsWith("Extracting")
                            ? "Extracting..."
                            : "Downloading...",
                        style: const TextStyle(
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
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight, baseSize) {
    return Stack(
      children: [
        // 🟢 Main horizontal layout content
        Column(
          children: [
            SizedBox(
              height: baseSize * (isTablet(context) ? 0.05 : 0.03),
            ),

            // 🎬 Animation description
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
                                text: '${widget.animationName}\n',
                                style: TextStyle(
                                  fontSize: baseSize *
                                      (isTablet(context) ? 0.06 : 0.065),
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
                                text: '${widget.animationDescription}\n',
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

                  // 🎨 Gradient fade at bottom of text
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
                              const Color(0xFFFCDBB3).withOpacity(0.0),
                              const Color(0xFFFDD8AD),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ⬇️ Download button
            Flexible(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: _isLoading
                      ? null
                      : () async {
                    if (widget.downloadLink.isNotEmpty) {
                      setState(() {
                        _isLoading = true;
                        _isDownloading = true;
                        _downloadProgress = 0;
                        _progressText = "Preparing download...";
                      });

                      String fileName = "${widget.animationName}.zip";
                      await downloadAnimation(
                          widget.downloadLink, fileName);
                      await getLocationAndSaveDownload();

                      setState(() {
                        _isLoading = false;
                        _isDownloading = false;
                      });

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DownloadConfirm(
                            packageName: widget.animationName,
                          ),
                        ),
                      );
                      print("Animation Id: ${widget.animationId}");
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'No download link found for ${widget.animationName}'),
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
                          _isLoading
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

        // 🔵 Smooth overlay progress (centered)
        AnimatedOpacity(
          opacity: _isDownloading ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          child: IgnorePointer(
            ignoring: !_isDownloading,
            child: Container(
              color: Colors.black.withOpacity(0.45),
              child: Center(
                child: Container(
                  width: screenWidth * 0.6,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _progressText.startsWith("Extracting")
                            ? "Extracting..."
                            : "Downloading...",
                        style: const TextStyle(
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
          ),
        ),
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
    // 🔹 Send progress every few files to avoid flooding UI
    if (extracted % 5 == 0 || extracted == total) {
      final progress = extracted / total;
      sendPort.send(progress);
    }
  }

  await inputStream.close();
  print('✅ Extraction complete to $outputDir');
  sendPort.send('done');
}