import 'dart:convert';
import 'dart:math';
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
  bool isTablet(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final diagonal = sqrt(size.width * size.width + size.height * size.height);
    return diagonal > 1100;
  }

  double scaleForDevice(
      BuildContext context,
      double phoneValue,
      double tabletValue,
      ) {
    return isTablet(context) ? tabletValue : phoneValue;
  }

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
                                user,
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

  Widget _buildPortraitLayout(
      BuildContext context,
      baseSize,
      scalingFactor,
      authProvider,
      User user,
      creditsEarned,
      ) {
    final screenWidth = MediaQuery.of(context).size.width;

    double fontBase = screenWidth * scaleForDevice(context, 0.04, 0.032);
    double iconBase = screenWidth * scaleForDevice(context, 0.055, 0.04);
    double cardPadding = screenWidth * scaleForDevice(context, 0.045, 0.03);
    double titleSize = screenWidth * scaleForDevice(context, 0.05, 0.033);

    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(height: screenWidth * 0.08),

            // TOP BUTTONS (unchanged)
            _buildTopButtons(context, scalingFactor, user),

            SizedBox(height: screenWidth * 0.15),

            // ACCOUNT MANAGEMENT CARD
            Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Account Management",
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: screenWidth * 0.03),

                  _buildAccountCard(
                    context,
                    fontBase,
                    iconBase,
                    cardPadding,
                    user,
                  ),
                ],
              ),
            ),

            SizedBox(height: screenWidth * 0.15),
          ],
        ),
      ),
    );
  }

  Widget _buildTopButtons(
      BuildContext context,
      double scalingFactor,
      User user,
      ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildInkWellButton(context, 'Meet The Team', scalingFactor, () async {
              final Uri url = Uri.parse('https://sites.google.com/view/wired-international-team/home');
              if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
            }),
            _buildInkWellButton(context, 'About WiRED', scalingFactor, () async {
              final Uri url = Uri.parse('https://sites.google.com/view/healthmap-about/home');
              if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
            }),
          ],
        ),
        SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildInkWellButton(context, 'Privacy Policy', scalingFactor, () async {
              final Uri url = Uri.parse('https://sites.google.com/view/healthmapprivacypolicy/home');
              if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
            }),
            _buildInkWellButton(context, 'Exams', scalingFactor, () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ExamStart(user: user)),
              );
            }),
          ],
        )
      ],
    );
  }

  Widget _buildAccountCard(
      BuildContext context,
      double fontBase,
      double iconBase,
      double padding,
      User user,
      ) {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFFFCEDDA).withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 3),
          )
        ],
      ),
      child: Column(
        children: [
          _buildAccountRow(
            context,
            icon: Icons.download_outlined,
            label: "Request Data Deletion",
            color: Color(0xFF0070C0),
            fontSize: fontBase,
            iconSize: iconBase,
            padding: padding,
            onTap: () async {
              final Uri deleteAccountUri = Uri.parse(
                  "https://sites.google.com/view/wired-international-healthmap/home");
              if (await canLaunchUrl(deleteAccountUri)) {
                await launchUrl(deleteAccountUri, mode: LaunchMode.externalApplication);
              } else {
                _showCopyDeleteAccountDialog(context);
              }
            },
          ),

          _responsiveDivider(),

          _buildAccountRow(
            context,
            icon: Icons.logout,
            label: "Log out",
            color: Color(0xFF0070C0),
            fontSize: fontBase,
            iconSize: iconBase,
            padding: padding,
            onTap: () {
              Provider.of<AuthProvider>(context, listen: false).logOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => Login()),
              );
            },
          ),

          _responsiveDivider(),

          _buildAccountRow(
            context,
            icon: Icons.delete_outline,
            label: "Delete Account",
            color: Colors.red,
            fontSize: fontBase,
            iconSize: iconBase,
            padding: padding,
            onTap: () async {
              bool confirmDelete = await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text("Delete Account"),
                  content: Text("Are you sure? This cannot be undone."),
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
          ),
        ],
      ),
    );
  }

  Widget _responsiveDivider() {
    return Container(
      height: 1,
      color: Colors.black.withOpacity(0.12),
      margin: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _buildAccountRow(
      BuildContext context, {
        required IconData icon,
        required String label,
        required Color color,
        required double fontSize,
        required double iconSize,
        required double padding,
        required VoidCallback onTap,
      }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: padding * 0.8,
          horizontal: padding,
        ),
        child: Row(
          children: [
            Icon(icon, size: iconSize, color: color),
            SizedBox(width: padding * 0.6),
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                color: color,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInkWellButton(
      BuildContext context,
      String text,
      double scalingFactor,
      VoidCallback onTap,
      ) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    // Use height in landscape, width in portrait
    final base = isLandscape
        ? mediaQuery.size.height     // prevent huge buttons
        : mediaQuery.size.width;

    // Fully responsive values
    double buttonWidth = base * scaleForDevice(context, 0.40, 0.28);
    double buttonHeight = base * scaleForDevice(context, 0.20, 0.14);
    double fontSize = base * scaleForDevice(context, 0.040, 0.026);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.grey.withOpacity(0.25),
        child: Container(
          width: buttonWidth,
          height: buttonHeight,
          decoration: BoxDecoration(
            color: const Color(0xFFFCEDDA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 6,
                offset: const Offset(3, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(
      BuildContext context,
      baseSize,
      double scalingFactor,
      AuthProvider authProvider,
      User user,
      int creditsEarned,
      ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive values
    double fontBase = screenWidth * scaleForDevice(context, 0.03, 0.018);
    double iconBase = screenWidth * scaleForDevice(context, 0.04, 0.025);
    double cardPadding = screenWidth * scaleForDevice(context, 0.035, 0.022);
    double titleSize = screenWidth * scaleForDevice(context, 0.035, 0.022);

    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: screenHeight * 0.04),

            // TOP BUTTON ROWS
            _buildTopButtons(context, scalingFactor, user),

            SizedBox(height: screenHeight * 0.08),

            // ACCOUNT MANAGEMENT
            Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Account Management",
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02),

                  _buildAccountCard(
                    context,
                    fontBase,
                    iconBase,
                    cardPadding,
                    user,
                  ),
                ],
              ),
            ),

            SizedBox(height: screenHeight * 0.08),
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


