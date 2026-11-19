import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/models/exam_models.dart';
import 'package:wired_test/models/active_exam_session.dart';
import 'package:wired_test/pages/exam/exam_page.dart';
import 'package:wired_test/services/exam_sync_service.dart';
import 'package:wired_test/state/exam_controller.dart';

// Synthetic local fixtures only: no HTTP, databases, or installed app storage.
class _Service implements ExamSyncService {
  @override
  Future<ActiveExamSessionResult> getActiveExamSession(int examId) async =>
      const ActiveExamSessionResult(ActiveExamSessionOutcome.noActiveSession);
  final starts = <int>[];
  @override
  Future<Map<String, dynamic>?> startExamSession(int examId) async {
    starts.add(examId);
    return {
      'session_id': 'fresh-session',
      'exam': {'id': examId, 'duration_minutes': 30},
      'questions': [
        {
          'id': 1,
          'question_text': 'Fresh question',
          'question_type': 'single',
          'options': {'a': 'Option A', 'b': 'Option B'}
        }
      ]
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected service call: ${invocation.memberName}');
}

// Prepare real Hive restoration before widget pumping; the page's repeated
// restore is a no-op in widget mode, so no native file I/O runs under fake time.
// Fresh-page routing uses the mocked start result; real fresh initialization is
// covered separately below and by the existing isolation suite.
class _Controller extends ExamController {
  _Controller(Box<ExamAttempt> attempts, this.source, Box<dynamic> state)
      : super(attempts, source, state);
  final _Service source;
  bool widgetMode = false;
  int restores = 0;
  Future<void> prepareRecovery() => super.restoreExamIfExists();
  @override
  Future<void> restoreExamIfExists() async {
    restores++;
    if (!widgetMode) await super.restoreExamIfExists();
  }

  @override
  Future<List<Map<String, dynamic>>?> startExam(
      {required int examId, required int userId}) async {
    if (!widgetMode || recoveryStateFor(examId, userId) == ExamRecoveryState.unresolved) {
      return super.startExam(examId: examId, userId: userId);
    }
    final response = await source.startExamSession(examId);
    return (response!['questions'] as List).cast<Map<String, dynamic>>();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Box<ExamAttempt> attempts;
  late Box<dynamic> state;
  late _Service service;
  late _Controller controller;
  final time = DateTime.utc(2026, 1, 1);

  setUpAll(() {
    Hive.registerAdapter(ExamAttemptAdapter());
    Hive.registerAdapter(AnswerRecordAdapter());
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('exam_legacy_recovery_');
    Hive.init(temp.path);
    attempts = await Hive.openBox<ExamAttempt>('attempts');
    state = await Hive.openBox('state');
    service = _Service();
    controller = _Controller(attempts, service, state);
  });
  tearDown(() async {
    controller.dispose();
    await Hive.close();
    await temp.delete(recursive: true);
  });

  Future<void> seed(
      {int delayMs = 0,
      bool sessionOnly = false,
      bool missingAttempt = false,
      int remaining = 1200}) async {
    if (!missingAttempt) {
      await attempts.put(
          'saved-session',
          ExamAttempt(
              attemptId: 'saved-session',
              examId: 1,
              userId: 7,
              startedAt: time,
              durationSeconds: 1800,
              answers: [
                AnswerRecord(
                    questionId: 1,
                    selectedOptionId: 'a',
                    selectedOptionIds: ['a'],
                    updatedAt: time)
              ]));
    }
    await state.putAll({
      'exam_start_time':
          time.add(Duration(milliseconds: delayMs)).toIso8601String(),
      'exam_duration': 30,
      'exam_id': 1,
      'user_id': 7,
      if (!sessionOnly) 'attempt_id': 'saved-session',
      'session_id': 'saved-session',
      'remaining_seconds': remaining,
      'is_paused': true,
      'current_index': 0,
      'cached_questions': [
        {
          'id': 1,
          'question_text': 'Saved question',
          'question_type': 'single',
          'options': {'a': 'Option A', 'b': 'Option B'}
        }
      ],
      'saved_answers': [
        {
          'question_id': 1,
          'selected_option': 'a',
          'selected_options': ['a'],
          'updated_at': time.toIso8601String()
        }
      ]
    });
  }

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final recovery = controller.recoveryStateFor(1, 7);
    if (recovery == ExamRecoveryState.resumable) {
      await tester.runAsync(controller.prepareRecovery);
    }
    controller.widgetMode = true;
    await tester.pumpWidget(ChangeNotifierProvider<ExamController>.value(
        value: controller,
        child: const MaterialApp(
            home: ExamPage(
                examId: 1,
                userId: 7,
                sessionData: {'examTitle': 'Test exam'}))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  }

  Future<void> finishWidget(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      controller.pauseTimer();
      await controller.saveProgress(controller.getCurrentQuestionIndex());
    });
  }

  Future<void> unresolved(WidgetTester tester) async {
    final before = state.toMap();
    final answers =
        attempts.get('saved-session')?.answers.map((a) => a.toJson()).toList();
    expect(controller.recoveryStateFor(1, 7), ExamRecoveryState.unresolved);
    await show(tester);
    expect(find.text('Exam recovery'), findsOneWidget);
    expect(find.textContaining('saved exam session needs recovery'),
        findsOneWidget);
    expect(find.textContaining('submitted'), findsNothing);
    expect(find.textContaining('lost'), findsNothing);
    expect(service.starts, isEmpty);
    expect(controller.restores, 0);
    expect(state.toMap(), before);
    expect(
        attempts.get('saved-session')?.answers.map((a) => a.toJson()).toList(),
        answers);
    await finishWidget(tester);
  }

  test(
      'decision is read-only and distinguishes empty state from resumable legacy state',
      () async {
    expect(controller.recoveryStateFor(1, 7), ExamRecoveryState.none);
    await seed();
    final before = state.toMap();
    expect(controller.recoveryStateFor(1, 7), ExamRecoveryState.resumable);
    expect(state.toMap(), before);
    expect(controller.active, isNull);
    expect(service.starts, isEmpty);
  });

  testWidgets(
      'six-second legacy timestamp delay blocks fallback without changing saved data',
      (tester) async {
    await tester.runAsync(() async {
      await seed(delayMs: 6000);
    });
    await unresolved(tester);
  });
  testWidgets('missing cached questions do not create another session',
      (tester) async {
    await tester.runAsync(() async {
      await seed();
      await state.delete('cached_questions');
    });
    await unresolved(tester);
  });
  testWidgets('rejected cache ownership tag does not create another session',
      (tester) async {
    await tester.runAsync(() async {
      await seed();
      await state.put('cached_questions_identity', {
        'attempt_id': 'other-session',
        'exam_id': 1,
        'user_id': 7,
        'question_ids': [1]
      });
    });
    await unresolved(tester);
  });
  testWidgets('conflicting attempt/session IDs remain untouched',
      (tester) async {
    await tester.runAsync(() async {
      await seed();
      await state.put('session_id', 'different-session');
    });
    await unresolved(tester);
  });
  testWidgets(
      'wrong user identity does not reconstruct or replace the saved session',
      (tester) async {
    await tester.runAsync(() async {
      await seed();
      await state.put('user_id', 8);
    });
    await unresolved(tester);
  });
  testWidgets('orphaned unsubmitted attempt blocks a fresh server start',
      (tester) async {
    await tester.runAsync(() async {
      await attempts.put(
          'saved-session',
          ExamAttempt(
              attemptId: 'saved-session',
              examId: 1,
              userId: 7,
              startedAt: time,
              durationSeconds: 1800,
              answers: []));
    });
    await unresolved(tester);
  });
  testWidgets(
      'preserved unresolved session blocks replacement without restoring its archive',
      (tester) async {
    await tester.runAsync(() async {
      await state.put('preserved_exam_sessions', [
        {
          'snapshot': {
            'exam_id': 1,
            'user_id': 7,
            'session_id': 'saved-session',
            'saved_answers': []
          }
        }
      ]);
    });
    await unresolved(tester);
  });

  for (final delay in [0, 300, 5000]) {
    testWidgets(
        'consistent legacy session resumes with timestamp difference $delay ms',
        (tester) async {
      await tester.runAsync(() => seed(delayMs: delay));
      await show(tester);
      expect(service.starts, isEmpty);
      expect(find.text('Saved question'), findsOneWidget);
      expect(find.text('Exam recovery'), findsNothing);
      expect(controller.active?.attemptId, 'saved-session');
      expect(controller.active!.answers.single.normalizedOptions, ['a']);
      await finishWidget(tester);
    });
  }
  testWidgets('session-ID-only legacy session resumes without a new attempt',
      (tester) async {
    await tester.runAsync(() => seed(sessionOnly: true));
    await show(tester);
    expect(service.starts, isEmpty);
    expect(find.text('Saved question'), findsOneWidget);
    expect(controller.active?.attemptId, 'saved-session');
    await finishWidget(tester);
  });
  testWidgets(
      'consistent snapshot reconstructs a missing attempt without starting another',
      (tester) async {
    await tester.runAsync(() => seed(sessionOnly: true, missingAttempt: true));
    await show(tester);
    expect(service.starts, isEmpty);
    expect(find.text('Saved question'), findsOneWidget);
    expect(attempts.get('saved-session'), isNotNull);
    await finishWidget(tester);
  });
  testWidgets(
      'expired saved session shows its questions instead of requesting a new attempt',
      (tester) async {
    await tester.runAsync(() => seed(remaining: 0));
    await show(tester);
    expect(service.starts, isEmpty);
    expect(find.text('Saved question'), findsOneWidget);
    expect(controller.remainingSeconds, 0);
    await finishWidget(tester);
  });
  testWidgets('no saved evidence permits exactly one normal fresh start',
      (tester) async {
    await show(tester);
    expect(service.starts, [1]);
    expect(find.text('Fresh question'), findsOneWidget);
    expect(find.text('Exam recovery'), findsNothing);
    await finishWidget(tester);
  });
  test(
      'real fresh initialization remains resumable after exactly one mocked start',
      () async {
    expect(controller.recoveryStateFor(1, 7), ExamRecoveryState.none);
    expect(await controller.startExam(examId: 1, userId: 7), isNotEmpty);
    controller.pauseTimer();
    expect(service.starts, [1]);
    expect(controller.active?.attemptId, 'fresh-session');
    expect(controller.recoveryStateFor(1, 7), ExamRecoveryState.resumable);
  });
}
