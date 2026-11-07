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
    client = MockClient((request) {
      expectSync(request.url.toString(), 'https://example.invalid/users/me');
      requests.add(request.headers['authorization']!);
      final response = Completer<http.Response>();
      responses.add(response);
      return response.future;
    });
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
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 450));
  }

  Future<void> answer(WidgetTester tester, int index, String account,
      {bool failure = false}) async {
    responses[index]
        .complete(failure ? http.Response('{}', 503) : profile(account));
    await pump(tester);
  }

  for (final history in [false, true]) {
    final name = history ? 'History' : 'Tracker';
    final page = history ? const CreditsHistory() : const CMETracker();
    Finder displayed(String account) => find.text(history
        ? '$account history'
        : '${account == 'A' ? 11 : 22} credits earned');

    Future<void> mount(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
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
                  child: child!),
              home: page)));
      await pump(tester);
      expect(requests, ['Bearer A']);
    }

    for (final size in [const Size(400, 900), const Size(1200, 800)]) {
      testWidgets(
          '$name $size clears logout data, loads B, and ignores repeated same-session notifications',
          (tester) async {
        await http.runWithClient(() async {
          await mount(tester, size);
          await answer(tester, 0, 'A');
          expect(displayed('A'), findsOneWidget);
          await auth
              .loadStoredAuthData(); // Loading notifications, same identity.
          await pump(tester);
          await auth.logIn('A', expiry); // Same committed token, no transition.
          await pump(tester);
          expect(requests, hasLength(1));
          await auth.logOut();
          await pump(tester);
          expect(displayed('A'), findsNothing);
          expect(requests, hasLength(1)); // Logout must not fetch a profile.
          await auth.logIn('B', expiry);
          await pump(tester);
          expect(displayed('A'), findsNothing);
          expect(requests, ['Bearer A', 'Bearer B']);
          await answer(tester, 1, 'B');
          expect(displayed('B'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }, () => client);
      });
    }

    for (final reused in [false, true]) {
      testWidgets(
          '$name rejects delayed A after ${reused ? 'reused-token cycle' : 'direct B login'}',
          (tester) async {
        await http.runWithClient(() async {
          await mount(tester, const Size(400, 900));
          if (reused) await auth.logOut();
          await auth.logIn(reused ? 'A' : 'B', expiry);
          // No frame between logout/login: direct listener must see both.
          await pump(tester);
          expect(requests, hasLength(2));
          await answer(tester, 1, 'B');
          expect(displayed('B'), findsOneWidget);
          await answer(tester, 0, 'A');
          expect(displayed('B'), findsOneWidget);
          expect(displayed('A'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }, () => client);
      });
    }

    for (final failure in [false, true]) {
      testWidgets(
          '$name disposal during profile ${failure ? 'failure' : 'success'} is safe and detaches auth listener',
          (tester) async {
        await http.runWithClient(() async {
          await mount(tester, const Size(400, 900));
          await tester.pumpWidget(const SizedBox.shrink());
          await auth.logOut();
          await auth.logIn('B', expiry);
          await answer(tester, 0, 'A', failure: failure);
          expect(requests, hasLength(1));
          expect(tester.takeException(), isNull);
        }, () => client);
      });
    }
  }

  for (final size in [const Size(400, 900), const Size(1200, 800)]) {
    testWidgets(
        'History $size clears identity selections across reused-token transition',
        (tester) async {
      await http.runWithClient(() async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await auth.logIn('A', expiry);
        await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
            value: auth, child: MaterialApp(home: const CreditsHistory())));
        await pump(tester);
        await answer(tester, 0, 'A');
        final checkbox = find.descendant(
            of: find
                .ancestor(
                    of: find.text('A history'), matching: find.byType(Row))
                .first,
            matching: find.byType(InkWell));
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await pump(tester);
        expect(
            tester
                .widget<ElevatedButton>(find
                    .ancestor(
                        of: find.text('Email'),
                        matching: find.byWidgetPredicate(
                            (widget) => widget is ElevatedButton))
                    .first)
                .onPressed,
            isNotNull);
        await auth.logOut();
        await auth.logIn('A', expiry);
        await pump(tester);
        expect(find.text('A history'), findsNothing);
        await answer(tester, 1, 'B');
        expect(find.text('B history'), findsOneWidget);
        expect(
            tester
                .widget<ElevatedButton>(find
                    .ancestor(
                        of: find.text('Email'),
                        matching: find.byWidgetPredicate(
                            (widget) => widget is ElevatedButton))
                    .first)
                .onPressed,
            isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => client);
    });
  }
  testWidgets(
      'Tracker refresh completion from A cannot show success or errors in B session',
      (tester) async {
    await http.runWithClient(() async {
      tester.view.physicalSize = const Size(400, 900);
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
                  child: child!),
              home: const CMETracker())));
      await pump(tester);
      await answer(tester, 0, 'A');
      final indicator =
          tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      final refresh = indicator.onRefresh();
      await pump(tester);
      expect(requests, hasLength(2));
      await auth.logIn('B', expiry);
      await pump(tester);
      expect(requests, hasLength(3));
      await answer(tester, 2, 'B');
      await answer(tester, 1, 'A');
      await refresh;
      await pump(tester);
      expect(find.text('22 credits earned'), findsOneWidget);
      expect(find.text('11 credits earned'), findsNothing);
      expect(find.textContaining('Refresh complete.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });
}
