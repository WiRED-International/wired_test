import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wired_test/models/exam_models.dart';
import 'package:wired_test/pages/exam/review_answers_page.dart';
import 'package:wired_test/services/exam_sync_service.dart';
import 'package:wired_test/services/retry_queue_service.dart';
import 'package:wired_test/state/exam_controller.dart';
import 'package:wired_test/providers/auth_provider.dart';

const _attemptId = '42';
final _startedAt = DateTime.utc(2026, 1, 1, 9);

class _ExamHttpAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final started = Completer<void>();
  Future<ResponseBody> Function(RequestOptions)? respond;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (!started.isCompleted) started.complete();
    final handler = respond;
    if (handler == null) throw StateError('No mocked exam response configured');
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _CleanupFailingBox extends Fake implements Box<dynamic> {
  _CleanupFailingBox(this.delegate);
  final Box<dynamic> delegate;
  bool failCleanup = false;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      delegate.get(key, defaultValue: defaultValue);

  @override
  Future<void> put(dynamic key, dynamic value) => delegate.put(key, value);

  @override
  Future<void> putAll(Map<dynamic, dynamic> values) => delegate.putAll(values);

  @override
  Future<void> delete(dynamic key) async {
    if (failCleanup) throw StateError('Injected exam cleanup failure');
    await delegate.delete(key);
  }
}

class _AcknowledgmentAttempt extends ExamAttempt {
  _AcknowledgmentAttempt(ExamAttempt source)
      : super(
          attemptId: source.attemptId,
          examId: source.examId,
          userId: source.userId,
          startedAt: source.startedAt,
          durationSeconds: source.durationSeconds,
          answers: source.answers,
          submitted: source.submitted,
          submittedAt: source.submittedAt,
        );

  bool failSave = false;
  Completer<void>? gate;
  final saveStarted = Completer<void>();

  @override
  Future<void> save() async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    if (gate != null) await gate!.future;
    if (failSave) throw StateError('Injected acknowledgment write failure');
    await super.save();
  }
}

class _DeletionFailingSubmission extends PendingSubmission {
  _DeletionFailingSubmission(String payload)
      : super(
            attemptId: '42',
            payloadJson: payload,
            retryCount: 0,
            enqueuedAt: _startedAt);
  @override
  Future<void> delete() async {
    throw StateError('Synthetic queue cleanup failure');
  }
}

ResponseBody _response(int status) => ResponseBody.fromString(
        status == 200
            ? '{"message":"Exam submitted successfully","resolved_session_id":42}'
            : '{}',
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late Box<ExamAttempt> attempts;
  late Box<PendingSubmission> retryBox;
  late Box examBox;
  late _CleanupFailingBox cleanupBox;
  late _ExamHttpAdapter adapter;
  late ExamSyncService sync;
  late AuthProvider auth;
  late StreamController<List<ConnectivityResult>> connectivity;
  bool online = true;
  ExamController? controller;

  setUpAll(() {
    Hive.registerAdapter(ExamAttemptAdapter());
    Hive.registerAdapter(AnswerRecordAdapter());
    Hive.registerAdapter(PendingSubmissionAdapter());
  });

  Future<void> openBoxes() async {
    attempts = await Hive.openBox<ExamAttempt>('exam_attempts');
    retryBox = await Hive.openBox<PendingSubmission>('retry_queue');
    examBox = await Hive.openBox('examBox');
  }

  Future<void> reopen() async {
    sync.dispose();
    sync.dio.close(force: true);
    controller?.dispose();
    controller = null;
    await Hive.close();
    Hive.init(directory.path);
    await openBoxes();
  }

  setUp(() async {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://exam.invalid');
    messenger.setMockMethodCallHandler(storageChannel, (call) async {
      if (call.method == 'read') return 'test-token';
      if (call.method == 'write' || call.method == 'delete') return null;
      throw StateError('Unexpected secure storage method: ${call.method}');
    });
    directory = await Directory.systemTemp.createTemp('exam_acknowledgment_');
    Hive.init(directory.path);
    await openBoxes();
    await attempts.put(
      _attemptId,
      ExamAttempt(
        attemptId: _attemptId,
        examId: 10,
        userId: 7,
        startedAt: _startedAt,
        durationSeconds: 1800,
        answers: [
          AnswerRecord(
            questionId: 1,
            selectedOptionId: 'a',
            selectedOptionIds: ['a'],
            updatedAt: _startedAt,
          ),
        ],
      ),
    );
    await examBox.putAll({
      'exam_start_time': _startedAt.toIso8601String(),
      'exam_duration': 30,
      'exam_id': 10,
      'user_id': 7,
      'attempt_id': _attemptId,
      'session_id': _attemptId,
      'current_index': 0,
      'remaining_seconds': 1200,
      'is_paused': true,
    });
    online = true;
    auth = AuthProvider();
    connectivity = StreamController<List<ConnectivityResult>>.broadcast();
    sync = ExamSyncService(attempts, retryBox,
        onlineCheck: () async => online,
        connectivityChanges: connectivity.stream);
    adapter = _ExamHttpAdapter();
    sync.dio.httpClientAdapter = adapter;
    cleanupBox = _CleanupFailingBox(examBox);
    controller = ExamController(attempts, sync, cleanupBox);
    await controller!.restoreExamIfExists();
    expect(controller!.active, isNotNull);
  });

  tearDown(() async {
    controller?.dispose();
    controller = null;
    sync.dio.close(force: true);
    sync.dispose();
    auth.dispose();
    await connectivity.close();
    messenger.setMockMethodCallHandler(storageChannel, null);
    dotenv.clean();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<bool> submit() async {
    final payload = await controller!.buildSubmissionPayload();
    expect(payload, isNotNull);
    final accepted = await sync.submitExam(payload!);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.method, 'PUT');
    expect(adapter.requests.single.path, '/exam-sessions/42/submit');
    expect(adapter.requests.single.data['answers'], [
      {
        'question_id': 1,
        'selected_option_ids': ['a'],
        'updated_at': _startedAt.toIso8601String(),
      }
    ]);
    return accepted;
  }

  Future<Map<String, dynamic>> queueCompleted(
      {String key = '42-legacy', bool legacy = false}) async {
    final payload = (await controller!.buildSubmissionPayload())!;
    if (legacy) {
      payload.remove('user_id');
      payload.remove('attempt_id');
      payload['session_id'] = 42;
    }
    await retryBox.put(
        key,
        PendingSubmission(
            attemptId: '42',
            payloadJson: jsonEncode(payload),
            retryCount: 0,
            enqueuedAt: _startedAt));
    return payload;
  }

  Future<void> authenticate([int userId = 7]) async {
    if (auth.isLoading) await auth.loadStoredAuthData();
    final claims = base64Url
        .encode(utf8.encode(jsonEncode({'id': userId})))
        .replaceAll('=', '');
    await auth.logIn('e30.$claims.synthetic',
        DateTime.now().toUtc().add(const Duration(hours: 1)));
    sync.updateAuthentication(auth);
    await sync.trySyncNow();
  }

  void restoreSyncService() {
    sync = ExamSyncService(attempts, retryBox,
        onlineCheck: () async => online,
        connectivityChanges: connectivity.stream);
    sync.dio.httpClientAdapter = adapter;
  }

  test('authenticated startup submits only completed owned queue entries',
      () async {
    final payload = await queueCompleted();
    await attempts.put(
        'unfinished',
        ExamAttempt(
            attemptId: 'unfinished',
            examId: 11,
            userId: 7,
            startedAt: _startedAt,
            durationSeconds: 1800,
            answers: []));
    await attempts.put(
        'other-student',
        ExamAttempt(
            attemptId: 'other-student',
            examId: 12,
            userId: 8,
            startedAt: _startedAt,
            durationSeconds: 1800,
            answers: []));
    await retryBox.put(
        'other-student',
        PendingSubmission(
            attemptId: 'other-student',
            payloadJson: jsonEncode({
              'attempt_id': 'other-student',
              'exam_id': 12,
              'user_id': 8,
              'answers': payload['answers']
            }),
            retryCount: 0,
            enqueuedAt: _startedAt));
    adapter.respond = (_) async => _response(200);
    await authenticate();
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.method, 'PUT');
    expect(adapter.requests.single.path, '/exam-sessions/42/submit');
    expect(adapter.requests.single.data['answers'], payload['answers']);
    expect(adapter.requests.single.data.containsKey('exam_id'), isFalse);
    expect(attempts.get('42')!.submitted, isTrue);
    expect(attempts.get('unfinished')!.submitted, isFalse);
    expect(attempts.get('other-student')!.submitted, isFalse);
    expect(retryBox.keys.toList(), ['other-student']);
    expect(examBox.get('remaining_seconds'), 1200);
    controller!.selectAnswer(1, 'changed-after-sync');
    expect(attempts.get('42')!.answers.single.normalizedOptions, ['a']);
    expect(await controller!.buildSubmissionPayload(), isNull);
  });

  test('connectivity restoration triggers queue sync after offline startup',
      () async {
    await queueCompleted();
    online = false;
    adapter.respond = (_) async => _response(200);
    await authenticate();
    expect(adapter.requests, isEmpty);
    connectivity.add([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requests, isEmpty);
    online = true;
    connectivity.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    await sync.trySyncNow();
    expect(adapter.requests, hasLength(1));
    expect(retryBox.isEmpty, isTrue);
  });

  for (final failure in [
    DioExceptionType.connectionError,
    DioExceptionType.receiveTimeout
  ]) {
    test('$failure retains queue durably and retries after app restart',
        () async {
      await queueCompleted(legacy: true);
      adapter.respond = (options) async =>
          throw DioException(requestOptions: options, type: failure);
      await authenticate();
      expect(adapter.requests, hasLength(1));
      expect(retryBox.length, 1);
      expect(retryBox.values.single.retryCount, 1);
      expect(attempts.get('42')!.submitted, isFalse);
      await reopen();
      restoreSyncService();
      expect(retryBox.length, 1);
      adapter.respond = (_) async => _response(200);
      await authenticate();
      expect(adapter.requests, hasLength(2));
      expect(retryBox.isEmpty, isTrue);
      expect(attempts.get('42')!.submitted, isTrue);
    });
  }

  test('queue remains until confirmed acceptance is durably acknowledged',
      () async {
    await queueCompleted();
    final attempt = _AcknowledgmentAttempt(attempts.get('42')!);
    final gate = Completer<void>();
    attempt.gate = gate;
    await attempts.put('42', attempt);
    adapter.respond = (_) async => _response(200);
    final syncing = authenticate();
    await attempt.saveStarted.future;
    expect(retryBox.length, 1);
    gate.complete();
    await syncing;
    expect(retryBox.isEmpty, isTrue);
    await reopen();
    expect(attempts.get('42')!.submitted, isTrue);
    expect(attempts.get('42')!.submittedAt, isNotNull);
  });

  test(
      'automatic acknowledgment failure retains queue and retries locally without another PUT',
      () async {
    await queueCompleted();
    final attempt = _AcknowledgmentAttempt(attempts.get('42')!)
      ..failSave = true;
    await attempts.put('42', attempt);
    adapter.respond = (_) async => _response(200);
    await authenticate();
    expect(adapter.requests, hasLength(1));
    expect(retryBox.length, 1);
    expect(attempt.submitted, isFalse);
    attempt.failSave = false;
    await sync.trySyncNow();
    expect(adapter.requests, hasLength(1));
    expect(retryBox.isEmpty, isTrue);
    expect(attempt.submitted, isTrue);
  });

  test(
      'concurrent manual and automatic retries share one request and clear legacy duplicates',
      () async {
    final payload = await queueCompleted(key: '42-1000');
    await queueCompleted(key: '42-2000', legacy: true);
    final response = Completer<ResponseBody>();
    adapter.respond = (_) => response.future;
    final automatic = authenticate();
    await adapter.started.future;
    final manual = sync.submitExam(payload);
    final repeated = sync.trySyncNow();
    expect(adapter.requests, hasLength(1));
    response.complete(_response(200));
    await automatic;
    expect(await manual, isTrue);
    await repeated;
    expect(adapter.requests, hasLength(1));
    expect(retryBox.isEmpty, isTrue);
  });

  test(
      'lost acceptance response is safely reconciled by exact already-submitted response',
      () async {
    await queueCompleted();
    adapter.respond = (options) async => throw DioException(
        requestOptions: options, type: DioExceptionType.receiveTimeout);
    await authenticate();
    expect(retryBox.length, 1);
    adapter.respond = (_) async => ResponseBody.fromString(
            '{"message":"Exam already submitted"}', 400,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType]
            });
    await sync.trySyncNow();
    expect(retryBox.isEmpty, isTrue);
    expect(attempts.get('42')!.submitted, isTrue);
    expect(adapter.requests, hasLength(2));
  });

  test(
      'generic conflicts, wrong session responses, and server errors remain queued',
      () async {
    await queueCompleted();
    adapter.respond = (_) async => ResponseBody.fromString(
            '{"message":"Exam already submitted"}', 409,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType]
            });
    await authenticate();
    expect(retryBox.length, 1);
    adapter.respond = (_) async =>
        ResponseBody.fromString('{"resolved_session_id":99}', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
    await sync.trySyncNow();
    expect(retryBox.length, 1);
    adapter.respond = (_) async => _response(500);
    await sync.trySyncNow();
    expect(retryBox.length, 1);
    expect(attempts.get('42')!.submitted, isFalse);
  });

  test('unauthenticated and wrong-student retries do not dispatch queued data',
      () async {
    await queueCompleted();
    adapter.respond = (_) async => _response(200);
    sync.updateAuthentication(auth);
    await sync.autoSyncOnLaunch();
    expect(adapter.requests, isEmpty);
    await authenticate(8);
    expect(adapter.requests, isEmpty);
    expect(retryBox.length, 1);
    await authenticate(7);
    expect(adapter.requests, hasLength(1));
  });

  test(
      'legacy entries require provable ownership and malformed entries do not block valid work',
      () async {
    await retryBox.put(
        'malformed',
        PendingSubmission(
            attemptId: 'missing',
            payloadJson: 'invalid json',
            retryCount: 0,
            enqueuedAt: _startedAt));
    await retryBox.put(
        'orphan',
        PendingSubmission(
            attemptId: 'missing',
            payloadJson:
                '{"attempt_id":"missing","exam_id":10,"user_id":7,"answers":[{}]}',
            retryCount: 0,
            enqueuedAt: _startedAt));
    await queueCompleted(legacy: true);
    adapter.respond = (_) async => _response(200);
    await authenticate();
    expect(adapter.requests, hasLength(1));
    expect(retryBox.keys.toSet(), {'malformed', 'orphan'});
  });

  test('disposal stops future connectivity-triggered synchronization',
      () async {
    await queueCompleted();
    online = false;
    await authenticate();
    sync.dispose();
    online = true;
    connectivity.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requests, isEmpty);
    expect(retryBox.length, 1);
  });

  test(
      'queue deletion failure retains acknowledgment and retries cleanup without PUT',
      () async {
    final payload = (await controller!.buildSubmissionPayload())!;
    await retryBox.put('42', _DeletionFailingSubmission(jsonEncode(payload)));
    adapter.respond = (_) async => _response(200);
    await authenticate();
    expect(adapter.requests, hasLength(1));
    expect(attempts.get('42')!.submitted, isTrue);
    expect(retryBox.length, 1);
    await reopen();
    restoreSyncService();
    await authenticate();
    expect(adapter.requests, hasLength(1));
    expect(retryBox.isEmpty, isTrue);
  });

  test(
      'authentication changes cannot replace the token on an in-flight submission',
      () async {
    await queueCompleted();
    final response = Completer<ResponseBody>();
    adapter.respond = (_) => response.future;
    final syncing = authenticate();
    await adapter.started.future;
    final dispatchedToken = adapter.requests.single.headers['Authorization'];
    final claims =
        base64Url.encode(utf8.encode('{"id":8}')).replaceAll('=', '');
    await auth.logIn('e30.$claims.synthetic',
        DateTime.now().toUtc().add(const Duration(hours: 1)));
    sync.updateAuthentication(auth);
    expect(dispatchedToken, isNot('Bearer ${auth.authToken}'));
    response.complete(_response(200));
    await syncing;
    expect(adapter.requests, hasLength(1));
    expect(attempts.get('42')!.submitted, isTrue);
  });

  test('uninformative or malformed HTTP 200 retains queued work', () async {
    await queueCompleted();
    adapter.respond = (_) async => ResponseBody.fromString('{}', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
    await authenticate();
    expect(retryBox.length, 1);
    adapter.respond = (_) async =>
        ResponseBody.fromString('<html>proxy response</html>', 200);
    await sync.trySyncNow();
    expect(retryBox.length, 1);
    expect(attempts.get('42')!.submitted, isFalse);
  });

  test(
      'connectivity restoration during an offline probe schedules a fresh retry',
      () async {
    await queueCompleted();
    sync.dispose();
    final gate = Completer<bool>();
    final entered = Completer<void>();
    var probes = 0;
    sync = ExamSyncService(attempts, retryBox, onlineCheck: () {
      if (++probes == 1) {
        entered.complete();
        return gate.future;
      }
      return Future.value(true);
    }, connectivityChanges: connectivity.stream);
    sync.dio.httpClientAdapter = adapter;
    adapter.respond = (_) async => _response(200);
    final syncing = authenticate();
    await entered.future;
    connectivity.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    gate.complete(false);
    await syncing;
    expect(adapter.requests, hasLength(1));
    expect(retryBox.isEmpty, isTrue);
  });

  test('account changes before HTTP dispatch cancel the old request', () async {
    await queueCompleted();
    final gate = Completer<void>();
    final entered = Completer<void>();
    sync.dio.interceptors.insert(0,
        InterceptorsWrapper(onRequest: (request, handler) async {
      entered.complete();
      await gate.future;
      handler.next(request);
    }));
    final syncing = authenticate();
    await entered.future;
    final claims =
        base64Url.encode(utf8.encode('{"id":8}')).replaceAll('=', '');
    await auth.logIn('e30.$claims.synthetic',
        DateTime.now().toUtc().add(const Duration(hours: 1)));
    sync.updateAuthentication(auth);
    gate.complete();
    await syncing;
    expect(adapter.requests, isEmpty);
    expect(retryBox.length, 1);
    expect(attempts.get('42')!.submitted, isFalse);
  });

  testWidgets(
      'owned queue retries reachability without a connectivity event and stops on disposal',
      (tester) async {
    await tester.runAsync(() => queueCompleted());
    sync.dispose();
    var probes = 0;
    sync = ExamSyncService(attempts, retryBox, onlineCheck: () async {
      probes++;
      return false;
    }, connectivityChanges: connectivity.stream);
    sync.dio.httpClientAdapter = adapter;
    await tester.runAsync(() async {
      await auth.loadStoredAuthData();
      final claims =
          base64Url.encode(utf8.encode('{"id":7}')).replaceAll('=', '');
      await auth.logIn('e30.$claims.synthetic',
          DateTime.now().toUtc().add(const Duration(hours: 1)));
    });
    sync.updateAuthentication(auth);
    await tester.pump();
    expect(probes, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(probes, 2);
    expect(retryBox.length, 1);
    sync.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(probes, 2);
    expect(adapter.requests, isEmpty);
  });

  // The page awaits this exact service call before opening its success dialog.
  // These desired acceptance-boundary tests do not press the Submit button:
  // its static NetworkUtils.isOnline() performs non-injectable real DNS lookup.
  test(
      'HTTP 200 records submitted and submittedAt on the corresponding attempt',
      () async {
    adapter.respond = (_) async => _response(200);

    expect(await submit(), isTrue);

    final attempt = attempts.get(_attemptId)!;
    expect(attempt.submitted, isTrue);
    expect(attempt.submittedAt, isNotNull);
    expect(attempt.answers.single.normalizedOptions, ['a']);
  });

  test('success is not exposed to the dialog caller before acknowledgment',
      () async {
    final response = Completer<ResponseBody>();
    adapter.respond = (_) => response.future;
    final pending = submit();
    await adapter.started.future;
    expect(attempts.get(_attemptId)!.submitted, isFalse);
    expect(attempts.get(_attemptId)!.submittedAt, isNull);
    response.complete(_response(200));
    final accepted = await pending;
    // This is the continuation where the widget would display success; neither
    // dialog dismissal nor cleanup has been invoked by this test.
    expect(accepted, isTrue);
    expect(attempts.get(_attemptId)!.submitted, isTrue);
    expect(attempts.get(_attemptId)!.submittedAt, isNotNull);
  });

  test('acknowledgment survives Hive close/reopen before any cleanup',
      () async {
    adapter.respond = (_) async => _response(200);
    expect(await submit(), isTrue);
    await reopen();

    final attempt = attempts.get(_attemptId)!;
    expect(attempt.submitted, isTrue);
    expect(attempt.submittedAt, isNotNull);
    expect(attempt.answers.single.normalizedOptions, ['a']);
  });

  for (final status in [400, 409, 500]) {
    test('HTTP $status does not acknowledge or discard the attempt', () async {
      adapter.respond = (_) async => _response(status);
      expect(await submit(), isFalse);
      await reopen();

      final attempt = attempts.get(_attemptId)!;
      expect(attempt.submitted, isFalse);
      expect(attempt.submittedAt, isNull);
      expect(attempt.answers.single.normalizedOptions, ['a']);
    });
  }

  test('transport failure does not acknowledge or discard the attempt',
      () async {
    adapter.respond = (options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const SocketException('Injected connection failure'),
        );
    expect(await submit(), isFalse);
    await reopen();

    final attempt = attempts.get(_attemptId)!;
    expect(attempt.submitted, isFalse);
    expect(attempt.submittedAt, isNull);
    expect(attempt.answers.single.normalizedOptions, ['a']);
  });

  test('cleanup failure retains durable acknowledgment and recoverable answers',
      () async {
    adapter.respond = (_) async => _response(200);
    expect(await submit(), isTrue);
    cleanupBox.failCleanup = true;
    await expectLater(controller!.clearExamPersistence(), throwsStateError);
    await reopen();

    final attempt = attempts.get(_attemptId)!;
    expect(attempt.answers.single.normalizedOptions, ['a']);
    expect(examBox.get('attempt_id'), _attemptId);
    expect(attempt.submitted, isTrue);
    expect(attempt.submittedAt, isNotNull);
  });

  testWidgets('review updates only after durable automatic acknowledgment',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late _AcknowledgmentAttempt attempt;
    final gate = Completer<void>();
    await tester.runAsync(() async {
      final payload = (await controller!.buildSubmissionPayload())!;
      controller!.dispose();
      controller = ExamController(attempts, sync, cleanupBox,
          retryQueue: RetryQueueService(retryBox));
      await controller!.restoreExamIfExists();
      await controller!.queueOfflineSubmission(payload);
      attempt = _AcknowledgmentAttempt(attempts.get(_attemptId)!);
      attempt.gate = gate;
      await attempts.put(_attemptId, attempt);
    });
    await tester.pumpWidget(ChangeNotifierProvider<ExamController>.value(
      value: controller!,
      child: const MaterialApp(
          home: ReviewAnswersPage(questions: [
        {
          'id': 1,
          'question_text': 'Test question',
          'options': {'a': 'Test answer'}
        }
      ])),
    ));
    expect(find.text('Awaiting synchronization'), findsOneWidget);
    adapter.respond = (_) async => _response(200);
    late Future<void> syncing;
    await tester.runAsync(() async {
      syncing = authenticate();
      await attempt.saveStarted.future;
    });
    await tester.pump();
    expect(find.text('Awaiting synchronization'), findsOneWidget);
    expect(find.text('Exam Submitted'), findsNothing);
    await tester.runAsync(() async {
      gate.complete();
      await syncing;
    });
    await tester.pumpAndSettle();
    expect(find.text('Awaiting synchronization'), findsNothing);
    expect(find.text('Exam Submitted'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.ancestor(
        of: find.text('Exam Submitted'),
        matching:
            find.byWidgetPredicate((widget) => widget is ElevatedButton)));
    expect(button.onPressed, isNull);
    expect(retryBox.isEmpty, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('service acknowledgment survives disposal of the review route',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider<ExamController>.value(
      value: controller!,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.7)),
          child: child!,
        ),
        home: const ReviewAnswersPage(questions: [
          {
            'id': 1,
            'question_text': 'Test question',
            'options': {'a': 'Test answer'},
          }
        ]),
      ),
    ));
    expect(find.byType(ReviewAnswersPage), findsOneWidget);
    final response = Completer<ResponseBody>();
    adapter.respond = (_) => response.future;
    late Future<bool> pending;
    await tester.runAsync(() async {
      pending = submit();
      await adapter.started.future;
    });
    // Dispose the real page before the accepted response continuation executes.
    // Submission is invoked at the service boundary to avoid live DNS preflight.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(find.byType(ReviewAnswersPage), findsNothing);
    await tester.runAsync(() async {
      response.complete(_response(200));
      expect(await pending, isTrue);
      await reopen();
    });
    expect(attempts.get(_attemptId)!.submitted, isTrue);
    expect(attempts.get(_attemptId)!.submittedAt, isNotNull);
  });

  test(
      'accepted attempt is excluded from the unsent predicate after interruption',
      () async {
    adapter.respond = (_) async => _response(200);
    expect(await submit(), isTrue);
    // Simulate termination before cleanup without running synchronization.
    await reopen();

    final unsent = attempts.values.where((attempt) => !attempt.submitted);
    expect(unsent.map((attempt) => attempt.attemptId),
        isNot(contains(_attemptId)));
    expect(attempts.get(_attemptId)!.answers.single.normalizedOptions, ['a']);
  });

  test('HTTP 200 does not return success until acknowledgment save completes',
      () async {
    final payload = (await controller!.buildSubmissionPayload())!;
    final attempt = _AcknowledgmentAttempt(attempts.get(_attemptId)!);
    final gate = Completer<void>();
    attempt.gate = gate;
    await attempts.put(_attemptId, attempt);
    adapter.respond = (_) async => _response(200);
    var completed = false;
    final pending = sync.submitExam(payload).then((accepted) {
      completed = true;
      return accepted;
    });
    await attempt.saveStarted.future;
    final completedBeforeSave = completed;
    gate.complete();
    expect(await pending, isTrue);
    expect(completedBeforeSave, isFalse);
    await reopen();
    expect(attempts.get(_attemptId)!.submitted, isTrue);
    expect(attempts.get(_attemptId)!.submittedAt, isNotNull);
  });

  test('accepted request with failed local save throws a distinct outcome',
      () async {
    final payload = (await controller!.buildSubmissionPayload())!;
    final attempt = _AcknowledgmentAttempt(attempts.get(_attemptId)!);
    await attempts.put(_attemptId, attempt);
    attempt.failSave = true;
    adapter.respond = (_) async => _response(200);

    await expectLater(
        sync.submitExam(payload),
        throwsA(
          isA<ExamAcknowledgmentPersistenceException>()
              .having(
                  (error) => error.sessionId, 'accepted session', _attemptId)
              .having((error) => error.cause, 'local error', isA<StateError>()),
        ));

    expect(adapter.requests, hasLength(1));
    expect(attempt.submitted, isFalse);
    expect(attempt.submittedAt, isNull);
    await reopen();
    expect(attempts.get(_attemptId)!.submitted, isFalse);
    expect(attempts.get(_attemptId)!.answers.single.normalizedOptions, ['a']);
  });

  test('retry after acknowledgment failure only retries local persistence',
      () async {
    final payload = (await controller!.buildSubmissionPayload())!;
    final attempt = _AcknowledgmentAttempt(attempts.get(_attemptId)!);
    await attempts.put(_attemptId, attempt);
    attempt.failSave = true;
    adapter.respond = (_) async => _response(200);
    await expectLater(sync.submitExam(payload),
        throwsA(isA<ExamAcknowledgmentPersistenceException>()));
    attempt.failSave = false;

    expect(await sync.submitExam(payload), isTrue);

    expect(adapter.requests, hasLength(1));
    await reopen();
    expect(attempts.get(_attemptId)!.submitted, isTrue);
    expect(attempts.get(_attemptId)!.submittedAt, isNotNull);
  });

  test('conflicting endpoint and attempt IDs never acknowledge unrelated data',
      () async {
    final payload = (await controller!.buildSubmissionPayload())!;
    await attempts.put(
        '99',
        ExamAttempt(
          attemptId: '99',
          examId: 10,
          userId: 7,
          startedAt: _startedAt,
          durationSeconds: 1800,
          answers: [],
        ));
    payload['session_id'] = '99';
    adapter.respond = (_) async => _response(200);

    expect(await sync.submitExam(payload), isFalse);
    expect(adapter.requests, isEmpty);
    await reopen();
    expect(attempts.get('99')!.submitted, isFalse);
    expect(attempts.get(_attemptId)!.submitted, isFalse);
  });

  test('session-only payload acknowledges its matching local attempt',
      () async {
    final payload = (await controller!.buildSubmissionPayload())!;
    payload.remove('attempt_id');
    payload['session_id'] = 42;
    adapter.respond = (_) async => _response(200);

    expect(await sync.submitExam(payload), isTrue);

    await reopen();
    expect(attempts.get(_attemptId)!.submitted, isTrue);
    expect(attempts.get(_attemptId)!.submittedAt, isNotNull);
  });

  test('timeout does not acknowledge the attempt', () async {
    adapter.respond = (options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );

    expect(await submit(), isFalse);

    await reopen();
    expect(attempts.get(_attemptId)!.submitted, isFalse);
    expect(attempts.get(_attemptId)!.submittedAt, isNull);
  });

  test(
      'manual acknowledgment preserves answers and clears matching stale queue entries',
      () async {
    await retryBox.put(
        'saved-queue-entry',
        PendingSubmission(
          attemptId: _attemptId,
          payloadJson: '{"preserve":true}',
          retryCount: 0,
          enqueuedAt: _startedAt,
        ));
    adapter.respond = (_) async => _response(200);

    expect(await submit(), isTrue);

    await reopen();
    expect(attempts.get(_attemptId)!.answers.single.normalizedOptions, ['a']);
    expect(retryBox.get('saved-queue-entry'), isNull);
    expect(attempts.get(_attemptId)!.submitted, isTrue);
  });
}
