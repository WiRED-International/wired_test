import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wired_test/pages/policy.dart';

import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'home_page.dart';
import 'module_by_alphabet.dart';
import 'module_library.dart';

class ByAlphabet extends StatefulWidget {
  @override
  _ByAlphabetState createState() => _ByAlphabetState();
}

class Album {
  final String name;

  Album({
    required this.name
  });

  Album.fromJson(Map<String, dynamic> json)
      :name = json['name'] as String;

  Map<String, dynamic> toJson() => {
    'name': name,
  };
}

class _ByAlphabetState extends State<ByAlphabet> {
  late Future<List<Album>> futureAlbums;
  late List<Album> albums = [];

  Future<List<Album>> fetchAlbums() async {
    // Hardcoded list of albums from A to W and X-Y-Z
    albums = [
      Album(name: 'A'),
      Album(name: 'B'),
      Album(name: 'C'),
      Album(name: 'D'),
      Album(name: 'E'),
      Album(name: 'F'),
      Album(name: 'G'),
      Album(name: 'H'),
      Album(name: 'I'),
      Album(name: 'J'),
      Album(name: 'K'),
      Album(name: 'L'),
      Album(name: 'M'),
      Album(name: 'N'),
      Album(name: 'O'),
      Album(name: 'P'),
      Album(name: 'Q'),
      Album(name: 'R'),
      Album(name: 'S'),
      Album(name: 'T'),
      Album(name: 'U'),
      Album(name: 'V'),
      Album(name: 'W'),
      Album(name: 'X-Y-Z'),
    ];

    // Sorting alphabetically if needed
    albums.sort((a, b) => a.name.compareTo(b.name));

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
    var baseSize = MediaQuery.of(context).size.shortestSide;
    final appBarHeight = screenHeight * 0.055;
    final bottomNavBarHeight = screenHeight * 0.09;
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

  Widget _buildPortraitLayout(screenWidth, screenHeight, baseSize) {
    final appBarHeight = baseSize * (isTablet(context) ? 0.001 : 0.055);
    final bottomNavBarHeight = baseSize * (isTablet(context) ? 0.001 : 0.09);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        const SizedBox(height: 15),
        Text(
          "Search by Alphabet",
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
            fontWeight: FontWeight.w500,
            color: Color(0xFF0070C0),
          ),
        ),
        const SizedBox(height: 30),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: baseSize * (isTablet(context) ? 0.02 : 0.02),
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
                  final crossAxisCount = (isTablet(context) ? 4 : 4).floor();
                  final availableHeight = baseSize - (appBarHeight + bottomNavBarHeight + (baseSize * (isTablet(context) ? 0.4 : 0.1))); // Adjust based on AppBar and BottomNavigationBar
                  final itemHeight = availableHeight / (albums.length / crossAxisCount).ceil();
                  //final childAspectRatio = baseSize / (itemHeight * (isTablet(context) ? 7.0 : 4.0));
                  final childAspectRatio = baseSize / (itemHeight * (isTablet(context) ? 7 : 5.5));

                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: baseSize * (isTablet(context) ? 0.02 : 0.02),
                      crossAxisSpacing: baseSize * (isTablet(context) ? 0.02 : 0.02),
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
                              fontSize: baseSize * (isTablet(context) ? 0.07 : 0.075),
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
        //SizedBox(height: baseSize * (isTablet(context) ? .17 : 0.25)),
      ],
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight, baseSize) {
    final appBarHeight = baseSize * (isTablet(context) ? 0.001 : 0.1);
    final bottomNavBarHeight = baseSize * (isTablet(context) ? 0.001 : 0.1);
    return Column(
      children: [
        const SizedBox(height: 15),
        Text(
          "Search by Alphabet",
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
            fontWeight: FontWeight.w500,
            color: Color(0xFF0070C0),
          ),
        ),
        SizedBox(height: baseSize * (isTablet(context) ? 0.03 : 0.03),),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: baseSize * (isTablet(context) ? 0.1 : 0.1),
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

                  final crossAxisCount = (isTablet(context) ? 6 : 6).floor();
                  final availableHeight = baseSize - (appBarHeight + bottomNavBarHeight + (baseSize * (isTablet(context) ? 0.4 : 0.2)));  // Adjust based on AppBar and BottomNavigationBar
                  final itemHeight = availableHeight / (albums.length / crossAxisCount).ceil();
                  final childAspectRatio = screenWidth / (itemHeight * (isTablet(context) ? 7.0 : 7.0));

                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: baseSize * (isTablet(context) ? 0.02 : 0.02),
                      crossAxisSpacing: baseSize * (isTablet(context) ? 0.02 : 0.02),
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
                              fontSize: baseSize * (isTablet(context) ? 0.07 : 0.07),
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
    );
  }
}