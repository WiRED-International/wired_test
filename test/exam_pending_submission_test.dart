import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/models/exam_models.dart';
import 'package:wired_test/pages/exam/review_answers_page.dart';
import 'package:wired_test/services/exam_sync_service.dart';
import 'package:wired_test/services/retry_queue_service.dart';
import 'package:wired_test/state/exam_controller.dart';

class _PendingBox extends Fake implements Box<PendingSubmission> {
  _PendingBox(this.delegate);
  final Box<PendingSubmission> delegate;
  bool fail = false;
  Completer<void>? gate;
  final entered = Completer<void>();
  int puts = 0;
  @override
  Iterable<PendingSubmission> get values => delegate.values;
  @override
  bool containsKey(dynamic key) => delegate.containsKey(key);
  @override
  Future<void> put(dynamic key, PendingSubmission value) async {
    puts++;
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    if (fail) throw StateError('Synthetic queue write failure');
    await delegate.put(key, value);
  }
}

class _Service extends Fake implements ExamSyncService {
  @override
  void requestSync() {}
  @override
  final ValueNotifier<Set<String>> acknowledgedSessions = ValueNotifier({});
}

class _WidgetController extends ExamController {
  _WidgetController(
      super.attempts, super.syncService, super.examBox, this.tester,
      {super.retryQueue});
  final WidgetTester tester;
  Future<void>? enqueueResult;
  @override
  Future<void> queueOfflineSubmission(Map<String, dynamic> payload) {
    return enqueueResult = () async {
      Object? failure;
      await tester.runAsync(() async {
        try {
          await super.queueOfflineSubmission(payload);
        } catch (error) {
          failure = error;
        }
      });
      if (failure != null) throw failure!;
    }();
  }
}

Future<bool> _offline() async => false;

void main() {
  late Directory directory;
  late Box<ExamAttempt> attempts;
  late Box<dynamic> state;
  late Box<PendingSubmission> pending;
  late _PendingBox pendingWrites;
  late RetryQueueService queue;
  late ExamController controller;

  setUpAll(() {
    Hive.registerAdapter(ExamAttemptAdapter());
    Hive.registerAdapter(AnswerRecordAdapter());
    Hive.registerAdapter(PendingSubmissionAdapter());
  });

  Future<void> open() async {
    attempts = await Hive.openBox<ExamAttempt>('attempts');
    state = await Hive.openBox('state');
    pending = await Hive.openBox<PendingSubmission>('pending');
    pendingWrites = _PendingBox(pending);
    queue = RetryQueueService(pendingWrites);
    controller = ExamController(attempts, _Service(), state, retryQueue: queue);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('exam_pending_');
    Hive.init(directory.path);
    await open();
    final started = DateTime.utc(2026);
    await attempts.put(
        '42',
        ExamAttempt(
          attemptId: '42',
          examId: 10,
          userId: 7,
          startedAt: started,
          durationSeconds: 1800,
          answers: [
            AnswerRecord(
                questionId: 1, selectedOptionId: 'a', updatedAt: started),
            AnswerRecord(
                questionId: 2,
                selectedOptionIds: ['a', 'c'],
                updatedAt: started),
          ],
        ));
    await state.putAll({
      'exam_start_time': started.toIso8601String(),
      'exam_duration': 30,
      'exam_id': 10,
      'user_id': 7,
      'attempt_id': '42',
      'session_id': '42',
      'remaining_seconds': 1193,
      'is_paused': true,
      'current_index': 1,
      'flagged_questions': {'2': true},
      'cached_questions': [
        {
          'id': 1,
          'question_text': 'Synthetic question',
          'options': {'a': 'Alpha'}
        },
        {
          'id': 2,
          'question_text': 'Synthetic multiple',
          'options': {'a': 'Alpha', 'c': 'Gamma'}
        }
      ],
    });
    await controller.restoreExamIfExists();
  });

  tearDown(() async {
    controller.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<Map<String, dynamic>> payload() async =>
      (await controller.buildSubmissionPayload())!;

  Future<void> reopen() async {
    controller.dispose();
    await Hive.close();
    Hive.init(directory.path);
    await open();
  }

  test('stable session key durably preserves full submitted payload', () async {
    final submitted = await payload();
    await controller.queueOfflineSubmission(submitted);
    expect(pending.keys.toList(), ['42']);
    expect(jsonDecode(pending.get('42')!.payloadJson), submitted);
    expect(
        (submitted['answers'] as List)[1]['selected_option_ids'], ['a', 'c']);
    expect(controller.submissionPending, isTrue);
    expect(attempts.get('42')!.submitted, isFalse);
    expect(attempts.get('42')!.submittedAt, isNull);
    expect(state.get('remaining_seconds'), 1193);
    expect(state.get('current_index'), 1);
    expect(state.get('flagged_questions'), {'2': true});
    await reopen();
    expect(jsonDecode(pending.get('42')!.payloadJson), submitted);
    expect(controller.hasPendingSubmission(10, 7), isTrue);
    expect(attempts.get('42')!.submitted, isFalse);
  });

  test(
      'duplicate enqueues across service instances cannot overwrite the first payload',
      () async {
    final original = await payload();
    final changed = {...original, 'answers': <dynamic>[]};
    final gate = Completer<void>();
    pendingWrites.gate = gate;
    final first = queue.enqueue(original);
    await pendingWrites.entered.future;
    final second = RetryQueueService(pendingWrites).enqueue(changed);
    gate.complete();
    await Future.wait([first, second]);
    expect(pending.length, 1);
    expect(pendingWrites.puts, 1);
    expect(jsonDecode(pending.values.single.payloadJson), original);
    await queue.enqueue(changed);
    expect(pending.length, 1);
    expect(jsonDecode(pending.values.single.payloadJson), original);
  });

  test(
      'existing timestamp-keyed submissions remain untouched, including legacy duplicates',
      () async {
    final original = await payload();
    for (final key in ['42-1000', '42-2000']) {
      await pending.put(
          key,
          PendingSubmission(
              attemptId: '42',
              payloadJson: jsonEncode(original),
              retryCount: 2,
              enqueuedAt: DateTime.utc(2026)));
    }
    await queue.enqueue({...original, 'answers': <dynamic>[]});
    expect(pending.keys.toSet(), {'42-1000', '42-2000'});
    expect(pendingWrites.puts, 0);
    expect(pending.values.every((p) => p.payloadJson == jsonEncode(original)),
        isTrue);
    expect(pending.values.every((p) => p.retryCount == 2), isTrue);
    await reopen();
    expect(await controller.startExam(examId: 10, userId: 7), isNull);
    expect(controller.recoveryMessage, ExamController.pendingSubmissionMessage);
  });

  test(
      'pending completion blocks editing, restore, and new starts without server acceptance',
      () async {
    await controller.queueOfflineSubmission(await payload());
    final answers = attempts.get('42')!.answers.map((a) => a.toJson()).toList();
    controller.selectAnswer(1, 'changed');
    controller.selectMultipleAnswers(2, ['changed']);
    controller.toggleFlag(2);
    expect(
        attempts.get('42')!.answers.map((a) => a.toJson()).toList(), answers);
    expect(state.get('flagged_questions'), {'2': true});
    expect(await controller.buildSubmissionPayload(), isNull);
    expect(controller.savedExamId, isNull);
    expect(await controller.startExam(examId: 10, userId: 7), isNull);
    await reopen();
    await controller.restoreExamIfExists();
    expect(controller.active, isNull);
    expect(await controller.startExam(examId: 10, userId: 7), isNull);
    expect(controller.recoveryStateFor(10, 7), ExamRecoveryState.unresolved);
    expect(attempts.get('42')!.submitted, isFalse);
    expect(state.get('remaining_seconds'), 1193);
  });

  test('queue persistence failure retains editable exam and supports retry',
      () async {
    final submitted = await payload();
    final active = controller.active;
    pendingWrites.fail = true;
    await expectLater(
        controller.queueOfflineSubmission(submitted), throwsStateError);
    expect(pending.isEmpty, isTrue);
    expect(controller.submissionPending, isFalse);
    expect(controller.active, same(active));
    expect(controller.remainingSeconds, 1193);
    expect(state.get('current_index'), 1);
    controller.selectAnswer(1, 'c');
    expect(controller.active!.answers.first.normalizedOptions, ['c']);
    pendingWrites.fail = false;
    await controller.queueOfflineSubmission(await payload());
    expect(pending.length, 1);
    expect(controller.submissionPending, isTrue);
  });

  test('missing or conflicting session identities cannot create queue entries',
      () async {
    await expectLater(queue.enqueue({'answers': []}), throwsStateError);
    await expectLater(queue.enqueue({'attempt_id': '42', 'session_id': '43'}),
        throwsStateError);
    expect(pending.isEmpty, isTrue);
  });

  test('a colliding existing key is preserved rather than overwritten',
      () async {
    final submitted = await payload();
    await pending.put(
        '42',
        PendingSubmission(
            attemptId: 'older-session',
            payloadJson: '{"preserve":true}',
            retryCount: 3,
            enqueuedAt: DateTime.utc(2026)));
    await expectLater(queue.enqueue(submitted), throwsStateError);
    expect(pending.get('42')!.payloadJson, '{"preserve":true}');
    expect(pending.get('42')!.retryCount, 3);
  });

  test('queue identity alone blocks restart when the active snapshot is absent',
      () async {
    await queue.enqueue(await payload());
    await state.clear();
    await attempts.clear();
    await reopen();
    expect(await controller.startExam(examId: 10, userId: 7), isNull);
    expect(controller.recoveryMessage, ExamController.pendingSubmissionMessage);
    expect(pending.length, 1);
  });

  for (final fails in [false, true]) {
    testWidgets(
        'offline submit ${fails ? 'reports failed persistence' : 'locks completed submission'}',
        (tester) async {
      controller.dispose();
      final widgetController = _WidgetController(
          attempts, _Service(), state, tester,
          retryQueue: queue);
      controller = widgetController;
      await tester.runAsync(controller.restoreExamIfExists);
      pendingWrites.fail = fails;
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ChangeNotifierProvider<ExamController>.value(
        value: controller,
        child: Provider<ExamSyncService>.value(
          value: _Service(),
          child: MaterialApp(
              home: ReviewAnswersPage(questions: const [
            {
              'id': 1,
              'question_text': 'Synthetic question',
              'options': {'a': 'Alpha'}
            },
            {
              'id': 2,
              'question_text': 'Synthetic multiple',
              'options': {'a': 'Alpha', 'c': 'Gamma'}
            }
          ], onlineCheck: _offline)),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Submit Exam'));
      await tester.tap(find.text('Submit Exam'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(widgetController.enqueueResult, isNotNull);
      await widgetController.enqueueResult
          ?.then<void>((_) {}, onError: (Object _) {});
      await tester.pumpAndSettle();
      if (fails) {
        expect(
            find.textContaining('Submission was not saved.'), findsOneWidget);
        expect(controller.submissionPending, isFalse);
        expect(pending.isEmpty, isTrue);
        expect(controller.active!.answers, hasLength(2));
      } else {
        expect(find.text('Offline Mode'), findsOneWidget);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.text('Awaiting synchronization'), findsOneWidget);
        final submit = tester.widget<ElevatedButton>(find.ancestor(
            of: find.text('Awaiting synchronization'),
            matching:
                find.byWidgetPredicate((widget) => widget is ElevatedButton)));
        expect(submit.onPressed, isNull);
        expect(pending.length, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
