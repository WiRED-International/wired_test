import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../home_page.dart';
import '../menu.dart';
import '../module_library.dart';


class CMETracker extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String email;
  final String dateJoined;
  // final String profilePictureUrl;

  const CMETracker({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.dateJoined
  });

  @override
  _CMETrackerState createState() => _CMETrackerState();
}

class _CMETrackerState extends State<CMETracker> {
  final double circleDiameter = 130.0;
  final double circleDiameterSmall = 115.0;
  late Future<Map<String, dynamic>> moduleScores;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    moduleScores = fetchModuleScores();
  }

  Future<String?> getAuthToken() async {
    return await _storage.read(key: 'authToken');
  }


  Future<Map<String, dynamic>> fetchModuleScores() async {

    final token = await getAuthToken();
    if (token == null) {
      throw Exception('User is not logged in');
    }

    final url = Uri.parse('http://localhost:3000/users/me'); // Replace with your API URL

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token', // Include the token in the header
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch user data: ${response.statusCode}');
    }
  }

  void refreshScores() {
    setState(() {
      moduleScores = fetchModuleScores();
    });
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
                          onTrackerTap: () {
                            //Purposefully left blank
                          },
                          onMenuTap: () {
                            Navigator.push(context, MaterialPageRoute(
                                builder: (context) => Menu()));
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: FutureBuilder<Map<String, dynamic>>(
                            future: fetchModuleScores(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return Center(child: CircularProgressIndicator());
                              } else if (snapshot.hasError) {
                                return Center(child: Text('Error: ${snapshot.error}'));
                              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                return Center(child: Text('No data available'));
                              }

                              final userData = snapshot.data!;
                              final quizScores = userData['quizScores'] as List<dynamic>;
                              final latestScore = quizScores.isNotEmpty
                                  ? quizScores.last['score']
                                  : 'No score available';

                              return _buildPortraitLayout(
                                screenWidth,
                                screenHeight,
                                baseSize,
                                widget.firstName,
                                widget.lastName,
                                widget.email,
                                widget.dateJoined,
                                latestScore,
                              );
                            },
                          ),
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
                    onTrackerTap: () {
                      //Purposefully left blank
                    },
                    onMenuTap: () {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (context) => Menu()));
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(screenWidth, screenHeight, baseSize, firstName, lastName, email, dateJoined, latestScore) {
    return Column(
      children: <Widget>[
        Stack(
          clipBehavior: Clip.none, // Allows the circle to extend outside the container
          children: [
            Container(
              height: baseSize * (isTablet(context) ? 0.05 : 0.35),
              width: MediaQuery.of(context).size.width,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF2853FF),
                    Color(0xFFC3C6FB),
                  ],
                ),
              ),
            ),
            Positioned(
              top: baseSize * (isTablet(context) ? 0.05 : 0.35) - (circleDiameter / 2), // Middle of the circle aligns with the bottom
              left: baseSize * (isTablet(context) ? 0.05 : 0.18) - (circleDiameter / 2), // Horizontally centered
              child: Container(
                width: circleDiameter, // Diameter of the circle
                height: circleDiameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFCEEDB),
                ),
              ),
            ),
            // Second Circle
            Positioned(
              top: baseSize * (isTablet(context) ? 0.05 : 0.35) - circleDiameterSmall / 2, // Adjust position to place on top of first circle
              left: baseSize * (isTablet(context) ? 0.05 : 0.18) - (circleDiameterSmall / 2), // Smaller circle horizontally centered
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: circleDiameterSmall, // Smaller circle
                    height: circleDiameterSmall,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey, // Different color for the second circle
                    ),
                  ),
                  Icon(
                    Icons.person_2_sharp, // Flutter icon
                    size: baseSize * (isTablet(context) ? .07 : 0.25), // Scale the icon size
                    color: Colors.white,
                  ),
                ],
              ),
            ),
            // Text at the Bottom Center
            Positioned(
              bottom: 10.0, // Position slightly above the bottom of the container
              left: 0,
              right: baseSize * (isTablet(context) ? 0.07 : 0.06),
              child: Text(
                "Hi, $firstName",
                textAlign: TextAlign.center, // Center the text horizontally
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.07 : 0.06),
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.02 : 0.02),
        ),
        Row(
          children: [
            SizedBox(
              width: baseSize * (isTablet(context) ? 0.05 : 0.35),
            ),
            Text(
              "Joined: ${formatDate(dateJoined)}",
              style: TextStyle(
                fontSize: baseSize * (isTablet(context) ? 0.07 : 0.045),
                fontWeight: FontWeight.w400,
                color: Colors.black,
              ),
            ),
          ],
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.05 : 0.09),
        ),
        Text(
          "CME Credits Tracker",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.08 : 0.09),
            fontWeight: FontWeight.w500,
            color: Color(0xFF325BFF),
          ),
        ),
        Text(
          "Latest Score: $latestScore",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.07 : 0.06),
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight, baseSize) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Text(
          "You have successfully registered for the CME Credits Tracker. Please Log In with your email and password to continue.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
            fontWeight: FontWeight.w500,
            color: Color(0xFF0070C0),
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.05 : 0.03),
        ),
      ],
    );
  }
}


