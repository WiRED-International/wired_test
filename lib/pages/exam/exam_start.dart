import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import '../../services/exam_sync_service.dart';
import '../../state/exam_controller.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../cme/cme_tracker.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import '../../models/user.dart';
import 'exam_page.dart';

class ExamStart extends StatelessWidget {
  final User user;

  const ExamStart({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final baseSize = MediaQuery.of(context).size.shortestSide;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final scalingFactor = getScalingFactor(context);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Background gradient
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
                CustomAppBar(
                  onBackPressed: () {
                    Navigator.pop(context);
                  },
                  requireAuth: false,
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (isLandscape)
                        CustomSideNavBar(
                          onHomeTap: () => _navigateTo(context, const MyHomePage()),
                          onLibraryTap: () => _navigateTo(context, ModuleLibrary()),
                          onTrackerTap: () => _navigateTo(context, CMETracker()),
                          onMenuTap: () async {
                            bool isLoggedIn = await checkIfUserIsLoggedIn();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                              ),
                            );
                          },
                        ),

                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(context, screenWidth, screenHeight, baseSize, scalingFactor)
                              : _buildPortraitLayout(context, screenWidth, screenHeight, baseSize, scalingFactor),
                        ),
                      ),
                    ],
                  ),
                ),

                if (!isLandscape)
                  CustomBottomNavBar(
                    onHomeTap: () => _navigateTo(context, const MyHomePage()),
                    onLibraryTap: () => _navigateTo(context, ModuleLibrary()),
                    onTrackerTap: () => _navigateTo(context, CMETracker()),
                    onMenuTap: () async {
                      bool isLoggedIn = await checkIfUserIsLoggedIn();
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
          ],
        ),
      ),
    );
  }

  // 📱 Portrait layout
  Widget _buildPortraitLayout(
      BuildContext context, double screenWidth, double screenHeight, double baseSize, double scalingFactor) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: baseSize * 0.05, vertical: baseSize * 0.03),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Welcome to the',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: baseSize * (isTablet(context) ? 0.07 : 0.08),
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          Text(
            'Final Exam',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: baseSize * (isTablet(context) ? 0.07 : 0.08),
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          SizedBox(height: baseSize * 0.02),
          Text(
            'User ID: ${user.id ?? "N/A"}',
            style: TextStyle(
              fontSize: scalingFactor * (isTablet(context) ? 16 : 14),
              color: Colors.black87,
            ),
          ),
          Text(
            'Name: ${user.lastName}, ${user.firstName}',
            style: TextStyle(
              fontSize: scalingFactor * (isTablet(context) ? 16 : 14),
              color: Colors.black87,
            ),
          ),
          Text(
            'Email: ${user.email}',
            style: TextStyle(
              fontSize: scalingFactor * (isTablet(context) ? 16 : 14),
              color: Colors.black87,
            ),
          ),
          SizedBox(height: baseSize * 0.04),
          Text(
            'You must be scheduled for the exam before you can start it. '
            'Do not start the exam until you are instructed to do so. '
            'When you are ready to start the exam, click the button below. '
            "You will have a set amount of time to complete the exam, and you have the option to review all your answers before submitting. "
            "Good luck!"
            ,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: scalingFactor * (isTablet(context) ? 14 : 12),
              color: Colors.black54,
              height: 1.5,
            ),
          ),
          SizedBox(height: baseSize * 0.06),
          ElevatedButton(
            onPressed: () async {
              final sync = context.read<ExamSyncService>();
              final controller = context.read<ExamController>();

              try {
                print('==============================');
                print('📦 [DEBUG] Start Exam Button Pressed');
                print('==============================');

                // 🧩 1️⃣ Try restoring any unfinished exam
                print('🕵️ Checking Hive for existing exam data...');
                await controller.restoreExamIfExists();

                final remaining = controller.remainingSeconds;
                final savedExamId = controller.savedExamId;
                final savedIndex = controller.savedQuestionIndex;

                print('📊 Hive restore results → remaining: $remaining | savedExamId: $savedExamId | savedIndex: $savedIndex');

                final hasSavedExam = savedExamId != null && remaining > 0;

                if (hasSavedExam) {
                  print('🔁 [DEBUG] Resuming saved exam (ID: $savedExamId) at question index $savedIndex');

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Resuming your previous exam...')),
                  );

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExamPage(
                        examId: savedExamId,
                        userId: user.id!,
                        sessionData: null, // no need to refetch, Hive restores it
                      ),
                    ),
                  ).then((_) {
                    // ⏩ Jump to last saved question after navigation delay
                    Future.delayed(const Duration(milliseconds: 500), () {
                      final pageControllerField = controller.savedQuestionIndex;
                      if (pageControllerField > 0) {
                        print('⏩ Jumping to saved question index: $pageControllerField');
                      }
                    });
                  });

                  return;
                }

                // 🧩 2️⃣ Otherwise, start a new exam session
                print('🌐 [DEBUG] No saved exam found — requesting available exam...');
                final res = await sync.dio.get('/exams/available');
                print('✅ [DEBUG] API Response Status: ${res.statusCode}');
                print('📦 [DEBUG] API Raw Response: ${res.data}');

                final data = res.data is String ? jsonDecode(res.data) : res.data;

                if (data != null && data['id'] != null) {
                  final examId = data['id'];
                  print('🚀 [DEBUG] Starting new exam session for examId: $examId');
                  final session = await sync.startExamSession(examId);
                  print('🧾 [DEBUG] Session response: $session');

                  if (session != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExamPage(
                          examId: examId,
                          userId: user.id!,
                          sessionData: session,
                        ),
                      ),
                    );
                  } else {
                    print('⚠️ [DEBUG] startExamSession returned null');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Unable to start exam session.')),
                    );
                  }
                } else {
                  print('⚠️ [DEBUG] No exam available (data = $data)');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No exam available at this time.')),
                  );
                }
              } catch (e, st) {
                print('❌ [DEBUG] Error fetching or resuming exam: $e');
                print(st);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Unable to reach server. Try again later.')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0070C0),
              padding: EdgeInsets.symmetric(
                horizontal: scalingFactor * 40,
                vertical: scalingFactor * 15,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 5,
            ),
            child: Text(
              'Start Exam',
              style: TextStyle(
                fontSize: scalingFactor * (isTablet(context) ? 18 : 16),
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 💻 Landscape layout
  Widget _buildLandscapeLayout(
      BuildContext context, double screenWidth, double screenHeight, double baseSize, double scalingFactor) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: baseSize * 0.08, vertical: baseSize * 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Welcome to WiRED International',
            style: TextStyle(
              fontSize: baseSize * (isTablet(context) ? 0.06 : 0.07),
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          SizedBox(height: baseSize * 0.02),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildUserInfoTile(context, 'User ID', user.id?.toString() ?? 'N/A'),
              _buildUserInfoTile(context, 'Email', user.email ?? 'N/A'),
            ],
          ),
          SizedBox(height: baseSize * 0.04),
          Text(
            'Ensure a stable connection before starting. The exam can be completed offline and submitted when online.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: scalingFactor * (isTablet(context) ? 14 : 12),
              color: Colors.black54,
              height: 1.5,
            ),
          ),
          SizedBox(height: baseSize * 0.06),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Exam will start soon!')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0070C0),
              padding: EdgeInsets.symmetric(
                horizontal: scalingFactor * 50,
                vertical: scalingFactor * 18,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 6,
            ),
            child: Text(
              'Start Exam',
              style: TextStyle(
                fontSize: scalingFactor * (isTablet(context) ? 18 : 16),
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Small reusable info tile
  Widget _buildUserInfoTile(BuildContext context, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.0),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: getScalingFactor(context) * 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: getScalingFactor(context) * 14,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  // Simple navigation helper
  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }
}
