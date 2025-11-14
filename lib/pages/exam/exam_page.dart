import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/exam_controller.dart';
import '../../utils/dialog_utils.dart';
import '../../utils/screen_utils.dart';
import '../../utils/time_utils.dart';
import '../../widgets/exam/footer_buttons.dart';
import '../../widgets/exam/question_card.dart';

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

  // Track scroll state per question index
  final Map<int, bool> _isListScrollable = {};
  final Map<int, bool> _listAtBottom = {};
  final Map<int, ScrollController> _scrollControllers = {};

  void _ensureScrollHintVisible(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = _scrollControllers[index];
      if (ctrl != null && ctrl.hasClients) {
        final maxExtent = ctrl.position.maxScrollExtent;
        if (maxExtent > 0) {
          setState(() {
            _isListScrollable[index] = true;
            _listAtBottom[index] = false; // show hint right away
          });
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeExamState();
  }

  /// Handles resume or fresh load
  Future<void> _initializeExamState() async {
    try {
      final controller = context.read<ExamController>();

      debugPrint('🧩 [ExamPage] Checking for saved exam...');
      await controller.restoreExamIfExists();

      // Resume timer after restore
      controller.resumeTimer();

      // Load questions (cached or new)
      await _loadQuestions();

      // If no questions loaded, bail safely
      if (_questions.isEmpty) {
        debugPrint('⚠️ [ExamPage] No questions found, skipping page jump.');
        setState(() {
          _loading = false;
          _error = true;
        });
        return;
      }

      // After load, sync index
      final savedIndex = controller.getCurrentQuestionIndex();

      // 🧩 Ensure scroll-hint state is initialized or reset properly
      for (int i = 0; i < _questions.length; i++) {
        // keep structure consistent
        _isListScrollable[i] = _isListScrollable[i] ?? false;

        // ✅ reset the “at bottom” flag only for the current question
        if (i == savedIndex) {
          _listAtBottom[i] = false;
        } else {
          // preserve others if you want them remembered, or reset all to false
          _listAtBottom[i] = _listAtBottom[i] ?? false;
        }
      }

      setState(() {
        _currentIndex = savedIndex;
        _loading = false;
        _error = false;
      });

      // ✅ Delay jump until PageView is attached
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients &&
            savedIndex >= 0 &&
            savedIndex < _questions.length) {
          _pageController.jumpToPage(savedIndex);
          debugPrint('⏩ [ExamPage] Jumped to saved question index $savedIndex');

          _ensureScrollHintVisible(savedIndex);
        } else {
          debugPrint(
              '⚠️ [ExamPage] Skipped jumpToPage — controller not attached or index=0');
        }
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

    // Dispose all scroll controllers safely
    for (final ctrl in _scrollControllers.values) {
      ctrl.dispose();
    }
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

      // ✅ Safely reset scroll hint only for the current visible question
      if (_isListScrollable[_currentIndex] == true) {
        _listAtBottom[_currentIndex] = false;
        // Rebuild only if mounted (avoid setState on disposed widget)
        if (mounted) setState(() {});
        debugPrint(
            '🔁 [ExamPage] Scroll hint reset for question $_currentIndex');
      }
    }
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
        debugPrint(
            '⚠️ No cached questions found during resume — refetching from backend...');
        questions = await controller.startExam(
          examId: widget.examId,
          userId: widget.userId,
        );
      }
    } else {
      // ✅ Fresh start → start session and cache questions
      questions = await controller.startExam(
        examId: widget.examId,
        userId: widget.userId,
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
    final timeText = formatTime(remaining);

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
        final shouldExit = await DialogUtils.showExitExamDialog(context);
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
          backgroundColor: const Color(0xFF0070C0),
          elevation: 0,
          title: Row(
            children: [
              // 📘 Exam Title (responsive)
              Expanded(
                child: Text(
                  widget.sessionData?['examTitle'] ?? 'Exam',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ScreenUtils.scaleFont(context, 19),
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // ⏱ Timer Cluster (responsive)
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    color: Colors.white,
                    size: ScreenUtils.scaleFont(context, 16),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatTime(context
                        .watch<ExamController>()
                        .remainingSeconds),
                    style: TextStyle(
                      fontSize: ScreenUtils.scaleFont(context, 16),
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        body: PageView.builder(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _questions.length,
          onPageChanged: (i) {
            // keeps UI index and Hive in sync
            setState(() => _currentIndex = i);
            context.read<ExamController>().saveProgress(i);
            _ensureScrollHintVisible(i);
          },
          itemBuilder: (context, index) {
            final q = _questions[index];
            return Column(
              children: [
                Expanded(
                  child: QuestionCard(
                    parentContext: context,
                    controller: controller,
                    question: q,
                    index: index,
                    totalQuestions: _questions.length,
                    isListScrollable: _isListScrollable,
                    listAtBottom: _listAtBottom,
                    scrollControllers: _scrollControllers,
                  ),
                ),

                // ⬇️ Footer goes here
                FooterButtons(
                  parentContext: context,
                  controller: controller,
                  currentIndex: _currentIndex,
                  totalQuestions: _questions.length,
                  cameBackFromReview: _cameBackFromReview,
                  readyToSubmit: _readyToSubmit,
                  pageController: _pageController,

                  updateIndex: (newIndex) {
                    setState(() => _currentIndex = newIndex);
                  },
                  updateCameBackFromReview: (val) {
                    setState(() => _cameBackFromReview = val);
                  },
                  updateReadyToSubmit: (val) {
                    setState(() => _readyToSubmit = val);
                  },
                  refreshScrollHintForCurrent: () {
                    if (_isListScrollable[_currentIndex] == true) {
                      setState(() => _listAtBottom[_currentIndex] = false);
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
