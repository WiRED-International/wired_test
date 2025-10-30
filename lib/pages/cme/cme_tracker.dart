import 'package:intl/intl.dart';
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
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/landscape_profile_section.dart';
import '../../utils/profile_section.dart';
import '../../utils/side_nav_bar.dart';
import '../creditsTracker/credits_tracker.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import 'credits_history.dart';
import '../../models/user.dart';
import '../../../providers/quiz_score_provider.dart';

class CMETracker extends StatefulWidget {
  const CMETracker({Key? key}) : super(key: key);

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
      Provider.of<QuizScoreProvider>(context, listen: false).fetchQuizScores();
    });
  }

  Future<String?> getAuthToken() async {
    return await _storage.read(key: 'authToken');
  }

  Future<User> fetchUserData() async {
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
    await Provider.of<QuizScoreProvider>(context, listen: false)
        .fetchQuizScores();
  }

  int calculateCredits(List<dynamic>? quizScores) {
    final int currentYear = DateTime.now().year;
    if (quizScores == null) {
      debugPrint('🚫 quizScores is NULL');
      return 0;
    }

    if (quizScores.isEmpty) {
      debugPrint('⚠️ quizScores is EMPTY!');
      return 0;
    }

    debugPrint('📦 Received ${quizScores.length} quiz scores for credit calculation');
    for (var s in quizScores) {
      debugPrint('🔍 Entry: ${jsonEncode(s)}');
    }

    int totalCredits = 0;

    for (var score in quizScores) {
      if (score is Map<String, dynamic>) {
        final double scoreValue = double.tryParse(score['score'].toString()) ?? 0.0;
        final DateTime? dateTaken = DateTime.tryParse(score['date_taken'].toString());
        final String creditType = (score['credit_type'] ??
            score['module']?['credit_type'] ??
            'none')
            .toString()
            .toLowerCase();

        debugPrint('🧮 Evaluating: score=$scoreValue, creditType=$creditType, date=${dateTaken?.year}');

        if (creditType == 'cme' &&
            scoreValue >= 80.0 &&
            dateTaken != null &&
            dateTaken.year == currentYear) {
          totalCredits += 5;
          debugPrint('✅ Counted: $scoreValue (${dateTaken.year})');
        } else {
          debugPrint('❌ Skipped: score=$scoreValue, creditType=$creditType, date=${dateTaken?.year}');
        }
      }
    }

    debugPrint('📊 Total CME credits counted: $totalCredits');
    return totalCredits;
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

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // 🟠 Background Gradient
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
                // AppBar
                CustomAppBar(
                  onBackPressed: () => Navigator.pop(context),
                  requireAuth: false,
                  scale: scale,
                ),

                // Main content area
                Expanded(
                  child: Row(
                    children: [
                      // 🔹 Side Nav (Landscape only)
                      if (isLandscape)
                        CustomSideNavBar(
                          onHomeTap: () =>
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const MyHomePage()),
                              ),
                          onLibraryTap: () =>
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ModuleLibrary()),
                              ),
                          onTrackerTap: () =>
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        AuthGuard(child: CreditsTracker())),
                              ),
                          onMenuTap: () async {
                            bool isLoggedIn = await checkIfUserIsLoggedIn();
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

                      // Main content
                      Expanded(
                        child: FutureBuilder<User>(
                          future: userData,
                          builder: (context, userSnapshot) {
                            if (userSnapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            if (userSnapshot.hasError) {
                              return Center(child: Text('Error: ${userSnapshot.error}'));
                            }

                            final user = userSnapshot.data!;
                            final double totalCredits = user.totalCredits.toDouble();

                            // ✅ Now listen to provider *inside* the FutureBuilder
                            return Consumer<QuizScoreProvider>(
                              builder: (context, quizProvider, child) {
                                final quizScores =
                                List<Map<String, dynamic>>.from(quizProvider.quizScores);

                                if (quizProvider.isLoading) {
                                  return const Center(
                                    child: Text(
                                      "Loading your CME credits...",
                                      style: TextStyle(fontSize: 16, color: Colors.black54),
                                    ),
                                  );
                                }

                                if (quizScores.isEmpty) {
                                  return const Center(
                                    child: Text(
                                      "You haven’t earned any CME credits yet.\nComplete a quiz to get started!",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  );
                                }

                                // ✅ Calculate credits only once provider is ready
                                final double earnedCredits =
                                calculateCredits(quizScores).toDouble();

                                debugPrint('🎯 Provider ready — ${quizScores.length} scores, $earnedCredits credits');

                                // ✅ Filter CME modules for “recent credits” section
                                final cmeScores = quizScores
                                    .where((q) =>
                                (q['credit_type']?.toString().toLowerCase() == 'cme'))
                                    .toList();
                                cmeScores.sort((a, b) =>
                                    (b['date_taken'] ?? '').compareTo(a['date_taken'] ?? ''));
                                final recentCredits = cmeScores.take(3).toList();

                                final orientation = MediaQuery.of(context).orientation;

                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 400),
                                  switchInCurve: Curves.easeIn,
                                  switchOutCurve: Curves.easeOut,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(opacity: animation, child: child),
                                  child: orientation == Orientation.landscape
                                      ? KeyedSubtree(
                                    key: const ValueKey('landscape'),
                                    child: _buildLandscapeLayout(
                                      context,
                                      screenWidth,
                                      screenHeight,
                                      baseSize,
                                      scale,
                                      earnedCredits,
                                      totalCredits,
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
                                      earnedCredits,
                                      totalCredits,
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
                  ),
                ),

                // Bottom Nav (Portrait only)
                if (!isLandscape)
                  CustomBottomNavBar(
                    onHomeTap: () =>
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const MyHomePage()),
                        ),
                    onLibraryTap: () =>
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ModuleLibrary()),
                        ),
                    onTrackerTap: () =>
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => AuthGuard(child: CreditsTracker())),
                        ),
                    onMenuTap: () async {
                      bool isLoggedIn = await checkIfUserIsLoggedIn();
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // 📱 Portrait Layout
  // =====================================================
  Widget _buildPortraitLayout(BuildContext context,
      double screenWidth,
      double screenHeight,
      double baseSize,
      double scale,
      double earnedCredits,
      double totalCredits,
      List<Map<String, dynamic>> recentCredits,) {
    final safeTotal = totalCredits == 0 ? 1.0 : totalCredits;
    final percentComplete = (earnedCredits / safeTotal).clamp(0.0, 1.0);
    final remainingCredits = (safeTotal - earnedCredits).clamp(0.0, safeTotal);

    return RefreshIndicator(
      onRefresh: () async {
        await refreshData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Updated! Your credits are refreshed.'),
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

            // Progress card
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(baseSize * 0.04),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
                ),
                borderRadius: BorderRadius.circular(baseSize * 0.04),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("2025 Progress",
                        style: TextStyle(
                            fontSize: baseSize * 0.035, color: Colors.white70),
                      ),
                      SizedBox(height: baseSize * 0.01),
                      Text(
                        "${earnedCredits.toStringAsFixed(1)} / ${safeTotal
                            .toStringAsFixed(0)}",
                        style: TextStyle(
                          fontSize: baseSize * 0.05,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text("Credits Earned",
                        style: TextStyle(
                            fontSize: baseSize * 0.035, color: Colors.white70),
                      ),
                      SizedBox(height: baseSize * 0.025),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percentComplete,
                          minHeight: 8,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white),
                        ),
                      ),
                      SizedBox(height: baseSize * 0.01),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "${(percentComplete * 100).toStringAsFixed(
                              1)}% Complete",
                          style: TextStyle(fontSize: baseSize * 0.035,
                              color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: baseSize * 0.02,
                    right: baseSize * 0.02,
                    child: Container(
                      width: baseSize * 0.12,
                      height: baseSize * 0.12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.15),
                      ),
                      child: Icon(
                        Icons.emoji_events,
                        size: baseSize * 0.06,
                        color: (earnedCredits >= safeTotal)
                            ? Colors.amberAccent
                            : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

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
              "Recent Credits",
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
                "Reminder: You need ${remainingCredits.toStringAsFixed(
                    1)} more credits to meet your 2025 requirement.",
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
  Widget _buildLandscapeLayout(BuildContext context,
      double screenWidth,
      double screenHeight,
      double baseSize,
      double scale,
      double earnedCredits,
      double totalCredits,
      List<Map<String, dynamic>> recentCredits,) {
    double percentComplete = (earnedCredits / totalCredits).clamp(0.0, 1.0);
    double remainingCredits =
    (totalCredits - earnedCredits).clamp(0.0, totalCredits);

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

                  // 🟢 Progress Card
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(baseSize * 0.04),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF16A34A),
                          Color(0xFF22C55E),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(baseSize * 0.04),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "2025 Progress",
                              style: TextStyle(
                                fontSize: baseSize * 0.035,
                                color: Colors.white70,
                              ),
                            ),
                            SizedBox(height: baseSize * 0.01),
                            Text(
                              "${earnedCredits.toStringAsFixed(
                                  1)} / ${totalCredits.toStringAsFixed(0)}",
                              style: TextStyle(
                                fontSize: baseSize * 0.05,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              "Credits Earned",
                              style: TextStyle(
                                fontSize: baseSize * 0.035,
                                color: Colors.white70,
                              ),
                            ),
                            SizedBox(height: baseSize * 0.025),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percentComplete,
                                minHeight: 8,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            ),
                            SizedBox(height: baseSize * 0.01),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                "${(percentComplete * 100).toStringAsFixed(
                                    1)}% Complete",
                                style: TextStyle(
                                  fontSize: baseSize * 0.035,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          top: baseSize * 0.02,
                          right: baseSize * 0.02,
                          child: Container(
                            width: baseSize * 0.12,
                            height: baseSize * 0.12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.15),
                            ),
                            child: Icon(
                              Icons.emoji_events,
                              size: baseSize * 0.06,
                              color: (earnedCredits >= totalCredits)
                                  ? Colors.amberAccent
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Updated! Your credits are refreshed.'),
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
                    // 🧾 List of recent credits
                    ...recentCredits
                        .map((credit) =>
                        _buildCreditCard(baseSize, credit, scale))
                        .toList(),

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
                        "Reminder: You need ${remainingCredits.toStringAsFixed(
                            1)} more credits to meet your 2025 requirement.",
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
    final double score = (credit['score'] ?? 0).toDouble();
    final bool passed = score >= 80.0;
    final String? rawDate = credit['date_taken'];
    String formattedDate = '--';

    // ✅ Handle UTC → Local conversion safely before building widgets
    if (rawDate != null) {
      try {
        final parsedDate = DateTime.parse(rawDate).toLocal();
        formattedDate = DateFormat('yyyy-MM-dd').format(parsedDate);
      } catch (e) {
        debugPrint('⚠️ Invalid date format for ${credit['module_name']}: $rawDate');
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
            color: Colors.grey.withOpacity(0.2),
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
              passed ? "5 credits" : "No Credits",
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

