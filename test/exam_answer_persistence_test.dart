import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wired_test/models/exam_models.dart';
import 'package:wired_test/services/exam_sync_service.dart';
import 'package:wired_test/state/exam_controller.dart';

// Restoration and local progress saving must never need the backend.
class _UnusedExamSyncService implements ExamSyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected exam service call: ${invocation.memberName}');
}

const _attemptId = 'session-42';
final _startedAt = DateTime.utc(2026, 1, 1, 9);
final _older = DateTime.utc(2026, 1, 1, 9, 1);
final _newer = DateTime.utc(2026, 1, 1, 9, 2);

AnswerRecord _answer(int questionId, List<String> options, DateTime updatedAt) =>
    AnswerRecord(
      questionId: questionId,
      selectedOptionId: options.isEmpty ? null : options.first,
      selectedOptionIds: List<String>.from(options),
      updatedAt: updatedAt,
    );

List<Map<String, dynamic>> _snapshot(List<AnswerRecord> answers) => answers
    .map((answer) => {
          'question_id': answer.questionId,
          'selected_option': answer.selectedOptionId,
          'selected_options': List<String>.from(answer.selectedOptionIds ?? []),
          'updated_at': answer.updatedAt.toIso8601String(),
        })
    .toList();

Map<int, List<String>> _selections(ExamAttempt attempt) => {
      for (final answer in attempt.answers)
        answer.questionId: List<String>.from(answer.normalizedOptions),
    };

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
    directory = await Directory.systemTemp.createTemp('exam_answer_persistence_');
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

  Future<void> seed({
    required List<AnswerRecord> answers,
    List<AnswerRecord>? snapshot,
    bool includeAttempt = true,
  }) async {
    if (includeAttempt) {
      await attempts.put(
        _attemptId,
        ExamAttempt(
          attemptId: _attemptId,
          examId: 42,
          userId: 7,
          startedAt: _startedAt,
          durationSeconds: 1800,
          answers: answers,
        ),
      );
    }
    await examBox.putAll({
      'exam_start_time': _startedAt.toIso8601String(),
      'exam_duration': 30,
      'exam_id': 42,
      'user_id': 7,
      'attempt_id': _attemptId,
      'session_id': _attemptId,
      'current_index': 0,
      'remaining_seconds': 1200,
      // Positive remaining time with an explicit pause avoids all timer paths.
      'is_paused': true,
      'is_reviewed': false,
      if (snapshot != null) 'saved_answers': _snapshot(snapshot),
    });
    await reopen();
  }

  Future<ExamController> restore() async {
    controller ??=
        ExamController(attempts, _UnusedExamSyncService(), examBox);
    await controller!.restoreExamIfExists();
    expect(controller!.active, isNotNull);
    return controller!;
  }

  test('newer persisted attempt answer survives an older snapshot', () async {
    await seed(
      answers: [_answer(1, ['b'], _newer)],
      snapshot: [_answer(1, ['a'], _older)],
    );
    expect(_selections(attempts.get(_attemptId)!), {1: ['b']});

    final restored = await restore();

    expect(_selections(restored.active!), {1: ['b']});
    expect(restored.active!.answers.single.updatedAt, _newer);
  });

  test('newly answered question present only in the attempt survives', () async {
    await seed(
      answers: [_answer(1, ['a'], _older), _answer(2, ['c'], _newer)],
      snapshot: [_answer(1, ['a'], _older)],
    );
    expect(attempts.get(_attemptId)!.answers, hasLength(2));

    final restored = await restore();

    expect(_selections(restored.active!), {1: ['a'], 2: ['c']});
  });

  test('newer snapshot answer recovers over an older attempt answer', () async {
    await seed(
      answers: [_answer(1, ['a'], _older)],
      snapshot: [_answer(1, ['b'], _newer)],
    );
    expect(_selections(attempts.get(_attemptId)!), {1: ['a']});

    final restored = await restore();

    expect(_selections(restored.active!), {1: ['b']});
    expect(restored.active!.answers.single.updatedAt, _newer);
  });

  for (final includeAttempt in [true, false]) {
    test('snapshot-only answer recovers with '
        '${includeAttempt ? 'an empty' : 'a missing'} attempt', () async {
      await seed(
        answers: [],
        snapshot: [_answer(2, ['a', 'c'], _newer)],
        includeAttempt: includeAttempt,
      );
      expect(attempts.get(_attemptId)?.answers ?? [], isEmpty);

      final restored = await restore();

      expect(_selections(restored.active!), {2: ['a', 'c']});
      expect(restored.active!.answers.single.updatedAt, _newer);
    });
  }

  test('newer intentional empty multi-selection survives an older snapshot',
      () async {
    await seed(
      answers: [_answer(1, [], _newer)],
      snapshot: [_answer(1, ['a', 'c'], _older)],
    );
    expect(attempts.get(_attemptId)!.answers.single.selectedOptionIds, isEmpty);

    final restored = await restore();

    expect(restored.active!.answers, hasLength(1));
    expect(_selections(restored.active!), {1: <String>[]});
    expect(restored.active!.answers.single.updatedAt, _newer);
  });

  for (final emptySnapshot in [false, true]) {
    test('${emptySnapshot ? 'empty' : 'absent'} snapshot preserves attempt answers',
        () async {
      await seed(
        answers: [_answer(1, ['b'], _newer)],
        snapshot: emptySnapshot ? [] : null,
      );
      expect(examBox.containsKey('saved_answers'), emptySnapshot);

      final restored = await restore();

      expect(_selections(restored.active!), {1: ['b']});
      expect(restored.active!.answers.single.updatedAt, _newer);
    });
  }

  test('answer selection and normal save-progress round trip preserve answers',
      () async {
    await seed(answers: []);
    final original = await restore();
    original.selectAnswer(1, 'b');
    original.selectMultipleAnswers(2, ['a', 'c']);
    // Establish completed writes; this test does not simulate a killed write.
    await original.active!.save();
    final expectedSnapshot = _snapshot(original.active!.answers);
    await original.saveProgress(1);
    await reopen();

    expect(_selections(attempts.get(_attemptId)!), {1: ['b'], 2: ['a', 'c']});
    expect(examBox.get('saved_answers'), expectedSnapshot);
    final restored = await restore();

    expect(_selections(restored.active!), {1: ['b'], 2: ['a', 'c']});
    expect(_snapshot(restored.active!.answers), expectedSnapshot);
    expect(restored.getCurrentQuestionIndex(), 1);
    expect(restored.remainingSeconds, 1200);
  });

  for (final timestamp in [_older.toIso8601String(), 'invalid', null]) {
    test('equal or invalid snapshot timestamp retains attempt: $timestamp',
        () async {
      await seed(
        answers: [_answer(1, ['a'], _older)],
        snapshot: [_answer(1, ['b'], _newer)],
      );
      final snapshot = _snapshot([_answer(1, ['b'], _newer)]);
      snapshot.single['updated_at'] = timestamp;
      await examBox.put('saved_answers', snapshot);
      await reopen();

      final restored = await restore();

      expect(_selections(restored.active!), {1: ['a']});
      expect(examBox.get('saved_answers'), snapshot);
    });
  }

  for (final entry in <String, Object?>{
    'session_id': 'another-session',
    'exam_id': 99,
    'user_id': null,
  }.entries) {
    test('uncertain snapshot identity preserves both sources: ${entry.key}',
        () async {
      await seed(
        answers: [_answer(1, ['a'], _older)],
        snapshot: [_answer(1, ['b'], _newer)],
      );
      final snapshot = examBox.get('saved_answers');
      if (entry.value == null) {
        await examBox.delete(entry.key);
      } else {
        await examBox.put(entry.key, entry.value);
      }
      await reopen();

      controller = ExamController(attempts, _UnusedExamSyncService(), examBox);
      await controller!.restoreExamIfExists();
      expect(controller!.active, isNull);
      expect(_selections(attempts.get(_attemptId)!), {1: ['a']});
      expect(examBox.get('saved_answers'), snapshot);
      await reopen();
      expect(_selections(attempts.get(_attemptId)!), {1: ['a']});
    });
  }

  test('reconciliation preserves questions unique to either source', () async {
    await seed(
      answers: [_answer(1, ['a'], _older)],
      snapshot: [_answer(2, ['b'], _newer)],
    );

    final restored = await restore();

    expect(_selections(restored.active!), {1: ['a'], 2: ['b']});
    await reopen();
    expect(_selections(attempts.get(_attemptId)!), {1: ['a'], 2: ['b']});
  });

  test('newer empty snapshot selection overrides older nonempty attempt',
      () async {
    await seed(
      answers: [_answer(1, ['a', 'c'], _older)],
      snapshot: [_answer(1, [], _newer)],
    );

    final restored = await restore();

    expect(_selections(restored.active!), {1: <String>[]});
    expect(restored.active!.answers.single.selectedOptionId, isNull);
    expect(restored.active!.answers.single.updatedAt, _newer);
  });

  test('malformed snapshot record does not block other recoverable answers',
      () async {
    await seed(answers: [_answer(1, ['a'], _older)]);
    final snapshot = <dynamic>[
      {'question_id': 1, 'selected_options': [99]},
      ..._snapshot([_answer(2, ['b'], _newer)]),
    ];
    await examBox.put('saved_answers', snapshot);
    await reopen();

    final restored = await restore();

    expect(_selections(restored.active!), {1: ['a'], 2: ['b']});
    expect(examBox.get('saved_answers'), snapshot);
  });

  test('session ID alone supports legacy snapshot recovery', () async {
    await seed(
      answers: [],
      snapshot: [_answer(1, ['b'], _newer)],
    );
    await examBox.delete('attempt_id');
    await reopen();

    final restored = await restore();

    expect(_selections(restored.active!), {1: ['b']});
  });

  test('snapshot-only invalid timestamp recovers without becoming a new edit',
      () async {
    await seed(answers: []);
    final snapshot = _snapshot([_answer(1, ['b'], _newer)]);
    snapshot.single['updated_at'] = 'invalid';
    await examBox.put('saved_answers', snapshot);
    await reopen();

    final restored = await restore();

    expect(_selections(restored.active!), {1: ['b']});
    expect(restored.active!.answers.single.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    expect(examBox.get('saved_answers'), snapshot);
  });

  test('reconciliation copies records and option lists and persists before return',
      () async {
    await seed(
      answers: [_answer(1, ['a'], _older), _answer(2, ['c'], _newer)],
      snapshot: [_answer(1, ['b'], _newer)],
    );
    final originalAnswers = attempts.get(_attemptId)!.answers;
    final originalSnapshot = examBox.get('saved_answers');
    final restored = await restore();

    expect(_selections(restored.active!), {1: ['b'], 2: ['c']});
    expect(originalAnswers.first.selectedOptionIds, ['a']);
    expect(identical(restored.active!.answers.last, originalAnswers.last), isFalse);
    restored.active!.answers.last.selectedOptionIds!.add('d');
    restored.active!.answers.first.selectedOptionIds!.add('e');
    expect(originalAnswers.last.selectedOptionIds, ['c']);
    expect(examBox.get('saved_answers'), originalSnapshot);
    // No explicit save here: restoration itself must have persisted the merge.
    await reopen();
    expect(_selections(attempts.get(_attemptId)!), {1: ['b'], 2: ['c']});
    expect(examBox.get('saved_answers'), originalSnapshot);
  });

  test('repeated restoration and storage reopen never roll answers backward',
      () async {
    await seed(
      answers: [_answer(1, ['b'], _newer)],
      snapshot: [_answer(1, ['a'], _older)],
    );
    final observed = <Map<int, List<String>>>[];
    for (var cycle = 0; cycle < 3; cycle++) {
      final restored = await restore();
      observed.add(_selections(restored.active!));
      // Start/Resume and ExamPage both restore in the production flow.
      await restored.restoreExamIfExists();
      observed.add(_selections(restored.active!));
      await restored.saveProgress(0);
      await reopen();
    }

    expect(observed, everyElement(equals({1: ['b']})));
  });
}
