import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/pages/exam/review_answers_page.dart';
import '../../models/exam_models.dart';
import '../../state/exam_controller.dart';
import '../../utils/time_utils.dart';

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
          debugPrint('⚠️ [ExamPage] Skipped jumpToPage — controller not attached or index=0');
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
        debugPrint('🔁 [ExamPage] Scroll hint reset for question $_currentIndex');
      }
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
        debugPrint('⚠️ No cached questions found during resume — refetching from backend...');
        questions = await controller.startExam(
          examId: widget.examId,
          userId: widget.userId,
          sessionData: widget.sessionData,
        );
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
          title: Text('Time Left: ${formatTime(context.watch<ExamController>().remainingSeconds)}'),
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
            _ensureScrollHintVisible(i);
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
    final isMultiple = q['question_type'] == 'multiple';
    List<dynamic> options = [];

    // Handle both Map and List formats
    if (optionsData is Map<String, dynamic>) {
      options = optionsData.entries
          .map((e) => {'key': e.key, 'value': e.value})
          .toList();
    } else if (optionsData is List) {
      options = optionsData.asMap().entries
          .map((e) => {'key': '${e.key}', 'value': e.value})
          .toList();
    }

    final totalQuestions = _questions.length;

    final answerRecord = controller.active?.answers.firstWhere(
          (a) => a.questionId == q['id'],
      orElse: () => AnswerRecord(
        questionId: q['id'],
        selectedOptionIds: [],
        updatedAt: DateTime.now(),
      ),
    );

    final selectedOptions = (answerRecord?.selectedOptionIds ?? []).cast<String>();

    // Ensure keys exist
    _isListScrollable[index] = _isListScrollable[index] ?? false;
    _listAtBottom[index] = _listAtBottom[index] ?? false;
    _scrollControllers[index] ??= ScrollController();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 📘 Header (kept)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Practice Exam',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.access_time, color: Color(0xFF22C55E)),
                      const SizedBox(width: 6),
                      Text(
                        "${formatTime(controller.remainingSeconds)}  ${index + 1}/$totalQuestions",
                        style: const TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 🔘 Progress bar (kept)
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

            const SizedBox(height: 16),

            // Row with "Question x of y" + Flag (kept)
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
                    onPressed: () => controller.toggleFlag(q['id']),
                    tooltip: controller.isFlagged(q['id'])
                        ? 'Unflag this question'
                        : 'Flag for review',
                  ),
                ],
              ),
            ),

            // Question text (kept)
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

            // 🧩 Answer options with scroll hint + fade (new)
            Expanded(
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (sn) {
                      final max = sn.metrics.maxScrollExtent;
                      final pixels = sn.metrics.pixels;

                      final scrollable = max > 0;
                      final atBottom = pixels >= max - 10;

                      if (_isListScrollable[index] != scrollable ||
                          _listAtBottom[index] != atBottom) {
                        setState(() {
                          _isListScrollable[index] = scrollable;
                          _listAtBottom[index] = atBottom;
                        });
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scrollControllers[index],
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: options.length,
                      itemBuilder: (context, i) {
                        final opt = options[i];
                        final isSelected = selectedOptions.contains(opt['key']);

                        return GestureDetector(
                          onTap: () {
                            if (isMultiple) {
                              if (selectedOptions.contains(opt['key'])) {
                                selectedOptions.remove(opt['key']);
                              } else {
                                selectedOptions.add(opt['key']);
                              }
                              controller.selectMultipleAnswers(
                                q['id'],
                                List<String>.from(selectedOptions),
                              );
                            } else {
                              controller.selectAnswer(q['id'], opt['key']);
                            }
                            setState(() {});
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 16),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFE6F4EA)
                                  : Colors.white,
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
                                  isMultiple
                                      ? (isSelected
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank)
                                      : (isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off),
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

                  // ✨ Fading overlay with "Scroll for more" (new)
                  if ((_isListScrollable[index] ?? false) && !(_listAtBottom[index] ?? false))
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: 1.0,
                          duration: const Duration(milliseconds: 400),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Calculate horizontal shift dynamically — about 25% of screen width
                              final double horizontalShift = constraints.maxWidth * 0.35;

                              return Transform.translate(
                                offset: Offset(horizontalShift, 0), // ✅ pushes it slightly right
                                child: Container(
                                  height: 60,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Color(0xFFF9FAFB), // match your background color
                                      ],
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: const [
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Color(0xFF515151),
                                        size: 18,
                                      ),
                                      Text(
                                        'Scroll for more',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF515151),
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
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
                        // 🟣 NEW: Allow user to reopen ReviewAnswersPage once they’ve reached it
                        if (_cameBackFromReview && !_readyToSubmit) {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReviewAnswersPage(questions: _questions),
                            ),
                          );

                          // 🔁 Handle returned result
                          if (result == 'submitted') {
                            setState(() {
                              _readyToSubmit = true;
                              _cameBackFromReview = false;
                            });
                            return;
                          }

                          if (result is int && result >= 0 && result < _questions.length) {
                            setState(() {
                              _currentIndex = result;
                              _cameBackFromReview = true;

                              // Reset scroll hint for the returned question
                              if (_isListScrollable[result] == true) {
                                _listAtBottom[result] = false;
                              }
                            });
                            _pageController.jumpToPage(result);
                            return;
                          }

                          if (result == 'back_to_questions') {
                            // Re-show scroll hint for the current question when returning
                            if (_isListScrollable[_currentIndex] == true) {
                              _listAtBottom[_currentIndex] = false;
                              setState(() {});
                            }
                            return;
                          }
                        }

                        final nextIndex = _currentIndex + 1;
                        controller.saveProgress(nextIndex);

                        // 🟢 CASE 1: Next question
                        if (_currentIndex < _questions.length - 1) {
                          setState(() => _currentIndex = nextIndex);
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                          return;
                        }

                        // 🟡 CASE 2: Last question → go to ReviewAnswersPage
                        if (_currentIndex == _questions.length - 1 && !_readyToSubmit) {
                          // Reset the flags when navigating to review again
                          _cameBackFromReview = false;

                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReviewAnswersPage(questions: _questions),
                            ),
                          );

                          // 🟢 Case 1: User came back from review (didn't submit)
                          if (result == 'back_to_questions') {
                            setState(() {
                              _cameBackFromReview = true;
                              _readyToSubmit = false;
                            });
                            return;
                          }

                          // 🟣 Case 2: User submitted exam from review page
                          if (result == 'submitted') {
                            setState(() {
                              _readyToSubmit = true;
                              _cameBackFromReview = false;
                            });
                            return;
                          }

                          // 🟠 Case 3: User tapped on a question card → jump directly to it
                          if (result is int && result >= 0 && result < _questions.length) {
                            setState(() {
                              _cameBackFromReview = true;
                              _readyToSubmit = false;
                              _currentIndex = result;
                            });

                            // ✨ Smooth transition animation
                            await _pageController.animateToPage(
                              result,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOut,
                            );
                            return;
                          }
                        } // ✅ properly closes the ReviewAnswersPage block here

                        // 🔵 CASE 3: User ready to submit (final)
                        if (_readyToSubmit) {
                          // Navigate to review page again so the user can confirm submission there
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReviewAnswersPage(questions: _questions),
                            ),
                          );

                          // Handle result returned from review
                          if (result == 'submitted') {
                            // Exam was submitted successfully → go home (review page handles alerts)
                            Future.delayed(const Duration(milliseconds: 100), () {
                              Navigator.of(context).popUntil((route) => route.isFirst);
                            });
                          } else if (result == 'back_to_questions') {
                            setState(() {
                              _cameBackFromReview = true;
                              _readyToSubmit = false;
                            });
                          } else if (result is int && result >= 0 && result < _questions.length) {
                            setState(() {
                              _currentIndex = result;
                              _cameBackFromReview = true;
                              _readyToSubmit = false;
                            });
                            _pageController.jumpToPage(result);
                          }

                          return;
                        }
                      },

                      // 🧠 Button text logic
                      child: Text(
                        _cameBackFromReview
                            ? 'Review Answers' // After first visit to review page
                            : _currentIndex < _questions.length - 1
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
}
