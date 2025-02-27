import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_guard.dart';
import '../../providers/auth_provider.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/landscape_profile_section.dart';
import '../../utils/profile_section.dart';
import '../../utils/side_nav_bar.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import 'cme_tracker.dart';

class LeaderboardScreen extends StatefulWidget {
  @override
  _LeaderboardScreenState createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<dynamic> leaderboard = [];
  bool isLoading = true;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    fetchLeaderboard();
  }

  // Fetch the stored token
  Future<String?> getAuthToken() async {
    return await _storage.read(key: 'authToken');
  }

  // Fetch leaderboard data
  Future<List<dynamic>> fetchLeaderboardData() async {
    final token = await getAuthToken();
    if (token == null) {
      throw Exception('User is not logged in');
    }

    final url = Uri.parse('http://widm.wiredhealthresources.net/apiv2/leaderboard'); // Replace with remote URL if needed
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body); // Return the leaderboard data directly
    } else {
      throw Exception('Failed to fetch leaderboard: ${response.statusCode}');
    }
  }

// Keep this function for updating the state when needed
  Future<void> fetchLeaderboard() async {
    try {
      final leaderboardData = await fetchLeaderboardData();
      setState(() {
        leaderboard = leaderboardData;
        isLoading = false;
      });
    } catch (error) {
      setState(() {
        isLoading = false;
      });
      throw error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scalingFactor = getScalingFactor(context);
    bool isLandscape = MediaQuery
        .of(context)
        .orientation == Orientation.landscape;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/leaderboard_background.webp'),
                  fit: BoxFit.cover, // Ensures the image covers the entire screen
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
                            // Intentionally left blank
                          },
                          onTrackerTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    AuthGuard(
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
                              ? _buildLandscapeLayout(scalingFactor)
                              : _buildPortraitLayout(scalingFactor),
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
                      // Intentionally left blank
                    },
                    onTrackerTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AuthGuard(child: CMETracker()),
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

  Widget _buildPortraitLayout(scalingFactor) {
    return Column(
      children: [
        Text(
          "Leaderboard",
          style: TextStyle(
            fontSize: scalingFactor * (isTablet(context) ? 24 : 28),
            fontWeight: FontWeight.bold,
            color: Color(0xFF505050),
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 10 : 10),
        ),
        // Leaderboard Section
        Flexible(
          flex: 1,
          child: FutureBuilder<List<dynamic>>(
            future: fetchLeaderboardData(), // Fetch leaderboard data from the API
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(child: Text('Error loading leaderboard data'));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(child: Text('No leaderboard data available.'));
              } else {
                return Column(
                  children: [
                    // Header for Leaderboard
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 5 : 5)),
                            child: Text(
                              'Place',
                              textAlign: TextAlign.start,
                              style: TextStyle(
                                fontSize: scalingFactor * (isTablet(context) ? 18 : 20),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Name',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: scalingFactor * (isTablet(context) ? 18 : 20),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: scalingFactor * (isTablet(context) ? 5 : 5)),
                            child: Text(
                              'Credits',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: scalingFactor * (isTablet(context) ? 18 : 20),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Divider(),
                    // Display leaderboard data
                    Expanded(
                      child: ListView.separated(
                        itemCount: snapshot.data!.length,
                        separatorBuilder: (context, index) => Divider(
                          color: Colors.grey, // Divider color
                          thickness: 1, // Thickness of the divider
                        ),
                        itemBuilder: (context, index) {
                          final user = snapshot.data![index]['user'];
                          final quizzesCompleted = snapshot.data![index]['completedQuizzes'];
                          final credits = quizzesCompleted * 5;
                          final placement = index + 1;
                          final fullName = "${user['first_name']} ${user['last_name']}";

                          return Container(
                            margin: EdgeInsets.symmetric(vertical: scalingFactor * 0.01),
                            child: Flex(
                              direction: Axis.horizontal,
                              children: [
                                // Placement Section
                                Expanded(
                                  flex: 1, // Smallest section
                                  child: Container(
                                    height: scalingFactor * (isTablet(context) ? 50 : 65),
                                    decoration: BoxDecoration(
                                      border: const Border(
                                        right: BorderSide(
                                          color: Color(0xFFD6D6D6), // Border color
                                          width: 2.0, // Border width
                                        ),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '$placement',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Full Name Section
                                Expanded(
                                  flex: 6, // Largest section for the name
                                  child: Container(
                                    height: scalingFactor * (isTablet(context) ? 50 : 55),
                                    padding: EdgeInsets.only(left: scalingFactor * 10),
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      fullName,
                                      textAlign: TextAlign.start,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: scalingFactor * (isTablet(context) ? 14 : 16),
                                        color: Colors.black,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                                // Credits Section
                                Expanded(
                                  flex: 2, // Medium space for credits
                                  child: Container(
                                    height: scalingFactor * (isTablet(context) ? 50 : 55),
                                    alignment: Alignment.center,
                                    padding: EdgeInsets.only(right: scalingFactor * 10),
                                    child: Text(
                                      '$credits',
                                      textAlign: TextAlign.end,
                                      style: TextStyle(
                                        fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              }
            },
          ),
        ),
        SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
      ],
    );
  }


  Widget _buildLandscapeLayout(scalingFactor) {
    return Column(
      children: [
        Text(
          "Leaderboard",
          style: TextStyle(
            fontSize: scalingFactor * (isTablet(context) ? 24 : 28),
            fontWeight: FontWeight.bold,
            color: Color(0xFF505050),
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 10 : 10),
        ),
        // Leaderboard Section
        Flexible(
          flex: 1,
          child: FutureBuilder<List<dynamic>>(
            future: fetchLeaderboardData(), // Fetch leaderboard data from the API
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(child: Text('Error loading leaderboard data'));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(child: Text('No leaderboard data available.'));
              } else {
                return Column(
                  children: [
                    // Header for Leaderboard
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 5 : 5)),
                            child: Text(
                              'Place',
                              textAlign: TextAlign.start,
                              style: TextStyle(
                                fontSize: scalingFactor * (isTablet(context) ? 18 : 20),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Name',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: scalingFactor * (isTablet(context) ? 18 : 20),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: scalingFactor * (isTablet(context) ? 5 : 5)),
                            child: Text(
                              'Credits',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: scalingFactor * (isTablet(context) ? 18 : 20),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Divider(),
                    // Display leaderboard data
                    Expanded(
                      child: ListView.separated(
                        itemCount: snapshot.data!.length,
                        separatorBuilder: (context, index) => Divider(
                          color: Colors.grey, // Divider color
                          thickness: 1, // Thickness of the divider
                        ),
                        itemBuilder: (context, index) {
                          final user = snapshot.data![index]['user'];
                          final quizzesCompleted = snapshot.data![index]['completedQuizzes'];
                          final credits = quizzesCompleted * 5;
                          final placement = index + 1;
                          final fullName = "${user['first_name']} ${user['last_name']}";

                          return Container(
                            margin: EdgeInsets.symmetric(vertical: scalingFactor * 0.01),
                            child: Flex(
                              direction: Axis.horizontal,
                              children: [
                                // Placement Section
                                Expanded(
                                  flex: 1, // Smallest section
                                  child: Container(
                                    height: scalingFactor * (isTablet(context) ? 50 : 65),
                                    decoration: BoxDecoration(
                                      border: const Border(
                                        right: BorderSide(
                                          color: Color(0xFFD6D6D6), // Border color
                                          width: 2.0, // Border width
                                        ),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '$placement',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Full Name Section
                                Expanded(
                                  flex: 6, // Largest section for the name
                                  child: Container(
                                    height: scalingFactor * (isTablet(context) ? 50 : 55),
                                    padding: EdgeInsets.only(left: scalingFactor * 10),
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      fullName,
                                      textAlign: TextAlign.start,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                        color: Colors.black,
                                        fontWeight: FontWeight.w500
                                      ),
                                    ),
                                  ),
                                ),
                                // Credits Section
                                Expanded(
                                  flex: 2, // Medium space for credits
                                  child: Container(
                                    height: scalingFactor * (isTablet(context) ? 50 : 55),
                                    alignment: Alignment.center,
                                    padding: EdgeInsets.only(right: scalingFactor * 10),
                                    child: Text(
                                      '$credits',
                                      textAlign: TextAlign.end,
                                      style: TextStyle(
                                        fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              }
            },
          ),
        ),
        SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
      ],
    );
  }
}