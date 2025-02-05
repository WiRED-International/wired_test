import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
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
import 'login.dart';



class CreditsHistory extends StatefulWidget {

  @override
  _CreditsHistoryState createState() => _CreditsHistoryState();
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

class _CreditsHistoryState extends State<CreditsHistory> {
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
    // final baseSize = screenSize.shortestSide;
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
                    // Side Navigation Bar for Landscape
                    SizedBox(
                      width: screenSize.width * 0.12, // Adjust width as needed
                      child: CustomSideNavBar(
                        onHomeTap: () => _navigateTo(context, const MyHomePage()),
                        onLibraryTap: () => _navigateTo(context, ModuleLibrary()),
                        onTrackerTap: () => _navigateTo(context, AuthGuard(child: CMETracker())),
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
                    // Right Side Content
                    Expanded(
                      child: Column(
                        children: [
                          LandscapeProfileSection(
                            firstName: user.firstName ?? 'Guest',
                            dateJoined: user.dateJoined ?? 'Unknown',
                          ),
                          Expanded(
                            child: Center(
                              child: _buildLandscapeLayout(
                                context,
                                scalingFactor,
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
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Center(
                              child: _buildPortraitLayout(
                                context,
                                scalingFactor,
                                user.firstName,
                                user.dateJoined,
                                user.quizScores,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Bottom Navigation Bar for Portrait
                    CustomBottomNavBar(
                      onHomeTap: () => _navigateTo(context, const MyHomePage()),
                      onLibraryTap: () => _navigateTo(context, ModuleLibrary()),
                      onTrackerTap: () => _navigateTo(context, AuthGuard(child: CMETracker())),
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
                // Custom AppBar
                Positioned(
                  top: 0,
                  left: 0,
                  child: CustomAppBar(
                    onBackPressed: () {
                      Navigator.pop(context);
                    },
                    requireAuth: true,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

// Navigation Helper Function
  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  Widget _buildPortraitLayout(BuildContext context, scalingFactor, firstName,
      dateJoined, quizScores) {
    // Sort quizScores by date (latest first)
    quizScores?.sort((a, b) => DateTime.parse(b['date_taken']).compareTo(
        DateTime.parse(a['date_taken'])));

    // Format the date using intl
    final dateFormatter = DateFormat(
        'MMM dd, yyyy hh:mm a'); // Example: Jan 21, 2025 08:41 AM

    return Column(
      children: <Widget>[
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 25 : 25),
        ),
        Text(
          "Submitted CME History",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: scalingFactor * (isTablet(context) ? 22 : 28),
            fontWeight: FontWeight.w400,
            color: Color(0xFF325BFF),
          ),
        ),
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 5 : 5),
        ),
        Flexible(
            child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 5 : 3)),
                    child: Container(
                        child: quizScores != null && quizScores.isNotEmpty
                            ? ListView.builder(
                            itemCount: quizScores.length + 1,
                            // +1 for the extra space at the end
                            itemBuilder: (context, index) {
                              if (index == quizScores.length) {
                                return SizedBox(height: scalingFactor * (isTablet(context) ? 55 : 55)); // Extra space at the end
                              }
                              final quiz = quizScores[index];
                              final module = quiz['module'];
                              final dateTaken = quiz['date_taken'];
                              final formattedDate = dateFormatter.format(
                                  DateTime.parse(dateTaken));

                              return ListTile(
                                title: Text(
                                  module != null && module['name'] != null
                                      ? module['name']
                                      : 'Unknown',
                                  style: TextStyle(
                                    fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                subtitle: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: scalingFactor * (isTablet(context) ? 12 : 16),
                                      color: Colors.black, // Default text color
                                    ),
                                    children: [
                                      const TextSpan(
                                        text: 'Score: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500, // Bold for title
                                        ),
                                      ),
                                      TextSpan(
                                        text: '${double.parse(quiz['score']).toStringAsFixed(2)}%\n',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.normal, // Regular for value
                                        ),
                                      ),
                                      const TextSpan(
                                        text: 'Module ID: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500, // Bold for title
                                        ),
                                      ),
                                      TextSpan(
                                        text: module != null &&
                                            module['module_id'] != null
                                            ? module['module_id'].toString()
                                            : 'N/A',
                                        style: const TextStyle(
                                          color: Color(0xFF325BFF),
                                          // Custom color
                                          fontWeight: FontWeight.normal, // Regular for value
                                        ),
                                      ),
                                      const TextSpan(
                                        text: '\nDate Submitted: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight
                                              .w500, // Bold for title
                                        ),
                                      ),
                                      TextSpan(
                                        text: formattedDate,
                                        style: const TextStyle(
                                          fontWeight: FontWeight
                                              .normal, // Regular for value
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                        )
                            : Center(
                          child: Text(
                            "No completed credits",
                            style: TextStyle(
                              fontSize: scalingFactor *
                                  (isTablet(context) ? 24 : 24),
                              fontWeight: FontWeight.w300,
                              color: Colors.black,
                            ),
                          ),
                        )
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.0, 1.0],
                              colors: [
                                // Colors.transparent,
                                // Color(0xFFFFF0DC),
                                //Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
                                Color(0xFFFECF97).withOpacity(0.0),
                                Color(0xFFFECF97),
                              ],
                            ),
                          )
                      ),
                    ),
                  ),
                ]
            )
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(BuildContext context, scalingFactor, firstName,
      dateJoined, quizScores) {

    // Format the date using intl
    quizScores?.sort((a, b) => DateTime.parse(b['date_taken']).compareTo(
        DateTime.parse(a['date_taken'])));

    // Format the date using intl
    final dateFormatter = DateFormat(
        'MMM dd, yyyy hh:mm a'); // Example: Jan 21, 2025 08:41 AM

    return Column(
      children: <Widget>[
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 20 : 10),
        ),
        Text(
          "Submitted CME History",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: scalingFactor * (isTablet(context) ? 20 : 24),
            fontWeight: FontWeight.w400,
            color: Color(0xFF325BFF),
          ),
        ),
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 10 : 2),
        ),
        Flexible(
            child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 30 : 40)),
                    child: Container(
                        child: quizScores != null && quizScores.isNotEmpty
                            ? ListView.builder(
                            itemCount: quizScores.length + 1,
                            // +1 for the extra space at the end
                            itemBuilder: (context, index) {
                              if (index == quizScores.length) {
                                return SizedBox(height: scalingFactor * (isTablet(context) ? 55 : 55)); // Extra space at the end
                              }
                              final quiz = quizScores[index];
                              final module = quiz['module'];
                              final dateTaken = quiz['date_taken'];
                              final formattedDate = dateFormatter.format(
                                  DateTime.parse(dateTaken));

                              return ListTile(
                                title: Text(
                                  module != null && module['name'] != null
                                      ? module['name']
                                      : 'Unknown',
                                  style: TextStyle(
                                    fontSize: scalingFactor * (isTablet(context) ? 12 : 14),
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                subtitle: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: scalingFactor * (isTablet(context) ? 10 : 12),
                                      color: Colors.black, // Default text color
                                    ),
                                    children: [
                                      TextSpan(
                                        text: 'Score: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight
                                              .w500, // Bold for title
                                        ),
                                      ),
                                      TextSpan(
                                        text: '${quiz['score']}%\n',
                                        style: TextStyle(
                                          fontWeight: FontWeight
                                              .normal, // Regular for value
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'Module ID: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight
                                              .w500, // Bold for title
                                        ),
                                      ),
                                      TextSpan(
                                        text: module != null &&
                                            module['module_id'] != null
                                            ? module['module_id']
                                            : 'N/A',
                                        style: TextStyle(
                                          color: Color(0xFF325BFF),
                                          // Custom color
                                          fontWeight: FontWeight
                                              .normal, // Regular for value
                                        ),
                                      ),
                                      TextSpan(
                                        text: '\nDate Submitted: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight
                                              .w500, // Bold for title
                                        ),
                                      ),
                                      TextSpan(
                                        text: formattedDate,
                                        style: TextStyle(
                                          fontWeight: FontWeight
                                              .normal, // Regular for value
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                        )
                            : Center(
                          child: Text(
                            "No completed credits",
                            style: TextStyle(
                              fontSize: scalingFactor *
                                  (isTablet(context) ? 24 : 24),
                              fontWeight: FontWeight.w300,
                              color: Colors.black,
                            ),
                          ),
                        )
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.0, 1.0],
                              colors: [
                                // Colors.transparent,
                                // Color(0xFFFFF0DC),
                                //Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
                                Color(0xFFFECF97).withOpacity(0.0),
                                Color(0xFFFECF97),
                              ],
                            ),
                          )
                      ),
                    ),
                  ),
                ]
            )
        ),
      ],
    );
  }
}