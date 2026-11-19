import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/exam_models.dart';
import '../models/active_exam_session.dart';
import '../services/exam_sync_service.dart';
import '../services/retry_queue_service.dart';

enum ExamRecoveryState { none, resumable, unresolved }

class ExamController extends ChangeNotifier {
  final Box<ExamAttempt> _attempts;
  final ExamSyncService _syncService;
  final Box _examBox; // ✅ persistent exam session data
  final RetryQueueService? _retryQueue;
  final Map<int, bool> _flaggedQuestions = {}; // questionId → true/false
  bool isFlagged(int questionId) => _flaggedQuestions[questionId] ?? false;

  void toggleFlag(int questionId, {int? generation}) {
    if (_transitioning ||
        submissionLocked ||
        (generation != null && generation != _persistenceGeneration) ||
        _active == null) return;
    _flaggedQuestions[questionId] = !(_flaggedQuestions[questionId] ?? false);
    // Persist to Hive
    _trackStateWrite(_examBox.put('flagged_questions',
        _flaggedQuestions.map((k, v) => MapEntry(k.toString(), v))));
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
  bool _disposed = false;
  bool _timerCheckpointPending = false;
  Future<void>? _snapshotWriteTail;
  final Set<Future<void>> _pendingAnswerWrites = {};
  int _answerRevision = 0;
  final Set<Future<void>> _pendingStateWrites = {};
  bool _transitioning = false;
  int _persistenceGeneration = 0;
  int get persistenceGeneration => _persistenceGeneration;
  bool get persistenceTransitioning => _transitioning;

  bool _ownsPersistence(ExamAttempt attempt, int generation) =>
      !_disposed &&
      generation == _persistenceGeneration &&
      identical(_active, attempt);

  // Timer-only checkpoints share the snapshot writer, but never rewrite answers
  // or question position. A failed write must not poison subsequent saves.
  Future<void> _serializeSnapshotWrite(Future<void> Function() write) {
    final result =
        (_snapshotWriteTail ?? Future<void>.value()).then((_) => write());
    _snapshotWriteTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _persistTimerCheckpoint() {
    final attempt = _active;
    final generation = _persistenceGeneration;
    if (_disposed || attempt == null || _transitioning) return Future.value();
    return _trackStateWrite(_serializeSnapshotWrite(() async {
      if (!_ownsPersistence(attempt, generation) ||
          !_snapshotMatches(attempt) ||
          attempt.submitted ||
          attempt.submittedAt != null) {
        return;
      }
      await _examBox.putAll({
        'remaining_seconds': _remainingSeconds,
        'is_paused': _isPaused,
        'last_saved': DateTime.now().toIso8601String(),
      });
    }));
  }

  void _checkpointTimer({bool onPause = false}) {
    if (_timerCheckpointPending && !onPause) return;
    if (onPause) {
      // Queue a final checkpoint even if an older periodic write is in flight.
      unawaited(_persistTimerCheckpoint().catchError((Object _) {}));
      return;
    }
    _timerCheckpointPending = true;
    unawaited(_persistTimerCheckpoint().then<void>(
      (_) => _timerCheckpointPending = false,
      onError: (Object _) {
        _timerCheckpointPending = false;
      },
    ));
  }

  Future<void> _trackStateWrite(Future<void> write) {
    _pendingStateWrites.add(write);
    write.then<void>((_) => _pendingStateWrites.remove(write),
        onError: (Object error, StackTrace stack) {
      _pendingStateWrites.remove(write);
      debugPrint('Exam state write failed; retaining state for retry: $error');
    });
    return write;
  }

  Future<void> _drainPendingWrites() async {
    while (_pendingAnswerWrites.isNotEmpty || _pendingStateWrites.isNotEmpty) {
      await Future.wait([..._pendingAnswerWrites, ..._pendingStateWrites]);
    }
  }

  Future<void> _finishActiveWrites() async {
    await _drainPendingWrites();
    final attempt = _active;
    if (attempt == null) return;
    if (!_snapshotMatches(attempt)) {
      throw StateError(
          'Cannot replace an active exam with inconsistent saved identity');
    }
    // A fresh awaited snapshot is the fallback durability boundary even when
    // an individual answer save failed and was handled by the selection path.
    await _saveProgressFor(
        attempt, _persistenceGeneration, getCurrentQuestionIndex());
    await _examBox.put('flagged_questions',
        _flaggedQuestions.map((key, value) => MapEntry(key.toString(), value)));
  }

  ExamController(this._attempts, this._syncService, this._examBox,
      {RetryQueueService? retryQueue})
      : _retryQueue = retryQueue;

  static const pendingSubmissionMessage =
      'This exam is completed and awaiting synchronization. Your submitted answers are saved on this device.';

  ValueListenable<Set<String>> get acknowledgedSessions =>
      _syncService.acknowledgedSessions;

  bool get submissionPending =>
      _active != null &&
      (_retryQueue?.containsSession(_active!.attemptId) ?? false);

  bool get submissionLocked =>
      submissionPending ||
      _active?.submitted == true ||
      _active?.submittedAt != null;

  bool hasPendingSubmission(int examId, int userId) =>
      (_retryQueue?.containsExam(examId, userId) ?? false) ||
      _attempts.values.any((attempt) =>
          attempt.examId == examId &&
          attempt.userId == userId &&
          (_retryQueue?.containsSession(attempt.attemptId) ?? false));

  Future<void> queueOfflineSubmission(Map<String, dynamic> payload) async {
    final queue = _retryQueue;
    final attempt = _active;
    if (queue == null ||
        attempt == null ||
        _transitioning ||
        payload['attempt_id']?.toString() != attempt.attemptId ||
        payload['exam_id'] != attempt.examId ||
        payload['user_id'] != attempt.userId) {
      throw StateError('No matching exam is available to queue');
    }
    _transitioning = true;
    try {
      await _finishActiveWrites();
      await queue.enqueue(payload);
    } finally {
      _transitioning = false;
    }
    // Completion is represented by the durable queue, not server acceptance.
    pauseTimer();
    notifyListeners();
  }

  ExamAttempt? get active => _active;
  int get remainingSeconds => _remainingSeconds;
  bool get examExpired => _remainingSeconds <= 0;

  // ✅ Public getters for accessing saved Hive data
  int? get savedExamId {
    final id = _examBox.get('attempt_id') ?? _examBox.get('session_id');
    if (id == null || !_savedIdsAgree(id.toString())) return null;
    if (_retryQueue?.containsSession(id.toString()) ?? false) return null;
    final attempt = _attempts.get(id.toString());
    if (attempt != null &&
        (!_snapshotMatches(attempt) ||
            attempt.submitted ||
            attempt.submittedAt != null)) {
      return null;
    }
    return _examBox.get('exam_id') as int?;
  }

  int get savedQuestionIndex => _examBox.get('current_index', defaultValue: 0);

  String? recoveryMessage;

  static const _recoveryBlockedMessage =
      'A saved exam session needs recovery or the server session could not be '
      'safely verified. Your saved data has been kept; no new attempt has been '
      'started. Try again when connected, or ask your instructor or support for help.';

  /// Read-only decision: rejection of local evidence never authorizes a new
  /// server attempt. In particular, savedExamId == null is not proof of absence.
  ExamRecoveryState recoveryStateFor(int examId, int userId) {
    if (_transitioning) return ExamRecoveryState.unresolved;
    if (hasPendingSubmission(examId, userId)) {
      return ExamRecoveryState.unresolved;
    }
    final savedExam = _examBox.get('exam_id');
    final hasSnapshot = _snapshotKeys.any((key) => _examBox.get(key) != null);
    if (hasSnapshot && (savedExam == examId || savedExam is! int)) {
      final rawId = _examBox.get('attempt_id') ?? _examBox.get('session_id');
      final start = _examBox.get('exam_start_time');
      final duration = _examBox.get('exam_duration');
      if (savedExam != examId ||
          _examBox.get('user_id') != userId ||
          rawId == null ||
          !_savedIdsAgree(rawId.toString()) ||
          start is! String ||
          DateTime.tryParse(start) == null ||
          duration is! int ||
          duration <= 0) {
        return ExamRecoveryState.unresolved;
      }
      // A consistent session-ID-only snapshot can still reconstruct an attempt.
      // This temporary object is never saved by the decision method.
      final attempt = _attempts.get(rawId.toString()) ??
          ExamAttempt(
            attemptId: rawId.toString(),
            examId: examId,
            userId: userId,
            startedAt: DateTime.parse(start),
            durationSeconds: duration * 60,
            answers: [],
          );
      final questions = _examBox.get('cached_questions');
      if (!_snapshotMatches(attempt) ||
          attempt.submitted ||
          attempt.submittedAt != null ||
          questions is! List ||
          questions.isEmpty ||
          !_cacheMatches(attempt, questions)) {
        return ExamRecoveryState.unresolved;
      }
      return ExamRecoveryState.resumable;
    }
    // A server-created attempt can exist even if the active snapshot write failed.
    if (_attempts.values.any((a) =>
        a.examId == examId &&
        a.userId == userId &&
        !a.submitted &&
        a.submittedAt == null)) {
      return ExamRecoveryState.unresolved;
    }
    final preserved = _examBox.get(_preservedSessionsKey);
    if (preserved != null && preserved is! List)
      return ExamRecoveryState.unresolved;
    for (final entry in preserved as List? ?? const []) {
      final snapshot = entry is Map ? entry['snapshot'] : null;
      if (snapshot is! Map ||
          snapshot['exam_id'] != examId ||
          snapshot['user_id'] != userId) continue;
      final id = snapshot['attempt_id'] ?? snapshot['session_id'];
      final attempt = id == null ? null : _attempts.get(id.toString());
      if (attempt == null ||
          attempt.examId != examId ||
          attempt.userId != userId ||
          (!attempt.submitted && attempt.submittedAt == null)) {
        return ExamRecoveryState.unresolved;
      }
    }
    return ExamRecoveryState.none;
  }

  static const _snapshotKeys = [
    'exam_start_time',
    'exam_duration',
    'exam_id',
    'user_id',
    'session_id',
    'attempt_id',
    'current_index',
    'saved_answers',
    'cached_questions',
    'cached_questions_identity',
    'flagged_questions',
    'remaining_seconds',
    'is_paused',
    'is_reviewed',
    'last_saved',
  ];
  static const _preservedSessionsKey = 'preserved_exam_sessions';

  bool _savedIdsAgree(String id) =>
      id.isNotEmpty &&
      ['attempt_id', 'session_id'].every((key) {
        final value = _examBox.get(key);
        return value == null || value.toString() == id;
      });

  bool _snapshotMatches(ExamAttempt attempt) =>
      _savedIdsAgree(attempt.attemptId) &&
      _examBox.get('exam_id') == attempt.examId &&
      _examBox.get('user_id') == attempt.userId;

  // Preserve the complete previous snapshot before replacing the active slot.
  // Attempts remain in their own box; cleanup never removes these archives.
  Future<void> _preserveSavedSnapshot() async {
    final snapshot = <String, dynamic>{
      for (final key in _snapshotKeys)
        if (_examBox.get(key) != null) key: _examBox.get(key),
    };
    if (snapshot.isEmpty) return;
    final previous = _examBox.get(_preservedSessionsKey);
    if (previous != null && previous is! List) {
      throw StateError('Cannot preserve existing exam snapshot archive');
    }
    await _examBox.put(_preservedSessionsKey, [
      ...(previous as List? ?? const []),
      {
        'preserved_at': DateTime.now().toUtc().toIso8601String(),
        'snapshot': snapshot
      },
    ]);
  }

  void _rejectSavedSession() {
    // Leave both persisted sources untouched for recovery/investigation.
    if (_active != null) _persistenceGeneration++;
    _active = null;
    debugPrint(
        'Saved exam identity is inconsistent or completed; recovery blocked.');
    notifyListeners();
  }

  bool _cacheMatches(ExamAttempt attempt, List raw) {
    if (!_snapshotMatches(attempt) ||
        attempt.submitted ||
        attempt.submittedAt != null ||
        raw.any((q) => q is! Map || q['id'] is! int)) {
      return false;
    }
    final identity = _examBox.get('cached_questions_identity');
    if (identity != null) {
      return identity is Map &&
          identity['attempt_id'] == attempt.attemptId &&
          identity['exam_id'] == attempt.examId &&
          identity['user_id'] == attempt.userId &&
          identity['question_ids'] is List &&
          listEquals(identity['question_ids'] as List,
              raw.map((q) => q['id']).toList());
    }
    // Legacy caches have no separate owner tag. Accept only when the full
    // snapshot agrees with the durable attempt's start and duration as well.
    // Old starts recorded the two timestamps around separate Hive writes; allow
    // a small write delay, without accepting an unrelated session's timing.
    final start = _examBox.get('exam_start_time');
    return start is String &&
        DateTime.tryParse(start) != null &&
        DateTime.parse(start)
                .difference(attempt.startedAt)
                .inMilliseconds
                .abs() <=
            5000 &&
        _examBox.get('exam_duration') == attempt.durationSeconds ~/ 60;
  }

  /// 🔹 Start an exam (either from backend or cached sessionData)
  Future<List<Map<String, dynamic>>?> startExam({
    required int examId,
    required int userId,
  }) async {
    if (_transitioning) return null;
    if (hasPendingSubmission(examId, userId)) {
      recoveryMessage = pendingSubmissionMessage;
      return null;
    }
    recoveryMessage = null;
    final localRecovery = recoveryStateFor(examId, userId);
    _transitioning = true;
    try {
      if (localRecovery == ExamRecoveryState.resumable) {
        final restored = await _restoreExamIfExistsUnlocked();
        if (restored &&
            _active?.examId == examId &&
            _active?.userId == userId) {
          final questions = getCachedQuestions();
          if (questions != null && questions.isNotEmpty) return questions;
        }
        recoveryMessage = _recoveryBlockedMessage;
        return null;
      }
      await _finishActiveWrites();
      final recovered = await _syncService.getActiveExamSession(examId);
      if (recovered.outcome == ActiveExamSessionOutcome.recoverable &&
          recovered.session != null) {
        await _initializeRecoveredSession(recovered.session!, examId, userId);
        final restored = await _restoreExamIfExistsUnlocked();
        if (restored &&
            _active?.attemptId == recovered.session!.sessionId &&
            _active?.examId == examId &&
            _active?.userId == userId) {
          final questions = getCachedQuestions();
          if (questions != null && questions.isNotEmpty) return questions;
        }
        throw StateError('Recovered exam could not be restored locally');
      }
      if (recovered.outcome != ActiveExamSessionOutcome.noActiveSession ||
          localRecovery != ExamRecoveryState.none) {
        recoveryMessage = _recoveryBlockedMessage;
        return null;
      }
      await _preserveSavedSnapshot();
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

      if (sessionId == null ||
          exam is! Map ||
          exam['id'] != examId ||
          _attempts.containsKey(sessionId.toString())) {
        throw StateError('New exam response has conflicting session identity');
      }
      final startedAt = DateTime.now();
      final attempt = ExamAttempt(
        attemptId: sessionId.toString(),
        examId: examId,
        userId: userId,
        startedAt: startedAt,
        durationSeconds: durationSeconds,
        answers: [],
        submitted: false,
      );
      await _attempts.put(attempt.attemptId, attempt);
      // Initialize every shared field before exposing B as the active attempt.
      // A cache-write failure must not be treated as a successful fresh start.
      await _examBox.putAll({
        'exam_start_time': startedAt.toIso8601String(),
        'exam_duration': durationMinutes,
        'exam_id': examId,
        'user_id': userId,
        'session_id': sessionId,
        'attempt_id': attempt.attemptId,
        'current_index': 0,
        'saved_answers': <Map<String, dynamic>>[],
        'remaining_seconds': durationSeconds,
        'is_paused': false,
        'is_reviewed': false,
        'flagged_questions': <String, bool>{},
        'last_saved': startedAt.toIso8601String(),
        'cached_questions': questions.map((q) {
          final safeMap = Map<String, dynamic>.from(q);
          if (safeMap['options'] is! Map && safeMap['options'] != null) {
            safeMap['options'] = Map<String, dynamic>.from(safeMap['options']);
          }
          return safeMap;
        }).toList(),
        'cached_questions_identity': {
          'attempt_id': attempt.attemptId,
          'exam_id': examId,
          'user_id': userId,
          'question_ids': questions.map((q) => q['id']).toList(),
        },
      });
      _persistenceGeneration++;
      _active = attempt;
      _remainingSeconds = durationSeconds;
      _isPaused = false;
      _flaggedQuestions.clear();

      _startTimer();
      notifyListeners();

      debugPrint(
          '🧠 [ExamController] Started new exam and cached ${questions.length} questions.');
      return questions;
    } catch (e, st) {
      recoveryMessage = _recoveryBlockedMessage;
      debugPrint('❌ [ExamController] Error starting exam: $e');
      debugPrint(st.toString());
      return null;
    } finally {
      _transitioning = false;
    }
  }

  /// Called only while the transition lock owns all exam persistence writes.
  /// Repair missing metadata/cache, but never guess ownership of saved progress.
  Future<void> _initializeRecoveredSession(
      ActiveExamSession session, int examId, int userId) async {
    if (session.examId != examId) throw StateError('Recovered exam mismatch');
    final id = session.sessionId;
    final hasSnapshot = _snapshotKeys.any((key) => _examBox.get(key) != null);
    final savedId = _examBox.get('attempt_id') ?? _examBox.get('session_id');
    final sameSnapshot = savedId?.toString() == id &&
        _examBox.get('exam_id') == examId &&
        _examBox.get('user_id') == userId;
    if (hasSnapshot && !sameSnapshot) {
      throw StateError(
          'Cannot attribute existing saved exam data to recovered session');
    }
    if (!_savedIdsAgree(id) ||
        _attempts.values.any((a) =>
            a.examId == examId &&
            a.userId == userId &&
            a.attemptId != id &&
            !a.submitted &&
            a.submittedAt == null)) {
      throw StateError('Conflicting local session evidence');
    }
    final preserved = _examBox.get(_preservedSessionsKey);
    if (preserved != null &&
        (preserved is! List ||
            preserved.any((entry) {
              final snapshot = entry is Map ? entry['snapshot'] : null;
              return snapshot is Map &&
                  snapshot['exam_id'] == examId &&
                  snapshot['user_id'] == userId;
            }))) {
      throw StateError('Archived exam evidence requires manual reconciliation');
    }
    var attempt = _attempts.get(id);
    if (attempt != null &&
        (attempt.examId != examId ||
            attempt.userId != userId ||
            attempt.submitted ||
            attempt.submittedAt != null)) {
      throw StateError(
          'Recovered attempt conflicts with local identity or completion');
    }
    attempt ??= ExamAttempt(
        attemptId: id,
        examId: examId,
        userId: userId,
        startedAt: session.startedAt,
        durationSeconds: session.durationSeconds,
        answers: []);
    final snapshotAnswers = sameSnapshot ? _examBox.get('saved_answers') : null;
    final answers = snapshotAnswers is List
        ? _reconcileAnswers(attempt.answers, snapshotAnswers)
        : attempt.answers;
    // Do not mutate an existing attached object until the required snapshot is saved.
    final recoveredAttempt = ExamAttempt(
        attemptId: id,
        examId: examId,
        userId: userId,
        startedAt: session.startedAt,
        durationSeconds: session.durationSeconds,
        answers: answers,
        meta: attempt.meta,
        isReviewed: attempt.isReviewed);
    final snapshot = <String, dynamic>{
      'exam_start_time': session.startedAt.toIso8601String(),
      'exam_duration': session.durationMinutes,
      'exam_id': examId,
      'user_id': userId,
      'session_id': id,
      'attempt_id': id,
      'current_index': 0,
      'remaining_seconds': session.durationSeconds,
      'is_paused': false,
      'is_reviewed': attempt.isReviewed,
      'flagged_questions': <String, bool>{},
      'last_saved': session.startedAt.toIso8601String(),
      if (sameSnapshot)
        for (final key in [
          'current_index',
          'remaining_seconds',
          'is_paused',
          'is_reviewed',
          'flagged_questions',
          'last_saved'
        ])
          if (_examBox.get(key) != null) key: _examBox.get(key),
      'saved_answers': answers
          .map((a) => {
                'question_id': a.questionId,
                'selected_option': a.selectedOptionId,
                'selected_options':
                    List<String>.from(a.selectedOptionIds ?? []),
                'updated_at': a.updatedAt.toIso8601String(),
              })
          .toList(),
      'cached_questions': session.questions,
      'cached_questions_identity': {
        'attempt_id': id,
        'exam_id': examId,
        'user_id': userId,
        'question_ids': session.questions.map((q) => q['id']).toList(),
      },
    };
    await _attempts.put(id, recoveredAttempt);
    await _examBox.putAll(snapshot);
    // Invalidate callbacks belonging to any pre-recovery view before restoring.
    _persistenceGeneration++;
    _active = null;
  }

  /// ✅ Retrieve cached questions from Hive (used when resuming exam)
  List<Map<String, dynamic>>? getCachedQuestions() {
    final raw = _examBox.get('cached_questions');
    final attempt = _active;
    if (raw is List && attempt != null && _cacheMatches(attempt, raw)) {
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
            q['options'] = options
                .map((e) =>
                    e is Map ? Map<String, dynamic>.from(e) : {'value': e})
                .toList();
          }
        }

        return q;
      }).toList();
    }
    return null;
  }

  // ⏱️ Restore timer and state if app reopened mid-exam
  Future<void> restoreExamIfExists() async {
    if (_transitioning) return;
    _transitioning = true;
    try {
      await _restoreExamIfExistsUnlocked();
    } finally {
      _transitioning = false;
    }
  }

  Future<bool> _restoreExamIfExistsUnlocked() async {
    try {
      if (_active != null && !_snapshotMatches(_active!)) {
        _rejectSavedSession();
        return false;
      }
      await _drainPendingWrites();
      debugPrint('🕵️ [ExamController] Checking for saved exam...');

      final startTimeStr = _examBox.get('exam_start_time') as String?;
      final duration = _examBox.get('exam_duration') as int?;
      final examId = _examBox.get('exam_id') as int?;
      final userId = _examBox.get('user_id') as int?;
      final rawAttemptId =
          _examBox.get('attempt_id') ?? _examBox.get('session_id');
      final savedAnswers = _examBox.get('saved_answers');
      final savedIndex = _examBox.get('current_index') as int?;
      final remainingSeconds = _examBox.get('remaining_seconds') as int?;
      final isPaused = _examBox.get('is_paused') as bool? ?? false;
      final isReviewed = _examBox.get('is_reviewed') as bool? ?? false;

      // 🔹 If we don't even have core metadata, nothing to restore
      if (startTimeStr == null || duration == null || examId == null) {
        _rejectSavedSession();
        debugPrint('⚠️ [ExamController] No saved exam metadata found.');
        return false;
      }

      // 🔹 No attempt/session id → don't touch Hive attempts (prevents Null key crash)
      if (rawAttemptId == null) {
        _rejectSavedSession();
        debugPrint(
            '⚠️ [ExamController] No attempt_id/session_id found. Skipping restore.');
        return false;
      }

      final attemptId = rawAttemptId.toString();
      if (_retryQueue?.containsSession(attemptId) ?? false) {
        recoveryMessage = pendingSubmissionMessage;
        _rejectSavedSession();
        return false;
      }
      if (!_savedIdsAgree(attemptId) || userId == null) {
        _rejectSavedSession();
        return false;
      }
      var attempt = _attempts.get(attemptId);
      if (attempt != null &&
          (!_snapshotMatches(attempt) ||
              attempt.submitted ||
              attempt.submittedAt != null)) {
        _rejectSavedSession();
        return false;
      }

      // If missing, rebuild a minimal attempt from stored metadata
      if (attempt == null) {
        if (DateTime.tryParse(startTimeStr) == null) {
          _rejectSavedSession();
          return false;
        }
        debugPrint(
            'ℹ️ [ExamController] No attempt in box for $attemptId, reconstructing from cache.');
        attempt = ExamAttempt(
          attemptId: attemptId,
          examId: examId,
          userId: userId,
          startedAt: DateTime.tryParse(startTimeStr) ?? DateTime.now(),
          durationSeconds: duration * 60,
          answers: [],
          submitted: false,
        );
        await _attempts.put(attemptId, attempt);
      }

      if (savedAnswers is List) {
        attempt.answers = _reconcileAnswers(attempt.answers, savedAnswers);
      }
      restoreFlags();

      // ✅ Restore review flag
      attempt.isReviewed = isReviewed;
      await attempt.save();

      // ✅ Apply to controller state
      if (!identical(_active, attempt)) _persistenceGeneration++;
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
      return true;
    } catch (e, st) {
      debugPrint('❌ [ExamController] Error restoring exam: $e');
      debugPrint(st.toString());
      // Optional: if things look corrupt often, you can clear:
      // await clearExamPersistence();
      return false;
    }
  }

  List<AnswerRecord> _reconcileAnswers(
      List<AnswerRecord> persisted, List<dynamic> snapshot) {
    AnswerRecord copy(AnswerRecord answer) => AnswerRecord(
          questionId: answer.questionId,
          selectedOptionId: answer.selectedOptionId,
          selectedOptionIds: List<String>.from(answer.selectedOptionIds ?? []),
          updatedAt: answer.updatedAt,
        );

    final answers = {
      for (final answer in persisted) answer.questionId: copy(answer)
    };
    // Unknown snapshot timestamps must never become a new edit time.
    final unknownTime = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final raw in snapshot) {
      if (raw is! Map || raw['question_id'] is! int) continue;
      final single = raw['selected_option'];
      final multiple = raw['selected_options'];
      if ((single != null && single is! String) ||
          (multiple != null &&
              (multiple is! List || multiple.any((id) => id is! String)))) {
        continue;
      }
      final rawTime = raw['updated_at'];
      final updatedAt = rawTime is String ? DateTime.tryParse(rawTime) : null;
      final questionId = raw['question_id'] as int;
      final existing = answers[questionId];
      if (existing != null &&
          (updatedAt == null ||
              !existing.updatedAt.isAfter(unknownTime) ||
              !updatedAt.isAfter(existing.updatedAt))) {
        continue;
      }
      answers[questionId] = AnswerRecord(
        questionId: questionId,
        selectedOptionId: single as String?,
        selectedOptionIds: multiple == null ? [] : List<String>.from(multiple),
        updatedAt: updatedAt ?? unknownTime,
      );
    }
    return answers.values.toList();
  }

  // ✅ Timer logic
  void _startTimer() {
    _tick?.cancel();
    if (_disposed) return;

    if (_remainingSeconds <= 0) {
      // Immediately lock exam
      _submitOnTimeout();
      return;
    }

    debugPrint('⏱️ [ExamController] Timer started | $_remainingSeconds s left');

    var secondsSinceCheckpoint = 0;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_disposed ||
          _active == null ||
          _active!.submitted ||
          _active!.submittedAt != null) {
        t.cancel();
        return;
      }
      if (_remainingSeconds <= 0) {
        t.cancel();
        _submitOnTimeout();
      } else {
        _remainingSeconds -= 1;
        if (++secondsSinceCheckpoint >= 5) {
          secondsSinceCheckpoint = 0;
          _checkpointTimer();
        }
        notifyListeners();
      }
    });
  }

  void pauseTimer() {
    if (_tick != null) {
      _tick!.cancel();
      _isPaused = true;
      _checkpointTimer(onPause: true);
      debugPrint(
          '⏸️ [ExamController] Timer paused ($_remainingSeconds s left)');
    }
  }

  void resumeTimer() {
    if (_isPaused && _remainingSeconds > 0) {
      _isPaused = false;
      _startTimer();
    }
  }

  Future<void> _submitOnTimeout() async {
    debugPrint(
        '⏰ Exam time expired! Locking exam — waiting for manual submission.');

    // Stop the timer
    _tick?.cancel();
    _tick = null;

    // Freeze time
    _remainingSeconds = 0;
    _isPaused = true;

    // Save final state so UI knows exam is locked
    await _persistTimerCheckpoint();

    notifyListeners();
  }

  // ✅ Save and restore progress
  Future<void> saveProgress(int questionIndex, {int? generation}) {
    final attempt = _active;
    if (_transitioning ||
        attempt == null ||
        (generation != null && generation != _persistenceGeneration)) {
      return Future.value();
    }
    return _trackStateWrite(
        _saveProgressFor(attempt, _persistenceGeneration, questionIndex));
  }

  Future<void> _saveProgressFor(
      ExamAttempt attempt, int generation, int questionIndex) async {
    if (!_ownsPersistence(attempt, generation)) return;
    // Freeze each snapshot before yielding to pending writes.
    List<Map<String, dynamic>> snapshot() => attempt.answers
        .map((a) => {
              'question_id': a.questionId,
              'selected_option': a.selectedOptionId,
              'selected_options': List<String>.from(a.selectedOptionIds ?? []),
              'updated_at': a.updatedAt.toIso8601String(),
            })
        .toList();
    var revision = _answerRevision;
    var cachedAnswers = snapshot();

    while (true) {
      while (_pendingAnswerWrites.isNotEmpty) {
        await Future.wait(_pendingAnswerWrites.toList());
      }
      if (!_ownsPersistence(attempt, generation)) return;
      if (revision != _answerRevision) {
        revision = _answerRevision;
        cachedAnswers = snapshot();
      }
      // A handled attempt-save failure is not proof of persistence. Only a
      // completed snapshot write establishes this save boundary; errors propagate.
      await _serializeSnapshotWrite(() async {
        if (!_ownsPersistence(attempt, generation)) return;
        await _examBox.putAll({
          'exam_id': attempt.examId,
          'user_id': attempt.userId,
          'attempt_id': attempt.attemptId,
          'current_index': questionIndex,
          'saved_answers': cachedAnswers,
          'remaining_seconds': _remainingSeconds,
          'is_paused': _isPaused,
          'last_saved': DateTime.now().toIso8601String(),
        });
      });
      if (revision == _answerRevision) break;
    }

    debugPrint(
        '💾 [ExamController] Progress saved: Q$questionIndex | ${_remainingSeconds}s left');
  }

  int getCurrentQuestionIndex() =>
      _examBox.get('current_index', defaultValue: 0);

  void _saveAnswerSelection(ExamAttempt attempt) {
    _answerRevision++;
    final pending = () async {
      try {
        await attempt.save();
      } catch (error) {
        debugPrint(
            'Answer save failed; keeping current answers for retry: $error');
      }
    }();
    _pendingAnswerWrites.add(pending);
    pending.then((_) => _pendingAnswerWrites.remove(pending));
  }

  // Single-choice answer (existing)
  void selectAnswer(int questionId, String optionId, {int? generation}) {
    if (_transitioning ||
        submissionLocked ||
        (generation != null && generation != _persistenceGeneration)) return;
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

    debugPrint(
        '🟢 selectAnswer → Q$questionId = ${existing.selectedOptionIds}');
    // replace or add
    if (!activeAttempt.answers.contains(existing)) {
      activeAttempt.answers.add(existing);
    }

    _saveAnswerSelection(activeAttempt);
    notifyListeners();
  }

  // Multiple-choice support
  void selectMultipleAnswers(int questionId, List<String> selectedIds,
      {int? generation}) {
    if (_transitioning ||
        submissionLocked ||
        (generation != null && generation != _persistenceGeneration)) return;
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

    debugPrint(
        '🟢 selectMultipleAnswers → Q$questionId = ${existing.selectedOptionIds}');
    if (!activeAttempt.answers.contains(existing)) {
      activeAttempt.answers.add(existing);
    }

    _saveAnswerSelection(activeAttempt);
    notifyListeners();
  }

  Future<Map<String, dynamic>?> buildSubmissionPayload() async {
    if (_active == null || submissionLocked) return null;

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

  // 🧹 Clear all Hive data related to the ongoing exam
  Future<void> clearExamPersistence({int? generation}) async {
    if (generation != null && generation != _persistenceGeneration) return;
    if (_transitioning)
      throw StateError('Exam persistence transition is already in progress');
    _transitioning = true;
    try {
      if (_tick != null) {
        _tick!.cancel();
        _tick = null;
      }
      await _finishActiveWrites();
      _persistenceGeneration++;
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
      await _examBox.delete('cached_questions_identity');
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
    } finally {
      _transitioning = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    super.dispose();
  }
}
