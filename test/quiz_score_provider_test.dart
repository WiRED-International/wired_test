import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wired_test/providers/quiz_score_provider.dart';

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
}
