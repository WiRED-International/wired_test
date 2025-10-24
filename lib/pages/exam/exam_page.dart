import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/pages/exam/review_answers_page.dart';
import '../../models/exam_models.dart';
import '../../services/exam_sync_service.dart';
import '../../services/retry_queue_service.dart';
import '../../state/exam_controller.dart';

class ExamPage extends StatefulWidget {
  final int examId;
  final int userId;
  final Map<String, dynamic>? sessionData;

  const ExamPage({
    super.key,
    required this.examId,
    required this.userId,
    this.sessionData,
  });

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  List<Map<String, dynamic>> _questions = [];
  bool _loading = true;
  bool _error = false;
  bool _cameBackFromReview = false;
  bool _readyToSubmit = false;
  late ExamController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      controller = Provider.of<ExamController>(context, listen: false);

      controller.timeExpired.addListener(() {
        if (controller.timeExpired.value && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ReviewAnswersPage(
                questions: controller.getCachedQuestions() ?? [],
                readOnly: true, // ✅ locks review mode
              ),
            ),
          );
        }
      });
      await _initializeExamState();
    });
  }

  /// Handles resume or fresh load
  Future<void> _initializeExamState() async {
    try {
      final controller = context.read<ExamController>();

      debugPrint('🧩 [ExamPage] Checking for saved exam...');
      await controller.restoreExamIfExists();

      // Always ensure timer runs again after restore
      controller.resumeTimer();

      // Always load questions from backend/sessionData
      await _loadQuestions();

      // After load, sync index and UI
      final savedIndex = controller.getCurrentQuestionIndex();
      setState(() {
        _currentIndex = savedIndex;
        _loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pageController.jumpToPage(savedIndex);
        debugPrint('⏩ [ExamPage] Jumped to saved question index $savedIndex');
      });
    } catch (e, st) {
      debugPrint('❌ [ExamPage] Error initializing exam: $e');
      debugPrint(st.toString());
      setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    // Don't access context here — rely on lifecycle saves instead
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = context.read<ExamController>();

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      debugPrint('💾 [ExamPage] Auto-saving exam progress on app pause...');
      controller.pauseTimer();
      controller.saveProgress(_currentIndex);
    } else if (state == AppLifecycleState.resumed) {
      controller.resumeTimer();
    }
  }

  Future<bool> _showExitDialog(BuildContext context) async {
    return (await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exit Exam?'),
        content: const Text('Your progress will be saved so you can continue later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save & Exit'),
          ),
        ],
      ),
    )) ??
        false;
  }

  Future<void> _loadQuestions() async {
    if (_questions.isNotEmpty) return;

    final controller = context.read<ExamController>();
    final isResumingSameExam =
        controller.remainingSeconds > 0 &&
            controller.savedExamId == widget.examId;

    List<Map<String, dynamic>>? questions;

    if (isResumingSameExam) {
      // ✅ Use cached questions on resume (don’t create a new attempt)
      questions = controller.getCachedQuestions();
      if (questions == null || questions.isEmpty) {
        // Fallback: if no cache (first time implementing), do a safe fetch-only call
        // If you don’t have a separate “fetchQuestions” API, keep this as null and show error.
        debugPrint('⚠️ No cached questions found during resume.');
      }
    } else {
      // ✅ Fresh start → start session and cache questions
      questions = await controller.startExam(
        examId: widget.examId,
        userId: widget.userId,
        sessionData: widget.sessionData,
      );
    }

    setState(() {
      _questions = questions ?? [];
      _loading = false;
      _error = _questions.isEmpty;
    });

    debugPrint('🧠 Restored ${_questions.length} questions');
    if (_questions.isNotEmpty) {
      debugPrint('🧩 Example question: ${_questions.first}');
    }

    // Sync index after questions are available
    final savedIndex = controller.getCurrentQuestionIndex();
    if (savedIndex != 0 && savedIndex < _questions.length) {
      _currentIndex = savedIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(savedIndex);
          debugPrint('⏩ Jumped to saved question index $savedIndex');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExamController>();
    final remaining = controller.remainingSeconds;
    final timeText = _formatTime(remaining);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error || _questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Exam')),
        body: const Center(
          child: Text('Failed to load exam questions. Please try again.'),
        ),
      );
    }

      return PopScope(
        canPop: false, // we decide when to pop
        // ✅ Use this if your SDK shows onPopInvoked as deprecated:
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final shouldExit = await _showExitDialog(context);
          if (shouldExit) {
            final controller = context.read<ExamController>();
            await controller.saveProgress(_currentIndex);
            if (!mounted) return;
            Navigator.pop(context); // exit after saving
          }
        },
        child: Scaffold(
        backgroundColor: const Color(0xFFFFF7EB),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text('Time Left: ${_formatTime(context.watch<ExamController>().remainingSeconds)}'),
          centerTitle: true,
          backgroundColor: const Color(0xFF0070C0),
        ),
        body: PageView.builder(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _questions.length,
          onPageChanged: (i) {
            // keeps UI index and Hive in sync
            setState(() => _currentIndex = i);
            context.read<ExamController>().saveProgress(i);
          },
          itemBuilder: (context, index) {
            final q = _questions[index];
            return _buildQuestionCard(context, context.read<ExamController>(), q, index);
          },
        ),
      ),
    );
  }

  // 🧩 Builds each question card
  Widget _buildQuestionCard(
      BuildContext context,
      ExamController controller,
      Map<String, dynamic> q,
      int index,
      ) {
    final questionText = q['question_text'] ?? q['text'] ?? 'No question text';
    final optionsData = q['options'];
    List<dynamic> options = [];

    // Handle both Map and List formats for options
    if (optionsData is Map<String, dynamic>) {
      options = optionsData.entries.map((e) => {'key': e.key, 'value': e.value}).toList();
    } else if (optionsData is List) {
      options = optionsData.asMap().entries.map((e) => {'key': '${e.key}', 'value': e.value}).toList();
    }

    final totalQuestions = _questions.length;
    final selectedOption = controller.active?.answers
        .firstWhere(
          (a) => a.questionId == q['id'],
      orElse: () => AnswerRecord(
        questionId: q['id'],
        selectedOptionId: null,
        updatedAt: DateTime.now(),
      ),
    )
        .selectedOptionId;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 📘 Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Practice Exam',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.access_time, color: Color(0xFF22C55E)),
                      const SizedBox(width: 6),
                      Text(
                        "${_formatTime(controller.remainingSeconds)}  ${index + 1}/$totalQuestions",
                        style: const TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 🔘 Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (index + 1) / totalQuestions,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade300,
                  color: const Color(0xFF22C55E),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Question info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Question ${index + 1} of $totalQuestions',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      controller.isFlagged(q['id'])
                          ? Icons.flag
                          : Icons.outlined_flag,
                      color: controller.isFlagged(q['id'])
                          ? Colors.orange
                          : Colors.grey,
                    ),
                    onPressed: () {
                      controller.toggleFlag(q['id']);
                    },
                    tooltip: controller.isFlagged(q['id'])
                        ? 'Unflag this question'
                        : 'Flag for review',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text(
                questionText,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),

            // 🧩 Answer options
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final opt = options[i];
                  final isSelected = selectedOption == opt['key'];

                  return GestureDetector(
                    onTap: () {
                      controller.selectAnswer(q['id'], opt['key']);
                      setState(() {});
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFE6F4EA) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF22C55E)
                              : Colors.grey.shade300,
                          width: 1.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: isSelected
                                ? const Color(0xFF22C55E)
                                : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              opt['value'].toString(),
                              style: TextStyle(
                                fontSize: 17,
                                color: isSelected
                                    ? const Color(0xFF22C55E)
                                    : Colors.black87,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // ⬜ Footer buttons (includes full review logic)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // PREVIOUS button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _currentIndex > 0
                          ? () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                        setState(() => _currentIndex--);
                      }
                          : null,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        "Previous",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // NEXT / REVIEW / SUBMIT button
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        final nextIndex = _currentIndex + 1;
                        controller.saveProgress(nextIndex);

                        // 🟢 1️⃣ Next question
                        if (_currentIndex < _questions.length - 1) {
                          setState(() => _currentIndex = nextIndex);
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                          return;
                        }

                        // 🟡 2️⃣ Last question → open ReviewAnswersPage
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReviewAnswersPage(questions: _questions),
                          ),
                        );

                        // 🔙 Only handle "back to questions"
                        if (result == 'back_to_questions') {
                          setState(() {});
                        }

                        // No submission handling here — handled fully in ReviewAnswersPage
                      },

                      // 🧠 Button text logic
                      child: Text(
                        _currentIndex < _questions.length - 1
                            ? 'Next Question'
                            : _readyToSubmit
                            ? 'Submit Exam'
                            : 'Review Answers',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }
}
