import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../providers/auth_guard.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'cme/cme_tracker.dart';
import 'home_page.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
import 'module_info.dart';
import 'module_library.dart';

class ModuleByTopic extends StatefulWidget {
  final String subcategoryName;
  final int subcategoryId;

  const ModuleByTopic({Key? key, required this.subcategoryName, required this.subcategoryId}) : super(key: key);
  @override
  _ModuleByTopicState createState() => _ModuleByTopicState();
}

class Modules {
  int? id;
  String? description;
  List<String>? topics;
  String? name;
  String? topic;
  String? downloadLink;

  Modules({
    this.id,
    this.description,
    this.topics,
    this.name,
    this.topic,
    this.downloadLink
  });

  Modules.fromJson(Map<String, dynamic> json)
      : id = json['id'] as int?,
        description = json['description'] as String?,
        topics = json['topics'] != null ? List<String>.from(json['topics']) : null,
        name = json['name'] as String?,
        topic = json['topic'] as String?,
        downloadLink = json['downloadLink'] as String?;

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'topics': topics,
    'name': name,
    'topic': topic,
    'downloadLink': downloadLink,
  };
}

class _ModuleByTopicState extends State<ModuleByTopic> {
  late Future<List<Modules>> futureModules;
  late List<Modules> moduleData = [];

  Future<List<Modules>> fetchModules() async {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final apiEndpoint = '/modules?subcategoryId=${widget.subcategoryId}';

    try {
      final response = await http.get(Uri.parse('$apiBaseUrl$apiEndpoint'));

      debugPrint("Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check what data is being decoded
        debugPrint("Fetched Data: $data");

        // Ensure that the data is a List
        if (data is List) {
          List<Modules> allModules = data.map<Modules>((e) => Modules.fromJson(e)).toList();

          // Sort modules by name
          allModules.sort((a, b) => a.name!.compareTo(b.name!));

          setState(() {
            moduleData = allModules;  // Update the moduleData list here
          });

          return allModules;
        }
      } else {
        debugPrint("Failed to load modules, status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error fetching modules: $e");
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    futureModules = fetchModules();
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
            children: [
              Text(
                widget.subcategoryName,
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF548235),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Flexible(
          child: Stack(
            children: [
              Container(
                // height: screenHeight * 0.61,
                width: screenWidth * 1.0,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                ),
                child: FutureBuilder<List<Modules>>(
                  future: futureModules,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const CircularProgressIndicator();
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else if (moduleData.isEmpty) {  // Check if moduleData is empty
                      return const Text('No Modules Found');
                    } else {
                      return ListView.builder(
                        itemCount: moduleData.length + 1, // Increase the item count by 1 to account for the SizedBox as the last item
                        itemBuilder: (context, index) {
                          if (index == moduleData.length) {
                            // This is the last item (the SizedBox or Container)
                            return const SizedBox(
                              height: 160,
                            );
                          }
                          final module = moduleData[index];
                          final moduleName = module.name ?? "Unknown Module";
                          final downloadLink = module.downloadLink ?? "No Link available";
                          final moduleDescription = module.description ?? "No Description available";
                          return Column(
                            children: [
                              InkWell(
                                onTap: () async {
                                  if (downloadLink.isNotEmpty) {
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleInfo(
                                        moduleId: module.id!,
                                        moduleName: moduleName,
                                        moduleDescription: moduleDescription,
                                        downloadLink: downloadLink
                                    )));
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('No download link found for $moduleName')),
                                    );
                                  }
                                },
                                child: Center(
                                  child: ListTile(
                                    title: Text(
                                      moduleName,
                                      style: TextStyle(
                                        fontSize: baseSize * (isTablet(context) ? 0.054 : 0.054),
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF0070C0),
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
                        },
                      );
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
                      height: 150,
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
                            Color(0xFFFDD09A),
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
            children: [
              Text(
                widget.subcategoryName,
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF548235),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.015 : 0.015),
        ),
        Flexible(
          child: Stack(
            children: [
              Container(
                // height: baseSize * (isTablet(context) ? 0.68 : 0.68),
                width: baseSize * (isTablet(context) ? 1.25 : 1.0),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                ),
                child: FutureBuilder<List<Modules>>(
                  future: futureModules,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const CircularProgressIndicator();
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else if (moduleData.isEmpty) {  // Check if moduleData is empty
                      return const Text('No Modules Found');
                    } else {
                      return ListView.builder(
                        itemCount: moduleData.length + 1, // Increase the item count by 1 to account for the SizedBox as the last item
                        itemBuilder: (context, index) {
                          if (index == moduleData.length) {
                            // This is the last item (the SizedBox or Container)
                            return const SizedBox(
                              height: 160,
                            );
                          }
                          final module = moduleData[index];
                          final moduleName = module.name ?? "Unknown Module";
                          final downloadLink = module.downloadLink ?? "No Link available";
                          final moduleDescription = module.description ?? "No Description available";
                          return Column(
                            children: [
                              InkWell(
                                onTap: () async {
                                  if (downloadLink.isNotEmpty) {
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleInfo(
                                        moduleId: module.id!,
                                        moduleName: moduleName,
                                        moduleDescription: moduleDescription,
                                        downloadLink: downloadLink
                                    )));
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('No download link found for $moduleName')),
                                    );
                                  }
                                },
                                child: Center(
                                  child: ListTile(
                                    title: Text(
                                      moduleName,
                                      style: TextStyle(
                                        fontSize: baseSize * (isTablet(context) ? 0.054 : 0.054),
                                        fontFamilyFallback: [
                                          'NotoSans',
                                          'NotoSerif',
                                          'Roboto',
                                          'sans-serif'
                                        ],
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF0070C0),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                height: 1,
                                width: 800,
                                color: Colors.grey,
                              ),
                            ],
                          );
                        },
                      );
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
                      height: 150,
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
}