import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/providers/auth_provider.dart';
import 'package:wired_test/providers/quiz_score_provider.dart';

void main() {
  testWidgets(
      'real AuthProvider proxy preserves instance and observes cycles between frames',
      (tester) async {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
    addTearDown(dotenv.clean);
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final stored = <String, String>{
      'pending_quiz_scores': '{"1234":{"score":88}}'
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          return stored[key];
        case 'write':
          stored[key] = args['value'] as String;
          return null;
        case 'delete':
          stored.remove(key);
          return null;
        default:
          throw StateError('Unexpected storage operation');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final auth = AuthProvider();
    addTearDown(auth.dispose);
    var requests = 0;
    final oldResponse = Completer<http.Response>();
    final client = MockClient((_) {
      requests++;
      return requests == 1
          ? oldResponse.future
          : Future.value(http.Response(
              jsonEncode([
                {
                  'module_id': 42,
                  'score': 90,
                  'module': {'name': 'Current $requests', 'credit_type': 'cme'}
                },
              ]),
              200));
    });
    addTearDown(client.close);
    late QuizScoreProvider scores;
    var creates = 0;
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProxyProvider<AuthProvider, QuizScoreProvider>(
            create: (context) {
              creates++;
              return QuizScoreProvider(clientFactory: () => client)
                ..syncAuthProvider(context.read<AuthProvider>());
            },
            update: (_, auth, previous) {
              final provider = previous!;
              provider.syncAuthProvider(auth);
              return provider;
            },
          ),
        ],
        child: MaterialApp(
            home: Consumer<QuizScoreProvider>(builder: (_, provider, __) {
          scores = provider;
          return Text(
              provider.quizScores.map((q) => q['module_name']).join(','));
        }))));
    await tester.pumpAndSettle();
    final original = scores;
    final expiry = DateTime.now().add(const Duration(hours: 1));
    await auth.logIn('A', expiry);
    await tester.pumpAndSettle();
    expect(requests, 0); // Synchronizing authentication must not fetch.
    final old = scores.fetchQuizScores();
    await tester.pump();
    expect(requests, 1);

    // No widget frame between logout and same-token login: listener must see both.
    await auth.logOut();
    await auth.logIn('A', expiry);
    oldResponse.complete(
        http.Response('[{"module_id":42,"module":{"name":"Old A"}}]', 200));
    await old;
    await tester.pumpAndSettle();
    expect(scores.quizScores, isEmpty);
    expect(find.textContaining('Old A'), findsNothing);
    await scores.fetchQuizScores();
    await tester.pumpAndSettle();
    expect(find.text('Current 2'), findsOneWidget);

    await auth.logOut();
    expect(scores.quizScores, isEmpty);
    await auth.logIn('B', expiry);
    await tester.pumpAndSettle();
    expect(scores, same(original));
    expect(creates, 1);
    expect(requests, 2);
    expect(find.text('Current 2'), findsNothing);
    await scores.fetchQuizScores();
    await tester.pumpAndSettle();
    expect(find.text('Current 3'), findsOneWidget);
    expect(stored['pending_quiz_scores'], '{"1234":{"score":88}}');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
