import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:wired_test/pages/cme/submit_credits.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/profile_section.dart';
import '../../utils/side_nav_bar.dart';
import '../home_page.dart';
import '../menu.dart';
import '../module_library.dart';
import 'credits_history.dart';


class CMETracker extends StatefulWidget {

  @override
  _CMETrackerState createState() => _CMETrackerState();
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

class _CMETrackerState extends State<CMETracker> {
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

    final url = Uri.parse('http://10.0.2.2:3000/users/me'); // Replace with your API URL
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
    var baseSize = MediaQuery.of(context).size.shortestSide;
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<User>(
          future: userData,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else if (!snapshot.hasData) {
              return Center(child: Text('No data available'));
            }

            final user = snapshot.data!;
            return Stack(
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
                    ProfileSection(
                      firstName: user.firstName ?? 'Guest',
                      dateJoined: user.dateJoined ?? 'Unknown',
                    ),
                    SizedBox(
                      height: baseSize * (isTablet(context) ? 0.05 : 0.07),
                    ),
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
                                // Intentionally left blank
                              },
                              onMenuTap: () {
                                Navigator.push(context, MaterialPageRoute(
                                    builder: (context) => Menu()));
                              },
                            ),
                          Expanded(
                            child: Stack(
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
                                      child: isLandscape
                                        ? _buildLandscapeLayout(context, baseSize, user.firstName, user.dateJoined, user.quizScores)
                                        : _buildPortraitLayout(context, baseSize, user.firstName, user.dateJoined, user.quizScores),
                                    ),
                                  ),
                                ),
                              ],
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
                          // Intentionally left blank
                        },
                        onMenuTap: () {
                          Navigator.push(context,
                              MaterialPageRoute(builder: (context) => Menu()));
                        },
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

  Widget _buildPortraitLayout(BuildContext context, baseSize, firstName, dateJoined, quizScores) {

    // Calculate credits
    final int creditsEarned = quizScores != null
        ? quizScores.where((score) {
      if (score is Map<String, dynamic> && score['score'] != null) {
        final scoreValue = double.tryParse(score['score'].toString()) ?? 0.0;
        return scoreValue >= 80.0;
      }
      return false;
    }).length * 5 // Each score above 80 adds 5 credits
        : 0;

    // Maximum credits
    const int maxCredits = 50;

    // Calculate remaining credits
    final int creditsRemaining = maxCredits - creditsEarned;

    return Column(
      children: <Widget>[
        Text(
          "CME Credits Tracker",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.08 : 0.09),
            fontWeight: FontWeight.w500,
            color: Color(0xFF325BFF),
          ),
        ),
        SizedBox(height: baseSize * (isTablet(context) ? 0.05 : 0.10)),
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: baseSize * (isTablet(context) ? 0.05 : 0.04)
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "CREDITS",
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.05 : 0.045),
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              SizedBox(width: baseSize * (isTablet(context) ? 0.05 : 0.045)),
              RichText(
                textAlign: TextAlign.right,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: "$creditsEarned",
                      style: TextStyle(
                        fontSize: baseSize * (isTablet(context) ? 0.05 : 0.045),
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFBD34FD), // Purple for earned credits
                      ),
                    ),
                    TextSpan(
                      text: "/$maxCredits",
                      style: TextStyle(
                        fontSize: baseSize * (isTablet(context) ? 0.05 : 0.045),
                        fontWeight: FontWeight.bold,
                        color: Colors.black, // Black for max credits
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
        SizedBox(height: baseSize * (isTablet(context) ? 0.05 : 0.03)),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: baseSize * (isTablet(context) ? 0.05 : 0.04)
          ),
          child: LinearProgressIndicator(
            value: creditsEarned / maxCredits,
            backgroundColor: Colors.white,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFBD34FD)),
            minHeight: 15,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        SizedBox(height: baseSize * (isTablet(context) ? 0.05 : 0.10)),
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: baseSize * (isTablet(context) ? 0.05 : 0.09),
          ),
          child: RichText(
            textAlign: TextAlign.left,
            text: TextSpan(
              style: TextStyle(
                fontSize: baseSize * (isTablet(context) ? 0.045 : 0.06),
                fontWeight: FontWeight.w400,
                color: Colors.black, // Default color for the text
              ),
              children: [
                TextSpan(text: "So far this year you have earned "),
                TextSpan(
                  text: "$creditsEarned credits",
                  style: TextStyle(color: Color(0xFFBD34FD)), // Purple for credits earned
                ),
                TextSpan(text: ", and you have "),
                TextSpan(
                  text: "$creditsRemaining more credits",
                  style: TextStyle(color: Color(0xFFBD34FD)), // Purple for credits remaining
                ),
                TextSpan(text: " to go before Dec. 31."),
              ],
            ),
          ),
        ),
        SizedBox(height: baseSize * (isTablet(context) ? 0.05 : 0.10)),
        Semantics(
          label: 'CME Credits History Button',
          hint: 'Tap to view your CME credits history',
          child: GestureDetector(
            onTap: () async {
              Navigator.push(
                  context, MaterialPageRoute(builder: (context) => CreditsHistory()));
            },
            child: FractionallySizedBox(
              widthFactor: isTablet(context) ? 0.33 : 0.7,
              child: Container(
                height: baseSize * (isTablet(context) ? 0.09 : 0.13),
                decoration: BoxDecoration(
                  color: Color(0xFF6B72FF),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(
                          1, 3), // changes position of shadow
                    ),
                  ],
                ),
                child: LayoutBuilder(
                    builder: (context, constraints) {
                      double buttonWidth = constraints.maxWidth;
                      double fontSize = buttonWidth * 0.2;
                      double padding = buttonWidth * 0.02;
                      return Padding(
                        padding: EdgeInsets.all(padding),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.fitWidth,
                                child: Text(
                                  "Credits History",
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: baseSize * (isTablet(context) ? 0.05 : 0.10)),
        Semantics(
          label: 'Submit CME Credits Button',
          hint: 'Tap to submit your CME credits',
          child: GestureDetector(
            onTap: () async {
              Navigator.push(
                  context, MaterialPageRoute(builder: (context) => SubmitCredits()));
            },
            child: FractionallySizedBox(
              widthFactor: isTablet(context) ? 0.33 : 0.7,
              child: Container(
                height: baseSize * (isTablet(context) ? 0.09 : 0.13),
                decoration: BoxDecoration(
                  color: Color(0xFF6B72FF),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(
                          1, 3), // changes position of shadow
                    ),
                  ],
                ),
                child: LayoutBuilder(
                    builder: (context, constraints) {
                      double buttonWidth = constraints.maxWidth;
                      double fontSize = buttonWidth * 0.2;
                      double padding = buttonWidth * 0.02;
                      return Padding(
                        padding: EdgeInsets.all(padding),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.fitWidth,
                                child: Text(
                                  "Submit New Credits",
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildLandscapeLayout(BuildContext context, baseSize, firstName, dateJoined, quizScores) {
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


