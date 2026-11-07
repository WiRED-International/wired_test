import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/pages/cme/login.dart';
import 'package:wired_test/pages/menu/menu.dart';
import 'package:wired_test/providers/auth_provider.dart';
import 'package:wired_test/providers/quiz_score_provider.dart';
import 'package:wired_test/providers/user_provider.dart';

// REGRESSION tests assert desired caller sequencing and intentionally fail until
// callers await authentication and guard asynchronous UI work. No logout-failure
// policy is prescribed: failure semantics are characterized separately below.
class _Storage {
  final values = <String, String>{};
  final calls = <String>[];
  Future<void> Function(String method, String key)? before;

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments as Map;
    final key = args['key'] as String;
    calls.add('${call.method}:$key');
    await before?.call(call.method, key);
    switch (call.method) {
      case 'read':
        return values[key];
      case 'write':
        values[key] = args['value'] as String;
        return null;
      case 'delete':
        values.remove(key);
        return null;
    }
    throw StateError('Unexpected storage operation: ${call.method}');
  }
}

class _Scores extends QuizScoreProvider {
  int fetches = 0;
  @override
  Future<void> fetchQuizScores() async {
    fetches++;
  }
}

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
  late _Storage storage;
  late AuthProvider auth;
  late _Scores scores;
  late _Navigation navigation;
  late MockClient client;
  late Completer<http.Response> loginResponse;
  var posts = 0;
  final expiry = DateTime.utc(2099);
  final token = 'e30.${base64Url.encode(utf8.encode(jsonEncode({
            'id': 1,
            'exp': expiry.millisecondsSinceEpoch ~/ 1000
          }))).replaceAll('=', '')}.signature';

  setUp(() {
    storage = _Storage();
    auth = AuthProvider();
    scores = _Scores();
    navigation = _Navigation();
    loginResponse = Completer<http.Response>();
    posts = 0;
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, storage.handle);
    client = MockClient((request) async {
      expect(request.url.host, 'example.invalid');
      if (request.url.path == '/auth/login') {
        posts++;
        return loginResponse.future;
      }
      expect(request.url.path, '/users/me');
      return http.Response(
          '{"id":1,"first_name":"Test","createdAt":"2025-01-01","quizScores":[]}',
          200);
    });
  });
  tearDown(() {
    client.close();
    scores.dispose();
    auth.dispose();
    dotenv.clean();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void respond() => loginResponse.complete(http.Response(
      jsonEncode({
        'token': token,
        'user': {'id': 1, 'firstName': 'Test', 'createdAt': '2025-01-01'}
      }),
      200));

  Future<void> mount(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Keep Ahem test-font layout separate from lifecycle assertions.
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<QuizScoreProvider>.value(value: scores),
          ChangeNotifierProvider(create: (_) => UserProvider()),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(0.5)),
                child: child!),
            navigatorObservers: [navigation],
            home: page)));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(
        find.byType(TextFormField).at(0), 'test@example.invalid');
    await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
    tester.testTextInput.hide();
    await tester.pump();
    await tester.ensureVisible(find.text('Login'));
    await tester.tap(find.text('Login'));
    await tester.pump();
  }

  testWidgets(
      'CHARACTERIZATION login publishes only after both writes; valid credentials survive restart',
      (tester) async {
    final gate = Completer<void>();
    storage.before = (method, key) async {
      if (method == 'write' && key == 'tokenExpiry') await gate.future;
    };
    var notifications = 0;
    auth.addListener(() => notifications++);
    final pending = auth.logIn(token, expiry);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(auth.isLoggedIn, isTrue); // In-memory mutation precedes persistence.
    expect(notifications, 0);
    expect(storage.values['tokenExpiry'], isNull);
    gate.complete();
    await pending;
    expect(notifications, 1);
    final restarted = AuthProvider();
    await restarted.loadStoredAuthData();
    expect(restarted.isLoggedIn, isTrue);
    expect(restarted.authToken, token);
    restarted.dispose();
  });

  testWidgets(
      'CHARACTERIZATION delayed logout retains session until both deletes complete',
      (tester) async {
    await auth.logIn(token, expiry);
    final gate = Completer<void>();
    storage.before = (method, key) async {
      if (method == 'delete' && key == 'authToken') await gate.future;
    };
    var notifications = 0;
    auth.addListener(() => notifications++);
    final pending = auth.logOut();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(auth.authToken, token);
    expect(auth.isLoggedIn, isTrue);
    expect(notifications, 0);
    gate.complete();
    await pending;
    expect(auth.isLoggedIn, isFalse);
    expect(storage.values, isEmpty);
    expect(notifications, 1);
  });

  testWidgets(
      'CHARACTERIZATION logout deletion failure propagates and retains in-memory session',
      (tester) async {
    await auth.logIn(token, expiry);
    storage.before = (method, key) async {
      if (method == 'delete' && key == 'tokenExpiry') {
        throw PlatformException(code: 'storage-unavailable');
      }
    };
    var notifications = 0;
    auth.addListener(() => notifications++);
    await expectLater(auth.logOut(), throwsA(isA<PlatformException>()));
    expect(auth.isLoggedIn, isTrue);
    expect(auth.authToken, token);
    expect(storage.values['authToken'],
        isNull); // Partial deletion is current behavior.
    expect(storage.values['tokenExpiry'], isNotNull);
    expect(notifications, 0);
  });

  testWidgets(
      'CHARACTERIZATION login persistence failure propagates before notification',
      (tester) async {
    storage.before = (method, key) async {
      if (method == 'write' && key == 'tokenExpiry') {
        throw PlatformException(code: 'write-failed');
      }
    };
    var notifications = 0;
    auth.addListener(() => notifications++);
    await expectLater(
        auth.logIn(token, expiry), throwsA(isA<PlatformException>()));
    expect(auth.isLoggedIn, isTrue);
    expect(notifications, 0);
    expect(storage.values['authToken'], token);
    expect(storage.values['tokenExpiry'], isNull);
  });

  for (final checkNavigation in [false, true]) {
    testWidgets(
        'REGRESSION login waits for persistence before ${checkNavigation ? 'navigation' : 'score fetching'}',
        (tester) async {
      await http.runWithClient(() async {
        final gate = Completer<void>();
        storage.before = (method, key) async {
          if (method == 'write' && key == 'tokenExpiry') await gate.future;
        };
        await mount(tester, Login());
        await submit(tester);
        await tester.runAsync(() async {
          respond();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.runAsync(() => Future<void>.delayed(const Duration(
            milliseconds:
                20))); // Observe callbacks without building destination UI.
        final earlyFetches = scores.fetches;
        final earlyNavigation = navigation.replacements;
        gate.complete();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        expect(scores.fetches, 1);
        expect(navigation.replacements, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        if (checkNavigation) {
          expect(earlyNavigation, 0,
              reason: 'Navigation must await AuthProvider.logIn');
        } else {
          expect(earlyFetches, 0,
              reason: 'Score fetching must await AuthProvider.logIn');
        }
      }, () => client);
    });
  }

  testWidgets(
      'CHARACTERIZATION repeated login taps submit once and stay busy while pending',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester, Login());
      await submit(tester);
      await tester.tap(find.byType(CircularProgressIndicator));
      await tester.pump();
      expect(posts, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.runAsync(() async {
        loginResponse.complete(http.Response('{}', 401));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.text('Invalid Email or Password'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Login'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }, () => client);
  });

  testWidgets(
      'CHARACTERIZATION initial login storage failure shows error and clears busy state',
      (tester) async {
    await http.runWithClient(() async {
      storage.before = (method, key) async {
        if (method == 'write') throw PlatformException(code: 'write-failed');
      };
      await mount(tester, Login());
      await submit(tester);
      await tester.runAsync(() async {
        respond();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(
          find.textContaining('An unexpected error occurred.'), findsOneWidget);
      expect(scores.fetches, 0);
      expect(navigation.replacements, 0);
      expect(auth.isLoggedIn, isFalse);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Login'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }, () => client);
  });

  testWidgets(
      'REGRESSION leaving Login during pending HTTP causes no disposed-context errors',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester, Login());
      await submit(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      // A failed response also exercises the final, currently unguarded setState.
      await tester.runAsync(() async {
        loginResponse.complete(http.Response('{}', 401));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      expect(scores.fetches, 0);
      expect(navigation.replacements, 0);
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets(
      'REGRESSION provider persistence failure is handled and releases Login busy state',
      (tester) async {
    await http.runWithClient(() async {
      storage.before = (method, key) async {
        // The page's initial token write succeeds; AuthProvider's expiry write fails.
        if (method == 'write' && key == 'tokenExpiry') {
          throw PlatformException(code: 'expiry-write-failed');
        }
      };
      await mount(tester, Login());
      await submit(tester);
      await tester.runAsync(() async {
        respond();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      // Production currently drops logIn's Future, so the storage error escapes
      // this widget callback; the framework reports that as the regression.
      expect(scores.fetches, 0);
      expect(navigation.replacements, 0);
      expect(tester.takeException(), isNull);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }, () => client);
  });
  for (final repeated in [false, true]) {
    testWidgets(
        'REGRESSION Menu ${repeated ? 'ignores repeated logout taps' : 'awaits logout before navigation'}',
        (tester) async {
      await http.runWithClient(() async {
        await auth.logIn(token, expiry);
        final gate = Completer<void>();
        storage.before = (method, key) async {
          if (method == 'delete' && key == 'authToken') await gate.future;
        };
        await mount(tester, const Menu());
        await tester.ensureVisible(find.text('Log out'));
        // Invoke the actual row callback twice before a frame, modelling rapid taps.
        final row = find
            .ancestor(
                of: find.text('Log out'),
                matching: find.byType(GestureDetector))
            .first;
        final tap = tester.widget<GestureDetector>(row).onTap!;
        tap();
        if (repeated) tap();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        final earlyNavigation = navigation.replacements;
        final deletes =
            storage.calls.where((c) => c == 'delete:authToken').length;
        gate.complete();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        expect(auth.isLoggedIn, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        if (repeated) {
          expect(deletes, 1);
        } else {
          expect(earlyNavigation, 0);
        }
      }, () => client);
    });
  }
}
