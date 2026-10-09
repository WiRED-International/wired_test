import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../../../utils/custom_app_bar.dart';
import '../../../utils/custom_nav_bar.dart';
import '../../../utils/side_nav_bar.dart';
import '../../../utils/functions.dart';
import '../../../utils/app_layout.dart';
import '../../home_page.dart';
import '../../menu/guestMenu.dart';
import '../../menu/menu.dart';
import '../../module_library.dart';
import '../credits_tracker.dart';
import '../../../providers/auth_guard.dart';

class SpecializationTrainingProgressData {
  final Map<String, dynamic> specialization;
  final List<Map<String, dynamic>> modules;
  final List<Map<String, dynamic>> quizScores;

  SpecializationTrainingProgressData({
    required this.specialization,
    required this.modules,
    required this.quizScores,
  });
}

class SpecializationTrainingList extends StatefulWidget {
  const SpecializationTrainingList({super.key});

  @override
  State<SpecializationTrainingList> createState() =>
      _SpecializationTrainingListState();
}

class _SpecializationTrainingListState
    extends State<SpecializationTrainingList> {
  final _storage = const FlutterSecureStorage();
  late Future<SpecializationTrainingProgressData> futureModules;

  @override
  void initState() {
    super.initState();
    futureModules = fetchSpecializationModules();
  }

  Future<SpecializationTrainingProgressData>
    fetchSpecializationModules() async {
      final token = await _storage.read(key: 'authToken');

      if (token == null) {
        throw Exception('User not logged in');
      }

      final apiBaseUrl = dotenv.env['API_BASE_URL'];

      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/classes/progress/specialization'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to fetch Specialization Training progress: '
              '${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      final specialization =
      Map<String, dynamic>.from(data['specialization']);

      final modules = (data['modules'] as List)
          .map((module) => Map<String, dynamic>.from(module))
          .toList();

      final quizScores = (data['quizScores'] as List)
          .map((score) => Map<String, dynamic>.from(score))
          .toList();

      return SpecializationTrainingProgressData(
        specialization: specialization,
        modules: modules,
        quizScores: quizScores,
      );
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
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MyHomePage()));
        },
        onLibraryTap: () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => ModuleLibrary()));
        },
        onTrackerTap: () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => AuthGuard(child: CreditsTracker())));
        },
        onMenuTap: () async {
          bool isLoggedIn = await checkIfUserIsLoggedIn();

          if (!context.mounted) return;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => isLoggedIn ? Menu() : GuestMenu(),
            ),
          );
        },
        scale: scale,
      ),

      // ❗ IMPORTANT: no Center()
      child: isLandscape
          ? Row(
        children: [
          CustomSideNavBar(
            onHomeTap: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MyHomePage()));
            },
            onLibraryTap: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ModuleLibrary()));
            },
            onTrackerTap: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => AuthGuard(child: CreditsTracker())));
            },
            onMenuTap: () async {
              bool isLoggedIn = await checkIfUserIsLoggedIn();

              if (!context.mounted) return;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => isLoggedIn ? Menu() : GuestMenu(),
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

  // ===========================================================
  // 🧩 Portrait Layout
  // ===========================================================
  Widget _buildPortraitLayout(double screenWidth, double screenHeight, double baseSize, double scale) {
    return FutureBuilder<SpecializationTrainingProgressData>(
      future: futureModules,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              snapshot.error.toString(),
              textAlign: TextAlign.center,
            ),
          );
        }

        final progressData = snapshot.data;

        if (progressData == null) {
          return const Center(
            child: Text('No Specialization Training data available.'),
          );
        }

        final specializationModules = progressData.modules;
        final quizScores = progressData.quizScores;

        final specializationName =
            progressData.specialization['name'] ?? 'Not Selected';

        final quizModules = specializationModules
            .where((module) => module['has_quiz'] == true)
            .toList();

        int completedModules =
        _calculateCompletedModules(quizModules, quizScores);

        int totalModules = quizModules.length;

        double completionPercent = totalModules > 0
            ? (completedModules / totalModules * 100).clamp(0, 100)
            : 0;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: baseSize * 0.07 * scale,
            vertical: baseSize * 0.03 * scale,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "CHW Specialization Training",
                style: TextStyle(
                  fontSize: baseSize * 0.055 * scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: baseSize * 0.01 * scale),
              Text(
                "View your specialization module quiz scores and progress",
                style: TextStyle(
                  fontSize: baseSize * 0.032 * scale,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: baseSize * 0.015 * scale),

              Text(
                "Specialization: $specializationName",
                style: TextStyle(
                  fontSize: baseSize * 0.032 * scale,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: baseSize * 0.05 * scale),

              // 🟧 Progress Card (Orange)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(baseSize * 0.04 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B00),
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

              // Module Cards
              Column(
                children: specializationModules
                  .map(
                    (m) => _buildModuleCard(
                      baseSize,
                      m,
                      quizScores,
                      scale,
                    ),
                  )
                  .toList(),
              ),
              SizedBox(height: baseSize * 0.15 * scale),
            ],
          ),
        );
      },
    );
  }

  int _calculateCompletedModules(
    List<Map<String, dynamic>> modules,
    List<Map<String, dynamic>> quizScores,
  ) {
    return modules.where((module) {
      final moduleId = module['id']?.toString();

      final matchedScore = quizScores.firstWhere(
            (score) => score['module_id']?.toString() == moduleId,
        orElse: () => {},
      );

      if (matchedScore.isEmpty) {
        return false;
      }

      final score = matchedScore['score'];

      return score is num && score >= 80;
    }).length;
  }

  // ===========================================================
  // 🧩 Landscape Layout (reuse same)
  // ===========================================================
  Widget _buildLandscapeLayout(
      double screenWidth, double screenHeight, double baseSize, double scale) {
    return _buildPortraitLayout(screenWidth, screenHeight, baseSize, scale);
  }

  // ===========================================================
  // 🔹 Module Card Widget
  // ===========================================================
  Widget _buildModuleCard(
      double baseSize,
      Map<String, dynamic> module,
      List<Map<String, dynamic>> quizScores,
      double scale,
      ) {
    final moduleId = module['id']?.toString();
    final hasQuiz = module['has_quiz'] == true;

    final matchedScore = quizScores.firstWhere(
          (score) => score['module_id']?.toString() == moduleId,
      orElse: () => {},
    );

    final score =
    matchedScore.isNotEmpty && matchedScore['score'] is num
        ? matchedScore['score']
        : null;

    final attempted = score != null;
    final passed = attempted && score >= 80;

    final String status;

    if (!hasQuiz) {
      status = 'No Quiz';
    } else if (passed) {
      status = 'Passed';
    } else if (attempted) {
      status = 'No Pass';
    } else {
      status = 'Not Attempted';
    }

    final borderColor = !hasQuiz
        ? Colors.grey.shade300
        : passed
        ? const Color(0xFF22C55E)
        : attempted
        ? const Color(0xFFE11D48)
        : Colors.grey.shade300;

    final statusBackgroundColor = !hasQuiz
        ? const Color(0xFFF3F4F6)
        : passed
        ? const Color(0xFFD1FAE5)
        : attempted
        ? const Color(0xFFFEE2E2)
        : const Color(0xFFF3F4F6);

    final statusTextColor = !hasQuiz
        ? Colors.grey.shade700
        : passed
        ? const Color(0xFF15803D)
        : attempted
        ? const Color(0xFFBE123C)
        : Colors.grey.shade700;

    return Container(
      margin: EdgeInsets.only(bottom: baseSize * 0.03 * scale),
      padding: EdgeInsets.all(baseSize * 0.035 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(baseSize * 0.03 * scale),
        border: Border.all(
          color: borderColor,
          width: 1.2,
        ),
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
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module['name'] ?? 'Untitled Module',
                  style: TextStyle(
                    fontSize: baseSize * 0.04 * scale,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: baseSize * 0.01 * scale),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: baseSize * 0.02 * scale,
                        vertical: baseSize * 0.007 * scale,
                      ),
                      decoration: BoxDecoration(
                        color: statusBackgroundColor,
                        borderRadius:
                        BorderRadius.circular(baseSize * 0.015 * scale),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: baseSize * 0.028 * scale,
                          color: statusTextColor,
                        ),
                      ),
                    ),
                    SizedBox(width: baseSize * 0.02 * scale),
                    if (hasQuiz)
                      Text(
                        'Passing: 80%',
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

          if (hasQuiz)
            Text(
              attempted ? '${score.toString()} / 100' : '--',
              style: TextStyle(
                fontSize: baseSize * 0.032 * scale,
                fontWeight: FontWeight.w600,
                color: passed
                    ? const Color(0xFF15803D)
                    : attempted
                    ? const Color(0xFFBE123C)
                    : Colors.grey,
              ),
            ),
        ],
      ),
    );
  }
}
