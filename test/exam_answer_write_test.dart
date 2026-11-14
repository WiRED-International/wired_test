import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wired_test/models/exam_models.dart';
import 'package:wired_test/services/exam_sync_service.dart';
import 'package:wired_test/state/exam_controller.dart';

class _UnusedExamSyncService implements ExamSyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected exam service call: ${invocation.memberName}');
}

const _attemptId = 'answer-write-session';
final _startedAt = DateTime.utc(2026, 1, 1, 9);

// Only completion/failure injection uses a double. It remains attached to a real
// Hive box, and successful saves delegate to HiveObject.save(). Arm after restore
// so the controller's awaited restoration save still uses the real implementation.
class _ControlledAttempt extends ExamAttempt {
  _ControlledAttempt()
      : super(
          attemptId: _attemptId,
          examId: 42,
          userId: 7,
          startedAt: _startedAt,
          durationSeconds: 1800,
          answers: [],
        );

  Completer<void>? saveGate;
  Object? nextSaveError;
  Future<void>? delayedSave;
  bool delayedSaveCompleted = false;

  @override
  Future<void> save() {
    final error = nextSaveError;
    nextSaveError = null;
    if (error != null) return Future<void>.error(error);
    final gate = saveGate;
    saveGate = null;
    if (gate == null) return super.save();
    return delayedSave = gate.future.then((_) => super.save()).whenComplete(() {
      delayedSaveCompleted = true;
    });
  }
}

class _ProgressBox extends Fake implements Box<dynamic> {
  _ProgressBox(this.delegate);
  final Box<dynamic> delegate;
  bool failWrites = false;
  Completer<void>? writeGate;
  Completer<void>? writeStarted;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      delegate.get(key, defaultValue: defaultValue);

  @override
  Future<void> put(dynamic key, dynamic value) => delegate.put(key, value);

  @override
  Future<void> putAll(Map<dynamic, dynamic> values) async {
    if (failWrites) throw StateError('Injected snapshot write failure');
    final gate = writeGate;
    writeGate = null;
    if (gate != null) {
      writeStarted!.complete();
      await gate.future;
    }
    await delegate.putAll(values);
  }
}

// Observe otherwise-unhandled errors without letting the test runner consume
// them first. An event-queue turn drains scheduled microtasks; no timed sleep.
Future<List<Object>> _captureAsyncErrors(Future<void> Function() action) {
  final completed = Completer<List<Object>>();
  final errors = <Object>[];
  runZonedGuarded(() async {
    try {
      await action();
      await Future<void>(() {});
      completed.complete(errors);
    } catch (error, stack) {
      completed.completeError(error, stack);
    }
  }, (error, stack) => errors.add(error));
  return completed.future;
}

void main() {
  late Directory directory;
  late Box<ExamAttempt> attempts;
  late Box examBox;
  ExamController? controller;

  setUpAll(() {
    Hive.registerAdapter(ExamAttemptAdapter());
    Hive.registerAdapter(AnswerRecordAdapter());
  });

  Future<void> openBoxes() async {
    attempts = await Hive.openBox<ExamAttempt>('exam_attempts');
    examBox = await Hive.openBox('examBox');
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('exam_answer_write_');
    Hive.init(directory.path);
    await openBoxes();
  });

  tearDown(() async {
    controller?.dispose();
    controller = null;
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> reopen() async {
    controller?.dispose();
    controller = null;
    await Hive.close();
    Hive.init(directory.path);
    await openBoxes();
  }

  Future<ExamController> seed({ExamAttempt? attempt, Box? progressBox}) async {
    await attempts.put(
      _attemptId,
      attempt ??
          ExamAttempt(
            attemptId: _attemptId,
            examId: 42,
            userId: 7,
            startedAt: _startedAt,
            durationSeconds: 1800,
            answers: [],
          ),
    );
    await examBox.putAll({
      'exam_start_time': _startedAt.toIso8601String(),
      'exam_duration': 30,
      'exam_id': 42,
      'user_id': 7,
      'attempt_id': _attemptId,
      'session_id': _attemptId,
      'current_index': 0,
      'remaining_seconds': 1200,
      'is_paused': true,
    });
    controller = ExamController(
        attempts, _UnusedExamSyncService(), progressBox ?? examBox);
    await controller!.restoreExamIfExists();
    expect(controller!.active, isNotNull);
    return controller!;
  }

  test('characterization: rapid single-choice changes persist the final answer',
      () async {
    final exam = await seed();
    exam.selectAnswer(1, 'a');
    exam.selectAnswer(1, 'b');
    exam.selectAnswer(1, 'c');
    // No extra active.save(): exercise normal Hive close draining queued writes.
    await reopen();

    expect(attempts.get(_attemptId)!.answers.single.normalizedOptions, ['c']);
  });

  for (final emptyFinal in [false, true]) {
    test('characterization: rapid multi-choice changes persist '
        '${emptyFinal ? 'an intentional empty selection' : 'the final selection'}',
        () async {
      final exam = await seed();
      exam.selectMultipleAnswers(1, ['a']);
      exam.selectMultipleAnswers(1, ['a', 'b']);
      exam.selectMultipleAnswers(1, ['b']);
      final expected = emptyFinal ? <String>[] : ['c', 'd'];
      exam.selectMultipleAnswers(1, expected);
      await reopen();

      final answer = attempts.get(_attemptId)!.answers.single;
      expect(answer.selectedOptionIds, expected);
      expect(answer.selectedOptionId, emptyFinal ? isNull : 'c');
      expect(answer.normalizedOptions, expected);
    });
  }

  test('characterization: a pending real Hive save serializes later mutation',
      () async {
    final exam = await seed();
    final answer = AnswerRecord(
      questionId: 1,
      selectedOptionId: 'a',
      selectedOptionIds: ['a'],
      updatedAt: _startedAt,
    );
    exam.active!.answers = [answer];
    final pending = exam.active!.save();
    // Mutate in the same synchronous turn, before queued serialization starts.
    answer.selectedOptionId = 'b';
    answer.selectedOptionIds![0] = 'b';
    await pending;
    await reopen();

    expect(attempts.get(_attemptId)!.answers.single.normalizedOptions, ['b']);
  });

  test('regression: saveProgress freezes option lists at invocation', () async {
    final exam = await seed();
    exam.selectMultipleAnswers(1, ['a']);
    await exam.active!.save();
    final answer = exam.active!.answers.single;
    final originalTime = answer.updatedAt.toIso8601String();
    final pending = exam.saveProgress(0);
    answer.selectedOptionIds!.add('b');
    await pending;
    await reopen();

    final snapshot = (examBox.get('saved_answers') as List).single as Map;
    expect(snapshot['selected_option'], 'a');
    expect(snapshot['updated_at'], originalTime);
    expect(snapshot['selected_options'], ['a']);
  });

  test('regression: saveProgress waits for pending selection-save completion',
      () async {
    final attempt = _ControlledAttempt();
    final exam = await seed(attempt: attempt);
    expect(identical(exam.active, attempt), isTrue);
    expect(attempt.isInBox, isTrue);
    final gate = Completer<void>();
    attempt.saveGate = gate;
    exam.selectAnswer(1, 'b');
    expect(exam.active!.answers.single.normalizedOptions, ['b']);
    final progress = exam.saveProgress(0);
    var progressCompleted = false;
    final observedProgress = progress.then((_) => progressCompleted = true);
    // Finish a real write in the separate snapshot box as a deterministic
    // checkpoint, without releasing the controlled attempt write.
    await examBox.put('write_test_checkpoint', true);
    final completedBeforeRelease = progressCompleted;
    try {
      expect(attempt.delayedSaveCompleted, isFalse);
    } finally {
      gate.complete();
      await attempt.delayedSave;
      await observedProgress;
    }

    expect(completedBeforeRelease, isFalse,
        reason: 'The Save & Exit persistence boundary must drain answer saves.');
    await reopen();
    expect(attempts.get(_attemptId)!.answers.single.normalizedOptions, ['b']);
  });

  test('regression: asynchronous selection-save failure is handled', () async {
    final attempt = _ControlledAttempt();
    final exam = await seed(attempt: attempt);
    final failure = StateError('Injected asynchronous answer write failure');
    attempt.nextSaveError = failure;

    final errors = await _captureAsyncErrors(() async {
      exam.selectAnswer(1, 'b');
    });

    expect(exam.active!.answers.single.normalizedOptions, ['b']);
    expect(errors, isEmpty);
  });

  test('characterization: failed save retains answer and permits later success',
      () async {
    final attempt = _ControlledAttempt();
    final exam = await seed(attempt: attempt);
    final failure = StateError('Injected asynchronous answer write failure');
    attempt.nextSaveError = failure;
    final errors = await _captureAsyncErrors(() async {
      exam.selectMultipleAnswers(1, ['a', 'b']);
    });
    expect(errors, isEmpty);
    expect(exam.active!.answers.single.normalizedOptions, ['a', 'b']);

    exam.selectMultipleAnswers(1, ['c']);
    await reopen();

    expect(attempts.get(_attemptId)!.answers.single.normalizedOptions, ['c']);
  });

  test('older completion cannot remove a newer pending selection save', () async {
    final attempt = _ControlledAttempt();
    final exam = await seed(attempt: attempt);
    final olderGate = Completer<void>();
    attempt.saveGate = olderGate;
    exam.selectAnswer(1, 'a');
    final olderSave = attempt.delayedSave!;
    final newerGate = Completer<void>();
    attempt.saveGate = newerGate;
    exam.selectAnswer(1, 'b');
    final newerSave = attempt.delayedSave!;
    olderGate.complete();
    await olderSave;
    // Let tracking cleanup for the older operation finish.
    await Future<void>(() {});
    var completed = false;
    final progress = exam.saveProgress(0).then((_) => completed = true);
    await examBox.put('write_test_checkpoint', true);
    final completedBeforeRelease = completed;
    newerGate.complete();
    await newerSave;
    await progress;

    expect(completedBeforeRelease, isFalse);
    await reopen();
    expect(attempts.get(_attemptId)!.answers.single.normalizedOptions, ['b']);
  });

  test('saveProgress includes edits made while waiting for selection writes',
      () async {
    final attempt = _ControlledAttempt();
    final exam = await seed(attempt: attempt);
    final gate = Completer<void>();
    attempt.saveGate = gate;
    exam.selectAnswer(1, 'a');
    final delayed = attempt.delayedSave!;
    final progress = exam.saveProgress(0);
    exam.selectAnswer(1, 'b');
    gate.complete();
    await delayed;
    await progress;
    await reopen();

    final snapshot = (examBox.get('saved_answers') as List).single as Map;
    expect(snapshot['selected_options'], ['b']);
    expect(snapshot['selected_option'], 'b');
  });

  test('handled selection failure still requires a successful snapshot write',
      () async {
    final attempt = _ControlledAttempt();
    final progressBox = _ProgressBox(examBox);
    final exam = await seed(attempt: attempt, progressBox: progressBox);
    attempt.nextSaveError = StateError('Injected selection write failure');
    progressBox.failWrites = true;
    final errors = await _captureAsyncErrors(() async {
      exam.selectMultipleAnswers(1, ['a', 'b']);
      await expectLater(exam.saveProgress(0), throwsStateError);
    });
    expect(errors, isEmpty);
    expect(exam.active!.answers.single.normalizedOptions, ['a', 'b']);
    expect(examBox.containsKey('saved_answers'), isFalse);

    progressBox.failWrites = false;
    await exam.saveProgress(0);
    await reopen();
    final snapshot = (examBox.get('saved_answers') as List).single as Map;
    expect(snapshot['selected_options'], ['a', 'b']);
  });

  test('saveProgress persists edits made during the snapshot write', () async {
    final progressBox = _ProgressBox(examBox);
    final exam = await seed(progressBox: progressBox);
    exam.selectAnswer(1, 'a');
    final gate = Completer<void>();
    final started = Completer<void>();
    progressBox.writeGate = gate;
    progressBox.writeStarted = started;
    final progress = exam.saveProgress(0);
    await started.future;
    exam.selectAnswer(1, 'b');
    gate.complete();
    await progress;
    await reopen();

    final snapshot = (examBox.get('saved_answers') as List).single as Map;
    expect(snapshot['selected_options'], ['b']);
    expect(snapshot['selected_option'], 'b');
  });
}
