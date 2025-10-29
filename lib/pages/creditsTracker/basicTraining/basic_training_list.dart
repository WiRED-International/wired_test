import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../../providers/auth_guard.dart';
import '../../../utils/custom_app_bar.dart';
import '../../../utils/custom_nav_bar.dart';
import '../../../utils/functions.dart';
import '../../../utils/side_nav_bar.dart';
import '../../cme/cme_tracker.dart';
import '../../home_page.dart';
import '../../menu/guestMenu.dart';
import '../../menu/menu.dart';
import '../../module_library.dart';
import '../../../data/basic_training_titles.dart';
import '../../../providers/quiz_score_provider.dart';
import '../credits_tracker.dart';

class BasicTrainingList extends StatefulWidget {
  const BasicTrainingList({super.key});

  @override
  State<BasicTrainingList> createState() => _BasicTrainingListState();
}

class _BasicTrainingListState extends State<BasicTrainingList> {
  final _storage = const FlutterSecureStorage();
  late Future<List<Map<String, dynamic>>> futureModules;
  final bool _enableDebug = false; // Toggle for logs

  @override
  void initState() {
    super.initState();
    futureModules = fetchBasicModules();
    final quizProvider = Provider.of<QuizScoreProvider>(context, listen: false);
    quizProvider.fetchQuizScores();
  }

  // =====================================================
  // 🔹 Fetch modules from backend
  // =====================================================
  Future<List<Map<String, dynamic>>> fetchBasicModules() async {
    final token = await _storage.read(key: 'authToken');
    if (token == null) throw Exception('User not logged in');

    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final url = Uri.parse('$apiBaseUrl/modules');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch modules: ${response.statusCode}');
    }

    final allModules = (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();

    // Keep only those where categories contains "basic"
    return _filterBasicModules(allModules);
  }

  // =====================================================
  // 🔹 Helper: Filter only basic modules
  // =====================================================
  List<Map<String, dynamic>> _filterBasicModules(List<Map<String, dynamic>> modules) {
    return modules.where((m) {
      final rawCategories = m['categories'];
      if (rawCategories == null) return false;

      List<String> categories = [];
      if (rawCategories is List) {
        categories = rawCategories.map((e) => e.toString().toLowerCase()).toList();
      } else if (rawCategories is String) {
        try {
          final decoded = jsonDecode(rawCategories);
          if (decoded is List) {
            categories = decoded.map((e) => e.toString().toLowerCase()).toList();
          }
        } catch (_) {}
      }

      return categories.contains('basic');
    }).toList();
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

    // Adjust font & padding scaling for tablet
    final scale = isTabletDevice ? 1.0 : 1.0;

    return Scaffold(
      body: SafeArea(
        child: Stack(
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

            Column(
              children: [
                // Custom AppBar
                CustomAppBar(
                  onBackPressed: () => Navigator.pop(context),
                  requireAuth: false,
                  scale: scale,
                ),

                // Expanded main content area
                Expanded(
                  child: Row(
                    children: [
                      // 🔹 Show side nav only in landscape mode
                      if (isLandscape)
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
                                  child: CMETracker(),
                                ),
                              ),
                            );
                          },
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
                          scale: scale,
                        ),

                      // 🔹 Main page content (responsive)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(screenWidth, screenHeight, baseSize, scale)
                              : _buildPortraitLayout(screenWidth, screenHeight, baseSize, scale),
                        ),
                      ),
                    ],
                  ),
                ),

                // 🔹 Bottom nav only when in portrait
                if (!isLandscape)
                  CustomBottomNavBar(
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // 🧩 Portrait Layout
  // =====================================================
  Widget _buildPortraitLayout(double screenWidth, double screenHeight, double baseSize, double scale) {
    final quizProvider = Provider.of<QuizScoreProvider>(context);
    final quizScores = quizProvider.quizScores;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: futureModules,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final modules = snapshot.data ?? [];
        final basicModules = _filterBasicModules(modules);
        int completedModules = _calculateCompletedModules(basicModules, quizScores);

        int totalModules = basicModules.length;
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
                        _buildModuleCard(baseSize, m, context, scale: scale))
                        .toList(),
                  ),
                  SizedBox(height: baseSize * 0.15 * scale), // space above fade
                ],
              ),
            ),
            // Positioned(
            //   bottom: 0,
            //   left: 0,
            //   right: 0,
            //   child: IgnorePointer(
            //     child: Container(
            //       //height: 150,
            //         height: screenHeight * 0.2,
            //         decoration: BoxDecoration(
            //           gradient: LinearGradient(
            //             begin: Alignment.topCenter,
            //             end: Alignment.bottomCenter,
            //             stops: [0.0, 1.0],
            //             colors: [
            //               // Colors.transparent,
            //               // Color(0xFFFFF0DC),
            //               //Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
            //               Color(0xFFFED09A).withOpacity(0.0),
            //               Color(0xFFFED09A),
            //             ],
            //           ),
            //         )
            //     ),
            //   ),
            // ),
          ],
        );
      },
    );
  }

  // =====================================================
  // 🧩 Landscape Layout
  // =====================================================
  Widget _buildLandscapeLayout(double screenWidth, double screenHeight, double baseSize, double scale) {
    final quizProvider = Provider.of<QuizScoreProvider>(context);
    final quizScores = quizProvider.quizScores;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: futureModules,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final modules = snapshot.data ?? [];
        final basicModules = _filterBasicModules(modules);
        int completedModules = _calculateCompletedModules(basicModules, quizScores);

        int totalModules = basicModules.length;
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
                            _buildModuleCard(baseSize, m, context, scale: scale))
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


  // =====================================================
  // 🧩 Module Card
  // =====================================================
  // Widget _buildModuleCard(double baseSize, Map<String, dynamic> module, BuildContext context) {
  //   final quizProvider = Provider.of<QuizScoreProvider>(context);
  //   final quizScores = quizProvider.quizScores;
  //
  //   final moduleId = module['id']?.toString();
  //   final moduleCustomId = module['module_id']?.toString();
  //
  //   final matchedScore = quizScores.firstWhere(
  //     (s) {
  //       final flatId = s['module_id']?.toString();
  //       final nestedId = s['module']?['id']?.toString();
  //       final nestedCustomId = s['module']?['module_id']?.toString();
  //       return flatId == moduleId || nestedId == moduleId || nestedCustomId == moduleCustomId;
  //     },
  //     orElse: () => {},
  //   );
  //
  //   final score = matchedScore.isNotEmpty && matchedScore['score'] is num
  //       ? matchedScore['score']
  //       : null;
  //
  //   final passing = module['passingScore'] ?? 80;
  //   final attempted = score != null;
  //   final passed = attempted && score >= passing;
  //
  //   Color borderColor = passed
  //       ? const Color(0xFF22C55E)
  //       : (!attempted ? Colors.grey.shade300 : const Color(0xFFE11D48));
  //
  //   return Container(
  //     margin: EdgeInsets.only(bottom: baseSize * 0.03),
  //     padding: EdgeInsets.symmetric(
  //       horizontal: baseSize * 0.04,
  //       vertical: baseSize * 0.03,
  //     ),
  //     decoration: BoxDecoration(
  //       color: Colors.white,
  //       borderRadius: BorderRadius.circular(baseSize * 0.03),
  //       border: Border.all(color: borderColor, width: 1.2),
  //       boxShadow: [
  //         BoxShadow(
  //           color: Colors.black12,
  //           blurRadius: 4,
  //           offset: const Offset(0, 2),
  //         ),
  //       ],
  //     ),
  //     child: Row(
  //       children: [
  //         Icon(
  //           passed
  //               ? Icons.check_circle_rounded
  //               : (!attempted ? Icons.radio_button_unchecked : Icons.cancel_rounded),
  //           color: passed
  //               ? const Color(0xFF22C55E)
  //               : (!attempted ? Colors.grey : const Color(0xFFE11D48)),
  //           size: baseSize * 0.06,
  //         ),
  //         SizedBox(width: baseSize * 0.04),
  //         Expanded(
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               Text(
  //                 module['name'] ?? 'Untitled Module',
  //                 style: TextStyle(
  //                   fontSize: baseSize * 0.038,
  //                   fontWeight: FontWeight.w600,
  //                   color: Colors.black87,
  //                 ),
  //               ),
  //               SizedBox(height: baseSize * 0.01),
  //               Row(
  //                 children: [
  //                   Container(
  //                     padding: EdgeInsets.symmetric(
  //                       horizontal: baseSize * 0.025,
  //                       vertical: baseSize * 0.005,
  //                     ),
  //                     decoration: BoxDecoration(
  //                       color: passed
  //                           ? const Color(0xFFD1FAE5)
  //                           : (!attempted
  //                           ? const Color(0xFFF3F4F6)
  //                           : const Color(0xFFFEE2E2)),
  //                       borderRadius: BorderRadius.circular(baseSize * 0.02),
  //                     ),
  //                     child: Text(
  //                       passed
  //                           ? "Passed"
  //                           : (!attempted ? "Not Attempted" : "No Pass"),
  //                       style: TextStyle(
  //                         color: passed
  //                             ? const Color(0xFF065F46)
  //                             : (!attempted
  //                             ? Colors.black54
  //                             : const Color(0xFF991B1B)),
  //                         fontSize: baseSize * 0.028,
  //                         fontWeight: FontWeight.w500,
  //                       ),
  //                     ),
  //                   ),
  //                   SizedBox(width: baseSize * 0.03),
  //                   Text(
  //                     "Passing: ${passing.toString()}%",
  //                     style: TextStyle(
  //                       fontSize: baseSize * 0.028,
  //                       color: Colors.black54,
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ],
  //           ),
  //         ),
  //         SizedBox(width: baseSize * 0.03),
  //         Text(
  //           attempted ? "${score.toString()} / 100" : "--",
  //           style: TextStyle(
  //             fontSize: baseSize * 0.035,
  //             fontWeight: FontWeight.bold,
  //             color: attempted
  //                 ? (passed
  //                 ? const Color(0xFF22C55E)
  //                 : const Color(0xFFE11D48))
  //                 : Colors.black38,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }
  Widget _buildModuleCard(
      double baseSize,
      Map<String, dynamic> module,
      BuildContext context, {
        double scale = 1.0, // ✅ default 1.0 for backward compatibility
      }) {
    final quizProvider = Provider.of<QuizScoreProvider>(context);
    final quizScores = quizProvider.quizScores;

    final moduleId = module['id']?.toString();
    final moduleCustomId = module['module_id']?.toString();

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
            passed
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
                        passed
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
                    SizedBox(width: baseSize * 0.03 * scale),
                    Text(
                      "Passing: ${passing.toString()}%",
                      style: TextStyle(
                        fontSize: baseSize * 0.028 * scale,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: baseSize * 0.03 * scale),
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
