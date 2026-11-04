import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wired_test/services/pending_quiz_score_repository.dart';

void main() {
  late String? raw;
  late String? fail;
  late PendingQuizScoreRepository repository;
  late int mutations;
  setUp(() {
    raw = null;
    fail = null;
    mutations = 0;
    repository = PendingQuizScoreRepository(
      read: () async {
        if (fail == 'read') throw StateError('read');
        return raw;
      },
      write: (value) async {
        if (fail == 'write') throw StateError('write');
        mutations++;
        raw = value;
      },
      delete: () async {
        if (fail == 'delete') throw StateError('delete');
        mutations++;
        raw = null;
      },
    );
  });

  Future<void> save(String id, [double score = 95]) =>
      repository.save(moduleId: id, moduleName: 'Lesson $id', score: score);

  test('concurrent saves wait for the whole preceding write', () async {
    final writeStarted = Completer<void>();
    final releaseWrite = Completer<void>();
    var reads = 0;
    var writes = 0;
    repository = PendingQuizScoreRepository(
      read: () async {
        reads++;
        return raw;
      },
      write: (value) async {
        if (++writes == 1) {
          writeStarted.complete();
          await releaseWrite.future;
        }
        raw = value;
      },
    );
    final first = save('A');
    await writeStarted.future;
    final second = save('B');
    final snapshot = repository.readAll();
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    releaseWrite.complete();
    await Future.wait([first, second]);
    expect((await snapshot).keys, ['A', 'B']);
  });

  test('retake replaces score and preserves unknown legacy fields', () async {
    raw = '{"A":{"score":"80","custom":{"keep":true}}}';
    await save('A', 90);
    await save('A', 70);
    final result = await repository.readAll();
    expect(result['A']['score'], 70);
    expect(result['A']['custom'], {'keep': true});
    expect(result['A']['date_saved'], isA<String>());
  });

  test('overlapping save and removal preserve unrelated entries', () async {
    await save('A');
    await Future.wait([save('B'), repository.remove('A'), save('C')]);
    expect((await repository.readAll()).keys, ['B', 'C']);
    await Future.wait([repository.remove('B'), save('A')]);
    expect((await repository.readAll()).keys, ['C', 'A']);
  });

  test('legacy entry read is non-mutating and missing removal is a no-op',
      () async {
    raw = '{"1234":{"score":88,"module_name":"Old","extra":[1,2]}}';
    final original = raw;
    expect((await repository.readAll())['1234']['extra'], [1, 2]);
    await repository.remove('absent');
    expect(raw, original);
    expect(mutations, 0);
  });

  for (final invalid in [
    '',
    '{',
    '[]',
    'null',
    '{"A":42}',
    '{"A":{"score":"invalid"}}',
    '{"A":{"score":80,"date_saved":42}}'
  ]) {
    test('rejects malformed storage without mutation: $invalid', () async {
      raw = invalid;
      await expectLater(repository.readAll(), throwsFormatException);
      await expectLater(save('B'), throwsFormatException);
      await expectLater(repository.remove('A'), throwsFormatException);
      expect(raw, invalid);
      expect(mutations, 0);
    });
  }

  for (final operation in ['read', 'write', 'delete']) {
    test('$operation failure is reported and the queue recovers', () async {
      await save('A');
      final original = raw;
      fail = operation;
      final failure =
          operation == 'delete' ? repository.remove('A') : save('B');
      final expectation = expectLater(failure, throwsStateError);
      await expectation;
      expect(raw, original);
      fail = null;
      await save('C');
      expect((await repository.readAll()).keys, ['A', 'C']);
      await repository.remove('A');
      await repository.remove('C');
      expect(raw, isNull);
    });
  }

  test('failed operation does not poison work already queued behind it',
      () async {
    final firstRead = Completer<String?>();
    var reads = 0;
    repository = PendingQuizScoreRepository(
      read: () => ++reads == 1 ? firstRead.future : Future.value(raw),
      write: (value) async {
        raw = value;
      },
    );
    final failed = expectLater(save('A'), throwsStateError);
    final next = save('B');
    firstRead.completeError(StateError('storage unavailable'));
    await failed;
    await next;
    expect((jsonDecode(raw!) as Map).keys, ['B']);
  });
}
