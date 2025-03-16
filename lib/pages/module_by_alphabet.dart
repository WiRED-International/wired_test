import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '.././utils/functions.dart';
import 'package:archive/archive_io.dart';
import '../providers/auth_guard.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/side_nav_bar.dart';
import 'cme/cme_tracker.dart';
import 'home_page.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
import 'module_library.dart';
import 'module_info.dart';

class ModuleByAlphabet extends StatefulWidget {
  final String letter;


  ModuleByAlphabet({required this.letter});

  @override
  _ModuleByAlphabetState createState() => _ModuleByAlphabetState();
}

class ModuleLetter {
  int? id;
  String? letters;

  ModuleLetter({this.id, this.letters});

  ModuleLetter.fromJson(Map<String, dynamic> json)
      : id = json['id'] as int?,
        letters = json['letters'] as String?;

  Map<String, dynamic> toJson() => {
    'id': id,
    'letters': letters,
  };
}

class Modules {
  int? id;
  String? name;
  String? description;
  String? downloadLink;
  List<ModuleLetter>? letters;
  Modules? redirectedModule;

  Modules({
    this.id,
    this.name,
    this.description,
    this.downloadLink,
    this.letters,
    this.redirectedModule,
  });

  Modules.fromJson(Map<String, dynamic> json)
      : id = json['id'] as int?,
        name = json['name'] as String?,
        description = json['description'] as String?,
        downloadLink = json['downloadLink'] as String?,
        letters = (json['letters'] as List<dynamic>?)
            ?.map((e) => ModuleLetter.fromJson(e as Map<String, dynamic>))
            .toList(),
        redirectedModule = json['redirectedModule'] != null
            ? Modules.fromJson(json['redirectedModule'])
            : null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'downloadLink': downloadLink,
    'letters': letters?.map((e) => e.toJson()).toList(),
    'redirectedModule': redirectedModule?.toJson(),
  };
}

class _ModuleByAlphabetState extends State<ModuleByAlphabet> {
  late Future<List<Modules>> futureModules;
  late List<Modules> moduleData = [];

  // Get the Module Data
  Future<List<Modules>> getModules() async {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final apiEndpoint = '/modules/';

    try {
      final response = await http.get(Uri.parse('$apiBaseUrl$apiEndpoint'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // List<Modules> allModules = data.map<Modules>((e) => Modules.fromJson(e))
        //     .toList();

        if (data is List) {
          List<Modules> allModules = data.map<Modules>((e) => Modules.fromJson(e)).toList();
          moduleData = allModules.where((module) {
            print("Module Name: ${module.letters}");
            // Check if any of the letters match the desired letter
            return module.letters?.any((letter) => letter.letters == widget.letter) ?? false;
          }).toList();

          List<Modules> filteredModules = allModules.where((module) => module.letters?.contains(
              widget.letter) ?? false).toList();
          // change to lower case and Sort modules by name
          filteredModules.sort((a, b) =>
              a.name!.toLowerCase().compareTo(b.name!.toLowerCase()));

          debugPrint("Module Data: ${filteredModules.length}");
          return filteredModules;
        } else {
          debugPrint("Data is not a list");
        }
      } else {
        debugPrint("Failed to load modules, status code: ${response.statusCode}");
      }
      //return moduleData;
    } catch (e) {
      debugPrint(" Error fetching modules: $e");
    }
    return [];
  }

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
    futureModules = getModules();
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
        Container(
          child: Column(
            //mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                "Search by",
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.07 : 0.08),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF0070C0),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Alphabet: ",
                    style: TextStyle(
                      fontSize: baseSize * (isTablet(context) ? 0.07 : 0.08),
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0070C0),
                    ),
                  ),
                  Text(
                    widget.letter,
                    style: TextStyle(
                      fontSize: baseSize * (isTablet(context) ? 0.07 : 0.08),
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF548235),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Flexible(
          //flex: 1,
          child: Stack(
            children: [
              Container(
                width: screenWidth * 1.0,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                ),
                child: FutureBuilder<List<Modules>>(
                  future: futureModules,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return ListView.builder(
                        itemCount: moduleData.length + 1,
                        // Increase the item count by 1 to account for the SizedBox as the last item
                        itemBuilder: (context, index) {
                          if (index == moduleData.length) {
                            // This is the last item (the SizedBox or Container)
                            return SizedBox(
                              height: screenHeight * 0.21,
                            );
                          }
                          final module = moduleData[index];
                          final moduleName = module.name ?? "Unknown Module";
                          debugPrint("Module Name: ${moduleName}");
                          final downloadLink = module.downloadLink ??
                              "No Link available";
                          final moduleDescription = module.description ??
                              "No Description available";

                          if (module.redirectedModule != null) {
                            return Column(
                              children: [
                                Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        vertical: baseSize * (isTablet(context) ? 0.01 : 0.02),
                                        horizontal: baseSize * (isTablet(context) ? 0.01 : 0.01)
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          "$moduleName see",
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: baseSize * (isTablet(context) ? 0.04 : 0.05),
                                            fontFamilyFallback: [
                                              'NotoSans',
                                              'NotoSerif',
                                              'Roboto',
                                              'sans-serif',
                                            ],
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        GestureDetector(
                                          onTap: () async {
                                            if (module.redirectedModule!.downloadLink != null &&
                                                module.redirectedModule!.downloadLink!.isNotEmpty) {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => ModuleInfo(
                                                    moduleId: module.redirectedModule!.id!,
                                                    moduleName: module.redirectedModule!.name!,
                                                    moduleDescription: module.redirectedModule!.description ?? "No Description available",
                                                    downloadLink: module.redirectedModule!.downloadLink!,
                                                  ),
                                                ),
                                              );
                                            } else {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('No download link found for ${module.redirectedModule!.name}')),
                                              );
                                            }
                                          },
                                          child: Text(
                                            module.redirectedModule!.name!,
                                            style: TextStyle(
                                              color: Color(0xFF0070C0), // Redirected module name in blue
                                              fontSize: baseSize * (isTablet(context) ? 0.045 : 0.055),
                                              fontFamilyFallback: [
                                                'NotoSans',
                                                'NotoSerif',
                                                'Roboto',
                                                'sans-serif',
                                              ],
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const Divider(
                                  color: Colors.grey,
                                  height: 1,
                                ),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                      vertical: screenHeight * (isTablet(context) ? 0.01 : 0.01),
                                      horizontal: screenWidth * (isTablet(context) ? 0.03 : 0.03)
                                  ),
                                  child: InkWell(
                                    onTap: () async {
                                      if (module.downloadLink != null && module.downloadLink!.isNotEmpty) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ModuleInfo(
                                              moduleId: module.id!,
                                              moduleName: moduleName,
                                              moduleDescription: moduleDescription,
                                              downloadLink: downloadLink,
                                            ),
                                          ),
                                        );
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('No download link found for ${module.name}')),
                                        );
                                      }
                                    },
                                    child: Center(
                                      child: Text(
                                        moduleName,
                                        style: TextStyle(
                                          color: Color(0xFF0070C0),
                                          fontSize: baseSize * (isTablet(context) ? 0.045 : 0.055),
                                          fontFamilyFallback: [
                                            'NotoSans',
                                            'NotoSerif',
                                            'Roboto',
                                            'sans-serif',
                                          ],
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                                const Divider(
                                  color: Colors.grey,
                                  height: 1,
                                ),
                              ],
                            );
                          }
                        },
                      );
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else {
                      return const CircularProgressIndicator();
                    }
                  },
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    //height: 150,
                      height: screenHeight * 0.2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.0, 1.0],
                          colors: [
                            // Colors.transparent,
                            // Color(0xFFFFF0DC),
                            //Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
                            Color(0xFFFED09A).withOpacity(0.0),
                            Color(0xFFFED09A),
                          ],
                        ),
                      )
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight, baseSize) {
    return Column(
      children: [
        Container(
          child: Column(
            //mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Search by ",
                    style: TextStyle(
                      fontSize: screenHeight * (isTablet(context) ? 0.08 : 0.08),
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0070C0),
                    ),
                  ),
                  Text(
                    "Alphabet: ",
                    style: TextStyle(
                      fontSize: screenHeight * (isTablet(context) ? 0.08 : 0.08),
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0070C0),
                    ),
                  ),
                  Text(
                    widget.letter,
                    style: TextStyle(
                      fontSize: screenHeight * (isTablet(context) ? 0.08 : 0.08),
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF548235),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Flexible(
          //flex: 5,
          child: Stack(
            children: [
              Container(
                //height: screenHeight * (isTablet(context) ? 0.63 : 0.62),
                width: baseSize * (isTablet(context) ? 0.8 : 1.1),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                ),
                child: FutureBuilder<List<Modules>>(
                  future: futureModules,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return ListView.builder(
                        itemCount: moduleData.length + 1,
                        // Increase the item count by 1 to account for the SizedBox as the last item
                        itemBuilder: (context, index) {
                          if (index == moduleData.length) {
                            // This is the last item (the SizedBox or Container)
                            return SizedBox(
                              height: screenHeight * 0.21,
                            );
                          }
                          final module = moduleData[index];
                          final moduleName = module.name ?? "Unknown Module";
                          debugPrint("Module Name: ${moduleName}");
                          final downloadLink = module.downloadLink ??
                              "No Link available";
                          final moduleDescription = module.description ??
                              "No Description available";

                          if (module.redirectedModule != null) {
                            return Column(
                              children: [
                                Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        vertical: screenHeight * (isTablet(context) ? 0.01 : 0.01),
                                        horizontal: baseSize * (isTablet(context) ? 0.01 : 0.01)
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          "$moduleName see",
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: screenHeight * (isTablet(context) ? 0.04 : 0.05),
                                            fontFamilyFallback: [
                                              'NotoSans',
                                              'NotoSerif',
                                              'Roboto',
                                              'sans-serif',
                                            ],
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        GestureDetector(
                                          onTap: () async {
                                            if (module.redirectedModule!.downloadLink != null &&
                                                module.redirectedModule!.downloadLink!.isNotEmpty) {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => ModuleInfo(
                                                    moduleId: module.redirectedModule!.id!,
                                                    moduleName: module.redirectedModule!.name!,
                                                    moduleDescription: module.redirectedModule!.description ?? "No Description available",
                                                    downloadLink: module.redirectedModule!.downloadLink!,
                                                  ),
                                                ),
                                              );
                                            } else {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('No download link found for ${module.redirectedModule!.name}')),
                                              );
                                            }
                                          },
                                          child: Text(
                                            module.redirectedModule!.name!,
                                            style: TextStyle(
                                              color: Color(0xFF0070C0), // Redirected module name in blue
                                              fontSize: screenHeight * (isTablet(context) ? 0.045 : 0.055),
                                              fontFamilyFallback: [
                                                'NotoSans',
                                                'NotoSerif',
                                                'Roboto',
                                                'sans-serif',
                                              ],
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const Divider(
                                  color: Colors.grey,
                                  height: 1,
                                ),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                      vertical: screenHeight * (isTablet(context) ? 0.01 : 0.01),
                                      horizontal: screenWidth * (isTablet(context) ? 0.01 : 0.01)
                                  ),
                                  child: InkWell(
                                    onTap: () async {
                                      if (module.downloadLink != null && module.downloadLink!.isNotEmpty) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ModuleInfo(
                                              moduleId: module.id!,
                                              moduleName: moduleName,
                                              moduleDescription: moduleDescription,
                                              downloadLink: downloadLink,
                                            ),
                                          ),
                                        );
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('No download link found for ${module.name}')),
                                        );
                                      }
                                    },
                                    child: Center(
                                      child: Text(
                                        moduleName,
                                        style: TextStyle(
                                          color: Color(0xFF0070C0),
                                          fontSize: screenHeight * (isTablet(context) ? 0.045 : 0.055),
                                          fontFamilyFallback: [
                                            'NotoSans',
                                            'NotoSerif',
                                            'Roboto',
                                            'sans-serif',
                                          ],
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                                const Divider(
                                  color: Colors.grey,
                                  height: 1,
                                ),
                              ],
                            );
                          }
                        },
                      );
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else {
                      return const CircularProgressIndicator();
                    }
                  },
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    //height: 150,
                      height: screenHeight * 0.2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.0, 1.0],
                          colors: [
                            // Colors.transparent,
                            // Color(0xFFFFF0DC),
                            //Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
                            Color(0xFFFED09A).withOpacity(0.0),
                            Color(0xFFFED09A),
                          ],
                        ),
                      )
                  ),
                ),
              ),
            ],
          ),
        ),
        // Flexible(
        //     flex: 1,
        //     child: SizedBox(
        //         height: baseSize * (isTablet(context) ? .17 : 0.2)
        //     )
        // ),
      ],
    );
  }
}
