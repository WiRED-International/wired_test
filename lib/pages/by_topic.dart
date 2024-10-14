import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wired_test/pages/policy.dart';
import 'package:wired_test/pages/topic_list.dart';

import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'home_page.dart';
import 'module_by_alphabet.dart';
import 'module_info.dart';
import 'module_library.dart';

class ByTopic extends StatefulWidget {
  @override
  _ByTopicState createState() => _ByTopicState();
}

class Category {
  String? name;
  String? category;
  String? id;

  Category({
    this.name,
    this.category,
    this.id,
  });

  Category.fromJson(Map<String, dynamic> json)
      : name = json['name'] as String?,
        category = json['category'] as String?,
        id = json['id'] as String;

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'id': id,
  };

  // Override == operator to compare Category objects by their category field
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Category && other.category == category;
  }

  // Override hashCode to ensure it is consistent with the == operator
  @override
  int get hashCode => category?.hashCode ?? 0;
}

class _ByTopicState extends State<ByTopic> {
  late Future<List<Category>> futureCategories;

  Future<List<Category>> fetchCategories() async {
    try {
      final response = await http.get(Uri.parse(
          'https://obrpqbo4eb.execute-api.us-west-2.amazonaws.com/api/topics'));

      debugPrint("Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check what data is being decoded
        debugPrint("Fetched Data: $data");

        // Ensure that the data is a List
        if (data is List) {
          print("Data is a List");
          List<Category> categories = data.map<Category>((e) =>
              Category.fromJson(e)).toList();

          // Filter out categories with null or empty names
          categories = categories.where((c) => c.category != null &&
              c.category!.isNotEmpty).toList();

          // Sort the list by category name
          categories.sort((a, b) =>
              a.category!.toLowerCase().compareTo(b.category!.toLowerCase()));

          // Remove duplicates by converting to a Set and back to a List
          categories = categories.toSet().toList();

          debugPrint("Parsed Categories Length: ${categories.length}");
          return categories;
        } else {
          debugPrint("Data is not a list");
        }
      } else {
        debugPrint(
            "Failed to load categories, status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error fetching categories: $e");
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    futureCategories = fetchCategories();
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
                              MaterialPageRoute(builder: (context) => MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ModuleLibrary()),
                            );
                          },
                          onHelpTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const Policy()),
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
                            builder: (context) => MyHomePage()),
                      );
                    },
                    onLibraryTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ModuleLibrary()),
                      );
                    },
                    onHelpTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const Policy()),
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
    return Column(
      children: [
        SizedBox(height: 10),
        Container(
          child: Column(
            children: [
              Text(
                "Search by Topic",
                style: TextStyle(
                  fontSize: screenWidth * 0.085,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF548235),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // List of topics container
        Stack(
          children: [
            Container(
              height: screenHeight * 0.65,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.transparent,
              ),
              child: FutureBuilder<List<Category>>(
                future: futureCategories,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  } else if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Text('No categories available');
                  } else {
                    final categories = snapshot.data!;
                    debugPrint("Number of Categories: ${categories.length}");
                    return ListView.builder(
                      itemCount: categories.length + 1,
                      itemBuilder: (context, index) {
                        if (index == categories.length) {
                          return const SizedBox(
                            height: 160,
                          );
                        }
                        final topic = categories[index];
                        final topicName = topic.name ?? "Unknown Module";
                        final category = topic.category ?? "Category not found";
                        return Column(
                          children: [
                            InkWell(
                              onTap: () async {
                                //print("Downloading ${moduleData[index].downloadLink}");
                                if (category.isNotEmpty) {
                                  // String fileName = "$moduleName.zip";
                                  // await downloadModule(downloadLink, fileName);
                                  Navigator.push(context, MaterialPageRoute(
                                      builder: (context) => TopicList(
                                          category: category,
                                          topicName: topicName)));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(
                                        'No category found for ${categories[index]
                                            .category}')),
                                  );
                                }
                              },
                              child: Center(
                                child: ListTile(
                                  title: Padding(
                                    padding: const EdgeInsets.only(
                                        top: 10, bottom: 10),
                                    child: Text(
                                      category,
                                      style: TextStyle(
                                        fontSize: screenWidth * 0.074,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF0070C0),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
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
                          Color(0xFFFED09A),
                        ],
                      ),
                    )
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight) {
    var baseSize = MediaQuery.of(context).size.shortestSide;
    return Column(
      children: [
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.03 : 0.03),
        ),
        Container(
          child: Column(
            children: [
              Text(
                "Search by Topic",
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.07 : 0.07),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF548235),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.015 : 0.015),
        ),
        // List of topics container
        Stack(
          children: [
            Container(
              height: baseSize * (isTablet(context) ? 0.68 : 0.68),
              width: baseSize * (isTablet(context) ? 1.25 : 1.0),
              decoration: BoxDecoration(
                color: Colors.transparent,
              ),
              child: FutureBuilder<List<Category>>(
                future: futureCategories,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  } else if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Text('No categories available');
                  } else {
                    final categories = snapshot.data!;
                    debugPrint("Number of Categories: ${categories.length}");
                    return ListView.builder(
                      itemCount: categories.length + 1,
                      itemBuilder: (context, index) {
                        if (index == categories.length) {
                          return const SizedBox(
                            height: 160,
                          );
                        }
                        final topic = categories[index];
                        final topicName = topic.name ?? "Unknown Module";
                        final category = topic.category ?? "Category not found";
                        return Column(
                          children: [
                            InkWell(
                              onTap: () async {
                                //print("Downloading ${moduleData[index].downloadLink}");
                                if (category.isNotEmpty) {
                                  // String fileName = "$moduleName.zip";
                                  // await downloadModule(downloadLink, fileName);
                                  Navigator.push(context, MaterialPageRoute(
                                      builder: (context) => TopicList(
                                          category: category,
                                          topicName: topicName)));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(
                                        'No category found for ${categories[index]
                                            .category}')),
                                  );
                                }
                              },
                              child: Center(
                                child: ListTile(
                                  title: Padding(
                                    padding: const EdgeInsets.only(
                                        top: 10, bottom: 10),
                                    child: Text(
                                      category,
                                      style: TextStyle(
                                        fontSize: baseSize * (isTablet(context) ? 0.0667 : 0.0667),
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
      ],
    );
  }
}


