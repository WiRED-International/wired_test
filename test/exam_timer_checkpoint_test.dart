import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wired_test/models/active_exam_session.dart';
import 'package:wired_test/models/exam_models.dart';
import 'package:wired_test/services/exam_sync_service.dart';
import 'package:wired_test/state/exam_controller.dart';

class _Box<T> extends Fake implements Box<T> {
  final data = <dynamic, T>{};
  @override
  T? get(dynamic key, {T? defaultValue}) => data[key] ?? defaultValue;
  @override
  Iterable<T> get values => data.values;
  @override
  bool containsKey(dynamic key) => data.containsKey(key);
  @override
  Future<void> put(dynamic key, T value) async {
    data[key] = value;
  }
}

class _State extends _Box<dynamic> {
  Completer<void>? gate;
  bool failNext = false;
  void Function()? afterWrite;
  int inFlight = 0;
  int maxInFlight = 0;
  final writes = <Map<dynamic, dynamic>>[];
  @override
  Future<void> putAll(Map<dynamic, dynamic> values) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      final pending = gate;
      gate = null;
      await pending?.future;
      if (failNext) {
        failNext = false;
        throw StateError('Synthetic checkpoint failure');
      }
      writes.add(Map.of(values));
      data.addAll(values);
      final callback = afterWrite;
      afterWrite = null;
      callback?.call();
    } finally {
      inFlight--;
    }
  }
}

class _Attempt extends ExamAttempt {
  _Attempt()
      : super(
            attemptId: 'A',
            examId: 1,
            userId: 7,
            startedAt: DateTime.utc(2026),
            durationSeconds: 1800,
            answers: []);
  @override
  Future<void> save() async {}
}

class _Service extends Fake implements ExamSyncService {
  @override
  Future<ActiveExamSessionResult> getActiveExamSession(int examId) async =>
      const ActiveExamSessionResult(ActiveExamSessionOutcome.noActiveSession);
  @override
  Future<Map<String, dynamic>?> startExamSession(int examId) async => {
        'session_id': 'B',
        'exam': {'id': examId, 'duration_minutes': 45},
        'questions': [
          {
            'id': 2,
            'question_text': 'Synthetic B',
            'options': {'a': 'Alpha'}
          }
        ]
      };
}

void main() {
  late _Box<ExamAttempt> attempts;
  late _State state;
  late ExamController controller;

  setUp(() {
    attempts = _Box<ExamAttempt>();
    attempts.data['A'] = _Attempt();
    state = _State();
    state.data.addAll({
      'exam_id': 1,
      'user_id': 7,
      'attempt_id': 'A',
      'session_id': 'A',
      'exam_start_time': DateTime.utc(2026).toIso8601String(),
      'exam_duration': 30,
      'remaining_seconds': 1200,
      'is_paused': true,
      'current_index': 0,
      'saved_answers': <Map<String, dynamic>>[],
    });
    controller = ExamController(attempts, _Service(), state);
  });

  Future<void> start() async {
    await controller.restoreExamIfExists();
    controller.resumeTimer();
  }

  testWidgets(
      'active countdown writes every five seconds and abrupt restart restores a recent checkpoint',
      (tester) async {
    await start();
    await tester.pump(const Duration(seconds: 4));
    expect(state.writes, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(state.get('remaining_seconds'), 1195);
    expect(state.writes.length, 1);
    await tester.pump(const Duration(seconds: 7));
    expect(controller.remainingSeconds, 1188);
    expect(state.get('remaining_seconds'), 1190);
    expect(state.writes.length, 2);
    controller.dispose(); // Abrupt loss: no pause/save callback.
    controller = ExamController(attempts, _Service(), state);
    await controller.restoreExamIfExists();
    expect(controller.remainingSeconds, 1190);
    expect(controller.active!.attemptId, 'A');
    await tester.pump(const Duration(seconds: 2));
    expect(controller.remainingSeconds, 1188);
    controller.dispose();
  });

  testWidgets(
      'pause checkpoints the latest second and stops countdown and periodic writes',
      (tester) async {
    await start();
    await tester.pump(const Duration(seconds: 7));
    controller.pauseTimer();
    await tester.pump();
    expect(state.get('remaining_seconds'), 1193);
    expect(state.get('is_paused'), isTrue);
    final writes = state.writes.length;
    await tester.pump(const Duration(minutes: 1));
    expect(controller.remainingSeconds, 1193);
    expect(state.writes.length, writes);
    controller.resumeTimer();
    await tester.pump(const Duration(seconds: 2));
    expect(controller.remainingSeconds, 1191);
    controller.dispose();
  });

  testWidgets(
      'slow checkpoints serialize with progress saves and a final pause',
      (tester) async {
    await start();
    final gate = Completer<void>();
    state.gate = gate;
    await tester.pump(const Duration(seconds: 5));
    expect(state.inFlight, 1);
    final saving = controller.saveProgress(3);
    await tester.pump(const Duration(seconds: 10));
    expect(state.inFlight, 1);
    controller.pauseTimer();
    gate.complete();
    await tester.pump();
    await saving;
    expect(state.maxInFlight, 1);
    expect(state.get('current_index'), 3);
    expect(state.get('remaining_seconds'), 1185);
    expect(state.get('is_paused'), isTrue);
    expect(state.get('saved_answers'), isEmpty);
    controller.dispose();
  });

  testWidgets(
      'new session waits for delayed old checkpoint and keeps its own timer',
      (tester) async {
    await start();
    final gate = Completer<void>();
    state.gate = gate;
    await tester.pump(const Duration(seconds: 5));
    var started = false;
    final starting = controller.startExam(examId: 2, userId: 8).then((value) {
      started = true;
      return value;
    });
    await tester.pump(const Duration(seconds: 10));
    expect(started, isFalse);
    expect(state.get('attempt_id'), 'A');
    gate.complete();
    await tester.pump();
    expect(await starting, isNotEmpty);
    expect(state.get('session_id'), 'B');
    expect(state.get('user_id'), 8);
    expect(state.get('remaining_seconds'), 2700);
    await tester.pump(const Duration(seconds: 5));
    expect(state.get('remaining_seconds'), 2695);
    expect(state.get('exam_id'), 2);
    expect(state.maxInFlight, 1);
    controller.dispose();
  });

  testWidgets('queued checkpoint is discarded after attempt completion',
      (tester) async {
    await start();
    final gate = Completer<void>();
    state.gate = gate;
    final saving = controller.saveProgress(0);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    // Invalidate ownership before the queued checkpoint reaches its write.
    controller.active!.submitted = true;
    gate.complete();
    await tester.pump();
    await saving;
    expect(state.writes.length, 1,
        reason: 'No timer checkpoint after completion');
    await tester.pump(const Duration(seconds: 10));
    expect(state.writes.length, 1);
    controller.dispose();
  });

  for (final field in ['user_id', 'exam_id', 'session_id']) {
    testWidgets('queued checkpoint rejects changed $field ownership',
        (tester) async {
      await start();
      final gate = Completer<void>();
      state.gate = gate;
      final saving = controller.saveProgress(0);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      state.afterWrite = () {
        state.data[field] = field == 'session_id' ? 'B' : 99;
        state.data['remaining_seconds'] = 2700;
      };
      gate.complete();
      await tester.pump();
      await saving;
      expect(state.writes.length, 1);
      expect(state.get('remaining_seconds'), 2700);
      controller.dispose();
    });
  }

  testWidgets('disposed controller discards queued checkpoints',
      (tester) async {
    await start();
    final gate = Completer<void>();
    state.gate = gate;
    final saving = controller.saveProgress(0);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    controller.dispose();
    gate.complete();
    await tester.pump();
    await saving;
    expect(state.writes.length, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(state.writes.length, 1);
  });

  testWidgets('failed checkpoint is contained and later checkpoints retry',
      (tester) async {
    await start();
    state.failNext = true;
    await tester.pump(const Duration(seconds: 5));
    expect(state.get('remaining_seconds'), 1200);
    await tester.pump(const Duration(seconds: 5));
    expect(state.get('remaining_seconds'), 1190);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets(
      'timeout persists zero after an in-flight checkpoint and stops writes',
      (tester) async {
    state.data['remaining_seconds'] = 6;
    await start();
    final gate = Completer<void>();
    state.gate = gate;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 2));
    gate.complete();
    await tester.pump();
    expect(state.get('remaining_seconds'), 0);
    expect(state.get('is_paused'), isTrue);
    final writes = state.writes.length;
    await tester.pump(const Duration(seconds: 10));
    expect(state.writes.length, writes);
    expect(state.maxInFlight, 1);
    controller.dispose();
  });
}
