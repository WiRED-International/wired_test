import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../../../providers/auth_guard.dart';
import '../../../utils/custom_app_bar.dart';
import '../../../utils/custom_nav_bar.dart';
import '../../../utils/functions.dart';
import '../../../utils/side_nav_bar.dart';
import '../../../utils/app_layout.dart';
import '../../home_page.dart';
import '../../menu/guestMenu.dart';
import '../../menu/menu.dart';
import '../../module_library.dart';
import '../credits_tracker.dart';

class BasicTrainingProgressData {
  final List<Map<String, dynamic>> modules;
  final List<Map<String, dynamic>> quizScores;

  BasicTrainingProgressData({
    required this.modules,
    required this.quizScores,
  });
}

class BasicTrainingList extends StatefulWidget {
  const BasicTrainingList({super.key});

  @override
  State<BasicTrainingList> createState() => _BasicTrainingListState();
}

class _BasicTrainingListState extends State<BasicTrainingList> {
  final _storage = const FlutterSecureStorage();
  late Future<BasicTrainingProgressData> futureModules;

  @override
  void initState() {
    super.initState();
    futureModules = fetchBasicModules();
  }

  // =====================================================
  // 🔹 Fetch modules from backend
  // =====================================================
  Future<BasicTrainingProgressData> fetchBasicModules() async {
    final token = await _storage.read(key: 'authToken');

    if (token == null) {
      throw Exception('User not logged in');
    }

    final apiBaseUrl =
        dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final url = Uri.parse(
      '$apiBaseUrl/api/classes/progress/basic',
    );

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch Basic Training progress: ${response.statusCode}',
      );
    }

    final responseData =
    jsonDecode(response.body) as Map<String, dynamic>;

    final modules = responseData['modules'] as List? ?? [];
    final quizScores = responseData['quizScores'] as List? ?? [];

    return BasicTrainingProgressData(
      modules: modules
          .map((module) => Map<String, dynamic>.from(module))
          .toList(),
      quizScores: quizScores
          .map((score) => Map<String, dynamic>.from(score))
          .toList(),
    );
  }

  // =====================================================
  // 🔹 Helper: Count how many modules are passed
  // =====================================================
  int _calculateCompletedModules(
      List<Map<String, dynamic>> basicModules,
      List<Map<String, dynamic>> quizScores,
      ) {
    return basicModules.where((module) {
      final moduleId = module['id']?.toString();
      final moduleCustomId = module['module_id']?.toString();

      final matchedScore = quizScores.firstWhere(
            (s) {
          final flatId = s['module_id']?.toString();
          final nestedId = s['module']?['id']?.toString();
          final nestedCustomId = s['module']?['module_module_id']?.toString();
          return flatId == moduleId || nestedId == moduleId || nestedCustomId == moduleCustomId;
        },
        orElse: () => {},
      );

      if (matchedScore.isEmpty) return false;
      final score = matchedScore['score'];
      return score is num && score >= 80;
    }).length;
  }

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
        onHomeTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MyHomePage()),
          );
        },
        onLibraryTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ModuleLibrary()),
          );
        },
        onTrackerTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AuthGuard(
                child: CreditsTracker(),
              ),
            ),
          );
        },
        onMenuTap: () async {
          bool isLoggedIn = await checkIfUserIsLoggedIn();

          if (!context.mounted) return;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
              isLoggedIn ? Menu() : GuestMenu(),
            ),
          );
        },
        scale: scale,
      ),

      // ❗ IMPORTANT: remove Center()
      child: isLandscape
          ? Row(
        children: [
          CustomSideNavBar(
            onHomeTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MyHomePage(),
                ),
              );
            },
            onLibraryTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ModuleLibrary(),
                ),
              );
            },
            onTrackerTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AuthGuard(
                    child: CreditsTracker(),
                  ),
                ),
              );
            },
            onMenuTap: () async {
              bool isLoggedIn = await checkIfUserIsLoggedIn();

              if (!context.mounted) return;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                  isLoggedIn ? Menu() : GuestMenu(),
                ),
              );
            },
            scale: scale,
          ),

          Expanded(
            child: _buildLandscapeLayout(
              screenWidth,
              screenHeight,
              baseSize,
              scale,
            ),
          ),
        ],
      )
          : _buildPortraitLayout(
        screenWidth,
        screenHeight,
        baseSize,
        scale,
      ),
    );
  }

  // =====================================================
  // 🧩 Portrait Layout
  // =====================================================
  Widget _buildPortraitLayout(double screenWidth, double screenHeight, double baseSize, double scale) {

    return FutureBuilder<BasicTrainingProgressData>(
      future: futureModules,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final progressData = snapshot.data;

        if (progressData == null) {
          return const Center(
            child: Text('No Basic Training progress data available.'),
          );
        }

        final basicModules = progressData.modules;
        final quizScores = progressData.quizScores;

        final quizModules = basicModules
            .where((module) => module['has_quiz'] == true)
            .toList();

        int completedModules =
          _calculateCompletedModules(quizModules, quizScores);

        int totalModules = quizModules.length;

        double completionPercent = totalModules > 0
            ? (completedModules / totalModules * 100).clamp(0, 100)
            : 0;

        return Stack(
          children: [
            // 🌿 Scrollable content
            SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: baseSize * 0.07 * scale,
                vertical: baseSize * 0.03 * scale,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "CHW Basic Training",
                    style: TextStyle(
                      fontSize: baseSize * 0.055 * scale,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: baseSize * 0.01 * scale),
                  Text(
                    "View your module quiz scores and progress",
                    style: TextStyle(
                      fontSize: baseSize * 0.032 * scale,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: baseSize * 0.05 * scale),

                  // Progress Card
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(baseSize * 0.04 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007BFF),
                      borderRadius: BorderRadius.circular(baseSize * 0.04 * scale),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Overall Progress",
                              style: TextStyle(
                                fontSize: baseSize * 0.035 * scale,
                                color: Colors.white70,
                              ),
                            ),
                            SizedBox(height: baseSize * 0.01 * scale),
                            Text(
                              "$completedModules / $totalModules",
                              style: TextStyle(
                                fontSize: baseSize * 0.05 * scale,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              "Modules Passed",
                              style: TextStyle(
                                fontSize: baseSize * 0.035 * scale,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          "${completionPercent.toStringAsFixed(0)}%",
                          style: TextStyle(
                            fontSize: baseSize * 0.06 * scale,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: baseSize * 0.05 * scale),

                  // Module List
                  Column(
                    children: basicModules
                        .map((m) =>
                        _buildModuleCard(
                          baseSize,
                          m,
                          context,
                          quizScores,
                          scale: scale,
                        ))
                        .toList(),
                  ),
                  SizedBox(height: baseSize * 0.15 * scale), // space above fade
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // =====================================================
  // 🧩 Landscape Layout
  // =====================================================
  Widget _buildLandscapeLayout(double screenWidth, double screenHeight, double baseSize, double scale) {

    return FutureBuilder<BasicTrainingProgressData>(
      future: futureModules,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final progressData = snapshot.data;

        if (progressData == null) {
          return const Center(
            child: Text('No Basic Training progress data available.'),
          );
        }

        final basicModules = progressData.modules;
        final quizScores = progressData.quizScores;

        final quizModules = basicModules
            .where((module) => module['has_quiz'] == true)
            .toList();

        int completedModules =
        _calculateCompletedModules(quizModules, quizScores);

        int totalModules = quizModules.length;

        double completionPercent = totalModules > 0
            ? (completedModules / totalModules * 100).clamp(0, 100)
            : 0;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: baseSize * (isTablet(context) ? 0.04 : 0.06),
            vertical: baseSize * (isTablet(context) ? 0.04 : 0.05),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 📘 Left Column — Info + Progress
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "CHW Basic Training",
                      style: TextStyle(
                        fontSize: baseSize * (isTablet(context) ? 0.045 : 0.055),
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: baseSize * 0.01),
                    Text(
                      "View your module quiz scores and progress",
                      style: TextStyle(
                        fontSize: baseSize * 0.032,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: baseSize * 0.05),

                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(baseSize * 0.04),
                      decoration: BoxDecoration(
                        color: const Color(0xFF007BFF),
                        borderRadius: BorderRadius.circular(baseSize * 0.04),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Overall Progress",
                                style: TextStyle(
                                  fontSize: baseSize * 0.035,
                                  color: Colors.white70,
                                ),
                              ),
                              SizedBox(height: baseSize * 0.01),
                              Text(
                                "$completedModules / $totalModules",
                                style: TextStyle(
                                  fontSize: baseSize * 0.05,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                "Modules Passed",
                                style: TextStyle(
                                  fontSize: baseSize * 0.035,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            "${completionPercent.toStringAsFixed(0)}%",
                            style: TextStyle(
                              fontSize: baseSize * 0.06,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: baseSize * 0.04),
                  ],
                ),
              ),

              SizedBox(width: baseSize * 0.05),

              // 📜 Right Column — Scrollable Modules + Fade
              Expanded(
                flex: 6,
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      child: Column(
                        children: basicModules
                            .map((m) =>
                            _buildModuleCard(
                              baseSize,
                              m,
                              context,
                              quizScores,
                              scale: scale,
                            ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModuleCard(
      double baseSize,
      Map<String, dynamic> module,
      BuildContext context,
      List<Map<String, dynamic>> quizScores, {
        double scale = 1.0,
      }) {

    final moduleId = module['id']?.toString();
    final moduleCustomId = module['module_id']?.toString();

    final hasQuiz = module['has_quiz'] == true;

    // 🔍 Find matching score
    final matchedScore = quizScores.firstWhere(
          (s) {
        final flatId = s['module_id']?.toString(); // quiz_scores.module_id
        final nestedId = s['module']?['id']?.toString(); // module.id
        final nestedCustomId = s['module']?['module_id']?.toString(); // module.module_id
        return flatId == moduleId || nestedId == moduleId || nestedCustomId == moduleCustomId;
      },
      orElse: () => {},
    );

    if (matchedScore.isEmpty) {
      debugPrint('❌ No match for module.id=$moduleId module.module_id=$moduleCustomId');
    }

    final score = matchedScore.isNotEmpty && matchedScore['score'] is num
        ? matchedScore['score']
        : null;

    final passing = module['passingScore'] ?? 80;
    final attempted = score != null;
    final passed = attempted && score >= passing;

    if (matchedScore.isNotEmpty) {
      debugPrint('✅ Module ${module['id']} matched → score=$score (passed=$passed)');
    } else {
      debugPrint('❌ No match for module ${module['id']}');
    }

    Color borderColor = passed
        ? const Color(0xFF22C55E)
        : (!attempted ? Colors.grey.shade300 : const Color(0xFFE11D48));

    return Container(
      margin: EdgeInsets.only(bottom: baseSize * 0.03 * scale),
      padding: EdgeInsets.symmetric(
        horizontal: baseSize * 0.04 * scale,
        vertical: baseSize * 0.03 * scale,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(baseSize * 0.03 * scale),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4 * scale,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            !hasQuiz
                ? Icons.remove_circle_outline
                : passed
                ? Icons.check_circle_rounded
                : (!attempted
                ? Icons.radio_button_unchecked
                : Icons.cancel_rounded),
            color: passed
                ? const Color(0xFF22C55E)
                : (!attempted
                ? Colors.grey
                : const Color(0xFFE11D48)),
            size: baseSize * 0.06 * scale, // ✅ scales on tablets
          ),
          SizedBox(width: baseSize * 0.04 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module['name'] ?? module['title'] ?? 'Untitled Module',
                  style: TextStyle(
                    fontSize: baseSize * 0.038 * scale,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: baseSize * 0.01 * scale),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: baseSize * 0.025 * scale,
                        vertical: baseSize * 0.005 * scale,
                      ),
                      decoration: BoxDecoration(
                        color: passed
                            ? const Color(0xFFD1FAE5)
                            : (!attempted
                            ? const Color(0xFFF3F4F6)
                            : const Color(0xFFFEE2E2)),
                        borderRadius:
                        BorderRadius.circular(baseSize * 0.02 * scale),
                      ),
                      child: Text(
                        !hasQuiz
                            ? "No Quiz"
                            : passed
                            ? "Passed"
                            : (!attempted ? "Not Attempted" : "No Pass"),
                        style: TextStyle(
                          color: passed
                              ? const Color(0xFF065F46)
                              : (!attempted
                              ? Colors.black54
                              : const Color(0xFF991B1B)),
                          fontSize: baseSize * 0.028 * scale,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (hasQuiz) ...[
                      SizedBox(width: baseSize * 0.03 * scale),
                      Text(
                        "Passing: ${passing.toString()}%",
                        style: TextStyle(
                          fontSize: baseSize * 0.028 * scale,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: baseSize * 0.03 * scale),
          if (hasQuiz)
            Text(
              attempted ? "${score.toString()} / 100" : "--",
              style: TextStyle(
                fontSize: baseSize * 0.035 * scale,
                fontWeight: FontWeight.bold,
                color: attempted
                    ? (passed
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFE11D48))
                    : Colors.black38,
              ),
            ),
        ],
      ),
    );
  }
}
