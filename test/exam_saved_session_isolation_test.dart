import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wired_test/models/exam_models.dart';
import 'package:wired_test/models/active_exam_session.dart';
import 'package:wired_test/services/exam_sync_service.dart';
import 'package:wired_test/state/exam_controller.dart';

// Synthetic fixtures only. No app initialization, actual account data, HTTP,
// databases, retry queues, or installed-app Hive directories are accessed.
const _examA = 101;
const _examB = 202;
const _sessionA = '9001';
const _sessionB = '9002';
final _started = DateTime.utc(2026, 11, 16, 9);
final _newer = _started.add(const Duration(minutes: 1));

Map<String, dynamic> _question(int id, String label) => {
      'id': id,
      'question_text': label,
      'options': {'a': 'A', 'b': 'B'},
    };

class _MockExams implements ExamSyncService {
  @override
  Future<ActiveExamSessionResult> getActiveExamSession(int examId) async =>
      const ActiveExamSessionResult(ActiveExamSessionOutcome.noActiveSession);
  final starts = <int>[];
  List<Map<String, dynamic>> bQuestions = [_question(201, 'Exam B question')];
  @override
  Future<Map<String, dynamic>?> startExamSession(int examId) async {
    starts.add(examId);
    if (examId != _examB) throw StateError('Unexpected mock exam start');
    return {
      'session_id': int.parse(_sessionB),
      'exam': {'id': _examB, 'duration_minutes': 45},
      'questions': bQuestions,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected service call: ${invocation.memberName}');
}

class _SnapshotFailureBox extends Fake implements Box<dynamic> {
  _SnapshotFailureBox(this.delegate, {this.failArchive = false});
  final Box<dynamic> delegate;
  final bool failArchive;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => delegate.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) {
    if (failArchive && key == 'preserved_exam_sessions') {
      return Future.error(StateError('Injected archive write failure'));
    }
    return delegate.put(key, value);
  }
  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) =>
      Future.error(StateError('Injected new snapshot write failure'));
}

void main() {
  late Directory temp;
  late Box<ExamAttempt> attempts;
  late Box<dynamic> state;
  late ExamController controller;
  late _MockExams service;

  setUpAll(() {
    Hive.registerAdapter(ExamAttemptAdapter());
    Hive.registerAdapter(AnswerRecordAdapter());
  });
  Future<void> open() async {
    attempts = await Hive.openBox<ExamAttempt>('isolated_attempts');
    state = await Hive.openBox('isolated_exam');
    controller = ExamController(attempts, service, state);
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('exam_isolation_');
    Hive.init(temp.path);
    service = _MockExams();
    await open();
  });
  tearDown(() async {
    controller.dispose();
    await Hive.close();
    // Delete only this test's freshly created directory.
    await temp.delete(recursive: true);
  });
  Future<void> reopen() async {
    controller.dispose();
    await Hive.close();
    Hive.init(temp.path);
    await open();
  }

  Future<void> seedA(
      {bool submitted = false, bool includeAttemptId = true}) async {
    await attempts.put(
        _sessionA,
        ExamAttempt(
          attemptId: _sessionA,
          examId: _examA,
          userId: 7,
          startedAt: _started,
          durationSeconds: 1800,
          submitted: submitted,
          submittedAt: submitted ? _newer : null,
          answers: [
            AnswerRecord(
                questionId: 101,
                selectedOptionId: 'a',
                selectedOptionIds: ['a'],
                updatedAt: _started)
          ],
        ));
    await state.putAll({
      'exam_start_time': _started.toIso8601String(),
      'exam_duration': 30,
      'exam_id': _examA,
      'user_id': 7,
      'session_id': int.parse(_sessionA),
      if (includeAttemptId) 'attempt_id': _sessionA,
      'current_index': 1,
      'remaining_seconds': 321,
      'is_paused': true,
      'is_reviewed': true,
      'flagged_questions': {'101': true},
      'last_saved': _newer.toIso8601String(),
      'cached_questions': [
        _question(101, 'Exam A question'),
        _question(102, 'Exam A second question')
      ],
      'saved_answers': [
        {
          'question_id': 101,
          'selected_option': 'b',
          'selected_options': ['b'],
          'updated_at': _newer.toIso8601String()
        }
      ],
    });
  }

  Future<void> startB() async {
    final questions = await controller.startExam(examId: _examB, userId: 7);
    // Use the public pause API immediately to avoid wall-clock ticks; do not
    // save progress here, because that would overwrite the fields under test.
    controller.pauseTimer();
    expect(questions, service.bQuestions);
    expect(service.starts, [_examB]);
    expect(controller.active?.attemptId, _sessionB);
    expect(controller.active?.answers, isEmpty);
    expect(controller.getCachedQuestions(), service.bQuestions);
  }

  test('control: completed A with awaited cleanup starts and restores clean B',
      () async {
    await seedA();
    await controller.restoreExamIfExists();
    // Model a durably acknowledged completion; do not invoke submission code.
    controller.active!.submitted = true;
    controller.active!.submittedAt = _newer;
    await controller.active!.save();
    await controller.clearExamPersistence();
    expect(state.isEmpty, isTrue);
    expect(attempts.get(_sessionA), isNull);
    await startB();
    expect(state.get('session_id').toString(), _sessionB);
    expect(state.get('attempt_id'), _sessionB);
    expect(state.get('saved_answers'), isEmpty);
    expect(state.get('current_index'), 0);
    expect(controller.isFlagged(101), isFalse);
    // Pause the test fixture explicitly for recovery without starting a timer.
    await state.put('is_paused', true);
    await reopen();
    await controller.restoreExamIfExists();
    expect(controller.active?.examId, _examB);
    expect(controller.active?.attemptId, _sessionB);
    expect(controller.active?.answers, isEmpty);
    expect(controller.active?.submitted, isFalse);
    expect(controller.active?.isReviewed, isFalse);
    expect(controller.remainingSeconds, 2700);
    expect(controller.getCachedQuestions(), service.bQuestions);
    expect(service.starts, [_examB]); // restoration performs no service call.
  });

  test('starting B initializes its fields and preserves A snapshot separately',
      () async {
    await seedA(submitted: true);
    await controller.restoreExamIfExists();
    final retainedKeys = [
      'attempt_id',
      'saved_answers',
      'remaining_seconds',
      'is_paused',
      'is_reviewed',
      'flagged_questions',
      'last_saved'
    ];
    final previous = {for (final key in retainedKeys) key: state.get(key)};
    await startB();
    final archived = (state.get('preserved_exam_sessions') as List)
        .single['snapshot'] as Map;
    for (final key in retainedKeys) {
      expect(archived[key], previous[key],
          reason: 'Preserved prior field: $key');
    }
    expect(state.get('attempt_id'), _sessionB);
    expect(state.get('saved_answers'), isEmpty);
    expect(state.get('remaining_seconds'), 2700);
    expect(state.get('is_paused'), isFalse);
    expect(state.get('is_reviewed'), isFalse);
    expect(state.get('flagged_questions'), isEmpty);
    expect(state.get('last_saved'), isNot(previous['last_saved']));
    expect(attempts.get(_sessionA)!.answers.single.normalizedOptions, ['a']);
    expect(state.get('exam_id'), _examB);
    expect(state.get('session_id').toString(), _sessionB);
    expect(state.get('user_id'), 7);
    expect(state.get('exam_duration'), 45);
    expect(state.get('exam_start_time'), isNot(_started.toIso8601String()));
    expect(state.get('current_index'), 0);
    expect(controller.remainingSeconds, 2700);
    expect(controller.active?.isReviewed, isFalse);
    expect(controller.isFlagged(101), isFalse);
  });

  test('fresh B start cannot reactivate a preserved submitted A', () async {
    await seedA(submitted: true);
    await startB();
    await reopen();
    await controller.restoreExamIfExists();
    expect(controller.savedExamId, _examB);
    expect(controller.active?.examId, _examB);
    expect(controller.active?.attemptId, _sessionB);
    expect(controller.active?.submitted, isFalse);
    expect(controller.active!.answers, isEmpty);
    expect(attempts.get(_sessionA)!.submitted, isTrue);
    expect(attempts.get(_sessionA)!.answers.single.normalizedOptions, ['a']);
    expect(controller.getCachedQuestions(), service.bQuestions);
    expect(controller.remainingSeconds, 2700);
  });

  final mismatches = <String, Map<String, dynamic>>{
    'attempt A, session B, exam B': {
      'attempt_id': _sessionA,
      'session_id': 9002,
      'exam_id': _examB
    },
    'attempt A, session B, exam A': {
      'attempt_id': _sessionA,
      'session_id': 9002,
      'exam_id': _examA
    },
    'attempt B, session B, exam A': {
      'attempt_id': _sessionB,
      'session_id': 9002,
      'exam_id': _examA
    },
  };
  for (final entry in mismatches.entries) {
    test(
        'REGRESSION: inconsistent identity must not activate a session: ${entry.key}',
        () async {
      await seedA();
      await attempts.put(
          _sessionB,
          ExamAttempt(
              attemptId: _sessionB,
              examId: _examB,
              userId: 7,
              startedAt: _started,
              durationSeconds: 2700,
              answers: []));
      await state.putAll(entry.value);
      await reopen();
      await controller.restoreExamIfExists();
      expect(service.starts, isEmpty);
      expect(
          state.get('saved_answers'), isNotNull); // preserve recovery evidence.
      expect(controller.active, isNull,
          reason:
              'Identity mismatch must block activation, not merely snapshot merging');
    });
  }

  for (final sharedQuestionId in [false, true]) {
    test(
        'REGRESSION: B must not recover A selections (${sharedQuestionId ? 'shared template ID' : 'different question IDs'})',
        () async {
      await seedA(includeAttemptId: false);
      if (sharedQuestionId)
        service.bQuestions = [
          _question(101, 'Exam B shared-template question')
        ];
      await startB();
      // session_id and exam_id now both identify B; the untagged snapshot is A's.
      await reopen();
      await controller.restoreExamIfExists();
      expect(controller.active?.examId, _examB);
      expect(controller.active?.attemptId, _sessionB);
      expect(controller.active!.answers, isEmpty,
          reason: 'A new B attempt must not inherit saved_answers from A');
    });
  }

  test('B retains its own review state and remaining time after restoration',
      () async {
    await seedA(includeAttemptId: false);
    await startB();
    expect(controller.active?.isReviewed, isFalse);
    expect(controller.remainingSeconds, 2700);
    await reopen();
    await controller.restoreExamIfExists();
    expect(controller.active?.examId, _examB);
    expect(controller.active?.isReviewed, isFalse);
    expect(controller.remainingSeconds, 2700);
    expect(controller.isFlagged(101), isFalse);
    final payload = await controller.buildSubmissionPayload();
    expect(payload?['exam_id'], _examB);
    expect(payload?['attempt_id'], _sessionB);
    expect(payload?['answers'], isEmpty);
    // Only construct the payload; no submission or synchronization is called.
  });

  test('REGRESSION: submitted attempt must not be restored as active',
      () async {
    await seedA(submitted: true);
    await reopen();
    await controller.restoreExamIfExists();
    expect(attempts.get(_sessionA)!.submitted, isTrue);
    expect(controller.active, isNull,
        reason:
            'Durably acknowledged attempts are completed, not recoverable active sessions');
  });

  test('REGRESSION: cached A questions must not be exposed as B questions',
      () async {
    await seedA();
    await attempts.put(
        _sessionB,
        ExamAttempt(
            attemptId: _sessionB,
            examId: _examB,
            userId: 7,
            startedAt: _started,
            durationSeconds: 2700,
            answers: []));
    await state.putAll({
      'attempt_id': _sessionB,
      'session_id': 9002,
      'exam_id': _examB,
      'saved_answers': <Map<String, dynamic>>[]
    });
    await reopen();
    await controller.restoreExamIfExists();
    expect(controller.active?.examId, _examB);
    final cached = controller.getCachedQuestions();
    expect(cached == null || cached.every((q) => q['id'] == 201), isTrue,
        reason: 'An unbound A question cache must not be presented under B');
  });

  test(
      'control: valid interrupted attempt restores newer answers, questions, flags and index',
      () async {
    await seedA();
    await reopen();
    await controller.restoreExamIfExists();
    expect(controller.active?.attemptId, _sessionA);
    expect(controller.active?.examId, _examA);
    expect(controller.active?.submitted, isFalse);
    expect(controller.active!.answers.single.normalizedOptions, ['b']);
    expect(controller.getCachedQuestions()!.map((q) => q['id']), [101, 102]);
    expect(controller.savedQuestionIndex, 1);
    expect(controller.remainingSeconds, 321);
    expect(controller.active?.isReviewed, isTrue);
    expect(controller.isFlagged(101), isTrue);
    expect(service.starts, isEmpty);
    // Round trip through public save and real disk without changing pause rules.
    await controller.saveProgress(1);
    expect(state.get('is_paused'), isTrue);
    await reopen();
    await controller.restoreExamIfExists();
    expect(controller.active!.answers.single.normalizedOptions, ['b']);
    expect(controller.active?.attemptId, _sessionA);
  });

  test('control: session_id-only interrupted recovery is supported', () async {
    await seedA(includeAttemptId: false);
    await reopen();
    await controller.restoreExamIfExists();
    expect(controller.active?.attemptId, _sessionA);
    expect(controller.active!.answers.single.normalizedOptions, ['b']);
    expect(service.starts, isEmpty);
  });

  test(
      'control: consistent snapshot reconstructs a missing interrupted attempt',
      () async {
    await seedA();
    await attempts.delete(
        _sessionA); // test fixture only; simulates missing attempt record.
    await reopen();
    await controller.restoreExamIfExists();
    expect(controller.active?.attemptId, _sessionA);
    expect(controller.active?.examId, _examA);
    expect(controller.active?.userId, 7);
    expect(controller.active!.answers.single.normalizedOptions, ['b']);
    expect(controller.active?.submitted, isFalse);
    expect(service.starts, isEmpty);
  });
  test('preservation failure blocks new start without touching prior answers', () async {
    await seedA();
    final before = state.toMap();
    controller.dispose();
    controller = ExamController(attempts, service, _SnapshotFailureBox(state, failArchive: true));
    expect(await controller.startExam(examId: _examB, userId: 7), isNull);
    expect(service.starts, isEmpty);
    expect(state.toMap(), before);
    expect(attempts.get(_sessionA)!.answers.single.normalizedOptions, ['a']);
  });

  test('required snapshot write failure blocks B before server start', () async {
    await seedA();
    final before = state.toMap();
    controller.dispose();
    controller = ExamController(attempts, service, _SnapshotFailureBox(state));
    await controller.restoreExamIfExists();
    expect(await controller.startExam(examId: _examB, userId: 7), isNull);
    expect(controller.active?.examId, _examA);
    expect(state.get('exam_id'), _examA);
    expect(service.starts, isEmpty);
    expect(state.toMap(), before);
    expect(attempts.get(_sessionB), isNull);
    expect(attempts.get(_sessionA)!.answers.single.normalizedOptions, ['b']);
  });

  test('preserved A evidence survives normal B cleanup and disk reopen', () async {
    await seedA();
    final before = state.toMap();
    await startB();
    await controller.clearExamPersistence();
    await reopen();
    expect((state.get('preserved_exam_sessions') as List).single['snapshot'], before);
    expect(attempts.get(_sessionA)!.answers.single.normalizedOptions, ['a']);
    expect(state.get('cached_questions_identity'), isNull);
    expect(state.get('exam_id'), isNull);
  });

  test('mismatched cache tag is withheld without modifying recovery evidence', () async {
    await startB();
    await state.put('is_paused', true);
    await state.put('cached_questions_identity', {
      'attempt_id': _sessionA, 'exam_id': _examA, 'user_id': 7,
      'question_ids': [201],
    });
    final before = state.toMap();
    await reopen();
    await controller.restoreExamIfExists();
    expect(controller.active?.examId, _examB);
    expect(controller.getCachedQuestions(), isNull);
    expect(state.toMap(), before);
  });

  test('legacy cache allows separate near-simultaneous start timestamps', () async {
    await seedA();
    await state.put('exam_start_time', _started.add(const Duration(milliseconds: 300)).toIso8601String());
    await reopen();
    await controller.restoreExamIfExists();
    expect(controller.active?.attemptId, _sessionA);
    expect(controller.getCachedQuestions()!.map((q) => q['id']), [101, 102]);
    expect(service.starts, isEmpty);
  });

  test('submission timestamp alone prevents resume without erasing answers', () async {
    await seedA();
    attempts.get(_sessionA)!.submittedAt = _newer;
    await attempts.get(_sessionA)!.save();
    final before = state.toMap();
    await reopen();
    await controller.restoreExamIfExists();
    expect(controller.active, isNull);
    expect(controller.savedExamId, isNull);
    expect(state.toMap(), before);
    expect(attempts.get(_sessionA)!.answers.single.normalizedOptions, ['a']);
  });

}
