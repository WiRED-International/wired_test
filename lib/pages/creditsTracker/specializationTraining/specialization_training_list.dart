import 'package:flutter/material.dart';
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

class SpecializationTrainingList extends StatefulWidget {
  const SpecializationTrainingList({super.key});

  @override
  State<SpecializationTrainingList> createState() =>
      _SpecializationTrainingListState();
}

class _SpecializationTrainingListState
    extends State<SpecializationTrainingList> {
  final List<Map<String, dynamic>> specializationModules = [
    {
      "id": 1,
      "title": "301 CHW Nutrition and Wellness",
      "status": "Not Attempted",
      "passingScore": "80%"
    },
    {
      "id": 2,
      "title": "302 CHW Mental Health Support",
      "status": "Not Attempted",
      "passingScore": "80%"
    },
    {
      "id": 3,
      "title": "303 CHW Maternal and Neonatal Care",
      "status": "Not Attempted",
      "passingScore": "80%"
    },
    {
      "id": 4,
      "title": "304 CHW Community Leadership",
      "status": "Not Attempted",
      "passingScore": "80%"
    },
    {
      "id": 5,
      "title": "305 CHW Non-Communicable Disease Management",
      "status": "Not Attempted",
      "passingScore": "80%"
    },
  ];

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final baseSize = mediaQuery.size.shortestSide;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final isTabletDevice = isTablet(context);
    final scale = isTabletDevice ? 1.0 : 1.0;

    int completedModules = 0;
    int totalModules = specializationModules.length;
    double completionPercent = totalModules > 0
        ? (completedModules / totalModules * 100).clamp(0, 100)
        : 0;

    return AppLayout(
      appBar: CustomAppBar(
        onBackPressed: () => Navigator.pop(context),
        requireAuth: false,
        scale: scale,
      ),

      bottomNav: CustomBottomNavBar(
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
  Widget _buildPortraitLayout(
      double screenWidth, double screenHeight, double baseSize, double scale) {
    int completedModules = 0;
    int totalModules = specializationModules.length;
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
                .map((m) => _buildModuleCard(baseSize, m, scale))
                .toList(),
          ),
          SizedBox(height: baseSize * 0.15 * scale),
        ],
      ),
    );
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
      double baseSize, Map<String, dynamic> module, double scale) {
    return Container(
      margin: EdgeInsets.only(bottom: baseSize * 0.03 * scale),
      padding: EdgeInsets.all(baseSize * 0.035 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(baseSize * 0.03 * scale),
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
        children: [
          // Title + Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module['title'],
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
                        color: Colors.grey.shade200,
                        borderRadius:
                        BorderRadius.circular(baseSize * 0.015 * scale),
                      ),
                      child: Text(
                        module['status'],
                        style: TextStyle(
                          fontSize: baseSize * 0.028 * scale,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    SizedBox(width: baseSize * 0.02 * scale),
                    Text(
                      "Passing: ${module['passingScore']}",
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
          const Icon(Icons.more_horiz, color: Colors.grey),
        ],
      ),
    );
  }
}
