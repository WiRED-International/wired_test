import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import '../../providers/auth_guard.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../cme/cme_tracker.dart';
import '../creditsTracker/credits_tracker.dart';
import '../download_confirm.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import '../../services/location_service.dart';

class PackageInfo extends StatefulWidget {
  final int packageId;
  final String packageName;
  final String packageDescription;
  final String? downloadLink;

  PackageInfo({
    required this.packageId,
    required this.packageName,
    required this.packageDescription,
    this.downloadLink
  });

  @override
  _PackageInfoState createState() => _PackageInfoState();
}

class Packages {
  String? name;
  String? description;
  String? downloadLink;

  Packages({
    this.name,
    this.description,
    this.downloadLink,
  });

  Packages.fromJson(Map<String, dynamic> json)
      : name = json['name'] as String,
        description = json['description'] as String,
        downloadLink = json['downloadLink'] as String;


  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'downloadLink': downloadLink,
  };
}

class _PackageInfoState extends State<PackageInfo> {
  late Future<Packages> futurePackage;
  late List<Packages> packageData = [];
  final GlobalKey _packageNameKey = GlobalKey();
  double topPadding = 0;
  bool _isLoading = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0; // 0.0–1.0
  String _progressText = "";

  // ✅ Safe storage path
  Future<String> getStoragePath() async {
    Directory? baseDir;

    try {
      // Prefer external app directory (visible via Files app)
      baseDir = await getExternalStorageDirectory();
    } catch (_) {}

    // Fallback to internal app docs dir
    baseDir ??= await getApplicationDocumentsDirectory();

    // Ensure /packages folder exists
    final packagesDir = Directory('${baseDir.path}/packages');
    if (!await packagesDir.exists()) {
      await packagesDir.create(recursive: true);
      // Give Android a moment to register it
      await Future.delayed(const Duration(milliseconds: 150));
    }

    return packagesDir.path;
  }

  // ✅ Streamed large-file download with progress + isolate extraction
  Future<void> downloadPackage(String url, String fileName) async {
    try {
      final storagePath = await getStoragePath();
      final packagesDir = Directory(storagePath);

      if (!packagesDir.existsSync()) {
        packagesDir.createSync(recursive: true);
        print('Created packages directory: ${packagesDir.path}');
      }

      final zipFile = File('${packagesDir.path}/$fileName');

      // Ensure parent directories exist (fixes PathNotFoundException)
      if (!await zipFile.parent.exists()) {
        await zipFile.parent.create(recursive: true);
        await Future.delayed(const Duration(milliseconds: 100));
      }

      print('DEBUG: Downloading to ${zipFile.path}');
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

      if (mounted) {
        setState(() {
          _isDownloading = true;
          _downloadProgress = 0.0;
          _progressText = "Starting download...";
        });
      }

      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);

        if (total > 0) {
          final now = DateTime.now();
          if (now.difference(lastUpdate).inMilliseconds > 250) {
            final progress = received / total;
            final percent = (progress * 100).toStringAsFixed(1);
            final elapsed = now.difference(startTime).inSeconds;
            final speed = received / (elapsed > 0 ? elapsed : 1);
            final mbSpeed = (speed / (1024 * 1024)).toStringAsFixed(2);

            if (mounted) {
              setState(() {
                _downloadProgress = progress;
                _progressText = "$percent% • $mbSpeed MB/s";
              });
            }
            lastUpdate = now;
          }
        }
      }

      await sink.close();
      print('✅ Download complete: ${zipFile.path}');

      // Switch overlay text to extracting
      if (mounted) {
        setState(() {
          _progressText = "Download complete — extracting...";
          _downloadProgress = 1.0;
        });
      }

      // 🧩 Extract in background isolate with progress
      final receivePort = ReceivePort();
      await Isolate.spawn(_extractZipWithProgress, {
        'zipPath': zipFile.path,
        'outputDir': packagesDir.path,
        'sendPort': receivePort.sendPort,
      });

      await for (final message in receivePort) {
        if (message is double) {
          // 0.0–1.0 extraction progress
          final percent = (message * 100).toStringAsFixed(0);
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

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Downloaded and extracted $fileName')),
            );
          }

          receivePort.close();
          break;
        }
      }
    } catch (e) {
      print('❌ Package download error: $e');
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading $fileName: $e')),
        );
      }
    }
  }
  @override
  void initState() {
    super.initState();
  }

// Consider using AutoSizeText for the package name instead of RichText

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final baseSize = MediaQuery.of(context).size.shortestSide;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // 🌈 Background gradient
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

            // 📱 Main content column
            Column(
              children: [
                // 🧭 Custom AppBar at top
                CustomAppBar(
                  onBackPressed: () => Navigator.pop(context),
                  requireAuth: false,
                ),

                // 🧱 Main content area
                Expanded(
                  child: Row(
                    children: [
                      // 🧩 Sidebar for landscape only
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
                                builder: (context) =>
                                    AuthGuard(child: CreditsTracker()),
                              ),
                            );
                          },
                          onMenuTap: () async {
                            bool isLoggedIn = await checkIfUserIsLoggedIn();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                isLoggedIn ? Menu() : GuestMenu(),
                              ),
                            );
                          },
                        ),

                      // 📄 Page body (either portrait or landscape layout)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(
                              screenWidth, screenHeight, baseSize)
                              : _buildPortraitLayout(
                              screenWidth, screenHeight, baseSize),
                        ),
                      ),
                    ],
                  ),
                ),

                // 🧭 Bottom navigation bar (portrait only)
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
                          builder: (context) =>
                              AuthGuard(child: CreditsTracker()),
                        ),
                      );
                    },
                    onMenuTap: () async {
                      bool isLoggedIn = await checkIfUserIsLoggedIn();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                          isLoggedIn ? Menu() : GuestMenu(),
                        ),
                      );
                    },
                  ),
              ],
            ),

            // 🔶 Smooth overlay progress bar (download/extraction)
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

            // 📘 Package description
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
                                text: '${widget.packageName}\n',
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
                                text: '${widget.packageDescription}\n',
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
                    if (widget.downloadLink != null) {
                      setState(() {
                        _isLoading = true;
                        _isDownloading = true; // start overlay
                        _downloadProgress = 0;
                        _progressText = "Preparing download...";
                      });

                      String fileName = "${widget.packageName}.zip";
                      await downloadPackage(widget.downloadLink!, fileName);

                      setState(() {
                        _isLoading = false;
                        _isDownloading = false; // remove overlay
                      });

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DownloadConfirm(
                              packageName: widget.packageName),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'No download link found for ${widget.packageName}'),
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
                            height:
                            baseSize * (isTablet(context) ? 0.0675 : 0.0675),
                            width:
                            baseSize * (isTablet(context) ? 0.0675 : 0.0675),
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
        // 🟢 Main column layout
        Column(
          children: [
            SizedBox(
              height: baseSize * (isTablet(context) ? 0.05 : 0.03),
            ),

            // 📘 Package Description Container
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
                                text: '${widget.packageName}\n',
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
                                text: '${widget.packageDescription}\n',
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

                  // 🎨 Gradient fade overlay
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

            // ⬇️ Download Button
            Flexible(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: _isLoading
                      ? null
                      : () async {
                    if (widget.downloadLink != null) {
                      setState(() {
                        _isLoading = true;
                        _isDownloading = true;
                        _downloadProgress = 0;
                        _progressText = "Preparing download...";
                      });

                      String fileName = "${widget.packageName}.zip";
                      await downloadPackage(
                          widget.downloadLink!, fileName);

                      setState(() {
                        _isLoading = false;
                        _isDownloading = false;
                      });

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DownloadConfirm(
                            packageName: widget.packageName,
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'No download link found for ${widget.packageName}',
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
                            height:
                            baseSize * (isTablet(context) ? 0.0675 : 0.0675),
                            width:
                            baseSize * (isTablet(context) ? 0.0675 : 0.0675),
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