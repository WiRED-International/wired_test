import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/custom_nav_bar.dart';
import 'download_confirm.dart';
import 'module_library.dart';

class ModuleInfo extends StatefulWidget {
  final String moduleName;
  final String moduleDescription;
  final String? downloadLink;

  ModuleInfo({required this.moduleName, required this.moduleDescription, this.downloadLink});

  @override
  _ModuleInfoState createState() => _ModuleInfoState();
}

class Modules {
  String? name;
  String? description;
  //String? topics;
  //String? version;
  String? downloadLink;
  //String? launchFile;
  //String? packageSize;
  //String? letters;
  List<String>? letters;
  //String? credits;
  //String? module_name;
  //String? id;


  Modules({
    this.name,
    this.description,
    //this.topics,
    //this.version,
    this.downloadLink,
    //this.launchFile,
    //this.packageSize,
    this.letters,
    //this.credits,
    //this.module_name,
    //this.id,
  });

  Modules.fromJson(Map<String, dynamic> json)
      : name = json['name'] as String,
        description = json['description'] as String,
  //topics = json['topics'] as String,
  //version = json['version'] as String,
        downloadLink = json['downloadLink'] as String,
  //launchFile = json['launchFile'] as String,
  //packageSize = json['packageSize'] as String,
  //letters = json['letters'] as String;
        letters = (json['letters'] as List<dynamic>?)?.map((e) => e as String).toList();
  //credits = json['credits'] as String,
  //module_name = json['module_name'] as String,
  //id = json['id'] as String;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    //'topics': topics,
    //'version': version,
    'downloadLink': downloadLink,
    //'launchFile': launchFile,
    //'packageSize': packageSize,
    'letters': letters,
    //'credits': credits,
    //'module_name': module_name,
    //'id': id,
  };
}

class _ModuleInfoState extends State<ModuleInfo> {
  late Future<Modules> futureModule;
  late List<Modules> moduleData = [];
  final GlobalKey _moduleNameKey = GlobalKey();
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

  // Download the Module
  Future<void> downloadModule(String url, String fileName) async {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final RenderBox renderBox = _moduleNameKey.currentContext?.findRenderObject() as RenderBox;
      final double moduleNameHeight = renderBox.size.height;
      print('Module Name Container Height: $moduleNameHeight');
      // Use addPostFrameCallback to get the height after the first build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_moduleNameKey.currentContext?.findRenderObject() != null) {
          final RenderBox renderBox = _moduleNameKey.currentContext!.findRenderObject() as RenderBox;
          final double moduleNameHeight = renderBox.size.height;

          // Calculate the top padding based on the module name container height
          setState(() {
            if (moduleNameHeight == 60) {
              topPadding = 145;
            } else if (moduleNameHeight == 150) {
              topPadding = 231;
            } else {
              topPadding = 180;
            }
          });

          // Print the module name height and calculated topPadding
          print('Module Name Container Height: $moduleNameHeight');
          print('Calculated Top Padding: $topPadding');
        } else {
          // Handle the case where the RenderBox is not yet available
          print('RenderBox is not available.');
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      // appBar: AppBar(
      //   //title: Text("title"),
      //   backgroundColor: Color(0xFFFFF0DC),
      //   elevation: 0,
      //
      // ),
      body: Stack(
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Calculate the available height for the description container
                  double availableHeight = constraints.maxHeight - 230;

                  return Center(
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                          ),
                          child: Row(
                            //mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Navigator.pop(context);
                                },
                                child: Row(
                                  children: [
                                    SvgPicture.asset(
                                      'assets/icons/chevron_left.svg',
                                      height: 28,
                                      width: 28,
                                    ),
                                    const Text(
                                      "Back",
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30,),
                        // Module Name Container
                        Container(
                          key: _moduleNameKey,
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          constraints: BoxConstraints(
                            minHeight: 60, // Minimum height for the container
                            maxHeight: 150, // Maximum height for longer titles
                          ),
                          child: Text(
                            widget.moduleName,
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF0070C0),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 20,),

                        // Module Description Container
                        Flexible(
                          child: Stack(
                            children: [
                              Positioned(
                                //top: MediaQuery.of(context).size.width / 50, // Adjust this value based on your layout
                                left: MediaQuery
                                    .of(context)
                                    .size
                                    .width / 11,
                                right: MediaQuery
                                    .of(context)
                                    .size
                                    .width / 11,
                                bottom: 220,
                                child: Container(
                                  height: availableHeight,
                                  width: 400,
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: SingleChildScrollView(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                          bottom: 50,
                                          top: topPadding,
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.moduleDescription,
                                            style: const TextStyle(
                                              fontSize: 24,
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
                                bottom: 220,
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
                                            Color(0xFFFCDBB3),
                                          ],
                                        ),
                                      )
                                  ),
                                ),
                              ),

                              // Download Button
                              Positioned(
                                bottom: 110,
                                left: MediaQuery
                                    .of(context)
                                    .size
                                    .width / 4.2,
                                right: MediaQuery
                                    .of(context)
                                    .size
                                    .width / 4.2,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: GestureDetector(
                                    onTap: _isLoading
                                        ? null
                                        :() async {
                                      if (widget.downloadLink != null) {

                                        setState(() {
                                          _isLoading = true;
                                        });

                                        String fileName = "$widget.moduleName.zip";
                                        await downloadModule(
                                            widget.downloadLink!, fileName);

                                        setState(() {
                                          _isLoading = false;
                                        });

                                        Navigator.push(context,
                                            MaterialPageRoute(
                                                builder: (context) =>
                                                    DownloadConfirm(
                                                        moduleName: widget
                                                            .moduleName)));
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(content: Text(
                                              'No download link found for ${widget
                                                  .moduleName}')),
                                        );
                                      }
                                    },
                                    child: FractionallySizedBox(
                                      widthFactor: 1.05,
                                      child: Container(
                                        //height: 60,
                                        height: screenHeight * 0.085,
                                        // width: MediaQuery.of(context).size.width / 2,
                                        //alignment: Alignment.center,
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
                                        child: Padding(
                                          padding: EdgeInsets.all(5.0),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment
                                                .center,
                                            children: [
                                              _isLoading
                                                  ? CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 3,
                                                    )
                                                  : const Padding(
                                                      padding: EdgeInsets.only(
                                                          left: 10),
                                                      child: Text(
                                                        "Download",
                                                        style: TextStyle(
                                                          fontSize: 32,
                                                          fontWeight: FontWeight.w500,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                              const SizedBox(width: 10,),
                                              SvgPicture.asset(
                                                'assets/icons/download_icon.svg',
                                                height: 42,
                                                width: 42,
                                              ),
                                            ],
                                          ),
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
                    ),
                  );
                }
    ),
            ),
          ),
          // Bottom Nav Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
              child: CustomBottomNavBar(
                onHomeTap: () {
                  print("Home");
                  //Navigator.push(context, MaterialPageRoute(builder: (context) => DownloadConfirm(moduleName: moduleName)));
                },
                onLibraryTap: () {
                  print("My Library");
                  Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleLibrary()));
                },
                onHelpTap: () {
                  print("Help");
                  //Navigator.push(context, MaterialPageRoute(builder: (context) => Help()));
                },
              ),
          ),
        ]
      ),
    );
  }
}