import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:wired_test/pages/byTopic/module_by_topic.dart';
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

class TopicList extends StatefulWidget {
  final String category;
  final int categoryId;

  const TopicList({super.key, required this.category, required this.categoryId});
  @override
  _TopicListState createState() => _TopicListState();
}

class SubCategory {
  String? name;
  int? categoryId;
  int? subcategoryId;

  SubCategory({
    this.name,
    this.categoryId,
    this.subcategoryId,
  });

  SubCategory.fromJson(Map<String, dynamic> json) {
    name = json['name'] as String?;
    categoryId = json['category_id'] as int?; // Convert category_id to string if it's an int
    subcategoryId = json['id'] as int; // Convert id to string if necessary
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'categoryId': categoryId,
    'subcategoryId': subcategoryId,
  };
}

class _TopicListState extends State<TopicList> {
  late Future<List<SubCategory>> futureSubcategories;
  List<String> topicNames = [];

  Future<List<SubCategory>> fetchSubcategories() async {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final apiEndpoint = '/subCategories';
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl$apiEndpoint'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Ensure that the data is a List
        if (data is List) {
          List<SubCategory> subCategories = data.map<SubCategory>((e) => SubCategory.fromJson(e)).toList();

          List<SubCategory> filteredSubCategories = subCategories
              .where((subCategory) => subCategory.categoryId == widget.categoryId)
              .toList();

          // Sort the topics by name
          filteredSubCategories.sort((a, b) => a.name!.compareTo(b.name!));

          // This is a temporary fix for the issue where some subcategories are empty. Remove each subcategory name from the list if there is a module associated with it.
          List<String> namesToRemove = ['Mouth and Teeth', 'Population Groups', 'Genetics/Birth Defects', 'Injuries and Wounds', 'Substance Abuse Problems', 'Disasters', 'Fitness and Exercise', 'Health System', 'Personal Health Issues', 'Safety Issues', 'Kenya', 'Mandarin'];
          filteredSubCategories.removeWhere((subCategory) => namesToRemove.contains(subCategory.name!));

          return filteredSubCategories;
        } else {
          debugPrint("Data is not a list");
        }
      } else {
        debugPrint("Failed to load topics, status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error fetching topics: $e");
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    futureSubcategories = fetchSubcategories();
  }

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
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
                              ? _buildLandscapeLayout(screenWidth, screenHeight)
                              : _buildPortraitLayout(screenWidth, screenHeight),
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

  Widget _buildPortraitLayout(screenWidth, screenHeight) {
    var baseSize = MediaQuery.of(context).size.shortestSide;
    return Column(
      children: [
        Container(
          child: Column(
            children: [
              Text(
                widget.category,
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
          //flex: 3,
          child: Stack(
            children: [
              Container(
                //height: screenHeight * 0.61,
                //height: baseSize * (isTablet(context) ? 0.08 : 1.5),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                ),
                child: FutureBuilder<List<SubCategory>>(
                  future: futureSubcategories,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const CircularProgressIndicator();
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Text('No topics available');
                    } else {
                      final List<SubCategory> subcategories = snapshot.data!;

                      return ListView.builder(
                        itemCount: subcategories.length + 1,
                        itemBuilder: (context, index) {
                          if (index == subcategories.length) {
                            return const SizedBox(
                              height: 160,
                            );
                          }
                          final subCategory = subcategories[index];
                          final subcategoryName = subCategory.name ?? "Unknown SubCategory";
                          final subcategoryId = subCategory.subcategoryId ?? 0;
                          return Column(
                            children: [
                              InkWell(
                                onTap: () async {
                                  if (subcategoryName.isNotEmpty) {
                                    // String fileName = "$moduleName.zip";
                                    // await downloadModule(downloadLink, fileName);
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleByTopic(subcategoryName: subcategoryName, subcategoryId: subcategoryId)));
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('No category found for ${subCategory.categoryId}')),
                                    );
                                  }
                                },
                                child: Center(
                                  child: ListTile(
                                    title: Text(
                                      subcategoryName,
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
                              Container(
                                color: Colors.grey,
                                height: 1,
                                width: baseSize * (isTablet(context) ? 0.75 : 0.85),
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
                            Color(0xFFFED09A).withValues(alpha: 0.0),
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
        //SizedBox(height: baseSize * (isTablet(context) ? .17 : 0.05)),
      ],
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight) {
    var baseSize = MediaQuery.of(context).size.shortestSide;
    return Column(
      children: [
        Container(
          child: Column(
            children: [
              Text(
                widget.category,
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.07 : 0.07),
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
                //height: baseSize * (isTablet(context) ? 0.68 : 0.68),
                //width: baseSize * (isTablet(context) ? 1.25 : 1.0),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                ),
                child: FutureBuilder<List<SubCategory>>(
                  future: futureSubcategories,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const CircularProgressIndicator();
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Text('No topics available');
                    } else {
                      final List<SubCategory> subcategories = snapshot.data!;

                      return ListView.builder(
                        itemCount: subcategories.length + 1,
                        itemBuilder: (context, index) {
                          if (index == subcategories.length) {
                            return const SizedBox(
                              height: 160,
                            );
                          }
                          final subCategory = subcategories[index];
                          final subcategoryName = subCategory.name ?? "Unknown SubCategory";
                          final subcategoryId = subCategory.subcategoryId ?? 0;
                          return Column(
                            children: [
                              InkWell(
                                onTap: () async {

                                  if (subcategoryName.isNotEmpty) {
                                    // String fileName = "$moduleName.zip";
                                    // await downloadModule(downloadLink, fileName);
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleByTopic(subcategoryName: subcategoryName, subcategoryId: subcategoryId)));
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('No category found for ${subCategory.categoryId}')),
                                    );
                                  }
                                },
                                child: Center(
                                  child: ListTile(
                                    title: Text(
                                      subcategoryName,
                                      style: TextStyle(
                                        fontSize: baseSize * (isTablet(context) ? 0.05 : 0.05),
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
                                width: 500,
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
                            Color(0xFFFED09A).withValues(alpha: 0.0),
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