import 'package:wired_test/services/pending_quiz_score_repository.dart';
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

class _Auth extends AuthProvider {
  String? token = 'A';
  @override
  bool get isLoggedIn => true;
  @override
  String? get authToken => token;
  @override
  String? getUserIdFromToken() => '7';
}

class _TrackedClient extends MockClient {
  _TrackedClient(Future<http.Response> Function(http.Request) handler)
      : super(handler);
  var closes = 0;

  @override
  void close() {
    closes++;
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, String> storage;
  late CmeAwardProvider awards;
  late _Auth auth;
  bool failPendingCleanup = false;
  bool failPendingRead = false;
  bool failPendingWrite = false;
  setUp(() {
    failPendingCleanup = false;
    failPendingRead = false;
    failPendingWrite = false;
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
    auth = _Auth();
    storage = {
      'quiz_scores': jsonEncode({'1234': 95.0}),
      'pending_quiz_scores': jsonEncode({
        '1234': {'module_name': 'Test lesson', 'score': 95.0}
      }),
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          if (failPendingRead && key == 'pending_quiz_scores') {
            throw PlatformException(code: 'read');
          }
          return storage[key];
        case 'write':
          if (failPendingWrite && key == 'pending_quiz_scores') {
            throw PlatformException(code: 'write');
          }
          storage[key] = args['value'] as String;
          return null;
        case 'delete':
          if (failPendingCleanup && key == 'pending_quiz_scores') {
            throw PlatformException(code: 'cleanup');
          }
          storage.remove(key);
          return null;
        default:
          throw TestFailure('Unexpected storage method: ${call.method}');
      }
    });
  });
  tearDown(() {
    awards.dispose();
    auth.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> mount(WidgetTester tester,
      {bool expectScore = true,
      Size size = const Size(1000, 1600),
      Duration submissionTimeout = const Duration(seconds: 30)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider(create: (_) => PendingQuizScoreRepository()),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<CmeAwardProvider>.value(value: awards),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(0.7)),
                child: child!),
            home: SubmitCredits(submissionTimeout: submissionTimeout))));
    await tester.pumpAndSettle();
    if (expectScore) expect(find.text('95.00'), findsOneWidget);
  }

  Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 10));
      if (done()) return;
    }
    fail('Expected asynchronous CME operation to finish');
  }

  for (final outcome in ['success', 'http error', 'exception']) {
    testWidgets('submission closes request client after $outcome',
        (tester) async {
      awards = CmeAwardProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient(
            (_) async => http.Response('{"credited_module_ids":[]}', 200)),
      )..syncAuthToken('A');
      final client = _TrackedClient((_) async {
        if (outcome == 'exception') throw http.ClientException('network');
        return http.Response('{}', outcome == 'success' ? 201 : 500);
      });
      final before = storage['pending_quiz_scores'];
      await http.runWithClient(() async {
        await mount(tester);
        await tester.ensureVisible(find.text('Submit'));
        await tester.runAsync(() => tester.tap(find.text('Submit')));
        await waitUntil(tester, () => client.closes == 1);
        if (outcome == 'success') {
          await waitUntil(
              tester, () => find.text('Success').evaluate().isNotEmpty);
          expect(storage.containsKey('pending_quiz_scores'), isFalse);
        } else {
          expect(storage['pending_quiz_scores'], before);
          expect(find.text('Success'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      }, () => client);
    });
  }

  for (final scenario in ['retry', 'retake', 'dispose', 'late error']) {
    testWidgets('stalled submission times out safely: $scenario',
        (tester) async {
      awards = CmeAwardProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient(
            (_) async => http.Response('{"credited_module_ids":[]}', 200)),
      )..syncAuthToken('A');
      final response = Completer<http.Response>();
      var posts = 0;
      final clients = <_TrackedClient>[];
      final before = storage['pending_quiz_scores'];
      await http.runWithClient(() async {
        await mount(tester,
            submissionTimeout: const Duration(milliseconds: 100));
        await tester.ensureVisible(find.text('Submit'));
        await tester.runAsync(() async {
          await tester.tap(find.text('Submit'));
          await tester.tap(find.text('Submit'));
        });
        expect(posts, 1);
        if (scenario == 'retake') {
          final repository = tester
              .element(find.byType(SubmitCredits))
              .read<PendingQuizScoreRepository>();
          await repository.save(
              moduleId: '1234', moduleName: 'Retake', score: 88);
        }
        final pending = storage['pending_quiz_scores'];
        if (scenario == 'dispose') {
          await tester.pumpWidget(const SizedBox());
        }
        await waitUntil(tester, () => clients.first.closes == 1);
        expect(storage['pending_quiz_scores'], pending);
        expect(posts, 1); // No automatic retry.
        if (scenario != 'dispose') {
          expect(find.textContaining('submission could not be confirmed'),
              findsOneWidget);
        }
        if (scenario == 'late error') {
          response.completeError(http.ClientException('late failure'));
        } else {
          response.complete(http.Response('{}', 201));
        }
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
        expect(storage['pending_quiz_scores'], pending);
        expect(find.text('Success'), findsNothing);
        expect(clients.first.closes, 1);
        if (scenario == 'retry') {
          expect(pending, before);
          await tester.runAsync(() => tester.tap(find.text('Submit')));
          await waitUntil(
              tester, () => find.text('Success').evaluate().isNotEmpty);
          expect(posts, 2);
          expect(clients.last.closes, 1);
          expect(storage.containsKey('pending_quiz_scores'), isFalse);
        }
        expect(tester.takeException(), isNull);
      }, () {
        final client = _TrackedClient((_) async =>
            ++posts == 1 ? await response.future : http.Response('{}', 200));
        clients.add(client);
        return client;
      });
    });
  }

  for (final failure in ['none', 'network', 'timeout', 'storage']) {
    testWidgets('successful pending POST survives $failure refresh',
        (tester) async {
      final stalled = Completer<http.Response>();
      var awardCalls = 0, posts = 0;
      awards = CmeAwardProvider(
        requestTimeout: const Duration(milliseconds: 30),
        readToken: () async {
          if (failure == 'storage') throw PlatformException(code: 'storage');
          return 'A';
        },
        clientFactory: () => MockClient((_) async {
          awardCalls++;
          if (failure == 'network') throw StateError('network');
          if (failure == 'timeout') return stalled.future;
          return http.Response('{"credited_module_ids":[42]}', 200);
        }),
      )..syncAuthToken('A');
      await http.runWithClient(() async {
        await mount(tester);
        await tester.ensureVisible(find.text('Submit'));
        await tester.runAsync(() async {
          await tester.tap(find.text('Submit'));
          await tester.tap(find.text('Submit')); // Guard the in-flight POST.
        });
        await waitUntil(
            tester,
            () => find
                .text('Your score has been submitted successfully!')
                .evaluate()
                .isNotEmpty);
        expect(storage.containsKey('pending_quiz_scores'), isFalse);
        expect(posts, 1);
        expect(find.text('An error occurred. Please try again.'), findsNothing);
        // Refresh completion cannot change the successful result.
        await waitUntil(tester, () => !awards.isLoading);
        expect(find.text('Success'), findsOneWidget);
        if (failure == 'timeout') {
          stalled.complete(http.Response('{"credited_module_ids":[999]}', 200));
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          expect(awards.hasEarnedCredit(999), isFalse);
        }
        expect(awardCalls, failure == 'storage' ? 0 : 1);
        expect(posts, 1);
        expect(tester.takeException(), isNull);
      },
          () => MockClient((request) async {
                expect(request.method, 'POST');
                expect(request.url.path, '/quiz-scores');
                expect(jsonDecode(request.body)['module_id'], '1234');
                posts++;
                return http.Response('{}', 201);
              }));
    });
  }

  testWidgets('successful pending bookkeeping preserves other saved scores',
      (tester) async {
    final pendingScores =
        jsonDecode(storage['pending_quiz_scores']!) as Map<String, dynamic>;
    pendingScores['5678'] = {'module_name': 'Z other lesson', 'score': 88.0};
    storage['pending_quiz_scores'] = jsonEncode(pendingScores);
    awards = CmeAwardProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient(
            (_) async => http.Response('{"credited_module_ids":[42]}', 200)))
      ..syncAuthToken('A');
    await http.runWithClient(() async {
      await mount(tester);
      await tester.ensureVisible(find.text('Submit').first);
      await tester.runAsync(() => tester.tap(find.text('Submit').first));
      await waitUntil(tester, () => find.text('Success').evaluate().isNotEmpty);
      expect(
          (jsonDecode(storage['pending_quiz_scores']!) as Map).keys, ['5678']);
      expect(find.text('Your score has been submitted successfully!'),
          findsOneWidget);
    }, () => MockClient((_) async => http.Response('{}', 201)));
  });

  testWidgets('navigation during pending refresh leaves POST successful',
      (tester) async {
    final response = Completer<http.Response>();
    var posts = 0;
    awards = CmeAwardProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient((_) => response.future))
      ..syncAuthToken('A');
    await http.runWithClient(() async {
      await mount(tester);
      await tester.ensureVisible(find.text('Submit'));
      await tester.runAsync(() => tester.tap(find.text('Submit')));
      await waitUntil(tester, () => find.text('Success').evaluate().isNotEmpty);
      expect(awards.isLoading, isTrue);
      expect(storage.containsKey('pending_quiz_scores'), isFalse);
      await tester.pumpWidget(const SizedBox());
      response.completeError(StateError('refresh failed after navigation'));
      await waitUntil(tester, () => !awards.isLoading);
      expect(posts, 1);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((_) async {
              posts++;
              return http.Response('{}', 200);
            }));
  });

  testWidgets('navigation during pending POST does not skip bookkeeping',
      (tester) async {
    final response = Completer<http.Response>();
    var posts = 0;
    awards = CmeAwardProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient(
            (_) async => http.Response('{"credited_module_ids":[42]}', 200)))
      ..syncAuthToken('A');
    await http.runWithClient(() async {
      await mount(tester);
      await tester.ensureVisible(find.text('Submit'));
      await tester.runAsync(() => tester.tap(find.text('Submit')));
      await tester.pumpWidget(const SizedBox());
      response.complete(http.Response('{}', 200));
      await waitUntil(
          tester, () => !storage.containsKey('pending_quiz_scores'));
      await waitUntil(tester, () => !awards.isLoading);
      expect(posts, 1);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((_) {
              posts++;
              return response.future;
            }));
  });
  testWidgets('successful pending POST survives pending cleanup failure',
      (tester) async {
    failPendingCleanup = true;
    var posts = 0;
    awards = CmeAwardProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient(
            (_) async => http.Response('{"credited_module_ids":[42]}', 200)))
      ..syncAuthToken('A');
    await http.runWithClient(() async {
      await mount(tester);
      await tester.ensureVisible(find.text('Submit'));
      await tester.runAsync(() => tester.tap(find.text('Submit')));
      await waitUntil(tester, () => find.text('Success').evaluate().isNotEmpty);
      await waitUntil(tester, () => !awards.isLoading);
      expect(posts, 1);
      expect(
          find.textContaining('Local cleanup was incomplete'), findsOneWidget);
      expect(storage.containsKey('pending_quiz_scores'), isTrue);
      expect(find.text('An error occurred. Please try again.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((_) async {
              posts++;
              return http.Response('{}', 201);
            }));
  });
  for (final size in [const Size(1000, 1600), const Size(1600, 1000)]) {
    for (final malformed in [false, true]) {
      testWidgets('load failure shows Retry and recovers: $malformed at $size',
          (tester) async {
        awards = CmeAwardProvider()..syncAuthToken('A');
        if (malformed) {
          storage['pending_quiz_scores'] = '{"1234":{"score":95},"broken":42}';
        } else {
          failPendingRead = true;
        }
        final original = storage['pending_quiz_scores'];
        await mount(tester, expectScore: false, size: size);
        expect(find.textContaining('Saved scores could not be loaded'),
            findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.textContaining('No saved scores yet.'), findsNothing);
        expect(storage['pending_quiz_scores'], original);
        failPendingRead = false;
        if (malformed) {
          // Simulate external repair; the UI itself must not reset the data.
          storage['pending_quiz_scores'] = jsonEncode({
            '1234': {'score': 95, 'module_name': 'Test lesson'}
          });
        }
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('95.00'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final score in [0, 0.5, 50, 100]) {
    testWidgets('submits valid score $score without changing the API contract',
        (tester) async {
      storage['pending_quiz_scores'] = jsonEncode({
        '1234': {'module_name': 'Test lesson', 'score': score}
      });
      awards = CmeAwardProvider(
          readToken: () async => 'A',
          clientFactory: () => MockClient(
              (_) async => http.Response('{"credited_module_ids":[]}', 200)))
        ..syncAuthToken('A');
      var posts = 0;
      await http.runWithClient(() async {
        await mount(tester, expectScore: false);
        await tester.ensureVisible(find.text('Submit'));
        await tester.runAsync(() => tester.tap(find.text('Submit')));
        await waitUntil(
            tester, () => find.text('Success').evaluate().isNotEmpty);
        expect(posts, 1);
        expect(storage.containsKey('pending_quiz_scores'), isFalse);
      },
          () => MockClient((request) async {
                final body = jsonDecode(request.body) as Map;
                expect(body.keys.toSet(), {'module_id', 'score', 'date_taken'});
                expect(body['score'], score);
                posts++;
                return http.Response('{"passed":false,"credits_awarded":0}',
                    score == 0 ? 200 : 201);
              }));
    });
  }
  for (final status in [401, 403, 404]) {
    for (final detailed in [false, true]) {
      testWidgets(
          'HTTP $status preserves score and explains recovery ($detailed)',
          (tester) async {
        awards = CmeAwardProvider()..syncAuthToken('A');
        final before = Map<String, String>.from(storage);
        await http.runWithClient(() async {
          await mount(tester);
          await tester.ensureVisible(find.text('Submit'));
          await tester.runAsync(() => tester.tap(find.text('Submit')));
          await waitUntil(
              tester,
              () => find
                  .textContaining('Your score remains saved on this device.')
                  .evaluate()
                  .isNotEmpty);
          if (status == 401) {
            expect(find.textContaining('Please log in again'), findsOneWidget);
          }
          if (status == 403) {
            expect(
                find.textContaining(detailed
                    ? 'You must be enrolled in this class.'
                    : 'permission'),
                findsOneWidget);
            expect(find.textContaining('archived'), findsNothing);
          }
          if (status == 404) {
            expect(
                find.textContaining(
                    'module could not be found or is unavailable'),
                findsOneWidget);
          }
          expect(find.text('Success'), findsNothing);
          expect(storage, before);
          expect(awards.isLoading, isFalse);
        },
            () => MockClient((_) async => http.Response(
                detailed
                    ? '{"message":"You must be enrolled in this class."}'
                    : 'not JSON',
                status)));
      });
    }
  }
  for (final token in [null, '']) {
    testWidgets('missing authentication shows login message ($token)',
        (tester) async {
      auth.token = token;
      awards = CmeAwardProvider();
      var posts = 0;
      final before = Map<String, String>.from(storage);
      await http.runWithClient(() async {
        await mount(tester);
        await tester.ensureVisible(find.text('Submit'));
        await tester.tap(find.text('Submit'));
        await tester.pump();
        expect(find.textContaining('Please log in before submitting'),
            findsOneWidget);
        expect(storage, before);
        expect(posts, 0);
      },
          () => MockClient((_) async {
                posts++;
                return http.Response('{}', 200);
              }));
    });
  }
  for (final timeout in [false, true]) {
    testWidgets(
        'uncertain request preserves pending score and allows retry ($timeout)',
        (tester) async {
      awards = CmeAwardProvider(
          readToken: () async => 'A',
          clientFactory: () => MockClient(
              (_) async => http.Response('{"credited_module_ids":[]}', 200)))
        ..syncAuthToken('A');
      var calls = 0;
      final before = Map<String, String>.from(storage);
      await http.runWithClient(() async {
        await mount(tester);
        await tester.ensureVisible(find.text('Submit'));
        await tester.runAsync(() => tester.tap(find.text('Submit')));
        await waitUntil(
            tester,
            () => find
                .textContaining('submission could not be confirmed')
                .evaluate()
                .isNotEmpty);
        expect(storage, before);
        expect(find.text('Success'), findsNothing);
        await tester.runAsync(() => tester.tap(find.text('Submit')));
        await waitUntil(
            tester, () => find.text('Success').evaluate().isNotEmpty);
        expect(calls, 2);
        expect(storage.containsKey('pending_quiz_scores'), isFalse);
      },
          () => MockClient((_) async {
                if (++calls == 1) {
                  if (timeout) throw TimeoutException('response lost');
                  throw http.ClientException('connection lost');
                }
                return http.Response(
                    '{"passed":false,"credits_awarded":0}', 200);
              }));
    });
  }
  for (final change in [
    'different score',
    'same score',
    'unknown fields',
    'absent'
  ]) {
    testWidgets('acknowledged POST conditionally cleans up: $change',
        (tester) async {
      storage['pending_quiz_scores'] = jsonEncode({
        '1234': {
          'module_name': 'Test lesson',
          'score': 95,
          'date_saved': '2000-01-01',
          'extra': {
            'nested': [1]
          }
        }
      });
      awards = CmeAwardProvider(
          readToken: () async => 'A',
          clientFactory: () => MockClient(
              (_) async => http.Response('{"credited_module_ids":[]}', 200)))
        ..syncAuthToken('A');
      final response = Completer<http.Response>();
      var posts = 0;
      await http.runWithClient(() async {
        await mount(tester);
        await tester.ensureVisible(find.text('Submit'));
        await tester.runAsync(() => tester.tap(find.text('Submit')));
        await waitUntil(tester, () => posts == 1);
        final repository = tester
            .element(find.byType(SubmitCredits))
            .read<PendingQuizScoreRepository>();
        if (change == 'absent') {
          await repository.remove('1234');
        } else if (change == 'unknown fields') {
          final data = jsonDecode(storage['pending_quiz_scores']!) as Map;
          data['1234']['extra']['nested'][0] = 2;
          storage['pending_quiz_scores'] = jsonEncode(data);
        } else {
          await repository.save(
              moduleId: '1234',
              moduleName: 'Test lesson',
              score: change == 'different score' ? 88 : 95);
        }
        final updated = storage['pending_quiz_scores'];
        response.complete(http.Response('{}', 200));
        await waitUntil(
            tester, () => find.text('Success').evaluate().isNotEmpty);
        expect(
            find.textContaining('Local cleanup was incomplete'), findsNothing);
        expect(storage['pending_quiz_scores'], updated);
        if (change != 'absent') {
          expect(find.textContaining('A newer saved result was kept'),
              findsOneWidget);
          Navigator.of(tester.element(find.text('Success'))).pop();
          await waitUntil(
              tester,
              () =>
                  find.text('Submit').evaluate().isNotEmpty &&
                  find.byType(CircularProgressIndicator).evaluate().isEmpty);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.ensureVisible(find.text('Submit'));
          await tester.runAsync(() => tester.tap(find.text('Submit')));
          await waitUntil(
              tester, () => find.text('Success').evaluate().isNotEmpty);
          expect(posts, 2);
          expect(storage.containsKey('pending_quiz_scores'), isFalse);
        }
      },
          () => MockClient((_) async =>
              ++posts == 1 ? await response.future : http.Response('{}', 201)));
    });
  }
  testWidgets(
      'legacy nine-digit key uses four-digit POST but original-key cleanup',
      (tester) async {
    storage['pending_quiz_scores'] = jsonEncode({
      '123456789': {'module_name': 'Test lesson', 'score': 95},
      '5678': {'module_name': 'Z other lesson', 'score': 88},
    });
    awards = CmeAwardProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient(
            (_) async => http.Response('{"credited_module_ids":[]}', 200)))
      ..syncAuthToken('A');
    await http.runWithClient(() async {
      await mount(tester);
      await tester.ensureVisible(find.text('Submit').first);
      await tester.runAsync(() => tester.tap(find.text('Submit').first));
      await waitUntil(tester, () => find.text('Success').evaluate().isNotEmpty);
      expect(
          (jsonDecode(storage['pending_quiz_scores']!) as Map).keys, ['5678']);
    },
        () => MockClient((request) async {
              expect(jsonDecode(request.body)['module_id'], '6789');
              return http.Response('{"quizScore":{"module_id":42}}', 201);
            }));
  });
  for (final failure in ['read', 'write']) {
    testWidgets(
        'accepted POST remains successful after conditional cleanup $failure failure',
        (tester) async {
      storage['pending_quiz_scores'] = jsonEncode({
        '1234': {'module_name': 'Test lesson', 'score': 95},
        '5678': {'module_name': 'Z other lesson', 'score': 88},
      });
      final before = storage['pending_quiz_scores'];
      awards = CmeAwardProvider(
          readToken: () async => 'A',
          clientFactory: () => MockClient(
              (_) async => http.Response('{"credited_module_ids":[]}', 200)))
        ..syncAuthToken('A');
      await http.runWithClient(() async {
        await mount(tester);
        await tester.ensureVisible(find.text('Submit').first);
        await tester.runAsync(() => tester.tap(find.text('Submit').first));
        await waitUntil(
            tester, () => find.text('Success').evaluate().isNotEmpty);
        expect(find.textContaining('Local cleanup was incomplete'),
            findsOneWidget);
        expect(find.textContaining('submission could not be confirmed'),
            findsNothing);
        expect(storage['pending_quiz_scores'], before);
      },
          () => MockClient((_) async {
                failPendingRead = failure == 'read';
                failPendingWrite = failure == 'write';
                return http.Response('{}', 201);
              }));
    });
  }
}
