import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wired_test/models/active_exam_session.dart';
import 'package:wired_test/models/exam_models.dart';
import 'package:wired_test/services/exam_sync_service.dart';

// Any storage access fails: retrieval must have no local persistence effects.
class _Box<T> extends Fake implements Box<T> {}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  Object? body;
  DioExceptionType? failure;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (failure != null) {
      throw DioException(requestOptions: options, type: failure!);
    }
    return ResponseBody.fromString(
        body is String ? body as String : jsonEncode(body), status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _payload() => {
      'session_id': 42,
      'exam_id': 10,
      'started_at': '2026-11-17T09:12:13-08:00',
      'exam': {'id': 10, 'duration_minutes': 45, 'answer_key': 'secret'},
      'questions': [
        for (final id in [9, 2])
          {
            'id': id,
            'question_text': 'Question $id',
            'question_type': 'multiple',
            'options': <String, dynamic>{'a': 'Alpha', 'b': 'Beta'},
            'option_order': ['b', 'a'],
            'correct_answer': 'a',
            'explanation': 'secret',
          }
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ExamSyncService service;
  late _Adapter adapter;

  setUp(() {
    dotenv.loadFromString(
        envString: 'API_BASE_URL=https://example.invalid/apiv2');
    messenger.setMockMethodCallHandler(channel, (call) async => 'test-token');
    service = ExamSyncService(_Box<ExamAttempt>(), _Box<PendingSubmission>());
    adapter = _Adapter()..body = _payload();
    service.dio.httpClientAdapter = adapter;
  });
  tearDown(() {
    service.dio.close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('GET uses configured URL and authentication, preserving original order',
      () async {
    final result = await service.getActiveExamSession(10);
    expect(result.outcome, ActiveExamSessionOutcome.recoverable);
    expect(result.statusCode, 200);
    final session = result.session!;
    expect(session.sessionId, '42');
    expect(session.examId, 10);
    expect(session.startedAt, DateTime.utc(2026, 11, 17, 17, 12, 13));
    expect(session.durationMinutes, 45);
    expect(session.durationSeconds, 2700);
    expect(session.questions.map((q) => q['id']), [9, 2]);
    expect((session.questions.first['options'] as Map).keys, ['b', 'a']);
    expect(session.questions.first['option_order'], ['b', 'a']);
    expect(
        session.questions.first.keys,
        unorderedEquals([
          'id',
          'question_text',
          'question_type',
          'options',
          'option_order'
        ]));
    expect(jsonEncode(session.questions), isNot(contains('secret')));
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.toString(),
        'https://example.invalid/apiv2/exams/10/active-session');
    expect(request.headers['Authorization'], 'Bearer test-token');
    expect(request.data, isNull);
  });

  test('top-level duration metadata and string session identity', () async {
    final body = _payload()..remove('exam');
    body.addAll({
      'session_id': 'session-42',
      'duration_minutes': 45,
      'duration_seconds': 2700
    });
    adapter.body = body;
    expect((await service.getActiveExamSession(10)).session!.sessionId,
        'session-42');
  });

  final malformed = <String, void Function(Map<String, dynamic>)>{
    'missing session': (p) => p.remove('session_id'),
    'wrong exam': (p) => p['exam_id'] = 11,
    'conflicting nested exam': (p) => p['exam']['id'] = 11,
    'invalid start': (p) => p['started_at'] = 'yesterday',
    'missing timezone': (p) => p['started_at'] = '2026-11-17T09:12:13',
    'missing duration': (p) => p.remove('exam'),
    'zero duration': (p) => p['exam']['duration_minutes'] = 0,
    'duration conflict': (p) => p['duration_minutes'] = 10,
    'seconds conflict': (p) => p['duration_seconds'] = 1,
    'empty questions': (p) => p['questions'] = [],
    'duplicate question': (p) => p['questions'][1]['id'] = 9,
    'missing option order': (p) => p['questions'][0].remove('option_order'),
    'duplicate option order': (p) =>
        p['questions'][0]['option_order'] = ['a', 'a'],
    'unknown option': (p) => p['questions'][0]['option_order'] = ['a', 'c'],
    'unsafe option object': (p) =>
        p['questions'][0]['options']['a'] = {'correct': true},
  };
  for (final entry in malformed.entries) {
    test('rejects ${entry.key}', () async {
      final body = _payload();
      entry.value(body);
      adapter.body = body;
      final result = await service.getActiveExamSession(10);
      expect(result.outcome, ActiveExamSessionOutcome.malformedResponse);
      expect(result.session, isNull);
      expect(adapter.requests, hasLength(1));
    });
  }
  for (final body in ['not JSON', '[]', 'null']) {
    test('rejects malformed envelope $body', () async {
      adapter.body = body;
      expect((await service.getActiveExamSession(10)).outcome,
          ActiveExamSessionOutcome.malformedResponse);
    });
  }
  final outcomes = {
    400: ActiveExamSessionOutcome.invalidExamId,
    401: ActiveExamSessionOutcome.authenticationFailure,
    500: ActiveExamSessionOutcome.serverFailure,
    503: ActiveExamSessionOutcome.serverFailure,
  };
  for (final entry in outcomes.entries) {
    test('HTTP ${entry.key} is distinct and never starts a session', () async {
      adapter.status = entry.key;
      adapter.body = 'non-JSON error';
      final result = await service.getActiveExamSession(10);
      expect(result.outcome, entry.value);
      expect(result.statusCode, entry.key);
      expect(result.session, isNull);
      expect(adapter.requests.single.method, 'GET');
    });
  }
  test('only documented 404 confirms no active session', () async {
    adapter.status = 404;
    adapter.body = ' { "message": "Active exam session not found" } ';
    final result = await service.getActiveExamSession(10);
    expect(result.outcome, ActiveExamSessionOutcome.noActiveSession);
    expect(result.statusCode, 404);
    expect(result.session, isNull);
    expect(adapter.requests.single.method, 'GET');
  });
  final unknown404s = <String, Object?>{
    'generic JSON': {'message': 'Not Found'},
    'missing route': {'error': 'Cannot GET /exams/10/active-session'},
    'HTML': '<html><body>404 Not Found</body></html>',
    'malformed JSON': '{"message":"Active exam session not found"',
    'empty body': '',
    'null': null,
    'empty object': <String, dynamic>{},
    'array': [
      {'message': 'Active exam session not found'}
    ],
    'wrong message type': {'message': 404},
    'different case': {'message': 'active exam session not found'},
    'unexpected fields': {
      'message': 'Active exam session not found',
      'error': 'route missing'
    },
  };
  for (final entry in unknown404s.entries) {
    test('404 ${entry.key} is a recovery failure', () async {
      adapter.status = 404;
      adapter.body = entry.value;
      final result = await service.getActiveExamSession(10);
      expect(result.outcome, ActiveExamSessionOutcome.malformedResponse);
      expect(result.statusCode, 404);
      expect(result.session, isNull);
      expect(adapter.requests.single.method, 'GET');
    });
  }
  for (final code in [
    'MULTIPLE_ACTIVE_SESSIONS',
    'ORIGINAL_QUESTIONS_UNAVAILABLE',
    'UNKNOWN'
  ]) {
    test('conflict $code', () async {
      adapter.status = 409;
      adapter.body = {'code': code};
      final result = await service.getActiveExamSession(10);
      expect(
          result.outcome,
          code == 'MULTIPLE_ACTIVE_SESSIONS'
              ? ActiveExamSessionOutcome.multipleActiveSessions
              : code == 'ORIGINAL_QUESTIONS_UNAVAILABLE'
                  ? ActiveExamSessionOutcome.originalQuestionsUnavailable
                  : ActiveExamSessionOutcome.malformedResponse);
      expect(result.session, isNull);
      expect(adapter.requests, hasLength(1));
    });
  }
  for (final type in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionError
  ]) {
    test('network failure $type does not retry or start', () async {
      adapter.failure = type;
      expect((await service.getActiveExamSession(10)).outcome,
          ActiveExamSessionOutcome.networkFailure);
      expect(adapter.requests.single.method, 'GET');
    });
  }
  test('invalid local exam ID makes no request', () async {
    expect((await service.getActiveExamSession(0)).outcome,
        ActiveExamSessionOutcome.invalidExamId);
    expect(adapter.requests, isEmpty);
  });
}
