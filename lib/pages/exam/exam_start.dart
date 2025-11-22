import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
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
import 'package:intl/intl.dart';
import '../../utils/screen_utils.dart';


class ExamStart extends StatefulWidget {
  final User user;

  const ExamStart({super.key, required this.user});

  @override
  State<ExamStart> createState() => _ExamStartState();
}

class _ExamStartState extends State<ExamStart> {
  String? assignedExamTitle;
  int? assignedExamDuration;
  bool hasAssignedExam = false;
  bool isLoadingExam = true;
  String? assignedExamStart;
  String? assignedExamEnd;

  @override
  void initState() {
    super.initState();
    _loadAssignedExam();
  }

  // --------------------------------------------
  // 🔵 Load assigned exam ONCE at page load
  // --------------------------------------------
  Future<void> _loadAssignedExam() async {
    try {
      final sync = context.read<ExamSyncService>();
      final res = await sync.dio.get('/exams/assigned');

      final data = res.data is String ? jsonDecode(res.data) : res.data;

      if (data is List && data.isNotEmpty) {
        setState(() {
          hasAssignedExam = true;
          assignedExamTitle = data.first['title'];
          assignedExamDuration = data.first['duration_minutes'];
          assignedExamStart = data.first['available_from'];
          assignedExamEnd = data.first['available_until'];
          isLoadingExam = false;
        });
      } else {
        setState(() {
          hasAssignedExam = false;
          isLoadingExam = false;
        });
      }
    } catch (e) {
      setState(() => isLoadingExam = false);
      print("❌ Error loading assigned exam: $e");
    }
  }

  String _formatLocal(String? utcString) {
    if (utcString == null) return "N/A";

    final utc = DateTime.parse(utcString).toUtc();
    final local = utc.toLocal();

    return DateFormat("MMM d, yyyy   h:mm a").format(local);
  }

  // --------------------------------------------
  // 🔵 Handle Start Exam (resume or new)
  // --------------------------------------------
  Future<void> _handleStartExam() async {
    final controller = context.read<ExamController>();
    final sync = context.read<ExamSyncService>();

    try {
      print('\n==============================');
      print('📦 [DEBUG] Start Exam Button Pressed');
      print('==============================\n');

      // 1️⃣ Try resume
      await controller.restoreExamIfExists();

      final remaining = controller.remainingSeconds;
      final savedExamId = controller.savedExamId;

      if (savedExamId != null && remaining > 0) {
        print('🔁 Resuming exam $savedExamId');

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExamPage(
              examId: savedExamId,
              userId: widget.user.id!,
              sessionData: {'examTitle': assignedExamTitle},
            ),
          ),
        );
        return;
      }

      // 2️⃣ Start new exam session
      final assignedRes = await sync.dio.get('/exams/assigned');
      final data = assignedRes.data is String
          ? jsonDecode(assignedRes.data)
          : assignedRes.data;

      if (data is! List || data.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No exam assigned at this time.')),
        );
        return;
      }

      final examId = data.first['exam_id'];
      final questions = await controller.startExam(
        examId: examId,
        userId: widget.user.id!,
      );

      if (questions == null || questions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to load exam questions.')),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExamPage(
            examId: examId,
            userId: widget.user.id!,
            sessionData: {'examTitle': assignedExamTitle},
          ),
        ),
      );
    } catch (e) {
      print("❌ Error starting exam: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start exam. Try again later.')),
      );
    }
  }

  // --------------------------------------------
  // 📱 Build
  // --------------------------------------------
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final baseSize = media.size.shortestSide;

    final body = _buildContent(context, baseSize);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            _buildBackground(),
            Column(
              children: [
                CustomAppBar(
                  onBackPressed: () => Navigator.pop(context),
                  requireAuth: false,
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (isLandscape)
                        CustomSideNavBar(
                          onHomeTap: () => _navigateTo(const MyHomePage()),
                          onLibraryTap: () => _navigateTo(ModuleLibrary()),
                          onTrackerTap: () => _navigateTo(CMETracker()),
                          onMenuTap: _openMenu,
                        ),
                      Expanded(child: Center(child: body)),
                    ],
                  ),
                ),
                if (!isLandscape)
                  CustomBottomNavBar(
                    onHomeTap: () => _navigateTo(const MyHomePage()),
                    onLibraryTap: () => _navigateTo(ModuleLibrary()),
                    onTrackerTap: () => _navigateTo(CMETracker()),
                    onMenuTap: _openMenu,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------
  // 🔹 Build main content
  // --------------------------------------------
  Widget _buildContent(BuildContext context, double baseSize) {
    final size = MediaQuery.of(context).size;
    final shortest = size.shortestSide;
    final isTablet = ScreenUtils.isTablet(context);

    // Shared button sizing (phone vs tablet)
    final double buttonWidth =
    isTablet ? shortest * 0.3 : shortest * 0.70;
    final double buttonHeight =
    isTablet ? shortest * 0.09 : shortest * 0.17;
    final double buttonFont =
    ScreenUtils.scaleFont(context, 18);

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: baseSize * 0.05,
        vertical: baseSize * 0.03,
      ),
      child: Column(
        children: [
          Text(
            'Welcome to the',
            style: TextStyle(
              fontSize: ScreenUtils.scaleFont(context, 32),
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Final Exam',
            style: TextStyle(
              fontSize: ScreenUtils.scaleFont(context, 32),
              fontWeight: FontWeight.bold,
            ),
          ),

          SizedBox(height: baseSize * 0.02),

          // ---------------------
          // USER INFO
          // ---------------------
          Text(
            'User ID: ${widget.user.id ?? "N/A"}',
            style: TextStyle(
              fontSize: ScreenUtils.scaleFont(context, 20),
            ),
          ),
          Text(
            'Name: ${widget.user.lastName}, ${widget.user.firstName}',
            style: TextStyle(
              fontSize: ScreenUtils.scaleFont(context, 20),
            ),
          ),
          Text(
            'Email: ${widget.user.email}',
            style: TextStyle(
              fontSize: ScreenUtils.scaleFont(context, 20),
            ),
          ),

          SizedBox(height: baseSize * 0.05),

          // ---------------------
          // EXAM MESSAGE
          // ---------------------
          if (isLoadingExam)
            const CircularProgressIndicator()
          else
            _buildAssignedExamMessage(context, baseSize),

          SizedBox(height: baseSize * 0.06),

          // ---------------------
          // START EXAM BUTTON (Correct Placement)
          // ---------------------
          SizedBox(
            width: buttonWidth,
            height: buttonHeight,
            child: ElevatedButton(
              onPressed: isLoadingExam ? null : _handleStartExam,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0070C0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              child: Text(
                'Start Exam',
                style: TextStyle(
                  fontSize: buttonFont,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------
  // 🔹 Assigned Exam UI Block
  // --------------------------------------------
  Widget _buildAssignedExamMessage(BuildContext context, double baseSize) {
    final bodyFont = ScreenUtils.scaleFont(context, 20);
    final titleFont = ScreenUtils.scaleFont(context, 25);

    if (!hasAssignedExam) {
      return Text(
        'You must be scheduled for the exam before you can start it.\n'
            'Do not start until instructed. Good luck!',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: bodyFont,
          color: Colors.black54,
          height: 1.5,
        ),
      );
    }

    return Column(
      children: [
        Text(
          '📘 $assignedExamTitle',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: titleFont,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF0070C0),
          ),
        ),
        SizedBox(height: baseSize * 0.02),
        Text(
          'You are scheduled for this exam.\n'
              'Exam Window:\n'
              '🟢 Opens: ${_formatLocal(assignedExamStart)}\n'
              '🔴 Closes: ${_formatLocal(assignedExamEnd)}\n\n'
              '⏱ Duration: $assignedExamDuration minutes.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: bodyFont,
            color: Colors.black54,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // --------------------------------------------
  // Background gradient
  // --------------------------------------------
  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFFFF0DC),
            Color(0xFFF9EBD9),
            Color(0xFFFFC888),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  // --------------------------------------------
  // Navigation helpers
  // --------------------------------------------
  void _navigateTo(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _openMenu() async {
    bool loggedIn = await checkIfUserIsLoggedIn();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => loggedIn ? Menu() : GuestMenu(),
      ),
    );
  }
}
