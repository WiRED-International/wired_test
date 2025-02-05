import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:wired_test/pages/cme/submit_credits.dart';
import '../../providers/auth_guard.dart';
import '../../providers/auth_provider.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/landscape_profile_section.dart';
import '../../utils/profile_section.dart';
import '../../utils/side_nav_bar.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
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

    const remoteServer = 'http://widm.wiredhealthresources.net/apiv2/users/me';
    const localServer = '''http://10.0.2.2:3000/users/me''';

    final url = Uri.parse(remoteServer);
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
                      width: screenSize.width * 0.12, // Adjust width as needed
                      child: CustomSideNavBar(
                        onHomeTap: () => _navigateTo(context, const MyHomePage()),
                        onLibraryTap: () => _navigateTo(context, ModuleLibrary()),
                        onTrackerTap: () {},
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
                    ),
                    // Right Content (Profile + Main Content)
                    Expanded(
                      child: Column(
                        children: [
                          LandscapeProfileSection(
                            firstName: user.firstName ?? 'Guest',
                            dateJoined: user.dateJoined ?? 'Unknown',
                          ),
                          SizedBox(height: screenSize.height * (isTabletDevice ? 0.05 : .05)),
                          Expanded(
                            child: Center(
                              child: _buildLandscapeLayout(
                                context,
                                scalingFactor,
                                authProvider,
                                user.firstName,
                                user.dateJoined,
                                user.quizScores,
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
                    ),
                    SizedBox(height: screenSize.height * (isTabletDevice ? 0.05 : .04)),
                    Expanded(
                      child: Center(
                        child: _buildPortraitLayout(
                          context,
                          scalingFactor,
                          authProvider,
                          user.firstName,
                          user.dateJoined,
                          user.quizScores,
                        ),
                      ),
                    ),
                    CustomBottomNavBar(
                      onHomeTap: () => _navigateTo(context, const MyHomePage()),
                      onLibraryTap: () => _navigateTo(context, ModuleLibrary()),
                      onTrackerTap: () {},
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
            );
          },
        ),
      ),
    );
  }

// Navigation Helper
  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  Widget _buildPortraitLayout(BuildContext context, scalingFactor,
      authProvider, firstName, dateJoined, quizScores) {
    // Get the current year
    final int currentYear = DateTime.now().year;
    print('QuizScores: $quizScores');

    // Calculate credits earned
    final int creditsEarned = quizScores != null
        ? quizScores.where((score) {
      if (score is Map<String, dynamic> &&
          score['score'] != null &&
          score['date_taken'] != null) {
        // Parse the score and date_taken
        final scoreValue = double.tryParse(score['score'].toString()) ?? 0.0;
        final DateTime? dateTaken =
        DateTime.tryParse(score['date_taken'].toString());

        // Include scores >= 80 and taken in the current year
        final isValid = scoreValue >= 80.0 &&
            dateTaken != null &&
            dateTaken.year == currentYear;

        print('Score: $scoreValue, Date Taken: $dateTaken, Valid: $isValid');

        return isValid;
      }
      return false;
    }).length * 5 : 0;

    // Maximum credits
    const int maxCredits = 50;

    // Calculate remaining credits
    final int creditsRemaining = maxCredits - creditsEarned;

    return SingleChildScrollView(
      child: Column(
        children: <Widget>[
          Text(
            "CME Credits Tracker",
            style: TextStyle(
              fontSize: scalingFactor * (isTablet(context) ? 24 : 32),
              fontWeight: FontWeight.w400,
              color: Color(0xFF325BFF),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 25 : 15)),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: scalingFactor * (isTablet(context) ? 25 : 25)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "CREDITS",
                  style: TextStyle(
                    fontSize: scalingFactor * (isTablet(context) ? 12 : 16),
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
                //SizedBox(width: scalingFactor * (isTablet(context) ? 0.05 : 15)),
                RichText(
                  //textAlign: TextAlign.right,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: "$creditsEarned",
                        style: TextStyle(
                          fontSize: scalingFactor *
                              (isTablet(context) ? 12 : 16),
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFBD34FD), // Purple for earned credits
                        ),
                      ),
                      TextSpan(
                        text: "/$maxCredits",
                        style: TextStyle(
                          fontSize: scalingFactor *
                              (isTablet(context) ? 12 : 16),
                          fontWeight: FontWeight.w500,
                          color: Colors.black, // Black for max credits
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 5 : 5)),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: scalingFactor * (isTablet(context) ? 20 : 20)
            ),
            child: LinearProgressIndicator(
              value: creditsEarned / maxCredits,
              backgroundColor: Colors.white,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFBD34FD)),
              minHeight: scalingFactor * (isTablet(context) ? 10 : 10),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 25 : 25)),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: scalingFactor * (isTablet(context) ? 40 : 40),
            ),
            child: RichText(
              textAlign: TextAlign.left,
              text: TextSpan(
                style: TextStyle(
                  fontSize: scalingFactor * (isTablet(context) ? 16 : 20),
                  fontWeight: FontWeight.w400,
                  color: Colors.black, // Default color for the text
                ),
                children: [
                  TextSpan(text: "You have earned "),
                  TextSpan(
                    text: "$creditsEarned credits",
                    style: TextStyle(
                        color: Color(0xFFBD34FD)), // Purple for credits earned
                  ),
                  TextSpan(text: " this year, and you have "),
                  TextSpan(
                    text: "$creditsRemaining more credits",
                    style: TextStyle(
                        color: Color(0xFFBD34FD)), // Purple for credits remaining
                  ),
                  TextSpan(text: " to go before Dec. 31."),
                ],
              ),
            ),
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 40 : 40)),
          Semantics(
            label: 'CME Credits History Button',
            hint: 'Tap to view your CME credits history',
            child: GestureDetector(
              onTap: () async {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AuthGuard(
                          child: CreditsHistory(),
                        ),
                  ),
                );
              },
              child: Container(
                width: scalingFactor * (isTablet(context) ? 180 : 230),
                height: scalingFactor * (isTablet(context) ? 35 : 40),
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
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Credits History",
                            style: TextStyle(
                              fontSize: scalingFactor * (isTablet(context) ? 16 : 20),
                              fontWeight: FontWeight.w400,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      );
                    }
                ),
              ),
            ),
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 30)),
          Semantics(
            label: 'Submit CME Credits Button',
            hint: 'Tap to submit your CME credits',
            child: GestureDetector(
              onTap: () async {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AuthGuard(
                          child: SubmitCredits(),
                        ),
                  ),
                );
              },
              child: Container(
                width: scalingFactor * (isTablet(context) ? 180 : 230),
                height: scalingFactor * (isTablet(context) ? 35 : 40),
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
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Submit New Credits",
                            style: TextStyle(
                              fontSize: scalingFactor * (isTablet(context) ? 16 : 20),
                              fontWeight: FontWeight.w400,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      );
                    }
                ),
              ),
            ),
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 70 : 70)),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout(BuildContext context, scalingFactor,
      authProvider, firstName, dateJoined, quizScores) {
    final int currentYear = DateTime.now().year;

    // Debug: Print the passed quizScores
    print('QuizScores: $quizScores');

    // Calculate credits earned
    final int creditsEarned = quizScores != null
        ? quizScores.where((score) {
      if (score is Map<String, dynamic> &&
          score['score'] != null &&
          score['date_taken'] != null) {
        // Parse the score and date_taken
        final scoreValue = double.tryParse(score['score'].toString()) ?? 0.0;
        final DateTime? dateTaken =
        DateTime.tryParse(score['date_taken'].toString());

        // Include scores >= 80 and taken in the current year
        final isValid = scoreValue >= 80.0 &&
            dateTaken != null &&
            dateTaken.year == currentYear;

        // Debug: Log filtering results
        print(
            'Score: $scoreValue, Date Taken: $dateTaken, Valid: $isValid');

        return isValid;
      }
      return false;
    }).length * 5 // Each valid score adds 5 credits
        : 0;

    // Maximum credits
    const int maxCredits = 50;

    // Calculate remaining credits
    final int creditsRemaining = maxCredits - creditsEarned;

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            "CME Credits Tracker",
            style: TextStyle(
              fontSize: scalingFactor * (isTablet(context) ? 22 : 28),
              fontWeight: FontWeight.w400,
              color: Color(0xFF325BFF),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 25 : 25)),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: scalingFactor * (isTablet(context) ? 75 : 75)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "CREDITS",
                  style: TextStyle(
                    fontSize: scalingFactor * (isTablet(context) ? 14 : 15),
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
                //SizedBox(width: scalingFactor * (isTablet(context) ? 0.05 : 15)),
                RichText(
                  //textAlign: TextAlign.right,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: "$creditsEarned",
                        style: TextStyle(
                          fontSize: scalingFactor *
                              (isTablet(context) ? 14 : 15),
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFBD34FD), // Purple for earned credits
                        ),
                      ),
                      TextSpan(
                        text: "/$maxCredits",
                        style: TextStyle(
                          fontSize: scalingFactor *
                              (isTablet(context) ? 14 : 15),
                          fontWeight: FontWeight.w500,
                          color: Colors.black, // Black for max credits
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
          //SizedBox(height: scalingFactor * (isTablet(context) ? 0.05 : 5)),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: scalingFactor * (isTablet(context) ? 65 : 70)
            ),
            child: LinearProgressIndicator(
              value: creditsEarned / maxCredits,
              backgroundColor: Colors.white,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFBD34FD)),
              minHeight: scalingFactor * (isTablet(context) ? 8 : 10),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 25 : 25)),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: scalingFactor * (isTablet(context) ? 70 : 50),
            ),
            child: RichText(
              textAlign: TextAlign.left,
              text: TextSpan(
                style: TextStyle(
                  fontSize: scalingFactor * (isTablet(context) ? 15 : 20),
                  fontWeight: FontWeight.w400,
                  color: Colors.black, // Default color for the text
                ),
                children: [
                  TextSpan(text: "You have earned "),
                  TextSpan(
                    text: "$creditsEarned credits",
                    style: TextStyle(
                        color: Color(0xFFBD34FD)), // Purple for credits earned
                  ),
                  TextSpan(text: " this year, and you have "),
                  TextSpan(
                    text: "$creditsRemaining more credits",
                    style: TextStyle(
                        color: Color(0xFFBD34FD)), // Purple for credits remaining
                  ),
                  TextSpan(text: " to go before Dec. 31."),
                ],
              ),
            ),
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 35 : 35)),
          Semantics(
            label: 'CME Credits History Button',
            hint: 'Tap to view your CME credits history',
            child: GestureDetector(
              onTap: () async {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AuthGuard(
                          child: CreditsHistory(),
                        ),
                  ),
                );
              },
              child: Container(
                width: scalingFactor * (isTablet(context) ? 150 : 200),
                height: scalingFactor * (isTablet(context) ? 30 : 35),
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
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Credits History",
                            style: TextStyle(
                              fontSize: scalingFactor * (isTablet(context) ? 15 : 20),
                              fontWeight: FontWeight.w400,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      );
                    }
                ),
              ),
            ),
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 25 : 25)),
          Semantics(
            label: 'Submit CME Credits Button',
            hint: 'Tap to submit your CME credits',
            child: GestureDetector(
              onTap: () async {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AuthGuard(
                          child: SubmitCredits(),
                        ),
                  ),
                );
              },
              child: Container(
                width: scalingFactor * (isTablet(context) ? 150 : 200),
                height: scalingFactor * (isTablet(context) ? 30 : 35),
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
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Submit New Credits",
                            style: TextStyle(
                              fontSize: scalingFactor * (isTablet(context) ? 15 : 20),
                              fontWeight: FontWeight.w400,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      );
                    }
                ),
              ),
            ),
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 10)),
        ],
      ),
    );
  }
}

