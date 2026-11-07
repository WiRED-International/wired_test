import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wired_test/providers/quiz_score_provider.dart';

class _TrackedClient extends MockClient {
  _TrackedClient(super.handler, {this.onClose});
  final void Function()? onClose;
  int closes = 0;

  @override
  void close() {
    closes++;
    if (closes > 1) throw StateError('Client closed twice');
    super.close();
    onClose?.call();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> storageCalls;
  late Map<String, String> storage;

  setUp(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
    storageCalls = [];
    storage = {
      'authToken': 'token',
      'pending_quiz_scores': '{"1234":{"score":88}}',
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      storageCalls.add(call);
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          return storage[key];
        case 'write':
          storage[key] = args['value'] as String;
          return null;
        case 'delete':
          storage.remove(key);
          return null;
        default:
          throw TestFailure('Unexpected storage operation: ${call.method}');
      }
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final legacy in [
    null,
    '{"1234":95.0}',
    '[{"module_id":42,"score":95}]',
  ]) {
    test('server fetch updates memory and preserves legacy value $legacy',
        () async {
      if (legacy != null) storage['quiz_scores'] = legacy;
      final before = Map<String, String>.from(storage);
      final provider = QuizScoreProvider();
      addTearDown(provider.dispose);
      final loadingStates = <bool>[];
      provider.addListener(() => loadingStates.add(provider.isLoading));
      await http.runWithClient(
          () => provider.fetchQuizScores(),
          () => MockClient((request) async {
                expect(request.url.path, '/quiz-scores');
                expect(request.headers['Authorization'], 'Bearer token');
                return http.Response(
                    jsonEncode([
                      {
                        'id': 1,
                        'user_id': 7,
                        'module_id': 42,
                        'score': 95,
                        'date_taken': '2026-01-01',
                        'module': {
                          'name': 'Lesson',
                          'credit_type': 'CME',
                          'categories': ['health'],
                        },
                      }
                    ]),
                    200);
              }));
      expect(provider.quizScores.single['score'], 95);
      expect(provider.quizScores.single['module_name'], 'Lesson');
      expect(provider.quizScores.single['credit_type'], 'cme');
      expect(loadingStates, [true, false]);
      expect(storage, before);
      expect(storageCalls.map((call) => call.method), ['read']);
      expect((storageCalls.single.arguments as Map)['key'], 'authToken');
    });
  }

  test(
      'failed fetch retains memory and releases loading without storage writes',
      () async {
    final provider = QuizScoreProvider();
    addTearDown(provider.dispose);
    provider.updateScore({'module_id': 42, 'score': 80});
    await http.runWithClient(() => provider.fetchQuizScores(),
        () => MockClient((_) async => http.Response('unavailable', 503)));
    expect(provider.quizScores.single['score'], 80);
    expect(provider.isLoading, isFalse);
    expect(storageCalls.map((call) => call.method), ['read']);
  });

  http.Response scores(String name) => http.Response(
      jsonEncode([
        {
          'id': 1,
          'user_id': 7,
          'module_id': 42,
          'score': 95,
          'module': {'name': name, 'credit_type': 'CME'}
        },
      ]),
      200);

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test(
      'same-session refresh replaces scores; repeated token sync preserves data',
      () async {
    var calls = 0;
    final provider = QuizScoreProvider(
      readToken: () async => 'A',
      clientFactory: () => MockClient((_) async => scores('Load ${++calls}')),
    )..syncAuthToken('A');
    addTearDown(provider.dispose);
    var notifications = 0;
    provider.addListener(() => notifications++);
    await provider.fetchQuizScores();
    expect(provider.quizScores.single['module_name'], 'Load 1');
    final before = notifications;
    provider.syncAuthToken('A');
    expect(notifications, before);
    expect(provider.quizScores.single['module_name'], 'Load 1');
    await provider.refreshScores();
    expect(provider.quizScores.single['module_name'], 'Load 2');
    expect(calls, 2);
  });

  test(
      'session change clears memory without fetching or touching pending scores',
      () async {
    final before = Map<String, String>.from(storage);
    final provider = QuizScoreProvider()..syncAuthToken('token');
    addTearDown(provider.dispose);
    await http.runWithClient(() => provider.fetchQuizScores(),
        () => MockClient((_) async => scores('Account A')));
    provider.syncAuthToken('B');
    expect(provider.quizScores, isEmpty);
    expect(provider.isLoading, isFalse);
    provider.updateScore({'module_id': 43, 'score': 80});
    provider.syncAuthToken(null);
    expect(provider.quizScores, isEmpty);
    await provider.fetchQuizScores();
    expect(storage, before);
    expect(storageCalls.map((call) => call.method), ['read']);
  });

  for (final oldFails in [false, true]) {
    test(
        'late old-session ${oldFails ? 'failure' : 'success'} cannot affect new session',
        () async {
      var token = 'A';
      final old = Completer<http.Response>();
      final fresh = Completer<http.Response>();
      final provider = QuizScoreProvider(
        readToken: () async => token,
        clientFactory: () => MockClient((request) =>
            request.headers['Authorization'] == 'Bearer A'
                ? old.future
                : fresh.future),
      )..syncAuthToken('A');
      addTearDown(provider.dispose);
      final a = provider.fetchQuizScores();
      await flush();
      provider.syncAuthToken(null);
      token = 'B';
      provider.syncAuthToken('B');
      final b = provider.fetchQuizScores();
      await flush();
      old.complete(oldFails ? http.Response('Unavailable', 503) : scores('A'));
      await a;
      expect(provider.isLoading, isTrue);
      expect(provider.quizScores, isEmpty);
      fresh.complete(scores('B'));
      await b;
      expect(provider.quizScores.single['module_name'], 'B');
      expect(provider.isLoading, isFalse);
    });
  }

  test('late A success after B completes cannot overwrite B', () async {
    var token = 'A';
    final old = Completer<http.Response>();
    final provider = QuizScoreProvider(
      readToken: () async => token,
      clientFactory: () => MockClient((request) =>
          request.headers['Authorization'] == 'Bearer A'
              ? old.future
              : Future.value(scores('B'))),
    )..syncAuthToken('A');
    addTearDown(provider.dispose);
    final a = provider.fetchQuizScores();
    await flush();
    token = 'B';
    provider.syncAuthToken('B');
    await provider.fetchQuizScores();
    old.complete(scores('A'));
    await a;
    expect(provider.quizScores.single['module_name'], 'B');
  });

  for (final newerFirst in [false, true]) {
    test(
        'overlapping same-session requests: newer completes ${newerFirst ? 'first' : 'last'}',
        () async {
      final responses = List.generate(2, (_) => Completer<http.Response>());
      var calls = 0;
      final provider = QuizScoreProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient((_) => responses[calls++].future),
      )..syncAuthToken('A');
      addTearDown(provider.dispose);
      final first = provider.fetchQuizScores();
      await flush();
      final second = provider.fetchQuizScores();
      await flush();
      if (newerFirst) {
        responses[1].complete(scores('New'));
        await second;
        responses[0].complete(scores('Old'));
        await first;
      } else {
        responses[0].complete(scores('Old'));
        await first;
        expect(provider.isLoading, isTrue);
        expect(provider.quizScores, isEmpty);
        responses[1].complete(scores('New'));
        await second;
      }
      expect(provider.quizScores.single['module_name'], 'New');
      expect(provider.isLoading, isFalse);
    });
  }

  test(
      'same-session HTTP/parse failure retains scores; new-session failure does not',
      () async {
    var body = 'Unavailable';
    var status = 503;
    var token = 'A';
    final provider = QuizScoreProvider(
      readToken: () async => token,
      clientFactory: () => MockClient((_) async => http.Response(body, status)),
    )..syncAuthToken('A');
    addTearDown(provider.dispose);
    provider.updateScore({'module_id': 42, 'score': 80});
    await provider.fetchQuizScores();
    expect(provider.quizScores.single['score'], 80);
    body = '{';
    status = 200;
    await provider.fetchQuizScores();
    expect(provider.quizScores.single['score'], 80);
    token = 'B';
    provider.syncAuthToken('B');
    await provider.fetchQuizScores();
    expect(provider.quizScores, isEmpty);
  });

  test('old delayed storage read cannot start HTTP after session changes',
      () async {
    final tokenRead = Completer<String?>();
    var reads = 0;
    var calls = 0;
    final provider = QuizScoreProvider(
      readToken: () => ++reads == 1 ? tokenRead.future : Future.value('B'),
      clientFactory: () => MockClient((_) async {
        calls++;
        return scores('B');
      }),
    )..syncAuthToken('A');
    addTearDown(provider.dispose);
    final a = provider.fetchQuizScores();
    provider.syncAuthToken('B');
    await provider.fetchQuizScores();
    tokenRead.complete('A');
    await a;
    expect(calls, 1);
    expect(provider.quizScores.single['module_name'], 'B');
  });

  test(
      'storage token mismatch sends no HTTP and preserves current-session data',
      () async {
    var calls = 0;
    final provider = QuizScoreProvider(
      readToken: () async => 'B',
      clientFactory: () => MockClient((_) async {
        calls++;
        return scores('B');
      }),
    )..syncAuthToken('A');
    addTearDown(provider.dispose);
    provider.updateScore({'module_id': 42, 'score': 80});
    await provider.fetchQuizScores();
    expect(calls, 0);
    expect(provider.quizScores.single['score'], 80);
    expect(provider.isLoading, isFalse);
  });

  test('logout/login with reused token rejects old generation', () async {
    final old = Completer<http.Response>();
    var calls = 0;
    final provider = QuizScoreProvider(
      readToken: () async => 'A',
      clientFactory: () => MockClient(
          (_) => ++calls == 1 ? old.future : Future.value(scores('New A'))),
    )..syncAuthToken('A');
    addTearDown(provider.dispose);
    final first = provider.fetchQuizScores();
    await flush();
    provider.syncAuthToken(null);
    provider.syncAuthToken('A');
    await provider.fetchQuizScores();
    old.complete(scores('Old A'));
    await first;
    expect(provider.quizScores.single['module_name'], 'New A');
  });

  for (final storageStalls in [false, true]) {
    testWidgets(
        'deadline bounds ${storageStalls ? 'storage' : 'network'} and ignores late completion',
        (tester) async {
      final tokenRead = Completer<String?>();
      final response = Completer<http.Response>();
      var calls = 0;
      final provider = QuizScoreProvider(
        readToken: () => storageStalls ? tokenRead.future : Future.value('A'),
        clientFactory: () => MockClient((_) {
          calls++;
          return response.future;
        }),
        requestTimeout: const Duration(seconds: 1),
      )..syncAuthToken('A');
      addTearDown(provider.dispose);
      provider.updateScore({'module_id': 42, 'score': 80});
      final load = provider.fetchQuizScores();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await load;
      expect(provider.isLoading, isFalse);
      expect(provider.quizScores.single['score'], 80);
      tokenRead.complete('A');
      response.complete(scores('Late'));
      await tester.pump();
      expect(calls, storageStalls ? 0 : 1);
      expect(provider.quizScores.single['score'], 80);
    });
  }

  for (final duringStorage in [false, true]) {
    test(
        'disposal during ${duringStorage ? 'storage' : 'HTTP'} prevents notifications',
        () async {
      final read = Completer<String?>();
      final response = Completer<http.Response>();
      var notifications = 0;
      var calls = 0;
      final provider = QuizScoreProvider(
        readToken: () => duringStorage ? read.future : Future.value('A'),
        clientFactory: () => MockClient((_) {
          calls++;
          return response.future;
        }),
      )..syncAuthToken('A');
      provider.addListener(() => notifications++);
      final load = provider.fetchQuizScores();
      await flush();
      provider.dispose();
      final before = notifications;
      read.complete('A');
      response.complete(scores('Late'));
      await load;
      provider.updateScore({'module_id': 1});
      provider.syncAuthToken('B');
      await provider.fetchQuizScores();
      expect(notifications, before);
      expect(calls, duringStorage ? 0 : 1);
    });
  }

  for (final status in [200, 503]) {
    test('HTTP $status closes its client exactly once', () async {
      final client = _TrackedClient((_) async => status == 200
          ? scores('Loaded')
          : http.Response('Unavailable', status));
      final provider = QuizScoreProvider(
        readToken: () async => 'A',
        clientFactory: () => client,
      )..syncAuthToken('A');
      await provider.fetchQuizScores();
      expect(client.closes, 1);
      provider.dispose();
      expect(client.closes, 1);
    });
  }

  testWidgets('timeout closes once and late completion cannot close again',
      (tester) async {
    final response = Completer<http.Response>();
    final client = _TrackedClient((_) => response.future);
    final provider = QuizScoreProvider(
      readToken: () async => 'A',
      clientFactory: () => client,
      requestTimeout: const Duration(seconds: 1),
    )..syncAuthToken('A');
    final load = provider.fetchQuizScores();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await load;
    expect(client.closes, 1);
    response.complete(scores('Late'));
    await tester.pump();
    provider.dispose();
    expect(client.closes, 1);
    expect(provider.quizScores, isEmpty);
  });

  for (final failOnClose in [false, true]) {
    test(
        'dispose closes pending client immediately; ${failOnClose ? 'abort error' : 'late response'} is safe',
        () async {
      final response = Completer<http.Response>();
      final client = _TrackedClient((_) => response.future,
          onClose: failOnClose
              ? () => response.completeError(http.ClientException('closed'))
              : null);
      final provider = QuizScoreProvider(
        readToken: () async => 'A',
        clientFactory: () => client,
      )..syncAuthToken('A');
      var notifications = 0;
      provider.addListener(() => notifications++);
      final load = provider.fetchQuizScores();
      await flush();
      expect(client.closes, 0);
      provider.dispose();
      expect(client.closes, 1); // No completion, timeout, or pump needed.
      final before = notifications;
      if (!failOnClose) response.complete(scores('Late'));
      await load;
      expect(client.closes, 1);
      expect(notifications, before);
      expect(provider.quizScores, isEmpty);
    });
  }

  test('dispose closes all overlapping clients even if one close throws',
      () async {
    final responses = List.generate(2, (_) => Completer<http.Response>());
    final clients = [
      _TrackedClient((_) => responses[0].future,
          onClose: () => throw StateError('close failed')),
      _TrackedClient((_) => responses[1].future),
    ];
    var created = 0;
    final provider = QuizScoreProvider(
      readToken: () async => 'A',
      clientFactory: () => clients[created++],
    )..syncAuthToken('A');
    final first = provider.fetchQuizScores();
    await flush();
    final second = provider.fetchQuizScores();
    await flush();
    provider.dispose();
    expect(clients.map((client) => client.closes), [1, 1]);
    for (final response in responses) {
      response.complete(scores('Late'));
    }
    await Future.wait([first, second]);
    expect(clients.map((client) => client.closes), [1, 1]);
  });

  test('standalone missing token still throws; storage errors release loading',
      () async {
    final missing = QuizScoreProvider(readToken: () async => null);
    addTearDown(missing.dispose);
    await expectLater(missing.fetchQuizScores(), throwsException);
    expect(missing.isLoading, isFalse);
    final failed = QuizScoreProvider(
        readToken: () async => throw StateError('storage failure'));
    addTearDown(failed.dispose);
    await failed.fetchQuizScores();
    expect(failed.isLoading, isFalse);
  });
}
