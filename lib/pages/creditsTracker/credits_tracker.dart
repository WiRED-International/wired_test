import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../providers/auth_guard.dart';
import '../../providers/auth_provider.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../cme/cme_tracker.dart';
import '../cme/submit_credits.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import 'basicTraining/basic_training_list.dart';

class CreditsTracker extends StatefulWidget {
  const CreditsTracker({super.key});

  @override
  State<CreditsTracker> createState() => _CreditsTrackerState();
}

class _CreditsTrackerState extends State<CreditsTracker> {
  late Future<User> userData;
  final _storage = const FlutterSecureStorage();

  Future<String?> getAuthToken() async {
    return await _storage.read(key: 'authToken');
  }

  Future<User> fetchUserData() async {
    final token = await getAuthToken();
    if (token == null) {
      throw Exception('User is not logged in');
    }
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final apiEndpoint = '/users/me';

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

  @override
  Widget build(BuildContext context) {
    double baseSize = MediaQuery.of(context).size.shortestSide;
    bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // 🌅 Gradient background
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
                Expanded(
                  child: Row(
                    children: [
                      // 🧭 Side nav (landscape only)
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
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => ModuleLibrary()),
                            );
                          },
                          onTrackerTap: () {}, // already here
                          onMenuTap: () async {
                            bool isLoggedIn = await checkIfUserIsLoggedIn();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                isLoggedIn ? Menu() : GuestMenu(),
                              ),
                            );
                          },
                        ),

                      // 🧩 Main content
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(baseSize)
                              : _buildPortraitLayout(baseSize),
                        ),
                      ),
                    ],
                  ),
                ),

                // 📱 Bottom nav (portrait only)
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => ModuleLibrary()),
                      );
                    },
                    onTrackerTap: () {},
                    onMenuTap: () async {
                      bool isLoggedIn = await checkIfUserIsLoggedIn();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                          isLoggedIn ? Menu() : GuestMenu(),
                        ),
                      );
                    },
                  ),
              ],
            ),

            // 📍 Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: CustomAppBar(
                onBackPressed: () {
                  Navigator.pop(context);
                },
                requireAuth: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // 📱 PORTRAIT LAYOUT
  // ============================================
  Widget _buildPortraitLayout(double baseSize) {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: baseSize * (isTablet(context) ? 0.05 : 0.07),
          vertical: baseSize * (isTablet(context) ? 0.05 : 0.06),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: baseSize * 0.08),

            // 🎓 Icon
            Container(
              padding: EdgeInsets.all(baseSize * 0.05),
              decoration: const BoxDecoration(
                color: Color(0xFF0070C0),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.school_rounded,
                color: Colors.white,
                size: baseSize * 0.12,
              ),
            ),

            SizedBox(height: baseSize * 0.05),

            // 🏷️ Title
            Text(
              "Credit Tracking",
              style: TextStyle(
                fontSize: baseSize * (isTablet(context) ? 0.045 : 0.055),
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),

            SizedBox(height: baseSize * 0.02),

            // 📝 Description
            Padding(
              padding: EdgeInsets.symmetric(horizontal: baseSize * 0.04),
              child: Text(
                "Welcome to the Credit Tracking section. Here you can view and manage your training credits and course progress.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.03 : 0.035),
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            ),

            SizedBox(height: baseSize * 0.06),

            // 🔵 Submit Credits Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: Text(
                  "Submit Credits",
                  style: TextStyle(
                    fontSize: baseSize * (isTablet(context) ? 0.035 : 0.04),
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007BFF),
                  padding: EdgeInsets.symmetric(vertical: baseSize * 0.035),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AuthGuard(child: SubmitCredits()),
                    ),
                  );
                },
              ),
            ),

            SizedBox(height: baseSize * 0.03),

            // Divider with "View Your Credits"
            Row(
              children: [
                Expanded(
                  child: Divider(
                    color: Colors.black26,
                    thickness: 1,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: baseSize * 0.02),
                  child: Text(
                    "View Your Credits",
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: baseSize * 0.03,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: Colors.black26,
                    thickness: 1,
                  ),
                ),
              ],
            ),

            SizedBox(height: baseSize * 0.04),

            // 🟦🟩🟪🟧 Credit Cards Grid
            Wrap(
              spacing: baseSize * 0.04,
              runSpacing: baseSize * 0.04,
              alignment: WrapAlignment.center,
              children: [
                _creditCard(
                  label: "CHW Basic Training",
                  color: const Color(0xFF007BFF),
                  icon: Icons.school_rounded,
                  baseSize: baseSize,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AuthGuard(child: BasicTrainingList()),
                      ),
                    );
                  },
                ),
                _creditCard(
                  label: "CME Credits",
                  color: const Color(0xFF22C55E),
                  icon: Icons.health_and_safety_rounded,
                  baseSize: baseSize,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AuthGuard(child: CMETracker()),
                      ),
                    );
                  },
                ),
                _creditCard(
                  label: "Advanced Training",
                  color: const Color(0xFF8B5CF6),
                  icon: Icons.workspace_premium_rounded,
                  baseSize: baseSize,
                  onTap: () {},
                ),
                _creditCard(
                  label: "Specialized Training",
                  color: const Color(0xFFFF6B00),
                  icon: Icons.star_rounded,
                  baseSize: baseSize,
                  onTap: () {},
                ),
              ],
            ),

            SizedBox(height: baseSize * 0.06),

            // 🔐 Footer text
            Text(
              "Your training progress is securely stored and protected",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: baseSize * 0.028,
                color: Colors.black54,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // 💻 LANDSCAPE LAYOUT
  // ============================================
  Widget _buildLandscapeLayout(double baseSize) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: baseSize * (isTablet(context) ? 0.05 : 0.06),
        vertical: baseSize * (isTablet(context) ? 0.04 : 0.05),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🟦 LEFT SIDE — Icon + Text
          Expanded(
            flex: 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 🎓 Icon
                Container(
                  padding: EdgeInsets.all(baseSize * 0.045),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0070C0),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    color: Colors.white,
                    size: baseSize * 0.13,
                  ),
                ),
                SizedBox(height: baseSize * 0.04),

                // 🏷️ Title
                Text(
                  "Credit Tracking",
                  style: TextStyle(
                    fontSize: baseSize * (isTablet(context) ? 0.045 : 0.05),
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),

                SizedBox(height: baseSize * 0.02),

                // 📝 Subtitle
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: baseSize * 0.02),
                  child: Text(
                    "Welcome to the Credit Tracking section. Here you can view and manage your training credits and course progress.",
                    style: TextStyle(
                      fontSize: baseSize * (isTablet(context) ? 0.03 : 0.033),
                      color: Colors.black87,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                SizedBox(height: baseSize * 0.05),

                // 🔐 Footer text
                Text(
                  "Your training progress is securely stored and protected",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: baseSize * 0.025,
                    color: Colors.black54,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(width: baseSize * 0.06),

          // 🟩 RIGHT SIDE — Buttons & Credits
          Expanded(
            flex: 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 🔵 Submit Credits Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    label: Text(
                      "Submit Credits",
                      style: TextStyle(
                        fontSize: baseSize * (isTablet(context) ? 0.035 : 0.04),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007BFF),
                      padding: EdgeInsets.symmetric(vertical: baseSize * 0.035),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      // TODO: Navigation or logic
                    },
                  ),
                ),

                SizedBox(height: baseSize * 0.03),

                // Divider with label
                Row(
                  children: [
                    const Expanded(
                      child: Divider(
                        color: Colors.black26,
                        thickness: 1,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: baseSize * 0.02),
                      child: Text(
                        "View Your Credits",
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: baseSize * 0.03,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Divider(
                        color: Colors.black26,
                        thickness: 1,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: baseSize * 0.04),

                // 🟦🟩🟪🟧 Grid of credit cards
                Wrap(
                  spacing: baseSize * 0.03,
                  runSpacing: baseSize * 0.03,
                  alignment: WrapAlignment.center,
                  children: [
                    _creditCard(
                      label: "CHW Basic Training",
                      color: const Color(0xFF007BFF),
                      icon: Icons.school_rounded,
                      baseSize: baseSize,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AuthGuard(child: BasicTrainingList()),
                          ),
                        );
                      },
                    ),
                    _creditCard(
                      label: "CME Credits",
                      color: const Color(0xFF22C55E),
                      icon: Icons.health_and_safety_rounded,
                      baseSize: baseSize,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AuthGuard(child: CMETracker()),
                          ),
                        );
                      },
                    ),
                    _creditCard(
                      label: "Advanced Training",
                      color: const Color(0xFF8B5CF6),
                      icon: Icons.workspace_premium_rounded,
                      baseSize: baseSize,
                      onTap: () {},
                    ),
                    _creditCard(
                      label: "Specialized Training",
                      color: const Color(0xFFFF6B00),
                      icon: Icons.star_rounded,
                      baseSize: baseSize,
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _creditCard({
    required String label,
    required Color color,
    required IconData icon,
    required double baseSize,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 160,
      height: 80,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 3,
        ),
        icon: Icon(icon, color: Colors.white, size: baseSize * 0.05),
        label: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: baseSize * 0.03,
          ),
        ),
      ),
    );
  }
}

