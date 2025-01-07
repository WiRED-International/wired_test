import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wired_test/pages/policy.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'download_confirm.dart';
import 'home_page.dart';
import 'menu.dart';
import 'module_library.dart';

class PackageInfo extends StatefulWidget {
  final String packageName;
  final String packageDescription;
  final String? downloadLink;

  PackageInfo({required this.packageName, required this.packageDescription, this.downloadLink});

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
      final filePath = '${directory!.path}/$fileName';
      final file = File(filePath);

      try {
        final response = await http.get(Uri.parse(url));
        await file.writeAsBytes(response.bodyBytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded $fileName')),
        );
        print('Directory: ${directory.path}');
        print('File Path: $filePath');

        // Unzip the downloaded file
        final bytes = file.readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);

        for (var file in archive) {
          final filename = file.name;
          final filePath = '${directory.path}/$filename';
          print('Processing file: $filename at path: $filePath');

          if (file.isFile) {
            final data = file.content as List<int>;
            File(filePath)
              ..createSync(recursive: true)
              ..writeAsBytesSync(data);
          } else {
            Directory(filePath).createSync(recursive: true);
            print('Directory created: $filePath');
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unzipped $fileName')),
        );
        print('Unzipped to: ${directory.path}');

        // Delete the zip file
        try {
          await file.delete();
          print('Zip file deleted: $filePath');
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
    // Use addPostFrameCallback to get the height after the first build
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   final RenderBox renderBox = _packageNameKey.currentContext?.findRenderObject() as RenderBox;
    //   final double packageNameHeight = renderBox.size.height;
    //   print('Package Name Container Height: $packageNameHeight');
    //   // Use addPostFrameCallback to get the height after the first build
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     if (_packageNameKey.currentContext?.findRenderObject() != null) {
    //       final RenderBox renderBox = _packageNameKey.currentContext!.findRenderObject() as RenderBox;
    //       final double packageNameHeight = renderBox.size.height;
    //       final double packageNameWidth = renderBox.size.width;
    //       final double aspectRatio = packageNameWidth / packageNameHeight;
    //
    //       // Calculate the top padding based on the package name container height
    //       setState(() {
    //         if (packageNameHeight > 55 && packageNameHeight < 90) {
    //           //topPadding = 145;
    //           topPadding = MediaQuery.of(context).size.height * 0.15;
    //         } else if (packageNameHeight >= 141) {
    //           //topPadding = 231;
    //           topPadding = MediaQuery.of(context).size.height * 0.23;
    //         } else {
    //           //topPadding = 180;
    //           topPadding = MediaQuery.of(context).size.height * 0.19;
    //         }
    //       });
    //
    //       // Print the package name height and calculated topPadding
    //       print('Package Name Container Height: $packageNameHeight');
    //       print('Package Name Container Width: $packageNameWidth');
    //
    //       print('Calculated Top Padding: $topPadding');
    //     } else {
    //       // Handle the case where the RenderBox is not yet available
    //       print('RenderBox is not available.');
    //     }
    //   });
    // });
  }

// Consider using AutoSizeText for the package name instead of RichText

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      body: Row(
        children: [
          // Conditionally show the side navigation bar in landscape mode
          if (isLandscape)
            CustomSideNavBar(
              onHomeTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => MyHomePage()));
              },
              onLibraryTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => ModuleLibrary()));
              },
              onHelpTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => const Policy()));
              },
            ),

          // Main content area (expanded to fill remaining space)
          Expanded(
            child: Stack(
              children: <Widget>[
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
                  child: SafeArea(
                    child: Center(
                      child: isLandscape ? _buildLandscapeLayout(
                          screenWidth, screenHeight) : _buildPortraitLayout(
                          screenWidth, screenHeight),
                    ),
                  ),
                ),
                // Conditionally show the bottom navigation bar in portrait mode
                if (!isLandscape)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: CustomBottomNavBar(
                      onHomeTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => MyHomePage()),
                        );
                      },
                      onLibraryTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (
                            context) => ModuleLibrary()));
                      },
                      onTrackerTap: () {
                        // Navigator.push(context, MaterialPageRoute(builder: (
                        //     context) => Policy()));
                      },
                      onMenuTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (
                            context) => Menu()));
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout(screenWidth, screenHeight) {
    return Column(
      children: [
        CustomAppBar(
          onBackPressed: () {
            Navigator.pop(context);
          },
        ),
        SizedBox(
          //height: 30,
          height: screenHeight * 0.031,
        ),

        // Package Description Container
        Flexible(
          child: Stack(
            children: [
              Positioned(
                left: screenWidth / 11,
                right: screenWidth / 11,
                bottom: screenHeight * 0.250,
                child: Container(
                  height: screenHeight * 0.60,
                  //width: 400,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: 50,
                        top: topPadding,
                      ),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${widget.packageName}\n',
                              style: TextStyle(
                                fontSize: 24.0,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF0070C0),
                              ),
                            ),
                            WidgetSpan(
                              child: SizedBox(
                                height: screenHeight * 0.06,
                              ),
                            ),
                            TextSpan(
                              text: '${widget.packageDescription}\n',
                              style: TextStyle(
                                fontSize: 24.0,
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
              ),

              // Container for gradient text fade
              Positioned(
                //bottom: 220,
                bottom: screenHeight * 0.250,
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

              // Download Button
              Positioned(
                //bottom: 110,
                bottom: screenHeight * 0.15,
                left: screenWidth / 4.2,
                right: screenWidth / 4.2,
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
                      width: screenWidth * 0.25,
                      height: screenHeight * 0.065,
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
                                fontSize: screenWidth * 0.071,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 7,),
                            SvgPicture.asset(
                              'assets/icons/download_icon.svg',
                              // height: 42,
                              // width: 42,
                              height: screenHeight * 0.0425,
                              width: screenWidth * 0.0425,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight) {
    var baseSize = MediaQuery.of(context).size.shortestSide;
    return Column(
      children: [
        CustomAppBar(
          onBackPressed: () {
            Navigator.pop(context);
          },
        ),
        SizedBox(
          //height: 30,
          height: screenHeight * 0.031,
        ),

        // Package Description Container
        Flexible(
          child: Stack(
            children: [
              Positioned(
                left: baseSize / (isTablet(context) ? 11 : 11),
                right: baseSize / (isTablet(context) ? 11 : 11),
                bottom: baseSize * (isTablet(context) ? 0.250 : 0.250),
                child: Container(
                  height: baseSize * (isTablet(context) ? 0.60 : 0.60),
                  //width: 400,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: 50,
                        top: topPadding,
                      ),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${widget.packageName}\n',
                              style: TextStyle(
                                //fontSize: 32.0,
                                fontSize: baseSize * (isTablet(context) ? 0.052 : 0.052),
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF0070C0),
                              ),
                            ),
                            WidgetSpan(
                              child: SizedBox(
                                height: screenHeight * 0.06,
                              ),
                            ),
                            TextSpan(
                              text: '${widget.packageDescription}\n',
                              style: TextStyle(
                                fontSize: baseSize * (isTablet(context) ? 0.032 : 0.032),
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
              ),

              // Container for gradient text fade
              Positioned(
                //bottom: 220,
                bottom: baseSize * (isTablet(context) ? 0.250 : 0.250),
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

              // Download Button
              Positioned(
                //bottom: 110,
                bottom: baseSize * (isTablet(context) ? 0.1 : 0.1),
                left: baseSize / (isTablet(context) ? 1.95 : 2.7),
                right: baseSize / (isTablet(context) ? 1.95 : 2.7),
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
                      width: baseSize * (isTablet(context) ? 0.25 : 0.25),
                      height: baseSize * (isTablet(context) ? 0.1 : 0.1),
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
                              height: baseSize * (isTablet(context) ? 0.0675 : 0.0425),
                              width: baseSize * (isTablet(context) ? 0.0675 : 0.0425),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }
}