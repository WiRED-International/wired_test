import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
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
import '../creditsTracker/credits_tracker.dart';
import '../exam/exam_start.dart';
import '../home_page.dart';
import '../module_library.dart';
import '../../models/user.dart';


class Menu extends StatefulWidget {
  final void Function(Locale)? onLocaleChange;

  const Menu({Key? key, this.onLocaleChange}) : super(key: key);

  @override
  _MenuState createState() => _MenuState();
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
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final apiEndpoint = '/users/me';

    final token = await getAuthToken();
    if (token == null) {
      throw Exception('User is not logged in');
    }

    final url = Uri.parse('$apiBaseUrl$apiEndpoint');
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

  Future<void> deleteAccount(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.authToken;

    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final apiEndpoint = '/auth/delete-account';

    if (token == null) {
      print("Error: No authentication token found.");
      return;
    }

    final response = await http.delete(
      Uri.parse('$apiBaseUrl$apiEndpoint'),
      headers: {
        'Authorization': 'Bearer $token', // Only send the token
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      print("Account deleted successfully.");
      authProvider.logOut();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => Login()),
        );
      }
    } else {
      print("Error: ${response.body}");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete account. Please try again.")),
        );
      }
    }
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
                              builder: (context) =>
                                  AuthGuard(
                                    child: CreditsTracker(),
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
                            creditsEarned: creditsEarned,
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
                    Expanded(
                      child: Center(
                        child: _buildPortraitLayout(
                          context,
                          baseSize,
                          scalingFactor,
                          authProvider,
                          user,
                          creditsEarned,
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
                            builder: (context) =>
                                AuthGuard(
                                  child: CreditsTracker(),
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


// Navigation Helper
  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  Widget _buildPortraitLayout(BuildContext context, baseSize, scalingFactor,
      authProvider, User user, creditsEarned) {
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 40)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildInkWellButton(context, 'Meet The Team', scalingFactor, () async {
                  final Uri url = Uri.parse('https://sites.google.com/view/wired-international-team/home');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not launch Meet The Team')),
                    );
                  }
                }),
                _buildInkWellButton(context, 'About WiRED', scalingFactor, () async {
                  final Uri url = Uri.parse('https://sites.google.com/view/healthmap-about/home');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not launch About WiRED')),
                    );
                  }
                }),
              ],
            ),
            SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 30)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildInkWellButton(context, 'Privacy Policy', scalingFactor, () async {
                  final Uri url = Uri.parse('https://sites.google.com/view/healthmapprivacypolicy/home');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not launch Privacy Policy')),
                    );
                  }
                }),
                _buildInkWellButton(context, 'Exams', scalingFactor, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ExamStart(user: user),
                    ),
                  );
                }),
              ],
            ),
            SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 70)),
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
                      left: scalingFactor * (isTablet(context) ? 20 : 15)),
                  child: Text(
                    'Log out',
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 16 : 18),
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
            GestureDetector(
              onTap: () async {
                bool confirmDelete = await showDialog(
                  context: context,
                  builder: (context) =>
                      AlertDialog(
                        title: Text("Delete Account"),
                        content: Text(
                            "Are you sure you want to delete your account? This action cannot be undone."),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text("Cancel"),
                          ),
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(context, true);
                              await deleteAccount(context);
                            },
                            child: Text("Delete"),
                          ),
                        ],
                      ),
                );

                if (confirmDelete == true) {
                  await deleteAccount(context);
                }
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(
                      left: scalingFactor * (isTablet(context) ? 20 : 15)),
                  child: Text(
                    'Delete Account',
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 16 : 18),
                      fontWeight: FontWeight.w400,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: scalingFactor * (isTablet(context) ? 30 : 30),
            ),
            GestureDetector(
              onTap: () async {
                final Uri deleteAccountUri = Uri.parse("https://sites.google.com/view/wired-international-healthmap/home");

                if (await canLaunchUrl(deleteAccountUri)) {
                  await launchUrl(deleteAccountUri, mode: LaunchMode.externalApplication);
                } else {
                  print("Could not open the delete account request page");
                  _showCopyDeleteAccountDialog(context);
                }
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 60 : 15)),
                  child: Text(
                    'Request Data Deletion',
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 15 : 18),
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF0070C0),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: scalingFactor * (isTablet(context) ? 20 : 30),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInkWellButton(BuildContext context, String text,
      double scalingFactor, VoidCallback onTap) {
    return Material(
      color: Colors.transparent, // Ensures ripple effect works
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        // Rounded edges for ripple effect
        splashColor: Colors.grey.withOpacity(0.3),
        // Light splash effect
        child: Container(
          height: scalingFactor * (isTablet(context) ? 80 : 90),
          width: scalingFactor * (isTablet(context) ? 150 : 165),
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
                fontSize: scalingFactor * (isTablet(context) ? 13 : 15),
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
      height: scalingFactor * (isTablet(context) ? 80 : 90),
      width: scalingFactor * (isTablet(context) ? 150 : 165),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.transparent, // Invisible placeholder
      ),
    );
  }


  Widget _buildLandscapeLayout(BuildContext context, baseSize, scalingFactor,
      authProvider, firstName, dateJoined, creditsEarned) {
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(height: scalingFactor * (isTablet(context) ? 20 : 20)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildInkWellButton(context, 'Meet The Team', scalingFactor, () async {
                  final Uri url = Uri.parse('https://sites.google.com/view/wired-international-team/home');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not launch Meet The Team')),
                    );
                  }
                }),
                _buildInkWellButton(context, 'About WiRED', scalingFactor, () async {
                  final Uri url = Uri.parse('https://sites.google.com/view/healthmap-about/home');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not launch About WiRED')),
                    );
                  }
                }),
              ],
            ),
            SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildInkWellButton(context, 'Privacy Policy', scalingFactor, () async {
                  final Uri url = Uri.parse('https://sites.google.com/view/healthmapprivacypolicy/home');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not launch Privacy Policy')),
                    );
                  }
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
                      left: scalingFactor * (isTablet(context) ? 60 : 55)),
                  child: Text(
                    'Log out',
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 15 : 16),
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF0070C0),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: scalingFactor * (isTablet(context) ? 15 : 15),
            ),
            GestureDetector(
              onTap: () async {
                bool confirmDelete = await showDialog(
                  context: context,
                  builder: (context) =>
                      AlertDialog(
                        title: Text("Delete Account"),
                        content: Text(
                            "Are you sure you want to delete your account? This action cannot be undone."),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text("Cancel"),
                          ),
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(context, true);
                              await deleteAccount(context);
                            },
                            child: Text("Delete"),
                          ),
                        ],
                      ),
                );

                if (confirmDelete == true) {
                  await deleteAccount(context);
                }
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(
                      left: scalingFactor * (isTablet(context) ? 60 : 55)),
                  child: Text(
                    'Delete Account',
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 15 : 16),
                      fontWeight: FontWeight.w400,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: scalingFactor * (isTablet(context) ? 15 : 15),
            ),
            GestureDetector(
              onTap: () async {
                final Uri deleteAccountUri = Uri.parse("https://sites.google.com/view/wired-international-healthmap/home");

                if (await canLaunchUrl(deleteAccountUri)) {
                  await launchUrl(deleteAccountUri, mode: LaunchMode.externalApplication);
                } else {
                  print("Could not open the delete account request page");
                  _showCopyDeleteAccountDialog(context);
                }
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 60 : 55)),
                  child: Text(
                    'Request Data Deletion',
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 15 : 16),
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
      ),
    );
  }

  void _showCopyDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Unable to Open Link"),
        content: SelectableText(
          "Please manually open this link in your browser:\n\nhttps://docs.google.com/document/d/YOUR_DOCUMENT_ID/view",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: "https://sites.google.com/view/wired-international-healthmap/home"));
              Navigator.of(context, rootNavigator: true).pop(); // Close dialog
            },
            child: Text("Copy Link"),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pop(); // Close dialog
            },
            child: Text("Close"),
          ),
        ],
      ),
    );
  }
}


