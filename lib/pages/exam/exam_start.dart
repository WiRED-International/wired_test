import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/exam_sync_service.dart';
import '../../state/exam_controller.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../../utils/app_layout.dart';
import '../cme/cme_tracker.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import '../../models/user.dart';
import 'exam_page.dart';
import 'package:intl/intl.dart';
import '../../utils/screen_utils.dart';
import '../creditsTracker/credits_tracker.dart';

class ExamStart extends StatefulWidget {
  final User user;

  const ExamStart({super.key, required this.user});

  @override
  State<ExamStart> createState() => _ExamStartState();
}

class _ExamStartState extends State<ExamStart> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _exams = [];
  bool isLoadingExam = true;
  bool _starting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAssignedExam();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_starting &&
        !isLoadingExam &&
        ModalRoute.of(context)?.isCurrent == true) {
      _loadAssignedExam();
    }
  }

  Future<void> _loadAssignedExam() async {
    if (!mounted) return;
    setState(() {
      isLoadingExam = true;
      _loadError = null;
    });
    try {
      final res =
          await context.read<ExamSyncService>().dio.get('/exams/assigned');
      final data = res.data is String ? jsonDecode(res.data) : res.data;
      if (data is! List) {
        throw const FormatException('Expected assigned exam list');
      }
      final exams =
          data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      if (!mounted) return;
      setState(() {
        _exams = exams;
        isLoadingExam = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _exams = [];
        _loadError = 'Unable to load assigned exams. Please try again.';
        isLoadingExam = false;
      });
      debugPrint('Error loading assigned exams: $e');
    }
  }

  String _formatLocal(Object? value) {
    final date = value is String ? DateTime.tryParse(value) : null;
    if (date == null) return 'N/A';
    return DateFormat('MMM d, yyyy   h:mm a').format(date.toLocal());
  }

  Future<void> _openExam(int examId, String? title) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ExamPage(
                  examId: examId,
                  userId: widget.user.id!,
                  sessionData: {'examTitle': title},
                )));
    if (mounted) await _loadAssignedExam();
  }

  Future<void> _handleStartExam([Map<String, dynamic>? selected]) async {
    if (_starting) return;
    setState(() => _starting = true);
    final controller = context.read<ExamController>();
    try {
      // Recovery takes priority before any new session or assignment lookup.
      final recoveryExamId = controller.savedExamId ?? selected?['exam_id'];
      if (recoveryExamId is int &&
          controller.recoveryStateFor(recoveryExamId, widget.user.id!) ==
              ExamRecoveryState.unresolved) {
        final questions = await controller.startExam(
            examId: recoveryExamId, userId: widget.user.id!);
        if (!mounted) return;
        if (questions == null || questions.isEmpty) {
          _showRecoveryMessage();
          return;
        }
        await _openExam(recoveryExamId, selected?['title'] as String?);
        return;
      }
      await controller.restoreExamIfExists();
      if (!mounted) return;
      final savedId = controller.savedExamId;
      if (savedId != null && controller.remainingSeconds > 0) {
        final matching = _exams.where((exam) => exam['exam_id'] == savedId);
        await _openExam(savedId,
            matching.isEmpty ? null : matching.first['title'] as String?);
        return;
      }
      if (selected == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No saved exam is available to resume.')));
        return;
      }
      if (selected['status'] != 'open' || selected['exam_id'] is! int) return;
      final examId = selected['exam_id'] as int;
      final recovery = controller.recoveryStateFor(examId, widget.user.id!);
      if (recovery == ExamRecoveryState.resumable) {
        await _openExam(examId, selected['title'] as String?);
        return;
      }
      // The backend still enforces availability, enrollment and attempt limits.
      final questions =
          await controller.startExam(examId: examId, userId: widget.user.id!);
      if (!mounted) return;
      if (questions == null || questions.isEmpty) {
        _showRecoveryMessage();
        return;
      }
      await _openExam(examId, selected['title'] as String?);
    } catch (e) {
      debugPrint('Error starting exam: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unable to start exam. Try again later.')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _showRecoveryMessage() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
      context.read<ExamController>().recoveryMessage ??
          'A saved exam session needs recovery or the server session could not be '
              'safely verified. Your saved data has been kept; no new attempt has been '
              'started. Try again when connected, or ask your instructor or support for help.',
    )));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final baseSize = media.size.shortestSide;

    final body = _buildContent(context, baseSize);

    return AppLayout(
      appBar: CustomAppBar(
        onBackPressed: () => Navigator.pop(context),
        requireAuth: false,
      ),

      bottomNav: isLandscape
          ? null
          : CustomBottomNavBar(
              onHomeTap: () => _navigateTo(const MyHomePage()),
              onLibraryTap: () => _navigateTo(ModuleLibrary()),
              onTrackerTap: () => _navigateTo(CreditsTracker()),
              onMenuTap: _openMenu,
            ),

      // ❗ IMPORTANT: no Center()
      child: isLandscape
          ? Row(
              children: [
                CustomSideNavBar(
                  onHomeTap: () => _navigateTo(const MyHomePage()),
                  onLibraryTap: () => _navigateTo(ModuleLibrary()),
                  onTrackerTap: () => _navigateTo(CMETracker()),
                  onMenuTap: _openMenu,
                ),
                Expanded(child: body),
              ],
            )
          : body,
    );
  }

  // --------------------------------------------
  // 🔹 Build main content
  // --------------------------------------------
  Widget _buildContent(BuildContext context, double baseSize) {
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
          if (context.watch<ExamController>().savedExamId != null)
            ElevatedButton(
              key: const ValueKey('resume-exam'),
              onPressed: _starting ? null : () => _handleStartExam(),
              child: const Text('Resume Exam'),
            ),
          TextButton.icon(
            onPressed: isLoadingExam || _starting ? null : _loadAssignedExam,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh exams'),
          ),
          if (isLoadingExam)
            const CircularProgressIndicator()
          else if (_loadError != null)
            Text(_loadError!)
          else if (_exams.isEmpty)
            const Text(
                'You must be scheduled for the exam before you can start it.')
          else
            for (final exam in _exams) _buildExamCard(context, exam),
        ],
      ),
    );
  }

  // --------------------------------------------
  // 🔹 Assigned Exam UI Block
  // --------------------------------------------
  Widget _buildExamCard(BuildContext context, Map<String, dynamic> exam) {
    final open = exam['status'] == 'open';
    final status = open
        ? 'Open'
        : exam['status'] == 'upcoming'
            ? 'Upcoming'
            : 'Unavailable';
    return Card(
      key: ValueKey('exam-${exam['exam_id']}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(exam['title']?.toString() ?? 'Exam',
              style: TextStyle(
                  fontSize: ScreenUtils.scaleFont(context, 22),
                  fontWeight: FontWeight.bold)),
          Text(status,
              style: TextStyle(
                  color: open ? Colors.green.shade800 : Colors.black87,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("Times shown in your device's local timezone."),
          Text('Opens: ${_formatLocal(exam['available_from'])}'),
          Text('Closes: ${_formatLocal(exam['available_until'])}'),
          Text("Duration: ${exam['duration_minutes'] ?? 'N/A'} minutes"),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: open && exam['exam_id'] is int && !_starting
                ? () => _handleStartExam(exam)
                : null,
            child: const Text('Start Exam'),
          ),
        ]),
      ),
    );
  }

  Future<void> _navigateTo(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await _loadAssignedExam();
  }

  void _openMenu() async {
    bool loggedIn = await checkIfUserIsLoggedIn();
    if (!mounted) return;
    await _navigateTo(loggedIn ? Menu() : GuestMenu());
  }
}
