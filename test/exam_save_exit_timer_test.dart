import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/models/exam_models.dart';
import 'package:wired_test/pages/exam/exam_page.dart';
import 'package:wired_test/services/exam_sync_service.dart';
import 'package:wired_test/state/exam_controller.dart';

// In-memory storage with the real controller and fake widget time. No network,
// native storage, or database is needed to exercise countdown persistence.
class _Box<T> extends Fake implements Box<T> {
  final data = <dynamic, T>{};
  @override
  T? get(dynamic key, {T? defaultValue}) => data[key] ?? defaultValue;
  @override
  Iterable<T> get values => data.values;
  @override
  Future<void> put(dynamic key, T value) async => data[key] = value;
  @override
  Future<void> putAll(Map<dynamic, T> entries) async => data.addAll(entries);
}

class _Attempt extends ExamAttempt {
  _Attempt()
      : super(
            attemptId: 'saved-session',
            examId: 1,
            userId: 7,
            startedAt: DateTime.utc(2026),
            durationSeconds: 1800,
            answers: [
              AnswerRecord(
                  questionId: 9,
                  selectedOptionId: 'a',
                  updatedAt: DateTime.utc(2026))
            ]);
  @override
  Future<void> save() async {}
}

class _Service extends Fake implements ExamSyncService {}

class _Controller extends ExamController {
  _Controller(super.attempts, super.syncService, super.examBox);
  Completer<void>? saveGate;
  bool failSave = false;
  int saves = 0;

  @override
  Future<void> saveProgress(int questionIndex, {int? generation}) async {
    saves++;
    await saveGate?.future;
    if (failSave) throw StateError('Synthetic storage failure');
    await super.saveProgress(questionIndex, generation: generation);
  }
}

void main() {
  late _Box<ExamAttempt> attempts;
  late _Box<dynamic> state;
  late _Controller controller;
  late GlobalKey<NavigatorState> navigator;

  setUp(() async {
    attempts = _Box<ExamAttempt>();
    state = _Box<dynamic>();
    await attempts.put('saved-session', _Attempt());
    await state.putAll({
      'exam_start_time': DateTime.utc(2026).toIso8601String(),
      'exam_duration': 30,
      'exam_id': 1,
      'user_id': 7,
      'attempt_id': 'saved-session',
      'session_id': 'saved-session',
      'remaining_seconds': 1200,
      'is_paused': true,
      'current_index': 0,
      'cached_questions': [
        {
          'id': 9,
          'question_text': 'Synthetic question',
          'question_type': 'single',
          'options': {'a': 'Alpha', 'b': 'Beta'}
        }
      ],
      'cached_questions_identity': {
        'attempt_id': 'saved-session',
        'exam_id': 1,
        'user_id': 7,
        'question_ids': [9]
      },
    });
    controller = _Controller(attempts, _Service(), state);
    navigator = GlobalKey<NavigatorState>();
  });

  tearDown(() => controller.dispose());

  Future<void> openExam(WidgetTester tester) async {
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const ExamPage(examId: 1, userId: 7)));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic question'), findsOneWidget);
  }

  Future<void> show(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider<ExamController>.value(
      value: controller,
      child: MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Exam selection')),
      ),
    ));
    await openExam(tester);
  }

  Future<void> exitDialog(WidgetTester tester, String action) async {
    navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Exit Exam?'), findsOneWidget);
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  testWidgets('Save & Exit freezes time before saving and resumes saved time',
      (tester) async {
    await show(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(controller.remainingSeconds, lessThan(1200));
    final gate = Completer<void>();
    controller.saveGate = gate;
    await exitDialog(tester, 'Save & Exit');
    final pausedAt = controller.remainingSeconds;
    expect(find.byType(ExamPage), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(controller.remainingSeconds, pausedAt,
        reason: 'The countdown must stop while the save is pending');

    // A foreground event must not restart the countdown during the exit save.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(controller.remainingSeconds, pausedAt);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ExamPage), findsNothing);
    expect(state.get('remaining_seconds'), pausedAt);
    expect(state.get('is_paused'), isTrue);
    await tester.pump(const Duration(minutes: 2));
    expect(controller.remainingSeconds, pausedAt);

    controller.saveGate = null;
    // Recreate the controller to prove resumption uses the persisted checkpoint.
    controller.dispose();
    controller = _Controller(attempts, _Service(), state);
    await tester.pumpWidget(ChangeNotifierProvider<ExamController>.value(
      value: controller,
      child: MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Exam selection')),
      ),
    ));
    await openExam(tester);
    expect(controller.remainingSeconds, pausedAt);
    expect(controller.active!.attemptId, 'saved-session');
    expect(controller.active!.userId, 7);
    expect(controller.active!.examId, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(controller.remainingSeconds, pausedAt - 3);
    controller.pauseTimer();
  });

  testWidgets('failed exit save retains the exam and allows retry',
      (tester) async {
    await show(tester);
    final attempt = controller.active;
    controller.failSave = true;
    await exitDialog(tester, 'Save & Exit');
    expect(find.byType(ExamPage), findsOneWidget);
    expect(find.text('Unable to save exam progress. Please try again.'),
        findsOneWidget);
    expect(controller.active, same(attempt));
    expect(controller.active!.answers.single.normalizedOptions, ['a']);
    final remaining = controller.remainingSeconds;
    await tester.pump(const Duration(seconds: 2));
    expect(controller.remainingSeconds, remaining - 2);
    expect(tester.takeException(), isNull);

    controller.failSave = false;
    await exitDialog(tester, 'Save & Exit');
    expect(find.byType(ExamPage), findsNothing);
    expect(state.get('is_paused'), isTrue);
  });

  testWidgets('Cancel leaves the countdown running without an exit save',
      (tester) async {
    await show(tester);
    final saves = controller.saves;
    await exitDialog(tester, 'Cancel');
    final remaining = controller.remainingSeconds;
    await tester.pump(const Duration(seconds: 2));
    expect(controller.remainingSeconds, remaining - 2);
    expect(find.byType(ExamPage), findsOneWidget);
    expect(controller.saves, saves);
    controller.pauseTimer();
  });
}
