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

    _buttonColors = {
      "Credits History": [
        Color(0xFF6B72FF),
        Color(0xFF325BFF),
        Color(0xFF6B72FF),
      ],
      "Submit New Credits": [
        Color(0xFF6B72FF),
        Color(0xFF325BFF),
        Color(0xFF6B72FF),
      ],
    };

    _buttonScales = {
      "Credits History": 1.0,
      "Submit New Credits": 1.0,
    };
  }

  Map<String, double> _buttonScales = {};
  Map<String, List<Color>> _buttonColors = {};

  void _onTapDown(String label) {
    setState(() {
      _buttonScales[label] = 0.95; // Slightly shrink the button on press
      _buttonColors[label] = [
        _buttonColors[label]![0].withOpacity(0.8), // Slightly dim the color
        _buttonColors[label]![1].withOpacity(0.8),
        _buttonColors[label]![2].withOpacity(0.8),
      ];
    });
  }

  void _onTapUp(String label, VoidCallback onTap) {
    setState(() {
      _buttonScales[label] = 1.0; // Restore button size
      _buttonColors[label] = [
        _buttonColors[label]![0].withOpacity(1.0), // Restore original color
        _buttonColors[label]![1].withOpacity(1.0),
        _buttonColors[label]![2].withOpacity(1.0),
      ];
    });

    onTap(); // Execute the actual button function
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
                      creditsEarned: user.quizScores != null ? user.quizScores!.length * 5 : 0,
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
    }).length * 20 : 0;

    final int maxCredits = getMaxCredits(creditsEarned);
    final int creditsRemaining = creditsEarned >= maxCredits ? 0 : maxCredits - creditsEarned;

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
                children: _buildConditionalText(creditsEarned, creditsRemaining, scalingFactor),
              ),
            ),
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 40 : 40)),

          // Credits History Button with New Style
          _buildSearchButton(
            label: "Credits History",
            gradientColors: [
              Color(0xFF6B72FF),
              Color(0xFF325BFF),
              Color(0xFF6B72FF),
            ],
            onTap: () async {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AuthGuard(child: CreditsHistory()),
                ),
              );
            },
            scalingFactor: scalingFactor,
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 40)),

          // Submit New Credits Button with New Style
          _buildSearchButton(
            label: "Submit New Credits",
            gradientColors: [
              Color(0xFF6B72FF),
              Color(0xFF325BFF),
              Color(0xFF6B72FF),
            ],
            onTap: () async {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AuthGuard(child: SubmitCredits()),
                ),
              );
            },
            scalingFactor: scalingFactor,
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 70 : 70)),
        ],
      ),
    );
  }

  // Helper method to build text spans for the badge message
  List<TextSpan> _buildConditionalText(int creditsEarned, int creditsRemaining, double scalingFactor) {
    String message = getNextBadgeMessage(creditsEarned, creditsRemaining);

    // If both placeholders are present
    if (message.contains("$creditsEarned") && message.contains("$creditsRemaining")) {
      return [
        TextSpan(text: message.split("$creditsEarned")[0]),
        TextSpan(
          text: "$creditsEarned credits",
          style: TextStyle(color: Color(0xFFBD34FD)),
        ),
        TextSpan(text: message.split("$creditsEarned")[1].split("$creditsRemaining")[0]),
        TextSpan(
          text: "$creditsRemaining credits",
          style: TextStyle(color: Color(0xFFBD34FD)),
        ),
        TextSpan(text: message.split("$creditsRemaining").last),
      ];
    }

    // If only creditsEarned placeholder is present
    if (message.contains("$creditsEarned")) {
      final parts = message.split("$creditsEarned");
      return [
        TextSpan(text: parts[0]),
        TextSpan(
          text: "$creditsEarned credits",
          style: TextStyle(color: Color(0xFFBD34FD)),
        ),
        TextSpan(text: parts.length > 1 ? parts[1] : ""),
      ];
    }

    // No placeholders present (likely for Supreme rank message)
    return [
      TextSpan(text: message),
    ];
  }



  Widget _buildSearchButton({
    required String label,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    required double scalingFactor,
  }) {
    return Semantics(
      label: '$label Button',
      hint: 'Tap to access $label',
      child: FractionallySizedBox(
        widthFactor: isTablet(context) ? 0.45 : 0.6,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          child: GestureDetector(
            onTapDown: (_) => _onTapDown(label),
            onTapUp: (_) => _onTapUp(label, onTap),
            onTapCancel: () {
              setState(() {
                _buttonScales[label] = 1.0;
                _buttonColors[label] = [
                  _buttonColors[label]![0].withOpacity(1.0), // Restore original
                  _buttonColors[label]![1].withOpacity(1.0),
                  _buttonColors[label]![2].withOpacity(1.0),
                ];
              });
            },
            child: AnimatedContainer(
              duration: Duration(milliseconds: 100),
              curve: Curves.easeOut,
              transform: Matrix4.diagonal3Values(
                  _buttonScales[label] ?? 1.0, _buttonScales[label] ?? 1.0, 1.0),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(30),
                splashColor: Colors.white.withOpacity(0.3),
                child: Container(
                  height: scalingFactor * (isTablet(context) ? 35 : 45),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _buttonColors[label] ?? gradientColors,
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: Offset(1, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 17 : 20),
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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

          SizedBox(height: scalingFactor * (isTablet(context) ? 25 : 25)),
          _buildSearchButtonLandscape(
            label: "Credits History",
            gradientColors: [
              Color(0xFF6B72FF),
              Color(0xFF325BFF),
              Color(0xFF6B72FF),
            ],
            onTap: () async {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AuthGuard(child: CreditsHistory()),
                ),
              );
            },
            scalingFactor: scalingFactor,
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 40)),

          // Submit New Credits Button with New Style
          _buildSearchButtonLandscape(
            label: "Submit New Credits",
            gradientColors: [
              Color(0xFF6B72FF),
              Color(0xFF325BFF),
              Color(0xFF6B72FF),
            ],
            onTap: () async {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AuthGuard(child: SubmitCredits()),
                ),
              );
            },
            scalingFactor: scalingFactor,
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 10)),
        ],
      ),
    );
  }

  Widget _buildSearchButtonLandscape({
    required String label,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    required double scalingFactor,
  }) {
    return Semantics(
      label: '$label Button',
      hint: 'Tap to access $label',
      child: FractionallySizedBox(
        widthFactor: isTablet(context) ? 0.35 : 0.5, // Adjust width for landscape
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(25),
          child: GestureDetector(
            onTapDown: (_) => _onTapDown(label),
            onTapUp: (_) => _onTapUp(label, onTap),
            onTapCancel: () {
              setState(() {
                _buttonScales[label] = 1.0;
                _buttonColors[label] = [
                  _buttonColors[label]![0].withOpacity(1.0),
                  _buttonColors[label]![1].withOpacity(1.0),
                  _buttonColors[label]![2].withOpacity(1.0),
                ];
              });
            },
            child: AnimatedContainer(
              duration: Duration(milliseconds: 100),
              curve: Curves.easeOut,
              transform: Matrix4.diagonal3Values(
                  _buttonScales[label] ?? 1.0, _buttonScales[label] ?? 1.0, 1.0),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(25),
                splashColor: Colors.white.withOpacity(0.3),
                child: Container(
                  height: scalingFactor * (isTablet(context) ? 30 : 35), // Reduced height for landscape
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _buttonColors[label] ?? gradientColors,
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: Offset(1, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 14 : 18), // Slightly smaller font size
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

