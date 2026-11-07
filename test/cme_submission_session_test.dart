import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/pages/cme/submit_credits.dart';
import 'package:wired_test/providers/auth_provider.dart';
import 'package:wired_test/providers/cme_award_provider.dart';
import 'package:wired_test/services/pending_quiz_score_repository.dart';

class _Navigation extends NavigatorObserver {
  int replacements = 0;
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacements++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final expiry = DateTime.utc(2099);
  late AuthProvider auth;
  late CmeAwardProvider awards;
  late PendingQuizScoreRepository pending;
  late Map<String, String> storage;
  late Completer<http.Response> response;
  late MockClient client;
  late _Navigation navigation;
  late List<http.Request> posts;
  late List<String> awardRequests;

  setUp(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
    auth = AuthProvider();
    navigation = _Navigation();
    posts = [];
    awardRequests = [];
    response = Completer<http.Response>();
    storage = {
      'pending_quiz_scores': jsonEncode({
        '1234': {
          'module_name': 'A lesson',
          'score': 95,
          'date_saved': '2025-01-01'
        },
        '5678': {'module_name': 'Z other lesson', 'score': 88}
      })
    };
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
      throw StateError('Unexpected secure storage call');
    });
    awards = CmeAwardProvider(
        clientFactory: () => MockClient((request) async {
              awardRequests.add(request.headers['authorization']!);
              return http.Response('{"credited_module_ids":[99]}', 200);
            }));
    auth.addListener(
        () => awards.syncAuthToken(auth.isLoggedIn ? auth.authToken : null));
    client = MockClient((request) {
      expectSync(request.method, 'POST');
      expectSync(request.url.toString(), 'https://example.invalid/quiz-scores');
      posts.add(request);
      return response.future;
    });
  });
  tearDown(() {
    awards.dispose();
    auth.dispose();
    client.close();
    dotenv.clean();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> drain(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }

  Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100; i++) {
      await drain(tester);
      if (done()) return;
    }
    fail('Submission did not reach expected completion');
  }

  Future<void> start(WidgetTester tester) async {
    pending = PendingQuizScoreRepository();
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await auth.logIn('A', expiry);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<PendingQuizScoreRepository>.value(value: pending),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<CmeAwardProvider>.value(value: awards),
        ],
        child: MaterialApp(
            navigatorObservers: [navigation],
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(0.7)),
                child: child!),
            // Retain the page across auth changes to exercise ownership independently
            // of AuthGuard disposing its child during ordinary UI logout.
            home: SubmitCredits())));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit').first);
    await tester.runAsync(() => tester.tap(find.text('Submit').first));
    await waitUntil(tester, () => posts.length == 1);
    expect(posts.single.headers['authorization'], 'Bearer A');
    expect(jsonDecode(posts.single.body)['score'], 95);
  }

  testWidgets(
      'owned success cleans acknowledged score and refreshes awards once',
      (tester) async {
    await http.runWithClient(() async {
      await start(tester);
      response.complete(http.Response('{}', 201));
      await waitUntil(
          tester,
          () =>
              find.text('Success').evaluate().isNotEmpty &&
              awardRequests.length == 1);
      final saved =
          jsonDecode(storage['pending_quiz_scores']!) as Map<String, dynamic>;
      expect(saved.keys, ['5678']);
      expect(awardRequests, ['Bearer A']);
      expect(navigation.replacements, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });

  for (final reused in [false, true]) {
    for (final retake in [false, true]) {
      testWidgets(
          'late A success preserves bookkeeping without affecting ${reused ? 'reused-token session' : 'B'} (retake=$retake)',
          (tester) async {
        await http.runWithClient(() async {
          await start(tester);
          await auth.logOut();
          await auth.logIn(
              reused ? 'A' : 'B', expiry); // No frame between transitions.
          await awards.fetchAwardedModules();
          expect(awards.hasEarnedCredit(99), isTrue);
          final baseline = List.of(awardRequests);
          if (retake) {
            await tester.runAsync(() => pending.save(
                moduleId: '1234', moduleName: 'A retake', score: 80));
          }
          final savedBefore = jsonDecode(storage['pending_quiz_scores']!)
              as Map<String, dynamic>;
          response.complete(http.Response('{}', 200));
          // Acknowledgement's cleanup runs even though the page still shows A's
          // old list and the operation no longer owns the current session.
          if (!retake) {
            await waitUntil(
                tester,
                () => !(jsonDecode(storage['pending_quiz_scores']!) as Map)
                    .containsKey('1234'));
          }
          for (var i = 0; i < 5; i++) {
            await drain(tester);
          }
          final savedAfter = jsonDecode(storage['pending_quiz_scores']!)
              as Map<String, dynamic>;
          expect(savedAfter['5678'], savedBefore['5678']);
          if (retake) expect(savedAfter['1234'], savedBefore['1234']);
          expect(awardRequests, baseline);
          expect(awards.hasEarnedCredit(99), isTrue);
          expect(find.text('Success'), findsNothing);
          expect(find.byType(SnackBar), findsNothing);
          expect(navigation.replacements, 0);
          expect(posts, hasLength(1));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }, () => client);
      });
    }
  }

  testWidgets(
      'disposal preserves acknowledgement cleanup without award refresh or UI',
      (tester) async {
    await http.runWithClient(() async {
      await start(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      response.complete(http.Response('{}', 200));
      await waitUntil(
          tester,
          () => !(jsonDecode(storage['pending_quiz_scores']!) as Map)
              .containsKey('1234'));
      for (var i = 0; i < 5; i++) {
        await drain(tester);
      }
      expect(
          (jsonDecode(storage['pending_quiz_scores']!) as Map<String, dynamic>)
              .keys,
          ['5678']);
      expect(awardRequests, isEmpty);
      expect(navigation.replacements, 0);
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets(
      'stale A failure does not show an error in B session or remove saved scores',
      (tester) async {
    await http.runWithClient(() async {
      await start(tester);
      final before =
          jsonDecode(storage['pending_quiz_scores']!) as Map<String, dynamic>;
      await auth.logOut();
      await auth.logIn('B', expiry);
      response.complete(http.Response('{"message":"A rejected"}', 401));
      for (var i = 0; i < 5; i++) {
        await drain(tester);
      }
      expect(
          jsonDecode(storage['pending_quiz_scores']!) as Map<String, dynamic>,
          before);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Success'), findsNothing);
      expect(awardRequests, isEmpty);
      expect(navigation.replacements, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });
}
