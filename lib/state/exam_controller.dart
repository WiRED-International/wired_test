import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/exam_models.dart';
import '../utils/network_utils.dart';
import '../utils/validation.dart';
import '../services/exam_sync_service.dart';

class ExamController extends ChangeNotifier {
  final Box<ExamAttempt> _attempts;
  final ExamSyncService _syncService;
  final Box _examBox; // ✅ persistent exam session data
  final Map<int, bool> _flaggedQuestions = {}; // questionId → true/false
  bool isFlagged(int questionId) => _flaggedQuestions[questionId] ?? false;

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
  bool get examExpired => _remainingSeconds <= 0;

  // ✅ Public getters for accessing saved Hive data
  int? get savedExamId => _examBox.get('exam_id');
  int get savedQuestionIndex => _examBox.get('current_index', defaultValue: 0);

  /// 🔹 Start an exam (either from backend or cached sessionData)
  Future<List<Map<String, dynamic>>?> startExam({
    required int examId,
    required int userId,
  }) async {
    try {
      final response = await _syncService.startExamSession(examId);
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
      try {
        debugPrint('🧠 Caching ${questions.length} questions for exam $examId...');
        await _examBox.putAll({
          'exam_start_time': DateTime.now().toIso8601String(),
          'exam_duration': durationMinutes,
          'exam_id': examId,
          'user_id': userId,
          'session_id': sessionId,
          'current_index': 0,
          'cached_questions': questions.map((q) {
            final safeMap = Map<String, dynamic>.from(q);
            // ensure options are Map<String, dynamic>
            if (safeMap['options'] is! Map && safeMap['options'] != null) {
              safeMap['options'] =
              Map<String, dynamic>.from(safeMap['options'] ?? {});
            }
            return safeMap;
          }).toList(),
        });
        await logExamBoxContents('after startExam');
        debugPrint('✅ [ExamController] Cached questions successfully to Hive');
      } catch (e, st) {
        debugPrint('❌ [ExamController] Failed to cache questions: $e');
        debugPrint(st.toString());
      }

      _startTimer();
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
    try {
      debugPrint('🕵️ [ExamController] Checking for saved exam...');

      final startTimeStr = _examBox.get('exam_start_time') as String?;
      final duration = _examBox.get('exam_duration') as int?;
      final examId = _examBox.get('exam_id') as int?;
      final userId = _examBox.get('user_id') as int?;
      final rawAttemptId = _examBox.get('attempt_id') ?? _examBox.get('session_id');
      final savedAnswers = _examBox.get('saved_answers');
      final savedIndex = _examBox.get('current_index') as int?;
      final remainingSeconds = _examBox.get('remaining_seconds') as int?;
      final isPaused = _examBox.get('is_paused') as bool? ?? false;
      final isReviewed = _examBox.get('is_reviewed') as bool? ?? false;

      // restore flagged question state
      restoreFlags();

      // 🔹 If we don't even have core metadata, nothing to restore
      if (startTimeStr == null || duration == null || examId == null) {
        debugPrint('⚠️ [ExamController] No saved exam metadata found.');
        return;
      }

      // 🔹 No attempt/session id → don't touch Hive attempts (prevents Null key crash)
      if (rawAttemptId == null) {
        debugPrint('⚠️ [ExamController] No attempt_id/session_id found. Skipping restore.');
        return;
      }

      final attemptId = rawAttemptId.toString();

      // 🔍 Try to load existing attempt from Hive
      var attempt = _attempts.get(attemptId);

      // If missing, rebuild a minimal attempt from stored metadata
      if (attempt == null) {
        debugPrint('ℹ️ [ExamController] No attempt in box for $attemptId, reconstructing from cache.');
        attempt = ExamAttempt(
          attemptId: attemptId,
          examId: examId,
          userId: userId ?? 0,
          startedAt: DateTime.tryParse(startTimeStr) ?? DateTime.now(),
          durationSeconds: duration * 60,
          answers: [],
          submitted: false,
        );
        await _attempts.put(attemptId, attempt);
      }

      // ✅ Restore answers if present
      if (savedAnswers is List && savedAnswers.isNotEmpty) {
        attempt.answers = savedAnswers.map<AnswerRecord>((a) {
          return AnswerRecord(
            questionId: a['question_id'] as int,
            // keep this in sync with your model shape
            selectedOptionId: a['selected_option'] as String? ?? '',
            selectedOptionIds: (a['selected_options'] as List?)?.cast<String>() ?? [],
            updatedAt: DateTime.tryParse(a['updated_at'] ?? '') ?? DateTime.now(),
          );
        }).toList();
      }

      // ✅ Restore review flag
      attempt.isReviewed = isReviewed;

      // ✅ Apply to controller state
      _active = attempt;
      _remainingSeconds = remainingSeconds ?? (duration * 60);
      _isPaused = isPaused;

      // Keep index if we had one
      if (savedIndex != null) {
        await _examBox.put('current_index', savedIndex);
      }

      // Restart timer if appropriate
      if (!_isPaused && _remainingSeconds > 0) {
        _startTimer();
      }

      notifyListeners();

      debugPrint(
        '✅ [ExamController] Restored attempt=$attemptId | exam=$examId | '
            'qIndex=${savedIndex ?? 0} | remaining=${_remainingSeconds}s',
      );
    } catch (e, st) {
      debugPrint('❌ [ExamController] Error restoring exam: $e');
      debugPrint(st.toString());
      // Optional: if things look corrupt often, you can clear:
      // await clearExamPersistence();
    }
  }

  // ✅ Timer logic
  void _startTimer() {
    _tick?.cancel();

    if (_remainingSeconds <= 0) {
      // Immediately lock exam
      _submitOnTimeout();
      return;
    }

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
    debugPrint('⏰ Exam time expired! Locking exam — waiting for manual submission.');

    // Stop the timer
    _tick?.cancel();
    _tick = null;

    // Freeze time
    _remainingSeconds = 0;
    _isPaused = true;

    // Save final state so UI knows exam is locked
    await _examBox.put('remaining_seconds', 0);
    await _examBox.put('is_paused', true);

    notifyListeners();
  }

  // ✅ Save and restore progress
  Future<void> saveProgress(int questionIndex) async {
    if (_active == null) return;

    // Store answers snapshot
    final cachedAnswers = _active!.answers.map((a) => {
      'question_id': a.questionId,
      'selected_option': a.selectedOptionId,
      'selected_options': a.selectedOptionIds,
      'updated_at': a.updatedAt.toIso8601String(),
    }).toList();

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

  // Single-choice answer (existing)
  void selectAnswer(int questionId, String optionId) {
    final activeAttempt = _active;
    if (activeAttempt == null) return;

    final existing = activeAttempt.answers.firstWhere(
          (a) => a.questionId == questionId,
      orElse: () => AnswerRecord(
        questionId: questionId,
        selectedOptionId: null,
        selectedOptionIds: [],
        updatedAt: DateTime.now(),
      ),
    );

    existing
      ..selectedOptionId = optionId
      ..selectedOptionIds = [optionId]
      ..updatedAt = DateTime.now();

    debugPrint('🟢 selectAnswer → Q$questionId = ${existing.selectedOptionIds}');
    // replace or add
    if (!activeAttempt.answers.contains(existing)) {
      activeAttempt.answers.add(existing);
    }

    activeAttempt.save();
    notifyListeners();
  }

  // Multiple-choice support
  void selectMultipleAnswers(int questionId, List<String> selectedIds) {
    final activeAttempt = _active;
    if (activeAttempt == null) return;

    final existing = activeAttempt.answers.firstWhere(
          (a) => a.questionId == questionId,
      orElse: () => AnswerRecord(
        questionId: questionId,
        selectedOptionId: null,
        selectedOptionIds: [],
        updatedAt: DateTime.now(),
      ),
    );

    existing
      ..selectedOptionIds = List<String>.from(selectedIds)
      ..selectedOptionId = selectedIds.isNotEmpty ? selectedIds.first : null
      ..updatedAt = DateTime.now();

    debugPrint('🟢 selectMultipleAnswers → Q$questionId = ${existing.selectedOptionIds}');
    if (!activeAttempt.answers.contains(existing)) {
      activeAttempt.answers.add(existing);
    }

    activeAttempt.save();
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

    final normalized = _active!.answers.map((a) {
      // Always produce MULTI-SELECT array, even for single-choice
      final List<String> ids =
      (a.selectedOptionIds != null && a.selectedOptionIds!.isNotEmpty)
          ? List<String>.from(a.selectedOptionIds!)
          : (a.selectedOptionId != null && a.selectedOptionId!.isNotEmpty)
          ? [a.selectedOptionId!]
          : <String>[];

      return {
        'question_id': a.questionId,
        'selected_option_ids': ids,
        'updated_at': a.updatedAt.toIso8601String(),
      };
    }).toList();

    return {
      'attempt_id': _active!.attemptId,
      'exam_id': _active!.examId,
      'user_id': _active!.userId,
      'started_at': _active!.startedAt.toIso8601String(),
      'submitted_at': DateTime.now().toIso8601String(),
      'answers': normalized,
    };
  }

  // ✅ Submit or enqueue
  Future<bool> submitNow({
    required Future<bool> Function(Map<String, dynamic>) onSubmit,
    required Future<void> Function(Map<String, dynamic>) onEnqueue,
  }) async {
    if (_active == null) return false;

    final payload = await buildSubmissionPayload();
    if (payload == null) return false;

    // Check online status
    final online = await NetworkUtils.isOnline();

    // ❌ If offline → queue, DO NOT auto-submit later
    if (!online) {
      debugPrint('📡 Offline — queued submission only.');
      await onEnqueue(payload);
      return false;
    }

    // Try submitting online
    bool ok = false;
    try {
      ok = await onSubmit(payload);
    } catch (e) {
      debugPrint('❌ Submit failed: $e');
      ok = false;
    }

    if (ok) {
      _active!
        ..submitted = true
        ..submittedAt = DateTime.now();
      await _active!.save();

      await clearExamPersistence();
    } else {
      // ❌ DO NOT auto-enqueue if submission fails while online.
      debugPrint('⚠️ Online but submit failed — NOT auto-enqueuing.');
    }

    notifyListeners();
    return ok;
  }

  // 🧹 Clear all Hive data related to the ongoing exam
  Future<void> clearExamPersistence() async {
    if (_tick != null) {
      _tick!.cancel();
      _tick = null;
    }
    debugPrint('🧹 [ExamController] Clearing ALL exam persistence...');

    // 1️⃣ Clear examBox (all keys)
    await _examBox.delete('exam_start_time');
    await _examBox.delete('exam_duration');
    await _examBox.delete('exam_id');
    await _examBox.delete('user_id');
    await _examBox.delete('session_id');
    await _examBox.delete('attempt_id');
    await _examBox.delete('current_index');
    await _examBox.delete('saved_answers');
    await _examBox.delete('cached_questions');
    await _examBox.delete('flagged_questions');
    await _examBox.delete('remaining_seconds');
    await _examBox.delete('is_paused');
    await _examBox.delete('is_reviewed');
    await _examBox.delete('last_saved');

    // 2️⃣ Clear the active attempt in the attempts Hive box
    if (_active != null) {
      final id = _active!.attemptId;
      if (_attempts.containsKey(id)) {
        await _attempts.delete(id);
        debugPrint('🗑️ Deleted attempt object: $id');
      }
    }

    // 3️⃣ Reset in-memory state
    _active = null;
    _remainingSeconds = 0;
    _isPaused = false;
    _flaggedQuestions.clear();

    debugPrint('🧹 ALL exam persistence cleared successfully.');
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
    super.dispose();
  }
}