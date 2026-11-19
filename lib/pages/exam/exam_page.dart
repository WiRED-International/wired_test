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
  int? _examPersistenceGeneration;
  List<Map<String, dynamic>> _questions = [];
  bool _loading = true;
  bool _error = false;
  bool _recoveryUnresolved = false;
  bool _cameBackFromReview = false;
  bool _savingExit = false;

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
      if (controller.recoveryStateFor(widget.examId, widget.userId) ==
          ExamRecoveryState.resumable) {
        await controller.restoreExamIfExists();
      }
      if (!mounted) return;

      // Resume timer after restore
      controller.resumeTimer();

      // Load questions (cached or new)
      await _loadQuestions();
      if (!mounted || _recoveryUnresolved) return;

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
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_pageController.hasClients &&
            savedIndex >= 0 &&
            savedIndex < _questions.length) {
          debugPrint(
              '⏩ [ExamPage] Jumping to saved question index $savedIndex');

          // 🔥 Fix navigation freeze bug
          await Future.delayed(const Duration(milliseconds: 30));

          _pageController.jumpToPage(savedIndex);
          _ensureScrollHintVisible(savedIndex);
        } else {
          debugPrint('⚠️ [ExamPage] Skipped jumpToPage — controller not ready');
        }

        // 🔥 Safe to resume the timer ONLY AFTER UI + page jump is stable
        controller.resumeTimer();
      });
    } catch (e, st) {
      debugPrint('❌ [ExamPage] Error initializing exam: $e');
      debugPrint(st.toString());
      if (mounted)
        setState(() {
          _loading = false;
          _error = true;
        });
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
      if (_examPersistenceGeneration != null) {
        controller.saveProgress(_currentIndex,
            generation: _examPersistenceGeneration);
      }
    } else if (state == AppLifecycleState.resumed && !_savingExit) {
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

  void _showRecoveryMessage() {
    if (!mounted) return;
    setState(() {
      _recoveryUnresolved = true;
      _loading = false;
    });
  }

  Future<void> _loadQuestions() async {
    if (_questions.isNotEmpty) return;

    final controller = context.read<ExamController>();
    final recovery = controller.recoveryStateFor(widget.examId, widget.userId);
    List<Map<String, dynamic>>? questions;
    if (recovery == ExamRecoveryState.resumable) {
      final attempt = controller.active;
      if (attempt == null ||
          attempt.examId != widget.examId ||
          attempt.userId != widget.userId) {
        _showRecoveryMessage();
        return;
      }
      questions = controller.getCachedQuestions();
      if (questions == null || questions.isEmpty) {
        _showRecoveryMessage();
        return;
      }
    } else {
      // A new session is requested only when no unresolved local session exists.
      questions = await controller.startExam(
          examId: widget.examId, userId: widget.userId);
      if (questions == null || questions.isEmpty) {
        _showRecoveryMessage();
        return;
      }
    }
    if (!mounted) return;

    setState(() {
      _examPersistenceGeneration = controller.persistenceGeneration;
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
    final bool expired = controller.examExpired;

    if (controller.submissionPending) {
      return Scaffold(
        appBar: AppBar(title: const Text('Submission pending')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text(ExamController.pendingSubmissionMessage)),
        ),
      );
    }

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_recoveryUnresolved) {
      return Scaffold(
        appBar: AppBar(title: const Text('Exam recovery')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
              child: Text(
            'A saved exam session needs recovery or the server session could not '
            'be safely verified. '
            'Your saved data has been kept, and no new attempt has been started. '
            'Please return to exam selection and try again when connected, '
            'or ask your instructor or support for help.',
          )),
        ),
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
        if (didPop || _savingExit) return;
        final shouldExit = await DialogUtils.showExitExamDialog(context);
        if (shouldExit && context.mounted) {
          final controller = context.read<ExamController>();
          _savingExit = true;
          controller.pauseTimer();
          try {
            await controller.saveProgress(_currentIndex,
                generation: _examPersistenceGeneration);
            if (!context.mounted) return;
            Navigator.pop(context); // exit only after saving the paused timer
          } catch (_) {
            if (!context.mounted) return;
            if (WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
              controller.resumeTimer();
            }
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Unable to save exam progress. Please try again.'),
            ));
          } finally {
            _savingExit = false;
          }
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
                    formatTime(
                        context.watch<ExamController>().remainingSeconds),
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
            context
                .read<ExamController>()
                .saveProgress(i, generation: _examPersistenceGeneration);
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
                    persistenceGeneration: _examPersistenceGeneration!,
                    question: q,
                    index: index,
                    totalQuestions: _questions.length,
                    isListScrollable: _isListScrollable,
                    listAtBottom: _listAtBottom,
                    scrollControllers: _scrollControllers,
                    examExpired: controller.examExpired,
                  ),
                ),

                // ⬇️ Footer goes here
                FooterButtons(
                  parentContext: context,
                  controller: controller,
                  persistenceGeneration: _examPersistenceGeneration!,
                  currentIndex: _currentIndex,
                  totalQuestions: _questions.length,
                  cameBackFromReview: _cameBackFromReview,
                  pageController: _pageController,
                  updateIndex: (newIndex) {
                    setState(() => _currentIndex = newIndex);
                  },
                  updateCameBackFromReview: (val) {
                    setState(() => _cameBackFromReview = val);
                  },
                  refreshScrollHintForCurrent: () {
                    if (_isListScrollable[_currentIndex] == true) {
                      setState(() => _listAtBottom[_currentIndex] = false);
                    }
                  },
                  examExpired: controller.examExpired,
                ),
                const SizedBox(height: 10),
              ],
            );
          },
        ),
      ),
    );
  }
}
