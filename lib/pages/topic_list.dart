import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wired_test/pages/module_by_topic.dart';
import 'package:wired_test/pages/policy.dart';
import 'package:wired_test/pages/topic_list.dart';

import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'home_page.dart';
import 'module_library.dart';

class TopicList extends StatefulWidget {
  final String category;
  final String topicName;

  const TopicList({Key? key, required this.category, required this.topicName}) : super(key: key);
  @override
  _TopicListState createState() => _TopicListState();
}

class Topic {
  String? name;
  String? category;
  String? id;

  Topic({
    this.name,
    this.category,
    this.id,
  });

  Topic.fromJson(Map<String, dynamic> json)
      : name = json['name'] as String?,
        category = json['category'] as String?,
        id = json['id'] as String;

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'id': id,
  };
}

class _TopicListState extends State<TopicList> {
  late Future<List<Topic>> futureTopics;
  List<String> topicNames = [];

  Future<List<Topic>> fetchTopics() async {
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
          List<Topic> topics = data.map<Topic>((e) => Topic.fromJson(e)).toList();

          // Filter topics based on the widget.category
          topics = topics.where((topic) => topic.category == widget.category).toList();

          // Sort the topics by name
          topics.sort((a, b) => a.name!.compareTo(b.name!));

          debugPrint("Parsed Topics Length: ${topics.length}");
          return topics;
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
    futureTopics = fetchTopics();
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
                              MaterialPageRoute(
                                  builder: (context) => MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => ModuleLibrary()),
                            );
                          },
                          onHelpTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const Policy()),
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
                        MaterialPageRoute(
                            builder: (context) => ModuleLibrary()),
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
        Container(
          child: Column(
            children: [
              Text(
                widget.category,
                style: TextStyle(
                  fontSize: screenWidth * 0.085,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF548235),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Stack(
          children: [
            Container(
              height: screenHeight * 0.61,
              width: screenWidth * 1.0,
              decoration: BoxDecoration(
                color: Colors.transparent,
              ),
              child: FutureBuilder<List<Topic>>(
                future: futureTopics,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  } else if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Text('No topics available');
                  } else {
                    final topics = snapshot.data!;
                    debugPrint("Number of Topics: ${topics.length}");
                    return ListView.builder(
                      itemCount: topics.length + 1,
                      itemBuilder: (context, index) {
                        if (index == topics.length) {
                          return const SizedBox(
                            height: 160,
                          );
                        }
                        final topic = topics[index];
                        final topicName = topic.name ?? "Unknown Module";
                        final category = topic.category ?? "Category not found";
                        final id = topic.id ?? "Unknown ID";
                        return Column(
                          children: [
                            InkWell(
                              onTap: () async {
                                //print("Downloading ${moduleData[index].downloadLink}");
                                if (category.isNotEmpty) {
                                  // String fileName = "$moduleName.zip";
                                  // await downloadModule(downloadLink, fileName);
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleByTopic(topicName: topicName, id: id)));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('No category found for ${topics[index].category}')),
                                  );
                                }
                              },
                              child: Center(
                                child: ListTile(
                                  title: Text(
                                    topicName,
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
        Stack(
          children: [
            Container(
              height: baseSize * (isTablet(context) ? 0.68 : 0.68),
              width: baseSize * (isTablet(context) ? 1.25 : 1.0),
              decoration: BoxDecoration(
                color: Colors.transparent,
              ),
              child: FutureBuilder<List<Topic>>(
                future: futureTopics,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  } else if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Text('No topics available');
                  } else {
                    final topics = snapshot.data!;
                    debugPrint("Number of Topics: ${topics.length}");
                    return ListView.builder(
                      itemCount: topics.length + 1,
                      itemBuilder: (context, index) {
                        if (index == topics.length) {
                          return const SizedBox(
                            height: 160,
                          );
                        }
                        final topic = topics[index];
                        final topicName = topic.name ?? "Unknown Module";
                        final category = topic.category ?? "Category not found";
                        final id = topic.id ?? "Unknown ID";
                        return Column(
                          children: [
                            InkWell(
                              onTap: () async {
                                //print("Downloading ${moduleData[index].downloadLink}");
                                if (category.isNotEmpty) {
                                  // String fileName = "$moduleName.zip";
                                  // await downloadModule(downloadLink, fileName);
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleByTopic(topicName: topicName, id: id)));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('No category found for ${topics[index].category}')),
                                  );
                                }
                              },
                              child: Center(
                                child: ListTile(
                                  title: Text(
                                    topicName,
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