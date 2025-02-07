import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wired_test/pages/policy.dart';

import '../providers/auth_guard.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'cme/cme_info.dart';
import 'cme/cme_tracker.dart';
import 'home_page.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
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
    // Hardcoded list of albums from A to W and X-Y-Z. Some letters have been removed because we don't have any modules for them at the moment.
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
  final Map<String, double> _buttonScales = {};
  final Map<String, List<Color>> _buttonColors = {};

  void _onTapDown(String label) {
    setState(() {
      _buttonScales.putIfAbsent(label, () => 1.0);
      _buttonColors.putIfAbsent(label, () => [
        const Color(0xFF548235),
        const Color(0xFF6BA644),
        const Color(0xFF93C573),
      ]);

      _buttonScales[label] = 0.95; // Shrink effect

      // Use new colors on tap down
      _buttonColors[label] = [
        Colors.green[900]!, // Change to a darker shade
        Colors.green[700]!,
        Colors.green[500]!,
      ];
    });
  }


  void _onTapUp(String label, VoidCallback onTap) {
    Future.delayed(const Duration(milliseconds: 100), () {
      setState(() {
        _buttonScales.putIfAbsent(label, () => 1.0);
        _buttonColors.putIfAbsent(label, () => [
          const Color(0xFF548235),
          const Color(0xFF6BA644),
          const Color(0xFF93C573),
        ]);

        _buttonScales[label] = 1.0; // Restore size

        // Restore original color
        _buttonColors[label] = [
          const Color(0xFF548235),
          const Color(0xFF6BA644),
          const Color(0xFF93C573),
        ];
      });
      onTap(); // Execute navigation
    });
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
    double scalingFactor = getScalingFactor(context);
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
                              ? _buildLandscapeLayout(screenWidth, screenHeight, scalingFactor)
                              : _buildPortraitLayout(screenWidth, screenHeight, scalingFactor),
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

  Widget _buildPortraitLayout(screenWidth, screenHeight, scalingFactor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Text(
          "Search by Alphabet",
          style: TextStyle(
            fontSize: scalingFactor * (isTablet(context) ? 30 : 30),
            fontWeight: FontWeight.w500,
            color: const Color(0xFF0070C0),
          ),
        ),
        SizedBox(height: scalingFactor * (isTablet(context) ? 20 : 20)),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: scalingFactor * (isTablet(context) ? 10 : 10),
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

                  /// Maintain dynamic grid sizing based on screen type
                  final crossAxisCount = isTablet(context) ? 4 : 4;
                  final buttonHeight = scalingFactor * (isTablet(context) ? 60 : 50); // Adjusted for tablets
                  final childAspectRatio = isTablet(context) ? 1.6 : 1.5; // Adjusted for tablet scaling

                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: scalingFactor * (isTablet(context) ? 9 : 8),
                      crossAxisSpacing: scalingFactor * (isTablet(context) ? 9 : 8),
                      childAspectRatio: childAspectRatio,
                    ),
                    itemCount: albums.length,
                    itemBuilder: (context, index) {
                      return _buildAnimatedGridButton(
                        label: albums[index].name,
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
                        scalingFactor: scalingFactor,
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

  Widget _buildAnimatedGridButton({
    required String label,
    required VoidCallback onTap,
    required double scalingFactor,
  }) {
    return GestureDetector(
      onTapDown: (_) => _onTapDown(label),
      onTapUp: (_) => _onTapUp(label, onTap),
      onTapCancel: () {
        setState(() {
          _buttonScales[label] = 1.0;
          _buttonColors[label] = [
            const Color(0xFF548235),
            const Color(0xFF6BA644),
            const Color(0xFF93C573),
          ];
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        transform: Matrix4.diagonal3Values(
          _buttonScales[label] ?? 1.0,
          _buttonScales[label] ?? 1.0,
          1.0,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _buttonColors[label] ?? [
              const Color(0xFF548235),
              const Color(0xFF6BA644),
              const Color(0xFF93C573),
            ],
          ),
          borderRadius: BorderRadius.circular(isTablet(context) ? 12 : 8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(1, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: scalingFactor * (isTablet(context) ? 24 : 24),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }



  Widget _buildLandscapeLayout(screenWidth, screenHeight, scalingFactor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Text(
          "Search by Alphabet",
          style: TextStyle(
            fontSize: scalingFactor * (isTablet(context) ? 24 : 24),
            fontWeight: FontWeight.w500,
            color: const Color(0xFF0070C0),
          ),
        ),
        SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: scalingFactor * (isTablet(context) ? 15 : 10),
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

                  /// Maintain dynamic grid sizing based on screen type
                  final crossAxisCount = isTablet(context) ? 6 : 5;
                  final buttonHeight = scalingFactor * (isTablet(context) ? 55 : 50); // Adjusted for tablets
                  final childAspectRatio = isTablet(context) ? 1.9 : 2.2; // Adjusted for tablet scaling

                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: scalingFactor * (isTablet(context) ? 10 : 8),
                      crossAxisSpacing: scalingFactor * (isTablet(context) ? 10 : 8),
                      childAspectRatio: childAspectRatio,
                    ),
                    itemCount: albums.length,
                    itemBuilder: (context, index) {
                      return _buildAnimatedGridButtonLandscape(
                        label: albums[index].name,
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
                        scalingFactor: scalingFactor,
                      );
                    },
                  );
                }
              },
            ),
          ),
        ),
        SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
      ],
    );
  }

  Widget _buildAnimatedGridButtonLandscape({
    required String label,
    required VoidCallback onTap,
    required double scalingFactor,
  }) {
    return GestureDetector(
      onTapDown: (_) => _onTapDown(label),
      onTapUp: (_) => _onTapUp(label, onTap),
      onTapCancel: () {
        setState(() {
          _buttonScales[label] = 1.0;
          _buttonColors[label] = [
            const Color(0xFF548235),
            const Color(0xFF6BA644),
            const Color(0xFF93C573),
          ];
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        transform: Matrix4.diagonal3Values(
          _buttonScales[label] ?? 1.0,
          _buttonScales[label] ?? 1.0,
          1.0,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _buttonColors[label] ?? [
              const Color(0xFF548235),
              const Color(0xFF6BA644),
              const Color(0xFF93C573),
            ],
          ),
          borderRadius: BorderRadius.circular(isTablet(context) ? 12 : 8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(1, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: scalingFactor * (isTablet(context) ? 21 : 24),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}