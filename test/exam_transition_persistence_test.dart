import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:wired_test/widgets/exam/question_card.dart';
import 'package:hive/hive.dart';
import 'package:wired_test/models/exam_models.dart';
import 'package:wired_test/models/active_exam_session.dart';
import 'package:wired_test/services/exam_sync_service.dart';
import 'package:wired_test/state/exam_controller.dart';

// Real temporary Hive data, with deterministic gates only at write boundaries.
class _Attempt extends ExamAttempt {
  _Attempt()
      : super(
            attemptId: 'A',
            examId: 1,
            userId: 7,
            startedAt: DateTime.utc(2026, 1, 1),
            durationSeconds: 1800,
            answers: [
              AnswerRecord(
                  questionId: 1,
                  selectedOptionId: 'a',
                  selectedOptionIds: ['a'],
                  updatedAt: DateTime.utc(2026, 1, 1))
            ]);
  Completer<void>? gate;
  bool failNext = false;
  @override
  Future<void> save() {
    if (failNext) {
      failNext = false;
      return Future.error(StateError('Injected answer failure'));
    }
    final pending = gate;
    gate = null;
    return pending == null
        ? super.save()
        : pending.future.then((_) => super.save());
  }
}

class _StateBox extends Fake implements Box<dynamic> {
  _StateBox(this.delegate);
  final Box<dynamic> delegate;
  Completer<void>? gate;
  Completer<void>? entered;
  bool failSnapshot = false;
  bool failAfterGate = false;
  int deletions = 0;
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      delegate.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) => delegate.put(key, value);
  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    if (failSnapshot) throw StateError('Injected required snapshot failure');
    final pending = gate;
    gate = null;
    if (pending != null) {
      entered!.complete();
      await pending.future;
    }
    if (failAfterGate) throw StateError('Injected delayed snapshot failure');
    await delegate.putAll(entries);
  }

  @override
  Future<void> delete(dynamic key) {
    deletions++;
    return delegate.delete(key);
  }
}

class _Service implements ExamSyncService {
  @override
  Future<ActiveExamSessionResult> getActiveExamSession(int examId) async =>
      const ActiveExamSessionResult(ActiveExamSessionOutcome.noActiveSession);
  final calls = <int>[];
  Completer<void>? gate;
  @override
  Future<Map<String, dynamic>?> startExamSession(int examId) async {
    calls.add(examId);
    await gate?.future;
    return {
      'session_id': 'B', 'exam': {'id': examId, 'duration_minutes': 45},
      // Deliberately reuse the question ID to exercise shared-template leakage.
      'questions': [
        {
          'id': 1,
          'question_text': 'B',
          'options': {'a': 'A', 'b': 'B'}
        }
      ]
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected service call: ${invocation.memberName}');
}

void main() {
  late Directory temp;
  late Box<ExamAttempt> attempts;
  late Box<dynamic> state;
  late _StateBox progress;
  late _Service service;
  late ExamController controller;
  late _Attempt attempt;

  setUpAll(() {
    Hive.registerAdapter(ExamAttemptAdapter());
    Hive.registerAdapter(AnswerRecordAdapter());
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('exam_transition_writes_');
    Hive.init(temp.path);
    attempts = await Hive.openBox<ExamAttempt>('attempts');
    state = await Hive.openBox('state');
    attempt = _Attempt();
    await attempts.put('A', attempt);
    await state.putAll({
      'exam_start_time': attempt.startedAt.toIso8601String(),
      'exam_duration': 30,
      'exam_id': 1,
      'user_id': 7,
      'attempt_id': 'A',
      'session_id': 'A',
      'current_index': 0,
      'remaining_seconds': 1200,
      'is_paused': true,
      'saved_answers': [
        {
          'question_id': 1,
          'selected_option': 'a',
          'selected_options': ['a'],
          'updated_at': attempt.startedAt.toIso8601String()
        }
      ]
    });
    service = _Service();
    progress = _StateBox(state);
    controller = ExamController(attempts, service, progress);
    await controller.restoreExamIfExists();
  });
  tearDown(() async {
    controller.dispose();
    await Hive.close();
    await temp.delete(recursive: true);
  });
  Future<void> checkpoint() => state.put('test_checkpoint', true);
  Map archive() =>
      (state.get('preserved_exam_sessions') as List).single['snapshot'] as Map;
  Future<void> startB() async {
    expect(await controller.startExam(examId: 2, userId: 7), isNotEmpty);
    controller.pauseTimer();
  }

  test('start waits for delayed answer save and archives latest selection',
      () async {
    final gate = Completer<void>();
    attempt.gate = gate;
    controller.selectAnswer(1, 'b');
    final starting = startB();
    await checkpoint();
    expect(service.calls, isEmpty);
    expect(state.get('preserved_exam_sessions'), isNull);
    gate.complete();
    await starting;
    expect(
        (archive()['saved_answers'] as List).single['selected_options'], ['b']);
    expect(state.get('exam_id'), 2);
    controller.dispose();
    await Hive.close();
    Hive.init(temp.path);
    attempts = await Hive.openBox<ExamAttempt>('attempts');
    state = await Hive.openBox('state');
    controller = ExamController(attempts, service, state);
    expect(
        (archive()['saved_answers'] as List).single['selected_options'], ['b']);
    expect(attempts.get('A')!.answers.single.normalizedOptions, ['b']);
  });

  test('start drains an already-running progress snapshot before replacing A',
      () async {
    controller.selectAnswer(1, 'b');
    final gate = Completer<void>();
    progress.gate = gate;
    progress.entered = Completer<void>();
    final saving = controller.saveProgress(3);
    await progress.entered!.future;
    final starting = startB();
    await checkpoint();
    expect(service.calls, isEmpty);
    gate.complete();
    await saving;
    await starting;
    expect(archive()['current_index'], 3);
    expect(
        (archive()['saved_answers'] as List).single['selected_options'], ['b']);
    expect(state.get('current_index'), 0);
    expect(state.get('session_id'), 'B');
  });

  test(
      'required persistence failure aborts before preservation and server start',
      () async {
    controller.selectAnswer(1, 'b');
    progress.failSnapshot = true;
    expect(await controller.startExam(examId: 2, userId: 7), isNull);
    expect(service.calls, isEmpty);
    expect(progress.deletions, 0);
    expect(state.get('exam_id'), 1);
    expect(state.get('preserved_exam_sessions'), isNull);
    expect(controller.active!.answers.single.normalizedOptions, ['b']);
    progress.failSnapshot = false;
    await startB();
    expect(
        (archive()['saved_answers'] as List).single['selected_options'], ['b']);
  });

  test(
      'handled answer-save failure still requires and obtains a durable snapshot',
      () async {
    attempt.failNext = true;
    controller.selectAnswer(1, 'b');
    await startB();
    expect(
        (archive()['saved_answers'] as List).single['selected_options'], ['b']);
    expect(service.calls, [2]);
  });

  test('cleanup waits for answer saves before deleting any metadata', () async {
    final generation = controller.persistenceGeneration;
    final gate = Completer<void>();
    attempt.gate = gate;
    controller.selectAnswer(1, 'b');
    final clearing = controller.clearExamPersistence();
    await checkpoint();
    expect(progress.deletions, 0);
    expect(attempts.get('A'), isNotNull);
    gate.complete();
    await clearing;
    expect(state.get('exam_id'), isNull);
    expect(attempts.get('A'), isNull);
    await controller.saveProgress(9, generation: generation);
    controller.selectAnswer(1, 'a', generation: generation);
    controller.toggleFlag(1, generation: generation);
    expect(state.get('exam_id'), isNull);
    expect(state.get('saved_answers'), isNull);
    expect(state.get('flagged_questions'), isNull);
  });

  test('cleanup drains delayed progress before deleting its shared keys',
      () async {
    final gate = Completer<void>();
    progress.gate = gate;
    progress.entered = Completer<void>();
    final saving = controller.saveProgress(4);
    await progress.entered!.future;
    final clearing = controller.clearExamPersistence();
    await checkpoint();
    expect(progress.deletions, 0);
    gate.complete();
    await saving;
    await clearing;
    expect(state.get('exam_id'), isNull);
    expect(state.get('saved_answers'), isNull);
    expect(controller.active, isNull);
  });

  test('cleanup persistence failure preserves answers and deletes nothing',
      () async {
    attempt.failNext = true;
    controller.selectAnswer(1, 'b');
    progress.failSnapshot = true;
    await expectLater(controller.clearExamPersistence(), throwsStateError);
    expect(progress.deletions, 0);
    expect(state.get('exam_id'), 1);
    expect(controller.active!.answers.single.normalizedOptions, ['b']);
    progress.failSnapshot = false;
    await controller.saveProgress(0);
    expect(
        (state.get('saved_answers') as List).single['selected_options'], ['b']);
  });

  test('old session callbacks cannot edit B even when question IDs are shared',
      () async {
    final generation = controller.persistenceGeneration;
    await startB();
    // Drain the new asynchronous pause checkpoint before freezing B's state.
    await controller.saveProgress(controller.getCurrentQuestionIndex());
    final before = state.toMap();
    controller.selectAnswer(1, 'a', generation: generation);
    controller.selectMultipleAnswers(1, ['a'], generation: generation);
    controller.toggleFlag(1, generation: generation);
    await controller.saveProgress(99, generation: generation);
    await controller.clearExamPersistence(generation: generation);
    expect(controller.active!.answers, isEmpty);
    expect(state.toMap(), before);
    controller.selectAnswer(1, 'b',
        generation: controller.persistenceGeneration);
    await controller.saveProgress(0,
        generation: controller.persistenceGeneration);
    expect(
        (state.get('saved_answers') as List).single['selected_options'], ['b']);
  });

  test('overlapping transitions and edits cannot bypass the durability barrier',
      () async {
    final gate = Completer<void>();
    attempt.gate = gate;
    controller.selectAnswer(1, 'b');
    final starting = startB();
    await checkpoint();
    expect(await controller.startExam(examId: 3, userId: 7), isNull);
    await expectLater(controller.clearExamPersistence(), throwsStateError);
    controller.selectAnswer(1, 'a');
    await controller.saveProgress(99);
    await controller.restoreExamIfExists();
    expect(controller.active!.answers.single.normalizedOptions, ['b']);
    expect(service.calls, isEmpty);
    gate.complete();
    await starting;
    expect(service.calls, [2]);
    expect(state.get('current_index'), 0);
  });

  test('a failed in-flight progress write aborts a waiting transition',
      () async {
    final gate = Completer<void>();
    progress.gate = gate;
    progress.entered = Completer<void>();
    final saving = controller.saveProgress(3);
    await progress.entered!.future;
    final failedSave = expectLater(saving, throwsStateError);
    final starting = controller.startExam(examId: 2, userId: 7);
    progress.failAfterGate = true;
    gate.complete();
    await failedSave;
    expect(await starting, isNull);
    expect(service.calls, isEmpty);
    expect(state.get('exam_id'), 1);
  });
  for (final multiple in [false, true]) {
    testWidgets(
        'stale ${multiple ? 'multiple' : 'single'} question widget callback cannot edit B',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final generation = controller.persistenceGeneration;
      final scrolls = <int, ScrollController>{};
      final question = {
        'id': 1,
        'question_text': 'Exam A question',
        'question_type': multiple ? 'multiple' : 'single',
        'options': {'a': 'Option A', 'b': 'Option B'}
      };
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => QuestionCard(
                    parentContext: context,
                    controller: controller,
                    persistenceGeneration: generation,
                    question: question,
                    index: 0,
                    totalQuestions: 1,
                    examExpired: false,
                    isListScrollable: {},
                    listAtBottom: {},
                    scrollControllers: scrolls,
                  ))));
      await tester.pumpAndSettle();
      final staleTap = tester
          .widget<GestureDetector>(find
              .ancestor(
                  of: find.text('Option B'),
                  matching: find.byType(GestureDetector))
              .first)
          .onTap!;
      await tester.runAsync(startB);
      // Rebuild the old question data after B becomes active. Its owner token
      // must remain A's token instead of being read afresh from the controller.
      await tester.pump();
      staleTap();
      await tester.pump();
      expect(controller.active?.attemptId, 'B');
      expect(controller.active!.answers, isEmpty);
      expect(state.get('saved_answers'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      for (final scroll in scrolls.values) {
        scroll.dispose();
      }
    });
  }

  test(
      'restoration reconciles existing saved answers before any fresh snapshot',
      () async {
    final newer = DateTime.utc(2026, 1, 1, 0, 1);
    await state.put('saved_answers', [
      {
        'question_id': 1,
        'selected_option': 'b',
        'selected_options': ['b'],
        'updated_at': newer.toIso8601String()
      }
    ]);
    expect(controller.active!.answers.single.normalizedOptions, ['a']);
    await controller.restoreExamIfExists();
    expect(controller.active!.answers.single.normalizedOptions, ['b']);
    expect(
        (state.get('saved_answers') as List).single['selected_options'], ['b']);
    expect(service.calls, isEmpty);
  });
}
