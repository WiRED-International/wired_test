import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/pages/policy.dart';
import '../../providers/auth_guard.dart';
import '../../providers/auth_provider.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/landscape_profile_section.dart';
import '../../utils/profile_section.dart';
import '../../utils/side_nav_bar.dart';
import 'package:http/http.dart' as http;
import '../cme/cme_tracker.dart';
import '../cme/login.dart';
import '../home_page.dart';
import '../module_library.dart';
import 'about_wired.dart';
import 'meet_team.dart';


class Menu extends StatefulWidget {
  @override
  _MenuState createState() => _MenuState();
}

class User {
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? dateJoined;
  final List<dynamic>? quizScores;


  User({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.dateJoined,
    required this.quizScores,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      firstName: json['first_name'] ?? 'Unknown',
      lastName: json['last_name'] ?? 'Unknown',
      email: json['email'] ?? 'No email',
      dateJoined: json['createdAt'] ?? 'Unknown Date',
      quizScores: json['quizScores'] ?? [], // Provide an empty list for quizScores if null
    );
  }

  Map<String, dynamic> toJson() => {
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'dateJoined': dateJoined,
    'quizScores': quizScores,
  };
}

class _MenuState extends State<Menu> {
  final double circleDiameter = 130.0;
  final double circleDiameterSmall = 115.0;
  late Future<User> userData;
  final _storage = const FlutterSecureStorage();
  bool showCreditsHistory = false;

  @override
  void initState() {
    super.initState();
    userData = fetchUserData();
  }

  Future<String?> getAuthToken() async {
    return await _storage.read(key: 'authToken');
  }

  Future<User> fetchUserData() async {
    final token = await getAuthToken();
    if (token == null) {
      throw Exception('User is not logged in');
    }

    final url = Uri.parse(
        'http://widm.wiredhealthresources.net/apiv2/users/me'); // Replace with your API URL
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token', // Include the token in the header
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      print('API Response: $json');
      return User.fromJson(json); // Parse the top-level response directly
    } else {
      throw Exception('Failed to fetch user data: ${response.statusCode}');
    }
  }

  void refreshScores() {
    setState(() {
      userData = fetchUserData();
    });
  }

    @override
    Widget build(BuildContext context) {
      final mediaQuery = MediaQuery.of(context);
      final screenSize = mediaQuery.size;
      final baseSize = screenSize.shortestSide;
      final isLandscape = mediaQuery.orientation == Orientation.landscape;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final scalingFactor = getScalingFactor(context);
      final isTabletDevice = isTablet(context);

      return Scaffold(
        body: SafeArea(
          child: FutureBuilder<User>(
            future: userData,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              } else if (!snapshot.hasData) {
                return const Center(child: Text('No data available'));
              }

              final user = snapshot.data!;
              return Stack(
                children: [
                  // Background Gradient
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
                  isLandscape
                      ? Row(
                    children: [
                      // Side Navigation Bar (Fixed Width)
                      SizedBox(
                        width: screenSize.width * 0.12,
                        // Adjust width as needed
                        child: CustomSideNavBar(
                          onHomeTap: () =>
                              _navigateTo(context, const MyHomePage()),
                          onLibraryTap: () =>
                              _navigateTo(context, ModuleLibrary()),
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
                          onMenuTap: () {},
                        ),
                      ),
                      // Right Content (Profile + Main Content)
                      Expanded(
                        child: Column(
                          children: [
                            LandscapeProfileSection(
                              firstName: user.firstName ?? 'Guest',
                              dateJoined: user.dateJoined ?? 'Unknown',
                            ),
                            SizedBox(height: screenSize.height *
                                (isTabletDevice ? 0.05 : .05)),
                            Expanded(
                              child: Center(
                                child: _buildLandscapeLayout(
                                  context,
                                  baseSize,
                                  scalingFactor,
                                  authProvider,
                                  user.firstName,
                                  user.dateJoined,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                      : Column(
                    children: [
                      ProfileSection(
                        firstName: user.firstName ?? 'Guest',
                        dateJoined: user.dateJoined ?? 'Unknown',
                        creditsEarned: user.quizScores != null ? user.quizScores!.length * 5 : 0,
                      ),
                      SizedBox(height: screenSize.height *
                          (isTabletDevice ? 0.05 : .04)),
                      Expanded(
                        child: Center(
                          child: _buildPortraitLayout(
                            context,
                            baseSize,
                            scalingFactor,
                            authProvider,
                            user.firstName,
                            user.dateJoined,
                          ),
                        ),
                      ),
                      CustomBottomNavBar(
                        onHomeTap: () =>
                            _navigateTo(context, const MyHomePage()),
                        onLibraryTap: () =>
                            _navigateTo(context, ModuleLibrary()),
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
                        onMenuTap: () {},
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      );
    }
  }

// Navigation Helper
    void _navigateTo(BuildContext context, Widget page) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => page));
    }

    Widget _buildPortraitLayout(BuildContext context, baseSize, scalingFactor, authProvider, firstName, dateJoined) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildInkWellButton(context,'Meet The Team', scalingFactor, () {
                print("Meet The Team Tapped");
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => MeetTeam()),
                );
              }),
              _buildInkWellButton(context, 'About WiRED', scalingFactor, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => AboutWired()),
                );
              }),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildInkWellButton(context, 'Privacy Policy', scalingFactor, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => Policy()),
                );
              }),
              _buildEmptyButton(context, scalingFactor),
            ],
          ),
          GestureDetector(
            onTap: () {
              Provider.of<AuthProvider>(context, listen: false).logOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => Login()),
              );
            },
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(
                    left: scalingFactor * (isTablet(context) ? 15 : 15)),
                child: Text(
                  'Log out',
                  style: TextStyle(
                    fontSize: scalingFactor * (isTablet(context) ? 18 : 18),
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF0070C0),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: scalingFactor * (isTablet(context) ? 20 : 0.06),
          ),
        ],
      );
    }

Widget _buildInkWellButton(BuildContext context, String text, double scalingFactor, VoidCallback onTap) {
  return Material(
    color: Colors.transparent, // Ensures ripple effect works
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10), // Rounded edges for ripple effect
      splashColor: Colors.grey.withOpacity(0.3), // Light splash effect
      child: Container(
        height: scalingFactor * (isTablet(context) ? 90 : 90),
        width: scalingFactor * (isTablet(context) ? 165 : 165),
        padding: EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Color(0xFFFCEDDA),
          border: Border.all(color: Colors.black, width: 0.7),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.5),
              spreadRadius: 2,
              blurRadius: 5,
              offset: Offset(3, 3),
            ),
          ],
        ),
        child: Center( // Ensures text is centered
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: scalingFactor * (isTablet(context) ? 15 : 15),
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ),
      ),
    ),
  );
}

// 🔹 Helper function for an empty placeholder button
Widget _buildEmptyButton(BuildContext context, double scalingFactor) {
  return Container(
    height: scalingFactor * (isTablet(context) ? 90 : 90),
    width: scalingFactor * (isTablet(context) ? 165 : 165),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      color: Colors.transparent, // Invisible placeholder
    ),
  );
}


    Widget _buildLandscapeLayout(BuildContext context, baseSize, scalingFactor, authProvider, firstName, dateJoined) {
      return SingleChildScrollView(
        child: Column(
          //mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            SizedBox(height: scalingFactor * (isTablet(context) ? 20 : 20)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildInkWellButton(context,'Meet The Team', scalingFactor, () {
                  print("Meet The Team Tapped");
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => MeetTeam()),
                  );
                }),
                _buildInkWellButton(context, 'About WiRED', scalingFactor, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AboutWired()),
                  );
                }),
              ],
            ),
            SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildInkWellButton(context, 'Privacy Policy', scalingFactor, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => Policy()),
                  );
                }),
                _buildEmptyButton(context, scalingFactor),
              ],
            ),
            SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 30)),
            GestureDetector(
              onTap: () {
                Provider.of<AuthProvider>(context, listen: false).logOut();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => Login()),
                );
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(
                      left: scalingFactor * (isTablet(context) ? 55 : 55)),
                  child: Text(
                    'Log out',
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 18 : 18),
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF0070C0),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: scalingFactor * (isTablet(context) ? 30 : 30),
            ),
          ],
        ),
      );
    }


