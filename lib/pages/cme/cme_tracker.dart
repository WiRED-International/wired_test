import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../providers/auth_guard.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../../utils/app_layout.dart';
import '../creditsTracker/credits_tracker.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import 'credits_history.dart';
import '../../models/user.dart';
import '../../models/cme_credit_totals.dart';
import 'cme_totals_card.dart';
import '../../../providers/quiz_score_provider.dart';

class CMETracker extends StatefulWidget {
  const CMETracker({super.key, this.loadUser});

  final Future<User> Function()? loadUser;

  @override
  State<CMETracker> createState() => _CMETrackerState();
}

class _CMETrackerState extends State<CMETracker> {
  final _storage = const FlutterSecureStorage();
  late Future<User> userData;

  @override
  void initState() {
    super.initState();
    userData = fetchUserData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<QuizScoreProvider>(context, listen: false).fetchQuizScores();
    });
  }

  Future<String?> getAuthToken() async {
    return await _storage.read(key: 'authToken');
  }

  Future<User> fetchUserData() async {
    if (widget.loadUser != null) return widget.loadUser!();
    final token = await getAuthToken();
    if (token == null) throw Exception('User not logged in');

    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final url = Uri.parse('$apiBaseUrl/users/me');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return User.fromJson(json);
    } else {
      throw Exception('Failed to fetch user data: ${response.statusCode}');
    }
  }

  // ✅ Refresh user + quiz scores
  Future<void> refreshData() async {
    setState(() {
      userData = fetchUserData();
    });
    await Future.wait([
      userData,
      Provider.of<QuizScoreProvider>(context, listen: false).fetchQuizScores(),
    ]);
  }

  // =====================================================
  // 🧭 Main Build
  // =====================================================
  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final baseSize = mediaQuery.size.shortestSide;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final isTabletDevice = isTablet(context);
    final scale = isTabletDevice ? 1.0 : 1.0;

    return AppLayout(
      appBar: CustomAppBar(
        onBackPressed: () => Navigator.pop(context),
        requireAuth: false,
        scale: scale,
      ),

      bottomNav: isLandscape
          ? null
          : CustomBottomNavBar(
              onHomeTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyHomePage()),
              ),
              onLibraryTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ModuleLibrary()),
              ),
              onTrackerTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AuthGuard(child: CreditsTracker()),
                ),
              ),
              onMenuTap: () async {
                bool isLoggedIn = await checkIfUserIsLoggedIn();
                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        isLoggedIn ? const Menu() : const GuestMenu(),
                  ),
                );
              },
              scale: scale,
            ),

      // ❗ NO Center()
      child: isLandscape
          ? Row(
              children: [
                CustomSideNavBar(
                  onHomeTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyHomePage()),
                  ),
                  onLibraryTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ModuleLibrary()),
                  ),
                  onTrackerTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AuthGuard(child: CreditsTracker()),
                    ),
                  ),
                  onMenuTap: () async {
                    bool isLoggedIn = await checkIfUserIsLoggedIn();
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            isLoggedIn ? const Menu() : const GuestMenu(),
                      ),
                    );
                  },
                  scale: scale,
                ),
                Expanded(
                  child: FutureBuilder<User>(
                    future: userData,
                    builder: (context, userSnapshot) {
                      if (userSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (userSnapshot.hasError) {
                        return Center(
                            child: Text('Error: ${userSnapshot.error}'));
                      }

                      final user = userSnapshot.data!;
                      final totals = user.cmeCredits;

                      return Consumer<QuizScoreProvider>(
                        builder: (context, quizProvider, child) {
                          final quizScores = List<Map<String, dynamic>>.from(
                              quizProvider.quizScores);

                          final cmeScores = quizScores
                              .where((q) =>
                                  (q['credit_type']?.toString().toLowerCase() ==
                                      'cme'))
                              .toList();

                          cmeScores.sort((a, b) => (b['date_taken'] ?? '')
                              .compareTo(a['date_taken'] ?? ''));

                          final recentCredits = cmeScores.take(3).toList();

                          final orientation =
                              MediaQuery.of(context).orientation;

                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            switchInCurve: Curves.easeIn,
                            switchOutCurve: Curves.easeOut,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                    opacity: animation, child: child),
                            child: orientation == Orientation.landscape
                                ? KeyedSubtree(
                                    key: const ValueKey('landscape'),
                                    child: _buildLandscapeLayout(
                                      context,
                                      screenWidth,
                                      screenHeight,
                                      baseSize,
                                      scale,
                                      totals,
                                      recentCredits,
                                    ),
                                  )
                                : KeyedSubtree(
                                    key: const ValueKey('portrait'),
                                    child: _buildPortraitLayout(
                                      context,
                                      screenWidth,
                                      screenHeight,
                                      baseSize,
                                      scale,
                                      totals,
                                      recentCredits,
                                    ),
                                  ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            )
          : FutureBuilder<User>(
              future: userData,
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (userSnapshot.hasError) {
                  return Center(child: Text('Error: ${userSnapshot.error}'));
                }

                final user = userSnapshot.data!;
                final totals = user.cmeCredits;

                return Consumer<QuizScoreProvider>(
                  builder: (context, quizProvider, child) {
                    final quizScores = List<Map<String, dynamic>>.from(
                        quizProvider.quizScores);

                    final cmeScores = quizScores
                        .where((q) =>
                            (q['credit_type']?.toString().toLowerCase() ==
                                'cme'))
                        .toList();

                    cmeScores.sort((a, b) => (b['date_taken'] ?? '')
                        .compareTo(a['date_taken'] ?? ''));

                    final recentCredits = cmeScores.take(3).toList();

                    return _buildPortraitLayout(
                      context,
                      screenWidth,
                      screenHeight,
                      baseSize,
                      scale,
                      totals,
                      recentCredits,
                    );
                  },
                );
              },
            ),
    );
  }

  // =====================================================
  // 📱 Portrait Layout
  // =====================================================
  Widget _buildPortraitLayout(
    BuildContext context,
    double screenWidth,
    double screenHeight,
    double baseSize,
    double scale,
    CmeCreditTotals totals,
    List<Map<String, dynamic>> recentCredits,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        await refreshData();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Refresh complete.'),
            backgroundColor: Color(0xFF16A34A),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: baseSize * 0.07 * scale,
          vertical: baseSize * 0.03 * scale,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              "CME Credits",
              style: TextStyle(
                fontSize: baseSize * 0.055 * scale,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: baseSize * 0.01 * scale),
            Text(
              "Track your Continuing Medical Education progress",
              style: TextStyle(
                fontSize: baseSize * 0.032 * scale,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: baseSize * 0.05 * scale),

            CmeTotalsCard(totals: totals),

            SizedBox(height: baseSize * 0.04 * scale),
            Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => CreditsHistory()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  padding: EdgeInsets.symmetric(
                    horizontal: baseSize * 0.1 * scale,
                    vertical: baseSize * 0.025 * scale,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.history, color: Colors.white),
                label: Text(
                  "View Complete CME History",
                  style: TextStyle(
                    fontSize: baseSize * 0.035 * scale,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            SizedBox(height: baseSize * 0.05 * scale),
            // Recent credits
            Text(
              "Recent Quiz Submissions",
              style: TextStyle(
                fontSize: baseSize * 0.045 * scale,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: baseSize * 0.02 * scale),
            Column(
              children: recentCredits
                  .map((credit) => _buildCreditCard(baseSize, credit, scale))
                  .toList(),
            ),
            SizedBox(height: baseSize * 0.04 * scale),

            // Reminder
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(baseSize * 0.03 * scale),
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Credit totals reflect confirmed backend awards, not quiz submissions.",
                style: TextStyle(
                  color: const Color(0xFF047857),
                  fontSize: baseSize * 0.035 * scale,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

// =====================================================
// 💻 Landscape Layout
// =====================================================
  Widget _buildLandscapeLayout(
    BuildContext context,
    double screenWidth,
    double screenHeight,
    double baseSize,
    double scale,
    CmeCreditTotals totals,
    List<Map<String, dynamic>> recentCredits,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: baseSize * (isTablet(context) ? 0.04 : 0.06),
        vertical: baseSize * (isTablet(context) ? 0.04 : 0.02),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🟩 Left Column — Info + Progress
          Expanded(
            flex: 4,
            child: Padding(
              padding: EdgeInsets.only(right: baseSize * 0.04),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "CME Credits",
                    style: TextStyle(
                      fontSize: baseSize * (isTablet(context) ? 0.045 : 0.055),
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: baseSize * 0.01),
                  Text(
                    "Track your Continuing Medical Education progress",
                    style: TextStyle(
                      fontSize: baseSize * 0.032,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: baseSize * 0.05),

                  CmeTotalsCard(totals: totals),
                  SizedBox(height: baseSize * 0.03),

                  // 🕓 History Button
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => CreditsHistory()));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      padding: EdgeInsets.symmetric(
                        horizontal: baseSize * 0.08,
                        vertical: baseSize * 0.02,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.history, color: Colors.white),
                    label: Text(
                      "View CME History",
                      style: TextStyle(
                        fontSize: baseSize * 0.035,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 📋 Right Column — Scrollable Recent Credits
          Expanded(
            flex: 6,
            child: RefreshIndicator(
              onRefresh: () async {
                await refreshData();

                // ✅ Show confirmation when refresh completes
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Refresh complete.'),
                      backgroundColor: Color(0xFF16A34A),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    const Text("Recent Quiz Submissions"),
                    // 🧾 List of recent credits
                    ...recentCredits.map(
                        (credit) => _buildCreditCard(baseSize, credit, scale)),

                    SizedBox(height: baseSize * 0.04),

                    // 🟢 Reminder Card
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(baseSize * 0.03 * scale),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "Credit totals reflect confirmed backend awards, not quiz submissions.",
                        style: TextStyle(
                          color: const Color(0xFF047857),
                          fontSize: baseSize * 0.035 * scale,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    SizedBox(height: baseSize * 0.04),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // 🧾 Reusable Credit Card
  // =====================================================
  Widget _buildCreditCard(
      double baseSize, Map<String, dynamic> credit, double scale) {
    final score = num.tryParse(credit['score'].toString()) ?? 0;
    final bool passed = score >= 80.0;
    final String? rawDate = credit['date_taken'];
    String formattedDate = '--';

    // ✅ Handle UTC → Local conversion safely before building widgets
    if (rawDate != null) {
      try {
        final parsedDate = DateTime.parse(rawDate).toLocal();
        formattedDate = DateFormat('yyyy-MM-dd').format(parsedDate);
      } catch (e) {
        debugPrint(
            '⚠️ Invalid date format for ${credit['module_name']}: $rawDate');
      }
    }

    return Container(
      margin: EdgeInsets.only(bottom: baseSize * 0.025),
      padding: EdgeInsets.all(baseSize * 0.03),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 📝 Left section — module info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  credit['module_name'] ?? 'Unknown Module',
                  style: TextStyle(
                    fontSize: baseSize * 0.04 * scale,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: baseSize * 0.006),
                Text(
                  "Score: ${credit['score'] ?? '--'}%",
                  style: TextStyle(
                    fontSize: baseSize * 0.03 * scale,
                    color: Colors.grey[700],
                  ),
                ),
                Text(
                  "Date: $formattedDate",
                  style: TextStyle(
                    fontSize: baseSize * 0.03 * scale,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),

          // 🎯 Right section — Credits badge
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: baseSize * 0.03,
              vertical: baseSize * 0.012,
            ),
            decoration: BoxDecoration(
              color: passed
                  ? const Color(0xFFDCFCE7) // light green background
                  : const Color(0xFFFEE2E2), // light red background
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              passed ? "Passed" : "Not passed",
              style: TextStyle(
                fontSize: baseSize * 0.032 * scale,
                fontWeight: FontWeight.w600,
                color: passed
                    ? const Color(0xFF16A34A) // green text
                    : const Color(0xFFDC2626), // red text
              ),
            ),
          ),
        ],
      ),
    );
  }
}
