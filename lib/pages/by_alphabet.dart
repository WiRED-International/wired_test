import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wired_test/pages/policy.dart';

import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import 'home_page.dart';
import 'module_by_alphabet.dart';
import 'module_library.dart';

class ByAlphabet extends StatefulWidget {
  @override
  _ByAlphabetState createState() => _ByAlphabetState();
}

class Album {
  final String description;
  final String id;
  final String name;

  Album({
    required this.description,
    required this.id,
    required this.name
  });

  Album.fromJson(Map<String, dynamic> json)
      : description = json['description'] as String,
        id = json['id'] as String,
        name = json['name'] as String;

    Map<String, dynamic> toJson() => {
      'description': description,
      'id': id,
      'name': name,
    };
}

class _ByAlphabetState extends State<ByAlphabet> {
  late Future<List<Album>> futureAlbums;
  late List<Album> albums = [];

  Future<List<Album>> fetchAlbums() async {
    try {
      final response = await http.get(Uri.parse(
          'https://obrpqbo4eb.execute-api.us-west-2.amazonaws.com/api/letters'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        albums = data.map<Album>((e) => Album.fromJson(e)).toList();
        albums.sort((a, b) => a.name.compareTo(b.name));
        return albums;
      } else {
        debugPrint("Failed to load albums");
      }
      return albums;
    } catch (e) {
      debugPrint("$e");
    }
    return albums;
  }

  @override
  void initState() {
    super.initState();
    futureAlbums = fetchAlbums();
  }

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    final appBarHeight = screenHeight * 0.055;
    final bottomNavBarHeight = screenHeight * 0.09;
    return Scaffold(
      body: Stack(
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
            child: SafeArea(
              child: Center(
                child: Column(
                  children: [
                    CustomAppBar(
                      onBackPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(height: 15),
                    Text(
                      "Search by Alphabet",
                      style: TextStyle(
                        fontSize: screenWidth * 0.08,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF0070C0),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.02,
                        ),
                        child: FutureBuilder<List<Album>>(
                          future: futureAlbums,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            } else if (snapshot.hasError) {
                              return Center(child: Text('Error: ${snapshot.error}'));
                            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const Center(child: Text('No Albums Found'));
                            } else {
                              albums = snapshot.data!;
                              // final screenWidth = MediaQuery.of(context).size.width;
                              final crossAxisCount = (screenWidth / 100).floor();
                              final availableHeight = screenHeight - (appBarHeight + bottomNavBarHeight + 285); // Adjust based on AppBar and BottomNavigationBar
                              final itemHeight = availableHeight / (albums.length / crossAxisCount).ceil();
                              final childAspectRatio = screenWidth / (itemHeight * 4.0);

                              return GridView.builder(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisSpacing: screenWidth * 0.03,
                                  crossAxisSpacing: screenWidth * 0.03,
                                  childAspectRatio: childAspectRatio,
                                ),
                                itemCount: albums.length,
                                itemBuilder: (context, index) {
                                  return InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ModuleByAlphabet(
                                            letter: albums[index].name,
                                            letterId: albums[index].id,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0xFF548235),
                                            Color(0xFF6BA644),
                                            Color(0xFF93C573),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        albums[index].name,
                                        style: TextStyle(
                                            color: Colors.white,
                                            //fontSize: 36,
                                            fontSize: screenWidth * 0.09,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            }
                          },
                        ),
                      ),
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
                Navigator.push(context, MaterialPageRoute(builder: (context) => MyHomePage()));
              },
              onLibraryTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleLibrary()));
              },
              onHelpTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const Policy()));
              },
            ),
          ),
        ],
      ),
    );
  }
}