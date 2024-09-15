import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wired_test/pages/topic_list.dart';

import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import 'home_page.dart';
import 'module_by_alphabet.dart';
import 'module_info.dart';
import 'module_library.dart';

class ModuleByTopic extends StatefulWidget {
  final String topicName;
  final String id;

  const ModuleByTopic({Key? key, required this.topicName, required this.id}) : super(key: key);
  @override
  _ModuleByTopicState createState() => _ModuleByTopicState();
}

class Modules {
  String? description;
  List<String>? topics;
  String? name;
  String? topic;
  String? downloadLink;

  Modules({
    this.description,
    this.topics,
    this.name,
    this.topic,
    this.downloadLink
  });

  Modules.fromJson(Map<String, dynamic> json)
      : description = json['description'] as String?,
        topics = json['topics'] != null ? List<String>.from(json['topics']) : null,
        name = json['name'] as String?,
        topic = json['topic'] as String?,
        downloadLink = json['downloadLink'] as String?;

  Map<String, dynamic> toJson() => {
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
    try {
      final response = await http.get(Uri.parse(
          'https://obrpqbo4eb.execute-api.us-west-2.amazonaws.com/api/modules'));

      debugPrint("Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check what data is being decoded
        debugPrint("Fetched Data: $data");

        // Ensure that the data is a List
        if (data is List) {
          print("Data is a List");
          List<Modules> allModules = data.map<Modules>((e) => Modules.fromJson(e)).toList();

          // Filter out modules with null or empty names
          //allModules = allModules.where((m) => m.name != null && m.name!.isNotEmpty).toList();

          debugPrint("Filtering by topicId: ${widget.id}");

          // Filter modules by the id
          allModules = allModules.where((module) => module.topics != null && module.topics!.contains(widget.id)).toList();

          debugPrint("Modules after filtering by topicId: ${allModules.length}");

          // change to lower case and Sort modules by name
          allModules.sort((a, b) => a.name!.compareTo(b.name!));

          debugPrint("Parsed Modules Length: ${allModules.length}");

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
    return Scaffold(
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
              child: Center(
                child: Column(
                  children: [
                    //Imported from utils/custom_app_bar.dart
                    CustomAppBar(
                      onBackPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                    Container(
                      child: Column(
                        children: [
                          Text(
                            widget.topicName,
                            style: const TextStyle(
                              fontSize: 36,
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
                          // height: 650,
                          // width: 400,
                          height: screenHeight * 0.61,
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
                                              Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleInfo(moduleName: moduleName, moduleDescription: moduleDescription, downloadLink: downloadLink)));
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
                                                style: const TextStyle(
                                                  fontSize: 32,
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
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CustomBottomNavBar(
              onHomeTap: () {
                print("Home");
                Navigator.push(context, MaterialPageRoute(builder: (context) => MyHomePage(title: 'WiRED International')));
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
        ],
      ),
    );
  }
}