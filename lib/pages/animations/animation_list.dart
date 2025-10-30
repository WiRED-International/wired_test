import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:wired_test/pages/animations/animation_info.dart';
import '../../providers/auth_guard.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../cme/cme_tracker.dart';
import '../creditsTracker/credits_tracker.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AnimationList extends StatefulWidget {
  const AnimationList({super.key});

  @override
  State<AnimationList> createState() => _AnimationListState();
}

class Animation {
  int? id;
  String? name;
  String? description;
  String? downloadLink;

  Animation({
    this.id,
    this.name,
    this.description,
    this.downloadLink,
  });

  Animation.fromJson(Map<String, dynamic> json)
      : id = json['id'] as int?,
        name = json['name'] as String,
        description = json['description'] as String,
        downloadLink = json['downloadLink'] as String;


  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'downloadLink': downloadLink,
  };
}

class _AnimationListState extends State<AnimationList> {
  late Future<List<Animation>> futureAnimations;

  Future<List<Animation>> fetchAnimations() async {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final apiEndpoint = '/modules?type=animation';
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl$apiEndpoint'));

      debugPrint("Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        debugPrint("Fetched Data: $data");

        if (data is List) {
          print("Data is a List");
          List<Animation> animations = data.map<Animation>((e) =>
              Animation.fromJson(e)).toList();

          // Filter out animations with null or empty names
          animations =
              animations.where((a) => a.name != null && a.name!.isNotEmpty)
                  .toList();

          debugPrint("Parsed Animations Length: ${animations.length}");
          return animations;
        } else {
          debugPrint("Data is not a list");
        }
      } else {
        debugPrint(
            "Failed to load animations, status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error fetching animations: $e");
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    futureAnimations = fetchAnimations();
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
                                builder: (context) =>
                                    AuthGuard(
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
                                builder: (context) =>
                                isLoggedIn
                                    ? Menu()
                                    : GuestMenu(),
                              ),
                            );
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
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
                              AuthGuard(
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
                          builder: (context) =>
                          isLoggedIn
                              ? Menu()
                              : GuestMenu(),
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
        Container(
          child: Column(
            children: [
              Text(
                "Animations",
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF548235),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: baseSize * (isTablet(context) ? 0.02 : 0.02),),
        Expanded(
          child: FutureBuilder<List<Animation>>(
            future: futureAnimations,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No animations available'));
              } else {
                final animations = snapshot.data!;
                debugPrint("Number of Animations: ${animations.length}");
                return ListView.builder(
                  itemCount: animations.length,
                  itemBuilder: (context, index) {
                    final animation = animations[index];
                    final animationId = animation.id ?? 0;
                    final animationName = animation.name ?? "Unknown Animation";
                    final animationDescription = animation.description ?? "";
                    final downloadLink = animation.downloadLink ?? "";

                    return Column(
                      children: [
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AnimationInfo(
                                  animationId: animationId,
                                  animationName: animationName,
                                  animationDescription: animationDescription,
                                  downloadLink: downloadLink,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              animationName,
                              style: TextStyle(
                                fontSize: baseSize * (isTablet(context) ? 0.054 : 0.054),
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF0070C0),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        Container(
                          color: Colors.grey,
                          height: 1,
                          width: baseSize * (isTablet(context) ? 0.75 : 0.7),
                        ),
                      ],
                    );
                  },
                );
              }
            },
          ),
        ),
      ],
    );
  }
  Widget _buildLandscapeLayout(screenWidth, screenHeight, baseSize) {
    return Column(
      children: [
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.03 : 0.03),
        ),
        Container(
          child: Column(
            children: [
              Text(
                "Animations",
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF548235),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: baseSize * (isTablet(context) ? 0.02 : 0.02),),
        Expanded(
          child: FutureBuilder<List<Animation>>(
            future: futureAnimations,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No animations available'));
              } else {
                final animations = snapshot.data!;
                debugPrint("Number of Animations: ${animations.length}");
                return ListView.builder(
                  itemCount: animations.length,
                  itemBuilder: (context, index) {
                    final animation = animations[index];
                    final animationId = animation.id ?? 0;
                    final animationName = animation.name ?? "Unknown Animation";
                    final animationDescription = animation.description ?? "";
                    final downloadLink = animation.downloadLink ?? "";

                    return Column(
                      children: [
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AnimationInfo(
                                  animationId: animationId,
                                  animationName: animationName,
                                  animationDescription: animationDescription,
                                  downloadLink: downloadLink,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              animationName,
                              style: TextStyle(
                                fontSize: baseSize * (isTablet(context) ? 0.054 : 0.054),
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF0070C0),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        Container(
                          color: Colors.grey,
                          height: 1,
                          width: baseSize * (isTablet(context) ? 0.75 : 0.7),
                        ),
                      ],
                    );
                  },
                );
              }
            },
          ),
        ),
      ],
    );
  }
}