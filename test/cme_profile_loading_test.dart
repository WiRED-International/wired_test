import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/pages/cme/cme_tracker.dart';
import 'package:wired_test/pages/cme/credits_history.dart';
import 'package:wired_test/providers/auth_provider.dart';
import 'package:wired_test/providers/quiz_score_provider.dart';

class _Scores extends QuizScoreProvider {
  int fetches = 0;
  @override
  Future<void> fetchQuizScores() async {
    fetches++;
  }
}

class _Client extends MockClient {
  _Client(super.handler, this.onClose);
  final VoidCallback onClose;
  @override
  void close() => onClose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final expiry = DateTime.utc(2099);
  final year = DateTime.now().year;
  late AuthProvider auth;
  late _Scores scores;
  late Map<String, String> storage;
  late List<String> requests;
  late List<Completer<http.Response>> responses;
  late MockClient client;
  late int closes;

  http.Response profile(String account) => http.Response(
      jsonEncode({
        'id': account == 'A' ? 1 : 2,
        'first_name': account,
        'quizScores': [
          {
            'id': 1,
            'module_id': 42,
            'score': 90,
            'date_taken': '$year-01-01T00:00:00Z',
            'module': {
              'name': '$account history',
              'module_id': '1234',
              'credit_type': 'cme'
            }
          }
        ],
        'cmeCredits': {
          'status': 'available',
          'annualRequirement': 75,
          'currentYear': {
            'year': year,
            'earnedCredits': account == 'A' ? 11 : 22
          },
          'previousYear': {'year': year - 1, 'earnedCredits': 0}
        }
      }),
      200);

  setUp(() {
    auth = AuthProvider();
    scores = _Scores()..syncAuthProvider(auth);
    storage = {};
    requests = [];
    responses = [];
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
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
      }
      throw StateError('Unexpected storage operation');
    });
    closes = 0;
    client = _Client((request) {
      expectSync(request.url.toString(), 'https://example.invalid/users/me');
      requests.add(request.headers['authorization']!);
      final response = Completer<http.Response>();
      responses.add(response);
      return response.future;
    }, () => closes++);
  });
  tearDown(() {
    scores.dispose();
    auth.dispose();
    client.close();
    dotenv.clean();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() async {});
    await tester.pump(const Duration(milliseconds: 450));
  }

  Future<void> answer(WidgetTester tester, int index, String account,
      {bool failure = false}) async {
    responses[index]
        .complete(failure ? http.Response('{}', 503) : profile(account));
    await pump(tester);
  }

  for (final history in [false, true]) {
    for (final landscape in [false, true]) {
      final name =
          '${history ? 'History' : 'Tracker'} ${landscape ? 'landscape' : 'portrait'}';
      Finder displayed(String account) => find.text(history
          ? '$account history'
          : '${account == 'A' ? 11 : 22} credits earned');

      Future<void> mount(WidgetTester tester) async {
        tester.view.physicalSize =
            landscape ? const Size(1200, 800) : const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await auth.logIn('A', expiry);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<QuizScoreProvider>.value(value: scores),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(0.8)),
              child: child!,
            ),
            home: history ? const CreditsHistory() : const CMETracker(),
          ),
        ));
        await pump(tester);
        expect(requests, ['Bearer A']);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }

      Future<void> retry(WidgetTester tester) async {
        await tester.tap(find.text('Retry'));
        await pump(tester);
      }

      testWidgets('$name loads profile and closes client', (tester) async {
        await http.runWithClient(() async {
          await mount(tester);
          await answer(tester, 0, 'A');
          expect(displayed('A'), findsOneWidget);
          expect(closes, 1);
        }, () => client);
      });

      for (final status in [401, 403, 500]) {
        testWidgets('$name HTTP $status gives guidance and Retry recovers',
            (tester) async {
          await http.runWithClient(() async {
            await mount(tester);
            responses[0]
                .complete(http.Response('private server details', status));
            await pump(tester);
            expect(
                find.textContaining(status == 401
                    ? 'log in again'
                    : status == 403
                        ? 'permission'
                        : 'try again'),
                findsOneWidget);
            expect(find.textContaining('Exception'), findsNothing);
            expect(find.textContaining('private server details'), findsNothing);
            expect(closes, 1);
            await retry(tester);
            expect(requests, ['Bearer A', 'Bearer A']);
            await answer(tester, 1, 'A');
            expect(displayed('A'), findsOneWidget);
            expect(find.text('Retry'), findsNothing);
            expect(closes, 2);
          }, () => client);
        });
      }

      testWidgets('$name network failure is friendly and recoverable',
          (tester) async {
        await http.runWithClient(() async {
          await mount(tester);
          responses[0]
              .completeError(http.ClientException('private network details'));
          await pump(tester);
          expect(find.textContaining('connection'), findsOneWidget);
          expect(find.textContaining('private network details'), findsNothing);
          expect(closes, 1);
          await retry(tester);
          await answer(tester, 1, 'A');
          expect(displayed('A'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }, () => client);
      });

      for (final lateError in [false, true]) {
        testWidgets(
            '$name times out and ignores late ${lateError ? 'error' : 'success'} after Retry',
            (tester) async {
          await http.runWithClient(() async {
            await mount(tester);
            await tester.pump(const Duration(seconds: 31));
            await pump(tester);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(find.textContaining('connection'), findsOneWidget);
            expect(find.text('Retry'), findsOneWidget);
            expect(closes, 1);
            await retry(tester);
            await answer(tester, 1, 'B');
            expect(displayed('B'), findsOneWidget);
            if (lateError) {
              responses[0].completeError(http.ClientException('late failure'));
              await pump(tester);
            } else {
              await answer(tester, 0, 'A');
            }
            expect(displayed('B'), findsOneWidget);
            expect(displayed('A'), findsNothing);
            expect(tester.takeException(), isNull);
          }, () => client);
        });
      }

      for (final retrying in [false, true]) {
        for (final reused in [false, true]) {
          testWidgets(
              '$name isolates ${retrying ? 'retry' : 'initial load'} across ${reused ? 'reused-token logout/login' : 'account switch'}',
              (tester) async {
            await http.runWithClient(() async {
              await mount(tester);
              if (retrying) {
                responses[0].complete(http.Response('{}', 500));
                await pump(tester);
                await retry(tester);
              }
              final stale = responses.length - 1;
              if (reused) await auth.logOut();
              await auth.logIn(reused ? 'A' : 'B', expiry);
              await pump(tester);
              expect(requests.last, reused ? 'Bearer A' : 'Bearer B');
              await answer(tester, responses.length - 1, 'B');
              await answer(tester, stale, 'A');
              expect(displayed('B'), findsOneWidget);
              expect(displayed('A'), findsNothing);
              expect(find.text('Retry'), findsNothing);
              expect(tester.takeException(), isNull);
            }, () => client);
          });
        }
      }

      testWidgets('$name disposal contains pending request failure',
          (tester) async {
        await http.runWithClient(() async {
          await mount(tester);
          await tester.pumpWidget(const SizedBox.shrink());
          responses[0].completeError(http.ClientException('disposed failure'));
          await pump(tester);
          expect(closes, 1);
          expect(tester.takeException(), isNull);
        }, () => client);
      });

      if (!history) {
        testWidgets('$name contains failed refresh and later refresh succeeds',
            (tester) async {
          await http.runWithClient(() async {
            await mount(tester);
            await answer(tester, 0, 'A');
            final refresh = tester
                .widget<RefreshIndicator>(find.byType(RefreshIndicator))
                .onRefresh();
            await pump(tester);
            responses[1].complete(http.Response('{}', 500));
            await pump(tester);
            await refresh; // Must complete normally, with no uncaught error.
            expect(find.text('Retry'), findsOneWidget);
            expect(find.textContaining('Refresh complete.'), findsNothing);
            expect(tester.takeException(), isNull);
            await retry(tester);
            await answer(tester, 2, 'A');
            final next = tester
                .widget<RefreshIndicator>(find.byType(RefreshIndicator))
                .onRefresh();
            await pump(tester);
            await answer(tester, 3, 'A');
            await next;
            await pump(tester);
            expect(displayed('A'), findsOneWidget);
            expect(find.textContaining('Refresh complete.'), findsOneWidget);
            expect(tester.takeException(), isNull);
          }, () => client);
        });
      }
    }
  }
}
