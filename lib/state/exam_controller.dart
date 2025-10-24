import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/exam_models.dart';
import '../pages/exam/review_answers_page.dart';
import '../utils/validation.dart';
import '../services/exam_sync_service.dart';

class ExamController extends ChangeNotifier {
  final Box<ExamAttempt> _attempts;
  final ExamSyncService _syncService;
  final Box _examBox; // ✅ persistent exam session data
  final Map<int, bool> _flaggedQuestions = {}; // questionId → true/false
  final ValueNotifier<bool> timeExpired = ValueNotifier(false);
  bool isFlagged(int questionId) => _flaggedQuestions[questionId] ?? false;
  Timer? _cleanupTimer; // clears cache after 3 hours (runtime)

  void toggleFlag(int questionId) {
    _flaggedQuestions[questionId] = !(_flaggedQuestions[questionId] ?? false);
    // Persist to Hive
    _examBox.put('flagged_questions',
        _flaggedQuestions.map((k, v) => MapEntry(k.toString(), v)));
    notifyListeners();
  }

  int get flaggedQuestionsCount =>
      _flaggedQuestions.values.where((v) => v == true).length;

  void restoreFlags() {
    final stored = _examBox.get('flagged_questions');
    if (stored is Map) {
      _flaggedQuestions
        ..clear()
        ..addAll(stored.map(
              (k, v) => MapEntry(int.tryParse(k.toString()) ?? 0, v == true),
        ));
    }
  }

  ExamAttempt? _active;
  Timer? _tick;
  int _remainingSeconds = 0;
  bool _isPaused = false;

  ExamController(this._attempts, this._syncService, this._examBox);

  ExamAttempt? get active => _active;
  int get remainingSeconds => _remainingSeconds;

  // ✅ Public getters for accessing saved Hive data
  int? get savedExamId => _examBox.get('exam_id');
  int get savedQuestionIndex => _examBox.get('current_index', defaultValue: 0);

  /// 🔹 Start an exam (either from backend or cached sessionData)
  Future<List<Map<String, dynamic>>?> startExam({
    required int examId,
    required int userId,
    Map<String, dynamic>? sessionData,
  }) async {
    try {
      final response = sessionData ?? await _syncService.startExamSession(examId);
      if (response == null) {
        debugPrint('❌ Failed to start session — using fallback.');
        return null;
      }

      final sessionId = response['session_id'];
      final exam = response['exam'];
      final durationMinutes = exam?['duration_minutes'] ?? 0;
      final durationSeconds = durationMinutes * 60;
      final questions =
          (response['questions'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      // ✅ Create and persist attempt
      final attempt = ExamAttempt(
        attemptId: sessionId.toString(),
        examId: examId,
        userId: userId,
        startedAt: DateTime.now(),
        durationSeconds: durationSeconds,
        answers: [],
        submitted: false,
      );

      await _attempts.put(attempt.attemptId, attempt);
      _active = attempt;
      _active!.isReviewed = false;
      await _active!.save();
      _remainingSeconds = durationSeconds;

      // ✅ Persist timer metadata in Hive
      await _examBox.put('exam_start_time', DateTime.now().toIso8601String());
      await _examBox.put('exam_duration', durationMinutes);
      await _examBox.put('exam_id', examId);
      await _examBox.put('user_id', userId);
      await _examBox.put('session_id', sessionId);
      await _examBox.put('current_index', 0);
      await _examBox.put('cached_questions',
          questions.map((q) => Map<String, dynamic>.from(q)).toList());

      _startTimer();

      // 🧹 Schedule automatic cache cleanup after 3 hours (runtime)
      _cleanupTimer?.cancel();
      _cleanupTimer = Timer(const Duration(hours: 3), () async {
        debugPrint('🕒 [ExamController] Auto-clearing cache after 3 hours (runtime)');
        await clearExamPersistence();
      });

      notifyListeners();

      debugPrint('🧠 [ExamController] Started new exam and cached ${questions.length} questions.');
      return questions;
    } catch (e, st) {
      debugPrint('❌ [ExamController] Error starting exam: $e');
      debugPrint(st.toString());
      return null;
    }
  }

  /// ✅ Retrieve cached questions from Hive (used when resuming exam)
  List<Map<String, dynamic>>? getCachedQuestions() {
    final raw = _examBox.get('cached_questions');
    if (raw is List) {
      return raw.map((item) {
        // Convert the root question map safely
        final q = Map<String, dynamic>.from(item as Map);

        // Normalize 'options' if it exists
        if (q['options'] != null) {
          final options = q['options'];
          if (options is Map) {
            q['options'] = Map<String, dynamic>.from(options);
          } else if (options is List) {
            // Some questions use list-based options
            q['options'] = options.map((e) => e is Map ? Map<String, dynamic>.from(e) : {'value': e}).toList();
          }
        }

        return q;
      }).toList();
    }
    return null;
  }

  // ⏱️ Restore timer and state if app reopened mid-exam
  Future<void> restoreExamIfExists() async {
    final startTimeStr = _examBox.get('exam_start_time');
    final duration = _examBox.get('exam_duration');
    final examId = _examBox.get('exam_id');
    final userId = _examBox.get('user_id');
    final attemptId = _examBox.get('attempt_id');
    final savedAnswers = _examBox.get('saved_answers');
    final savedIndex = _examBox.get('current_index');
    final remainingSeconds = _examBox.get('remaining_seconds');
    final isPaused = _examBox.get('is_paused') ?? false;
    final isReviewed = _examBox.get('is_reviewed') ?? false;

    restoreFlags();

    // 🕒 Check 3-hour global cache expiration
    if (startTimeStr != null) {
      final startedAt = DateTime.tryParse(startTimeStr);
      if (startedAt != null && DateTime.now().isAfter(startedAt.add(const Duration(hours: 3)))) {
        debugPrint('🕒 [ExamController] Cache expired (3-hour limit) — clearing.');
        await clearExamPersistence();
        return;
      }
    }

    if (startTimeStr == null || duration == null || examId == null) {
      debugPrint('⚠️ [ExamController] No saved exam found.');
      return;
    }

    // Restore or create active attempt
    final attempt = _attempts.get(attemptId) ??
        ExamAttempt(
          attemptId: attemptId?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
          examId: examId,
          userId: userId ?? 0,
          startedAt: DateTime.parse(startTimeStr),
          durationSeconds: duration * 60,
          answers: [],
          submitted: false,
        );

    // Restore answers
    if (savedAnswers is List && savedAnswers.isNotEmpty) {
      attempt.answers = savedAnswers.map((a) {
        return AnswerRecord(
          questionId: a['question_id'],
          selectedOptionId: a['selected_option'],
          updatedAt:
            DateTime.tryParse(a['updated_at'] ?? '') ?? DateTime.now(),
        );
      }).toList();
    }

    // ✅ Restore review flag
    attempt.isReviewed = isReviewed;

    _active = attempt;
    _remainingSeconds = remainingSeconds ?? (duration * 60);
    _isPaused = isPaused;

    // Re-save to Hive if missing
    await _attempts.put(_active!.attemptId, _active!);
    await _examBox.put('current_index', savedIndex);

    // ⏱️ Case 1: Exam still has time left — resume normally
    if (!_isPaused && _remainingSeconds > 0) {
      _startTimer();
    }

    // ⏰ Case 2: Timer already hit zero — redirect to Review Page (read-only)
    if (_remainingSeconds <= 0 && !_active!.submitted) {
      debugPrint('⏰ [ExamController] Time already expired — redirecting to review.');
      await Future.delayed(const Duration(milliseconds: 300));
      return;
    }

    restoreFlags();

    notifyListeners();

    debugPrint('✅ [ExamController] Exam restored | Q$savedIndex | $_remainingSeconds s left');
  }

  // ✅ Timer logic
  void _startTimer() {
    _tick?.cancel();
    if (_remainingSeconds <= 0) return;

    debugPrint('⏱️ [ExamController] Timer started | $_remainingSeconds s left');

    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remainingSeconds <= 0) {
        t.cancel();
        _submitOnTimeout();
      } else {
        _remainingSeconds -= 1;
        notifyListeners();
      }
    });
  }

  void pauseTimer() {
    if (_tick != null) {
      _tick!.cancel();
      _isPaused = true;
      debugPrint('⏸️ [ExamController] Timer paused ($_remainingSeconds s left)');
    }
  }

  void resumeTimer() {
    if (_isPaused && _remainingSeconds > 0) {
      _isPaused = false;
      _startTimer();
    }
  }

  Future<void> _submitOnTimeout() async {
    debugPrint('⏰ Exam time expired!');
    _tick?.cancel();

    // Mark as reviewed but don't clear cache
    if (_active != null) {
      _active!.isReviewed = true;
      await _active!.save();
    }

    // Notify UI through ValueNotifier
    timeExpired.value = true;

    // Notify listeners (UI can react)
    notifyListeners();
  }

  // ✅ Save and restore progress
  Future<void> saveProgress(int questionIndex) async {
    if (_active == null) return;

    // Store answers snapshot
    final cachedAnswers = _active!.answers
        .map((a) => {
      'question_id': a.questionId,
      'selected_option': a.selectedOptionId,
      'updated_at': a.updatedAt.toIso8601String(),
    })
        .toList();

    await _examBox.putAll({
      'exam_id': _active!.examId,
      'user_id': _active!.userId,
      'attempt_id': _active!.attemptId,
      'current_index': questionIndex,
      'saved_answers': cachedAnswers,
      'remaining_seconds': _remainingSeconds,
      'is_paused': _isPaused,
      'last_saved': DateTime.now().toIso8601String(),
    });

    debugPrint('💾 [ExamController] Progress saved: Q$questionIndex | ${_remainingSeconds}s left');
  }

  int getCurrentQuestionIndex() => _examBox.get('current_index', defaultValue: 0);

  // ✅ Select / update answer
  void selectAnswer(int questionId, String selectedOptionId) async {
    if (_active == null) return;

    final existingIndex = _active!.answers.indexWhere((a) => a.questionId == questionId);

    if (existingIndex != -1) {
      _active!.answers[existingIndex].selectedOptionId = selectedOptionId;
      _active!.answers[existingIndex].updatedAt = DateTime.now();
    } else {
      _active!.answers.add(
        AnswerRecord(
          questionId: questionId,
          selectedOptionId: selectedOptionId,
          updatedAt: DateTime.now(),
        ),
      );
    }

    await _active!.save();

    // 🧠 Persist answers in Hive for recovery
    final cachedAnswers = _active!.answers
        .map((a) => {
      'question_id': a.questionId,
      'selected_option': a.selectedOptionId,
      'updated_at': a.updatedAt.toIso8601String(),
    })
        .toList();
    await _examBox.put('saved_answers', cachedAnswers);

    notifyListeners();
  }

  void markReviewed() async {
    if (_active != null) {
      _active!.isReviewed = true;
      await _active!.save();
      notifyListeners();
    }
  }

  void resetReviewFlag() async {
    if (_active != null) {
      _active!.isReviewed = false;
      await _active!.save();
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> buildSubmissionPayload() async {
    if (_active == null) return null;

    final payload = {
      'attempt_id': _active!.attemptId,
      'exam_id': _active!.examId,
      'user_id': _active!.userId,
      'started_at': _active!.startedAt.toIso8601String(),
      'submitted_at': DateTime.now().toIso8601String(),
      'answers': _active!.answers.map((a) => {
        'question_id': a.questionId,
        'selected_option': a.selectedOptionId,
        'updated_at': a.updatedAt.toIso8601String(),
      }).toList(),
      'client_meta': {
        'app_version': '2.0.0',
        'device': 'android',
      }
    };

    final errors = validateSubmission(payload);
    if (errors.isNotEmpty) {
      debugPrint('Validation errors: $errors');
      return null;
    }
    return payload;
  }

  // ✅ Submit or enqueue
  Future<bool> submitNow({
    required Future<bool> Function(Map<String, dynamic>) onSubmit,
    required Future<void> Function(Map<String, dynamic>) onEnqueue,
  }) async {
    try {
      if (_active == null) return false;
      // 🔹 Build submission data
      final payload = await buildSubmissionPayload();
      if (payload == null) return false;

      bool ok = false;
      try {
        ok = await onSubmit(payload);
      } catch (e) {
        debugPrint('❌ [ExamController] Submit failed: $e');
        ok = false;
      }

      if (ok) {
        // Mark submission successful
        _active!
          ..submitted = true
          ..submittedAt = DateTime.now();
        await _active!.save();
        debugPrint('✅ [ExamController] Submission successful — clearing Hive...');
        // ✅ Clear all persisted exam data
        await clearExamPersistence();
      } else {
        // 🟡 Network or backend failure → enqueue for retry
        debugPrint('⚠️ [ExamController] Submission failed — enqueuing for retry');
        await onEnqueue(payload);
      }

      notifyListeners();
      debugPrint('🎯 [ExamController] ok=$ok | active.submitted=${_active?.submitted}');
      return ok; // ✅ return true if submission succeeded
    } catch (e) {
      debugPrint('❌ [ExamController] Exception during submit: $e');
      // Don’t clear cache if submission failed!
      final fallbackPayload = await buildSubmissionPayload();
      if (fallbackPayload != null) {
        await onEnqueue(fallbackPayload);
      } else {
        debugPrint('⚠️ [ExamController] Could not build fallback payload, skipping enqueue');
      }
      return false;
    }
  }

  // 🧹 Clear all Hive data related to the ongoing exam
  Future<void> clearExamPersistence() async {
    await _examBox.delete('exam_start_time');
    await _examBox.delete('exam_duration');
    await _examBox.delete('exam_id');
    await _examBox.delete('user_id');
    await _examBox.delete('session_id');
    await _examBox.delete('current_index');
    await _examBox.delete('saved_answers');
    await _examBox.delete('cached_questions'); // 🟢 add this line
    await _examBox.delete('flagged_questions');
    debugPrint('🧹 Cleared exam cache after submission');
  }

  /// 🧾 Debug utility: logs all Hive keys/values in the exam box
  Future<void> logExamBoxContents([String label = '']) async {
    final keys = _examBox.keys.toList();
    debugPrint('==============================');
    debugPrint('📦 [Hive Debug] Exam Box State $label');
    if (keys.isEmpty) {
      debugPrint('🔹 (empty)');
    } else {
      for (final k in keys) {
        debugPrint('🔹 $k → ${_examBox.get(k)}');
      }
    }
    debugPrint('==============================');
  }

  @override
  void dispose() {
    _tick?.cancel();
    _cleanupTimer?.cancel(); // stop 3-hour timer when controller destroyed
    super.dispose();
  }
}