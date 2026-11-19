import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wired_test/models/active_exam_session.dart';
import 'package:wired_test/models/exam_models.dart';
import 'package:wired_test/services/exam_sync_service.dart';
import 'package:wired_test/state/exam_controller.dart';

final _start = DateTime.utc(2026, 11, 17, 9);

ActiveExamSession _session({String id = '42'}) => ActiveExamSession.fromJson({
      'session_id': id,
      'exam_id': 10,
      'started_at': _start.toIso8601String(),
      'duration_minutes': 30,
      'questions': [
        for (final id in [9, 2])
          {
            'id': id,
            'question_text': 'Question $id',
            'question_type': 'single',
            'options': {'a': 'Alpha', 'b': 'Beta'},
            'option_order': ['b', 'a'],
          }
      ],
    }, requestedExamId: 10);

class _Service implements ExamSyncService {
  int gets = 0;
  int posts = 0;
  Completer<void>? gate;
  final entered = Completer<void>();
  ActiveExamSessionResult result = ActiveExamSessionResult(
      ActiveExamSessionOutcome.recoverable,
      session: _session());

  @override
  Future<ActiveExamSessionResult> getActiveExamSession(int examId) async {
    expect(examId, 10);
    gets++;
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    return result;
  }

  @override
  Future<Map<String, dynamic>?> startExamSession(int examId) async {
    posts++;
    return {
      'session_id': 'fresh',
      'exam': {'id': examId, 'duration_minutes': 30},
      'questions': _session().questions
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected service call: ${invocation.memberName}');
}

class _FailingBox extends Fake implements Box<dynamic> {
  _FailingBox(this.delegate);
  final Box<dynamic> delegate;
  bool fail = true;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      delegate.get(key, defaultValue: defaultValue);
  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    if (fail) throw StateError('Injected recovery snapshot failure');
    await delegate.putAll(entries);
  }

  @override
  Future<void> put(dynamic key, dynamic value) => delegate.put(key, value);
}

class _Unknown404Adapter implements HttpClientAdapter {
  _Unknown404Adapter(this.body);
  final String body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(body, 404, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Box<ExamAttempt> attempts;
  late Box<dynamic> state;
  late _Service service;
  late ExamController controller;

  setUpAll(() {
    Hive.registerAdapter(ExamAttemptAdapter());
    Hive.registerAdapter(AnswerRecordAdapter());
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('active_exam_recovery_');
    Hive.init(temp.path);
    attempts = await Hive.openBox<ExamAttempt>('attempts');
    state = await Hive.openBox('state');
    service = _Service();
    controller = ExamController(attempts, service, state);
  });
  tearDown(() async {
    controller.dispose();
    await Hive.close();
    await temp.delete(recursive: true);
  });

  Future<List<Map<String, dynamic>>?> enter() =>
      controller.startExam(examId: 10, userId: 7);

  for (final body in [
    '{"message":"Not Found"}',
    '<html>Cannot GET /exams/10/active-session</html>',
    '{broken'
  ]) {
    test(
        'unknown HTTP 404 cannot start an exam with clean local storage: $body',
        () async {
      const channel =
          MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => 'test-token');
      dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
      final retryBox =
          await Hive.openBox<PendingSubmission>('unused_retry_queue');
      final client = ExamSyncService(attempts, retryBox);
      final adapter = _Unknown404Adapter(body);
      client.dio.httpClientAdapter = adapter;
      controller.dispose();
      controller = ExamController(attempts, client, state);
      try {
        expect(controller.recoveryStateFor(10, 7), ExamRecoveryState.none);
        expect(await enter(), isNull);
        expect(controller.recoveryMessage, isNotNull);
        expect(adapter.requests, hasLength(1));
        expect(adapter.requests.single.method, 'GET');
        expect(adapter.requests.single.path, '/exams/10/active-session');
        expect(attempts.isEmpty, isTrue);
        expect(state.isEmpty, isTrue);
        expect(controller.active, isNull);
      } finally {
        client.dio.close();
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
  }

  Future<void> seed(
      {String id = '42',
      int examId = 10,
      int userId = 7,
      bool snapshot = true,
      bool completed = false}) async {
    await attempts.put(
        id,
        ExamAttempt(
            attemptId: id,
            examId: examId,
            userId: userId,
            startedAt: _start,
            durationSeconds: 1800,
            submitted: completed,
            answers: [
              AnswerRecord(
                  questionId: 9,
                  selectedOptionId: 'a',
                  selectedOptionIds: ['a'],
                  updatedAt: _start)
            ]));
    if (snapshot) {
      await state.putAll({
        'exam_id': examId,
        'user_id': userId,
        'attempt_id': id,
        'session_id': id,
        'exam_start_time': _start.toIso8601String(),
        'exam_duration': 30,
        'current_index': 1,
        'remaining_seconds': 321,
        'is_paused': true,
        'is_reviewed': true,
        'flagged_questions': {'9': true},
        'last_saved': _start.add(const Duration(minutes: 1)).toIso8601String(),
        'saved_answers': [
          {
            'question_id': 9,
            'selected_option': 'b',
            'selected_options': ['b'],
            'updated_at':
                _start.add(const Duration(seconds: 1)).toIso8601String()
          }
        ],
      });
    }
  }

  Future<void> reopen() async {
    controller.dispose();
    await Hive.close();
    Hive.init(temp.path);
    attempts = await Hive.openBox<ExamAttempt>('attempts');
    state = await Hive.openBox('state');
    controller = ExamController(attempts, service, state);
  }

  test(
      'missing local state recovers original server identity and ordered snapshot',
      () async {
    final questions = await enter();
    controller.pauseTimer();
    expect(questions!.map((q) => q['id']), [9, 2]);
    expect((questions.first['options'] as Map).keys, ['b', 'a']);
    expect(questions.first['option_order'], ['b', 'a']);
    expect(controller.active!.attemptId, '42');
    expect(controller.active!.startedAt, _start);
    expect(controller.active!.durationSeconds, 1800);
    expect(attempts.length, 1);
    expect(service.gets, 1);
    expect(service.posts, 0);
    await reopen();
    expect(await enter(), isNotEmpty);
    controller.pauseTimer();
    expect(controller.active!.attemptId, '42');
    expect(service.gets, 1, reason: 'Complete local state is restored offline');
    expect(service.posts, 0);
  });

  test('same-session recovery preserves answers and all existing progress',
      () async {
    await seed();
    final before = state.toMap();
    expect(await enter(), isNotEmpty);
    expect(controller.active!.answers.single.normalizedOptions, ['b']);
    expect(controller.active!.isReviewed, isTrue);
    expect(controller.remainingSeconds, 321);
    expect(controller.isFlagged(9), isTrue);
    for (final key in [
      'current_index',
      'remaining_seconds',
      'is_paused',
      'is_reviewed',
      'flagged_questions',
      'last_saved',
      'saved_answers'
    ]) {
      expect(state.get(key), before[key], reason: key);
    }
    final generation = controller.persistenceGeneration;
    expect(await enter(), isNotEmpty);
    expect(controller.persistenceGeneration, generation);
    expect(service.gets, 1);
    expect(service.posts, 0);
    await reopen();
    expect(await enter(), isNotEmpty);
    expect(controller.active!.answers.single.normalizedOptions, ['b']);
    expect(controller.remainingSeconds, 321);
    expect(service.gets, 1);
  });

  test('orphan attempt retains its answers when snapshot is absent', () async {
    await seed(snapshot: false);
    expect(await enter(), isNotEmpty);
    controller.pauseTimer();
    expect(controller.active!.answers.single.normalizedOptions, ['a']);
    expect(service.posts, 0);
  });

  test('newer durable attempt answers win over older snapshot answers',
      () async {
    await seed();
    final attempt = attempts.get('42')!;
    attempt.answers.single.updatedAt = _start.add(const Duration(minutes: 2));
    await attempt.save();
    expect(await enter(), isNotEmpty);
    expect(controller.active!.answers.single.normalizedOptions, ['a']);
    expect(
        (state.get('saved_answers') as List).single['selected_options'], ['a']);
  });

  test('verified local restoration makes no server request', () async {
    await seed();
    await state.put('cached_questions', _session().questions);
    await state.put('cached_questions_identity', {
      'attempt_id': '42',
      'exam_id': 10,
      'user_id': 7,
      'question_ids': [9, 2]
    });
    service.result =
        const ActiveExamSessionResult(ActiveExamSessionOutcome.networkFailure);
    expect(await enter(), isNotEmpty);
    expect(controller.active!.answers.single.normalizedOptions, ['b']);
    expect(service.gets, 0);
    expect(service.posts, 0);
  });

  test('404 with clean local state permits exactly one fresh start', () async {
    service.result =
        const ActiveExamSessionResult(ActiveExamSessionOutcome.noActiveSession);
    expect(await enter(), isNotEmpty);
    controller.pauseTimer();
    expect(controller.active!.attemptId, 'fresh');
    expect(await enter(), isNotEmpty);
    expect(service.gets, 1);
    expect(service.posts, 1);
  });

  for (final outcome in [
    ActiveExamSessionOutcome.noActiveSession,
    ActiveExamSessionOutcome.networkFailure,
    ActiveExamSessionOutcome.serverFailure,
    ActiveExamSessionOutcome.authenticationFailure,
    ActiveExamSessionOutcome.invalidExamId,
    ActiveExamSessionOutcome.multipleActiveSessions,
    ActiveExamSessionOutcome.originalQuestionsUnavailable,
    ActiveExamSessionOutcome.malformedResponse
  ]) {
    for (final evidence in [false, true]) {
      if (outcome == ActiveExamSessionOutcome.noActiveSession && !evidence) {
        continue; // The clean 404 case above exercises the permitted POST.
      }
      test('$outcome preserves evidence=$evidence and blocks POST', () async {
        if (evidence) await seed();
        final before = state.toMap();
        service.result = ActiveExamSessionResult(outcome);
        expect(await enter(), isNull);
        expect(
            controller.recoveryMessage, contains('saved data has been kept'));
        expect(state.toMap(), before);
        if (evidence) {
          expect(attempts.get('42')!.answers.single.normalizedOptions, ['a']);
        }
        expect(service.posts, 0);
      });
    }
  }

  test('404 with an orphan attempt cannot authorize a new start', () async {
    await seed(snapshot: false);
    service.result =
        const ActiveExamSessionResult(ActiveExamSessionOutcome.noActiveSession);
    expect(await enter(), isNull);
    expect(attempts.get('42')!.answers.single.normalizedOptions, ['a']);
    expect(state.isEmpty, isTrue);
    expect(service.posts, 0);
  });

  for (final conflict in [
    'other session',
    'other exam',
    'other user',
    'completed'
  ]) {
    test('server recovery cannot overwrite $conflict evidence', () async {
      await seed(
          id: conflict == 'other session' ? 'old' : '42',
          examId: conflict == 'other exam' ? 11 : 10,
          userId: conflict == 'other user' ? 8 : 7,
          completed: conflict == 'completed');
      final before = state.toMap();
      expect(await enter(), isNull);
      expect(state.toMap(), before);
      expect(service.posts, 0);
    });
  }

  test('unattributed answer snapshot is retained rather than adopted',
      () async {
    await state.put('saved_answers', [
      {'question_id': 9, 'selected_option': 'a'}
    ]);
    final before = state.toMap();
    expect(await enter(), isNull);
    expect(state.toMap(), before);
    expect(attempts.isEmpty, isTrue);
    expect(service.posts, 0);
  });

  test('snapshot storage failure can be retried after restart without POST',
      () async {
    final failing = _FailingBox(state);
    controller.dispose();
    controller = ExamController(attempts, service, failing);
    expect(await enter(), isNull);
    expect(attempts.get('42'), isNotNull);
    expect(controller.active, isNull);
    await reopen();
    expect(await enter(), isNotEmpty);
    controller.pauseTimer();
    expect(attempts.length, 1);
    expect(service.posts, 0);
    expect(service.gets, 2);
  });

  test(
      'overlapping recovery and stale callbacks cannot overwrite recovered progress',
      () async {
    await seed();
    await controller.restoreExamIfExists();
    controller.selectAnswer(9, 'a');
    service.gate = Completer<void>();
    final oldGeneration = controller.persistenceGeneration;
    final recovering = enter();
    await service.entered.future;
    expect(await enter(), isNull);
    controller.selectAnswer(9, 'b', generation: oldGeneration);
    service.gate!.complete();
    expect(await recovering, isNotEmpty);
    expect(controller.active!.answers.single.normalizedOptions, ['a']);
    controller.selectAnswer(9, 'b', generation: oldGeneration);
    await controller.saveProgress(0, generation: oldGeneration);
    expect(controller.active!.answers.single.normalizedOptions, ['a']);
    expect(state.get('current_index'), 1);
    expect(service.gets, 1);
    expect(service.posts, 0);
  });
}
