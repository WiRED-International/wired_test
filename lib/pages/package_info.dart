import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/auth_guard.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'cme/cme_tracker.dart';
import 'download_confirm.dart';
import 'home_page.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
import 'module_library.dart';

class PackageInfo extends StatefulWidget {
  final int packageId;
  final String packageName;
  final String packageDescription;
  final String? downloadLink;

  PackageInfo({required this.packageId, required this.packageName, required this.packageDescription, this.downloadLink});

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

  // Get Permissions
  Future<bool> checkAndRequestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }

  // Download the Package
  Future<void> downloadPackage(String url, String fileName) async {
    bool hasPermission = await checkAndRequestStoragePermission();
    print("Has Permission: $hasPermission");
    if (true) {
      final directory = await getExternalStorageDirectory(); // Get the External Storage Directory (Android)
      if (directory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to access storage directory')),
        );
        return;
      }

      // Check if the packages directory exists
      final packagesDirectoryPath = '${directory.path}/packages';
      final packagesDirectory = Directory(packagesDirectoryPath);
      if (!packagesDirectory.existsSync()) {
        packagesDirectory.createSync(recursive: true);
        print('Created directory: $packagesDirectoryPath');
      }

      final packagesFilePath = '$packagesDirectoryPath/$fileName';
      final file = File(packagesFilePath);

      try {
        final response = await http.get(Uri.parse(url));
        await file.writeAsBytes(response.bodyBytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded $fileName')),
        );
        print('Directory: ${directory.path}');
        print('File Path: $packagesFilePath');

        // Unzip the downloaded file
        final bytes = file.readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);

        for (var file in archive) {
          final filename = file.name;
          final packagesFilePath = '${directory.path}/packages/$filename';
          print('Processing file: $filename at path: $packagesFilePath');

          if (file.isFile) {
            final data = file.content as List<int>;
            File(packagesFilePath)
              ..createSync(recursive: true)
              ..writeAsBytesSync(data);
          } else {
            Directory(packagesFilePath).createSync(recursive: true);
            print('Directory created: $packagesFilePath');
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unzipped $fileName')),
        );
        print('Unzipped to: ${directory.path}');

        // Delete the zip file
        try {
          await file.delete();
          print('Zip file deleted: $packagesFilePath');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unzipped and deleted $fileName')),
          );
        } catch (e) {
          print('Error deleting zip file: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting $fileName')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading $fileName')),
        );
      }
    } else {
      openAppSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permission denied')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
  }

// Consider using AutoSizeText for the package name instead of RichText

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
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(screenWidth, screenHeight, baseSize) {
    return Column(
      children: [
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.03 : 0.03),
        ),

        // Package Description Container
        Flexible(
          flex: 6,
          child: Stack(
            children: [
              Container(
                height: baseSize * (isTablet(context) ? 60 : 60),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.only(
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
                                fontSize: baseSize * (isTablet(context) ? 0.06 : 0.065),
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF0070C0),
                              ),
                            ),
                            WidgetSpan(
                              child: SizedBox(
                                height: baseSize * (isTablet(context) ? 0.08 : 0.08),
                              ),
                            ),
                            TextSpan(
                              text: '${widget.packageDescription}\n',
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
              // Container for gradient text fade
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
                          stops: [0.0, 5.0],
                          colors: [
                            // Colors.transparent,
                            // Color(0xFFFFF0DC),
                            //Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
                            Color(0xFFFCDBB3).withOpacity(0.0),
                            Color(0xFFFDD8AD),
                          ],
                        ),
                      )
                  ),
                ),
              ),
            ],
          ),
        ),

              // Download Button
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
                        });

                        String fileName = "$widget.packageName.zip";
                        await downloadPackage(
                            widget.downloadLink!, fileName);

                        setState(() {
                          _isLoading = false;
                        });
                        print("Package Id: ${widget.packageId}");
                        Navigator.push(context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    DownloadConfirm(
                                        packageName: widget
                                            .packageName)));
                      } else {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(
                          SnackBar(content: Text(
                              'No download link found for ${widget
                                  .packageName}')),
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
                          ], // Your gradient colors
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(
                                0.5),
                            spreadRadius: 1,
                            blurRadius: 5,
                            offset: const Offset(1,
                                3), // changes position of shadow
                          ),
                        ],
                      ),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _isLoading
                                ? CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            )
                                : Text(
                              "Download",
                              style: TextStyle(
                                fontSize: baseSize * (isTablet(context) ? 0.071 : 0.071),
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 7,),
                            SvgPicture.asset(
                              'assets/icons/download_icon.svg',
                              // height: 42,
                              // width: 42,
                              height: baseSize * (isTablet(context) ? 0.0675 : 0.0675),
                              width: baseSize * (isTablet(context) ? 0.0675 : 0.0675),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            ],
          );
        }

  Widget _buildLandscapeLayout(screenWidth, screenHeight, baseSize) {
    return Column(
      children: [
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.05 : 0.03),
        ),

        // Package Description Container
        Flexible(
          flex: 6,
          child: Stack(
            children: [
                Container(
                  height: baseSize * (isTablet(context) ? 0.65 : 0.65),
                  //width: 400,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.only(
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
                                //fontSize: 32.0,
                                fontSize: baseSize * (isTablet(context) ? 0.06 : 0.065),
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF0070C0),
                              ),
                            ),
                            WidgetSpan(
                              child: SizedBox(
                                height: baseSize * (isTablet(context) ? 0.08 : 0.08),
                              ),
                            ),
                            TextSpan(
                              text: '${widget.packageDescription}\n',
                              style: TextStyle(
                                fontSize: screenHeight * (isTablet(context) ? 0.04 : 0.045),
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

              // Container for gradient text fade
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
                        stops: [0.0, 5.0],
                        colors: [
                          // Colors.transparent,
                          // Color(0xFFFFF0DC),
                          //Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
                          Color(0xFFFCDBB3).withOpacity(0.0),
                          Color(0xFFFDD8AD),
                        ],
                      ),
                    )
                  ),
                ),
              ),
            ],
          ),
        ),

              // Download Button
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
                  });

                  String fileName = "$widget.packageName.zip";
                  await downloadPackage(
                      widget.downloadLink!, fileName);

                  setState(() {
                    _isLoading = false;
                  });

                  Navigator.push(context,
                      MaterialPageRoute(
                          builder: (context) =>
                              DownloadConfirm(
                                  packageName: widget
                                      .packageName)));
                } else {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(
                    SnackBar(content: Text(
                        'No download link found for ${widget
                            .packageName}')),
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
                    ], // Your gradient colors
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(
                          0.5),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(1,
                          3), // changes position of shadow
                    ),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _isLoading
                          ? CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      )
                          : Text(
                        "Download",
                        style: TextStyle(
                          fontSize: baseSize * (isTablet(context) ? 0.07 : 0.07),
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 7,),
                      SvgPicture.asset(
                        'assets/icons/download_icon.svg',
                        // height: 42,
                        // width: 42,
                        height: baseSize * (isTablet(context) ? 0.0675 : 0.0675),
                        width: baseSize * (isTablet(context) ? 0.0675 : 0.0675),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
      ],
    );
  }
}