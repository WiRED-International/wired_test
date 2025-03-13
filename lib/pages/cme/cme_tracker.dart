import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:wired_test/pages/cme/submit_credits.dart';
import '../../providers/auth_guard.dart';
import '../../providers/auth_provider.dart';
import '../../utils/creditText.dart';
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
  final int creditsEarned;


  User({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.dateJoined,
    required this.quizScores,
  }): creditsEarned = _calculateCredits(quizScores ?? []);

  factory User.fromJson(Map<String, dynamic> json) {
    List<dynamic>? quizScores = json['quizScores'] ?? [];
    return User(
      firstName: json['first_name'] ?? 'Unknown',
      lastName: json['last_name'] ?? 'Unknown',
      email: json['email'] ?? 'No email',
      dateJoined: json['createdAt'] ?? 'Unknown Date',
      quizScores: quizScores, // Provide an empty list for quizScores if null
    );
  }

  Map<String, dynamic> toJson() => {
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'dateJoined': dateJoined,
    'quizScores': quizScores,
  };

  // Method to calculate creditsEarned
  static int _calculateCredits(List<dynamic>? quizScores) {
    final int currentYear = DateTime.now().year;

    if (quizScores == null) return 0;

    return quizScores.where((score) {
      if (score is Map<String, dynamic> &&
          score['score'] != null &&
          score['date_taken'] != null) {
        final scoreValue = double.tryParse(score['score'].toString()) ?? 0.0;
        final DateTime? dateTaken = DateTime.tryParse(score['date_taken'].toString());

        return scoreValue >= 80.0 &&
            dateTaken != null &&
            dateTaken.year == currentYear;
      }
      return false;
    }).length * 5;
  }
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
        _buttonColors[label]![0].withValues(alpha: 0.8),
        _buttonColors[label]![1].withValues(alpha: 0.8),
        _buttonColors[label]![2].withValues(alpha: 0.8),
      ];
    });
  }

  void _onTapUp(String label, VoidCallback onTap) {
    setState(() {
      _buttonScales[label] = 1.0; // Restore button size
      _buttonColors[label] = [
        _buttonColors[label]![0].withValues(alpha: 1.0), // Restore original color
        _buttonColors[label]![1].withValues(alpha: 1.0),
        _buttonColors[label]![2].withValues(alpha: 1.0),
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
    final remoteServer = dotenv.env['REMOTE_SERVER']!;
    final localServer = dotenv.env['LOCAL_SERVER']!;

    final apiEndpoint = '/users/me';

    final url = Uri.parse('$remoteServer$apiEndpoint');
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
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final scalingFactor = getScalingFactor(context);

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
            final int creditsEarned = user.creditsEarned ?? 0;
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
                      // width: screenSize.width * 0.12, // Adjust width as needed
                      width: scalingFactor * (isTablet(context) ? 55 : 58),
                      child: CustomSideNavBar(
                        onHomeTap: () => _navigateTo(context, const MyHomePage()),
                        onLibraryTap: () => _navigateTo(context, ModuleLibrary()),
                        onTrackerTap: () {},
                        onMenuTap: () async {
                          bool isLoggedIn = await checkIfUserIsLoggedIn();
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
                            creditsEarned: creditsEarned,
                          ),
                          SizedBox(height: scalingFactor * (isTablet(context) ? 15 : 15)),
                          Expanded(
                            child: Center(
                              child: _buildLandscapeLayout(
                                context,
                                scalingFactor,
                                authProvider,
                                user.firstName,
                                user.dateJoined,
                                user.quizScores,
                                creditsEarned,
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
                      creditsEarned: creditsEarned,
                    ),
                    //SizedBox(height: screenSize.height * (isTabletDevice ? 0.05 : .04)),
                    SizedBox(height: scalingFactor * (isTablet(context) ? 25 : 40)),
                    Expanded(
                      child: Center(
                        child: _buildPortraitLayout(
                          context,
                          scalingFactor,
                          authProvider,
                          user.firstName,
                          user.dateJoined,
                          user.quizScores,
                          creditsEarned,
                        ),
                      ),
                    ),
                    CustomBottomNavBar(
                      onHomeTap: () => _navigateTo(context, const MyHomePage()),
                      onLibraryTap: () => _navigateTo(context, ModuleLibrary()),
                      onTrackerTap: () {},
                      onMenuTap: () async {
                        bool isLoggedIn = await checkIfUserIsLoggedIn();
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
      authProvider, firstName, dateJoined, quizScores, int creditsEarned) {
    // Get the current year
    final int currentYear = DateTime.now().year;

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
              minHeight: scalingFactor * (isTablet(context) ? 8 : 10),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 25 : 25)),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: scalingFactor * (isTablet(context) ? 40 : 20),
            ),
            child: CreditText(
              creditsEarned: creditsEarned,
              creditsRemaining: creditsRemaining,
              scalingFactor: scalingFactor,
              context: context,
            ),
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 30)),

          // Credits History Button with New Style
          _buildButton(
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
          SizedBox(height: scalingFactor * (isTablet(context) ? 20 : 25)),

          // Submit New Credits Button with New Style
          _buildButton(
            label: "Submit Credits",
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


  Widget _buildButton({
    required String label,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    required double scalingFactor,
  }) {
    return Semantics(
      label: '$label Button',
      hint: 'Tap to access $label',
      child: FractionallySizedBox(
        widthFactor: isTablet(context) ? 0.38 : 0.5,
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
                  _buttonColors[label]![0].withValues(alpha: 1.0), // Restore original
                  _buttonColors[label]![1].withValues(alpha: 1.0),
                  _buttonColors[label]![2].withValues(alpha: 1.0),
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
                splashColor: Colors.white.withValues(alpha: 0.3),
                child: Container(
                  height: scalingFactor * (isTablet(context) ? 32 : 38),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _buttonColors[label] ?? gradientColors,
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
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
                        fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
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
      authProvider, firstName, dateJoined, quizScores, int creditsEarned) {
    final int currentYear = DateTime.now().year;

    final int maxCredits = getMaxCredits(creditsEarned);
    final int creditsRemaining = creditsEarned >= maxCredits ? 0 : maxCredits - creditsEarned;

    return SingleChildScrollView(
      child: Column(
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
          SizedBox(height: scalingFactor * (isTablet(context) ? 15 : 15)),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: scalingFactor * (isTablet(context) ? 55 : 65)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "CREDITS",
                  style: TextStyle(
                    fontSize: scalingFactor * (isTablet(context) ? 12 : 15),
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
                              (isTablet(context) ? 12 : 15),
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFBD34FD), // Purple for earned credits
                        ),
                      ),
                      TextSpan(
                        text: "/$maxCredits",
                        style: TextStyle(
                          fontSize: scalingFactor * (isTablet(context) ? 12 : 15),
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
            child: CreditText(
              creditsEarned: creditsEarned,
              creditsRemaining: creditsRemaining,
              scalingFactor: scalingFactor,
              context: context,
            ),
          ),

          SizedBox(height: scalingFactor * (isTablet(context) ? 25 : 25)),
          _buildButtonLandscape(
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
          SizedBox(height: scalingFactor * (isTablet(context) ? 25 : 25)),
          // Submit New Credits Button with New Style
          _buildButtonLandscape(
            label: "Submit Credits",
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

  Widget _buildButtonLandscape({
    required String label,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    required double scalingFactor,
  }) {
    return Semantics(
      label: '$label Button',
      hint: 'Tap to access $label',
      child: FractionallySizedBox(
        widthFactor: isTablet(context) ? 0.3 : 0.4, // Adjust width for landscape
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
                  _buttonColors[label]![0].withValues(alpha: 1.0),
                  _buttonColors[label]![1].withValues(alpha: 1.0),
                  _buttonColors[label]![2].withValues(alpha: 1.0),
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
                splashColor: Colors.white.withValues(alpha: 0.3),
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
                        color: Colors.black.withValues(alpha: 0.5),
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

