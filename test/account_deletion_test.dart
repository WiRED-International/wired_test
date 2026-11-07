import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/pages/menu/menu.dart';
import 'package:wired_test/providers/auth_provider.dart';
import 'package:wired_test/providers/quiz_score_provider.dart';

class _Navigation extends NavigatorObserver {
  int dialogs = 0;
  int replacements = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is DialogRoute) dialogs++;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacements++;
  }
}

// All deletion tests exercise the real page-owned confirmation flow.
// Captured callback errors remain observable assertions.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late AuthProvider auth;
  late QuizScoreProvider scores;
  late MockClient client;
  late _Navigation navigation;
  late Map<String, String> stored;
  late List<http.Request> deletes;
  late List<Object> errors;
  late Completer<http.Response> response;
  Object? transportError;
  Future<void> Function(String, String)? beforeStorage;
  final navigatorKey = GlobalKey<NavigatorState>();
  final expiry = DateTime.utc(2099);

  setUp(() {
    stored = {};
    deletes = [];
    errors = [];
    response = Completer<http.Response>();
    beforeStorage = null;
    transportError = null;
    navigation = _Navigation();
    auth = AuthProvider();
    scores = QuizScoreProvider()..syncAuthProvider(auth);
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      await beforeStorage?.call(call.method, key);
      switch (call.method) {
        case 'read':
          return stored[key];
        case 'write':
          stored[key] = args['value'] as String;
          return null;
        case 'delete':
          stored.remove(key);
          return null;
      }
      throw StateError('Unexpected storage method ${call.method}');
    });
    client = MockClient((request) {
      expectSync(request.url.host, 'example.invalid');
      if (request.method == 'DELETE') {
        expectSync(request.url.path, '/auth/delete-account');
        deletes.add(request);
        return response.future.then((value) {
          if (transportError != null) throw transportError!;
          return value;
        });
      }
      expectSync(request.method, 'GET');
      expectSync(request.url.path, '/users/me');
      return Future.value(http.Response(
          '{"id":1,"first_name":"Test","createdAt":"2025-01-01","quizScores":[]}',
          200));
    });
  });
  tearDown(() {
    scores.dispose();
    auth.dispose();
    client.close();
    dotenv.clean();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void launch(FutureOr<void> Function() action) {
    runZonedGuarded(() {
      Future<void>.sync(action).catchError((Object error) {
        errors.add(error);
      });
    }, (error, stack) {
      errors.add(error);
    });
  }

  Future<void> flush(WidgetTester tester) async {
    // http's streamed response needs the real event loop; storage/HTTP ownership
    // is controlled by completers rather than production services.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }

  Future<void> mount(WidgetTester tester) async {
    await auth.logIn('account-A', expiry);
    scores.updateScore({'module_id': 42, 'score': 90});
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<QuizScoreProvider>.value(value: scores),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [navigation],
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(0.5)),
              child: child!),
          home: const Menu(),
        )));
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester, {bool twice = false}) async {
    await tester.ensureVisible(find.text('Delete Account'));
    final row = find
        .ancestor(
            of: find.text('Delete Account'),
            matching: find.byType(GestureDetector))
        .first;
    final callback = tester.widget<GestureDetector>(row).onTap!;
    launch(() async {
      await Function.apply(callback, const []);
    });
    if (twice) {
      launch(() async {
        await Function.apply(callback, const []);
      });
    }
    await tester.pumpAndSettle();
  }

  void confirm(WidgetTester tester) {
    final button =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Delete'));
    launch(() async {
      await Function.apply(button.onPressed!, const []);
    });
  }

  Future<void> deleteFromPage(WidgetTester tester) async {
    await openDialog(tester);
    confirm(tester);
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester, int status) async {
    await flush(tester);
    response.complete(http.Response('{}', status));
    await tester.pump();
    await flush(tester);
    await tester.pump();
    await flush(tester);
  }

  for (final dismissal in ['Cancel', 'barrier', 'Back']) {
    testWidgets(
        '${dismissal == 'Cancel' ? 'CHARACTERIZATION' : 'REGRESSION'} $dismissal dismisses confirmation without requests or errors',
        (tester) async {
      await http.runWithClient(() async {
        await mount(tester);
        await openDialog(tester);
        if (dismissal == 'Cancel') {
          await tester.tap(find.text('Cancel'));
        } else if (dismissal == 'barrier') {
          await tester.tapAt(const Offset(5, 5));
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(deletes, isEmpty);
        expect(auth.isLoggedIn, isTrue);
        expect(errors, isEmpty,
            reason: 'Null dialog results must be handled safely');
      }, () => client);
    });
  }

  testWidgets('REGRESSION one confirmation sends exactly one DELETE',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      await openDialog(tester);
      confirm(tester);
      await tester.pumpAndSettle();
      final count = deletes.length;
      // Dispose both contexts before finishing to isolate duplicate networking.
      await tester.pumpWidget(const SizedBox.shrink());
      await finish(tester, 503);
      expect(errors, isEmpty);
      expect(count, 1);
    }, () => client);
  });

  testWidgets(
      'CHARACTERIZATION DELETE uses initiating authenticated bearer token',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      await deleteFromPage(tester);
      await flush(tester);
      expect(deletes, hasLength(1));
      expect(deletes.single.headers['authorization'], 'Bearer account-A');
      expect(deletes.single.headers['content-type'], 'application/json');
      expect(deletes.single.body, isEmpty);
      await finish(tester, 503);
      expect(errors, isEmpty);
    }, () => client);
  });

  testWidgets('REGRESSION rapid Delete Account taps open only one confirmation',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      await openDialog(tester, twice: true);
      final count = navigation.dialogs;
      expect(deletes, isEmpty);
      // Cancel both currently open dialogs to avoid dangling callback Futures.
      while (navigatorKey.currentState!.canPop()) {
        navigatorKey.currentState!.pop(false);
        await tester.pumpAndSettle();
      }
      expect(errors, isEmpty);
      expect(count, 1);
    }, () => client);
  });

  testWidgets('CHARACTERIZATION HTTP failure retains account and scores',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      await deleteFromPage(tester);
      await finish(tester, 503);
      await tester.pump();
      expect(auth.authToken, 'account-A');
      expect(scores.quizScores, hasLength(1));
      expect(navigation.replacements, 0);
      expect(find.text('Failed to delete account. Please try again.'),
          findsOneWidget);
      expect(errors, isEmpty);
    }, () => client);
  });

  for (final timeout in [false, true]) {
    testWidgets(
        'CHARACTERIZATION ${timeout ? 'transport TimeoutException' : 'network exception'} retains authentication and reports uncertain outcome',
        (tester) async {
      await http.runWithClient(() async {
        await mount(tester);
        await deleteFromPage(tester);
        transportError = timeout
            ? TimeoutException('Mock transport timeout')
            : http.ClientException('Mock network failure');
        await finish(tester, 503);
        expect(auth.authToken, 'account-A');
        expect(stored['authToken'], 'account-A');
        expect(scores.quizScores, hasLength(1));
        expect(navigation.replacements, 0);
        expect(errors, isEmpty);
        expect(find.textContaining('Unable to confirm account deletion.'),
            findsOneWidget);
      }, () => client);
    });
  }

  testWidgets(
      '15-second application deadline ignores late success and permits retry',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      await deleteFromPage(tester);
      await flush(tester);
      await tester.pump(const Duration(seconds: 14));
      expect(find.textContaining('Unable to confirm account deletion.'),
          findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Unable to confirm account deletion.'),
          findsOneWidget);
      expect(auth.authToken, 'account-A');
      expect(navigation.replacements, 0);
      expect(errors, isEmpty);
      await finish(tester, 200);
      expect(auth.authToken, 'account-A');
      expect(navigation.replacements, 0);
      response = Completer<http.Response>();
      await deleteFromPage(tester);
      expect(deletes, hasLength(2));
      await finish(tester, 503);
    }, () => client);
  });

  for (final reused in [false, true]) {
    testWidgets(
        'REGRESSION late deletion cannot affect ${reused ? 'reused-token new session' : 'Account B'}',
        (tester) async {
      await http.runWithClient(() async {
        await mount(tester);
        await deleteFromPage(tester);
        await flush(tester);
        await auth.logOut();
        final nextToken = reused ? 'account-A' : 'account-B';
        await auth.logIn(nextToken, expiry);
        scores.updateScore({'module_id': 99, 'score': 80});
        await finish(tester, 200);
        final currentToken = auth.authToken;
        final currentScores = List.of(scores.quizScores);
        final replacements = navigation.replacements;
        await tester.pumpWidget(const SizedBox.shrink());
        expect(errors, isEmpty);
        expect(currentToken, nextToken);
        expect(currentScores.single['module_id'], 99);
        expect(replacements, 0);
      }, () => client);
    });
  }

  testWidgets('REGRESSION success awaits logout persistence before navigation',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      final gate = Completer<void>();
      beforeStorage = (method, key) async {
        if (method == 'delete' && key == 'authToken') await gate.future;
      };
      await deleteFromPage(tester);
      await finish(tester, 200);
      final earlyNavigation = navigation.replacements;
      expect(auth.isLoggedIn, isTrue);
      gate.complete();
      await flush(tester);
      expect(auth.isLoggedIn, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(errors, isEmpty);
      expect(earlyNavigation, 0);
    }, () => client);
  });

  for (final duringConfirmation in [false, true]) {
    testWidgets(
        '${duringConfirmation ? 'REGRESSION' : 'CHARACTERIZATION'} disposal during ${duringConfirmation ? 'confirmation' : 'HTTP'} avoids invalid contexts',
        (tester) async {
      await http.runWithClient(() async {
        await mount(tester);
        if (duringConfirmation) {
          final pageRoute = ModalRoute.of(tester.element(find.byType(Menu)))!;
          await openDialog(tester);
          // Keep the dialog alive while removing its originating page. This
          // actually resumes the callback after disposal, rather than leaving
          // an unresolved dialog Future when the entire app is torn down.
          navigatorKey.currentState!.removeRoute(pageRoute);
          await tester.pumpAndSettle();
          confirm(tester);
          await tester.pumpAndSettle();
          await finish(tester, 503);
          expect(deletes, isEmpty);
        } else {
          await deleteFromPage(tester);
          await flush(tester);
          await tester.pumpWidget(const SizedBox.shrink());
          await finish(tester, 200);
        }
        await flush(tester);
        expect(navigation.replacements, 0);
        expect(errors, isEmpty);
        expect(tester.takeException(), isNull);
      }, () => client);
    });
  }

  testWidgets('REGRESSION dialog-confirmed response uses live page context',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      await openDialog(tester);
      confirm(tester);
      await tester.pumpAndSettle(); // Fully dispose the popped dialog context.
      await finish(tester, 503);
      await tester.pump();
      expect(auth.isLoggedIn, isTrue);
      expect(errors, isEmpty);
      expect(find.text('Failed to delete account. Please try again.'),
          findsOneWidget);
    }, () => client);
  });

  testWidgets(
      'CHARACTERIZATION successful deletion clears session-aware quiz state',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      await deleteFromPage(tester);
      await finish(tester, 200);
      expect(auth.isLoggedIn, isFalse);
      expect(scores.quizScores, isEmpty);
      expect(stored['authToken'], isNull);
      expect(stored['tokenExpiry'], isNull);
      expect(navigation.replacements, 1);
      expect(errors, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });

  testWidgets(
      'confirmed deletion with logout storage failure shows distinct error and no new DELETE',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      beforeStorage = (method, key) async {
        if (method == 'delete' && key == 'tokenExpiry') {
          throw PlatformException(code: 'delete-failed');
        }
      };
      await deleteFromPage(tester);
      await finish(tester, 200);
      await tester.pump();
      expect(deletes, hasLength(1));
      expect(auth.authToken, 'account-A');
      expect(auth.isLoggedIn, isTrue);
      expect(stored['authToken'], isNull);
      expect(stored['tokenExpiry'], isNotNull);
      expect(scores.quizScores, hasLength(1));
      expect(navigation.replacements, 0);
      expect(errors, isEmpty);
      expect(
          find.textContaining(
              'Account deletion was confirmed, but local sign-out failed.'),
          findsOneWidget);
      expect(deletes, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });
  testWidgets('HTTP failure releases guard for another confirmed attempt',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      await deleteFromPage(tester);
      await openDialog(tester); // Ignored while the first request is pending.
      expect(navigation.dialogs, 1);
      await finish(tester, 503);
      response = Completer<http.Response>();
      await deleteFromPage(tester);
      expect(navigation.dialogs, 2);
      expect(deletes, hasLength(2));
      await finish(tester, 503);
      expect(errors, isEmpty);
    }, () => client);
  });

  for (final reused in [false, true]) {
    testWidgets(
        'session change during confirmation rejects decision (reused=$reused)',
        (tester) async {
      await http.runWithClient(() async {
        await mount(tester);
        await openDialog(tester);
        await auth.logOut();
        await auth.logIn(reused ? 'account-A' : 'account-B', expiry);
        // No frame between authentication transitions.
        confirm(tester);
        await tester.pumpAndSettle();
        expect(deletes, isEmpty);
        expect(auth.isLoggedIn, isTrue);
        expect(navigation.replacements, 0);
        expect(errors, isEmpty);
      }, () => client);
    });
  }

  testWidgets(
      'disposal during awaited logout detaches listener and avoids UI work',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      final gate = Completer<void>();
      beforeStorage = (method, key) async {
        if (method == 'delete' && key == 'authToken') await gate.future;
      };
      await deleteFromPage(tester);
      await finish(tester, 200);
      expect(auth.isLoggedIn, isTrue);
      expect(navigation.replacements, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await flush(tester);
      expect(auth.isLoggedIn, isFalse);
      expect(navigation.replacements, 0);
      await auth.logIn('account-B', expiry);
      expect(auth.authToken, 'account-B');
      expect(errors, isEmpty);
      expect(tester.takeException(), isNull);
    }, () => client);
  });
}
