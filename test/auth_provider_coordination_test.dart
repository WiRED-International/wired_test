import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wired_test/providers/auth_provider.dart';
import 'package:wired_test/providers/quiz_score_provider.dart';

typedef _Snapshot = ({
  String? token,
  bool signedIn,
  bool loading,
  Map<String, String> persisted
});

class _Pause {
  final entered = Completer<void>();
  final release = Completer<void>();
}

class _Storage {
  final values = <String, String>{};
  final calls = <String>[];
  Future<void> Function(MethodCall call, String key)? before;

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments as Map;
    final key = args['key'] as String;
    calls.add('${call.method}:$key');
    // A delayed read can deliver a value captured before a concurrent mutation.
    final readValue = values[key];
    await before?.call(call, key);
    switch (call.method) {
      case 'read':
        return readValue;
      case 'write':
        values[key] = args['value'] as String;
        return null;
      case 'delete':
        values.remove(key);
        return null;
    }
    throw StateError('Unexpected storage operation ${call.method}');
  }

  _Pause pauseFirst(String method, String key) {
    final pause = _Pause();
    var intercepted = false;
    before = (call, actualKey) async {
      if (!intercepted && call.method == method && actualKey == key) {
        intercepted = true;
        pause.entered.complete();
        await pause.release.future;
      }
    };
    return pause;
  }

  void fail(String method, String key) {
    before = (call, actualKey) async {
      if (call.method == method && actualKey == key) {
        throw PlatformException(code: 'controlled-storage-failure');
      }
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final expiryA = DateTime.utc(2098);
  final expiryB = DateTime.utc(2099);
  late _Storage storage;
  late AuthProvider auth;
  late List<_Snapshot> notifications;
  var disposed = false;

  _Snapshot snapshot() => (
        token: auth.authToken,
        signedIn: auth.isLoggedIn,
        loading: auth.isLoading,
        persisted: Map<String, String>.unmodifiable(storage.values),
      );

  setUp(() {
    disposed = false;
    storage = _Storage();
    auth = AuthProvider();
    notifications = [];
    auth.addListener(() => notifications.add(snapshot()));
    messenger.setMockMethodCallHandler(channel, storage.handle);
  });
  tearDown(() {
    if (!disposed) auth.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Map<String, String> credentials(String token, DateTime expiry) => {
        'authToken': token,
        'tokenExpiry': expiry.toIso8601String(),
      };

  void expectCommitted(String? token, DateTime? expiry) {
    expect(auth.authToken, token);
    expect(auth.isLoggedIn, token != null);
    expect(
        storage.values, token == null ? isEmpty : credentials(token, expiry!));
  }

  test(
      'REGRESSION overlapping logins cannot leave older persisted credentials with newer memory',
      () async {
    final pause = storage.pauseFirst('write', 'authToken');
    final older = auth.logIn('A', expiryA);
    await pause.entered.future;
    final newer = auth.logIn('B', expiryB);
    await pumpEventQueue(); // Drain only unblocked work; no elapsed-time race.
    final afterNewer = snapshot();
    pause.release.complete();
    await Future.wait([older, newer]);
    // This assertion accepts a future serialized implementation that keeps A
    // unpublished while B waits; the final committed outcome must still be B.
    if (afterNewer.token == 'B') {
      expect(afterNewer.persisted, credentials('B', expiryB));
    }
    expectCommitted('B', expiryB);
    expect(
        notifications
            .every((n) => !n.signedIn || n.persisted['authToken'] == n.token),
        isTrue,
        reason: 'A completion must not announce B while storage contains A');
  });

  test(
      'REGRESSION login then logout cannot recreate credentials after logout completes',
      () async {
    final pause = storage.pauseFirst('write', 'tokenExpiry');
    final older = auth.logIn('A', expiryA);
    await pause.entered.future;
    final newer = auth.logOut();
    await pumpEventQueue();
    pause.release.complete();
    await Future.wait([older, newer]);
    expectCommitted(null, null);
    expect(notifications.last.persisted, isEmpty);
  });

  test('REGRESSION logout then login cannot delete the newer session',
      () async {
    await auth.logIn('A', expiryA);
    notifications.clear();
    final pause = storage.pauseFirst('delete', 'authToken');
    final older = auth.logOut();
    await pause.entered.future;
    final newer = auth.logIn('B', expiryB);
    await pumpEventQueue();
    pause.release.complete();
    await Future.wait([older, newer]);
    expectCommitted('B', expiryB);
  });

  for (final logout in [false, true]) {
    test(
        'REGRESSION delayed restoration cannot overwrite explicit ${logout ? 'logout' : 'login'}',
        () async {
      storage.values.addAll(credentials('A', expiryA));
      if (logout) await auth.loadStoredAuthData();
      notifications.clear();
      final pause = storage.pauseFirst('read', 'authToken');
      final restoring = auth.loadStoredAuthData();
      await pause.entered.future;
      final explicit = logout ? auth.logOut() : auth.logIn('B', expiryB);
      await pumpEventQueue();
      pause.release.complete();
      await Future.wait([restoring, explicit]);
      expect(auth.isLoading, isFalse);
      expectCommitted(logout ? null : 'B', logout ? null : expiryB);
    });
  }

  for (final key in ['authToken', 'tokenExpiry']) {
    test(
        'CHARACTERIZATION $key write failure preserves committed memory despite partial storage; later login recovers',
        () async {
      await auth.logIn('A', expiryA);
      notifications.clear();
      storage.fail('write', key);
      await expectLater(
          auth.logIn('B', expiryB), throwsA(isA<PlatformException>()));
      expect(notifications, isEmpty);
      expect(auth.authToken, 'A'); // Failed login never publishes B.
      expect(auth.isLoggedIn, isTrue);
      expect(
          storage.values, credentials(key == 'authToken' ? 'A' : 'B', expiryA));
      storage.before = null;
      await auth.logIn('C', expiryB);
      expectCommitted('C', expiryB);
      expect(notifications, hasLength(1));
    });

    test(
        'REGRESSION $key write failure must not publish an uncommitted session through getters',
        () async {
      await auth.logIn('A', expiryA);
      notifications.clear();
      storage.fail('write', key);
      await expectLater(
          auth.logIn('B', expiryB), throwsA(isA<PlatformException>()));
      expect(notifications, isEmpty);
      // Deliberately does not prescribe rollback/journaling of partial storage.
      expect(auth.authToken, 'A');
      expect(auth.isLoggedIn, isTrue);
      expect(auth.isTokenExpired(), isFalse);
    });

    test(
        'CHARACTERIZATION $key delete failure does not report successful logout; later logout recovers',
        () async {
      await auth.logIn('A', expiryA);
      notifications.clear();
      storage.fail('delete', key);
      await expectLater(auth.logOut(), throwsA(isA<PlatformException>()));
      expect(auth.authToken, 'A');
      expect(auth.isLoggedIn, isTrue);
      expect(notifications, isEmpty);
      expect(
          storage.values,
          key == 'authToken'
              ? credentials('A', expiryA)
              : {'tokenExpiry': expiryA.toIso8601String()});
      storage.before = null;
      await auth.logOut();
      expectCommitted(null, null);
      expect(notifications, hasLength(1));
      expect(notifications.single.signedIn, isFalse);
    });

    test(
        'CHARACTERIZATION $key restoration read failure preserves storage and later restoration recovers',
        () async {
      storage.values.addAll(credentials('A', expiryA));
      storage.fail('read', key);
      await auth.loadStoredAuthData(); // Read failures are contained today.
      expect(auth.isLoading, isFalse);
      expect(auth.isLoggedIn, isFalse);
      expect(auth.authToken, isNull); // No partial restoration is published.
      expect(storage.values, credentials('A', expiryA));
      expect(notifications.map((n) => n.loading), [true, false]);
      expect(notifications.last.signedIn, isFalse);
      storage.before = null;
      await auth.loadStoredAuthData();
      expectCommitted('A', expiryA);
      expect(auth.isLoading, isFalse);
    });
  }

  test(
      'REGRESSION pending login keeps the last committed session observable until persistence finishes',
      () async {
    await auth.logIn('A', expiryA);
    notifications.clear();
    final pause = storage.pauseFirst('write', 'tokenExpiry');
    final login = auth.logIn('B', expiryB);
    await pause.entered.future;
    final pending = snapshot();
    pause.release.complete();
    await login;
    expectCommitted('B', expiryB);
    expect(notifications, hasLength(1));
    expect(notifications.single.persisted, credentials('B', expiryB));
    expect(pending.token, 'A',
        reason: 'Getters must not publish B before persistence succeeds');
  });

  test(
      'CHARACTERIZATION successful sequential operations notify only after their storage steps',
      () async {
    await auth.loadStoredAuthData();
    notifications.clear();
    await auth.logIn('A', expiryA);
    await auth.logOut();
    expect(notifications.map((n) => n.token), ['A', null]);
    expect(notifications.first.persisted, credentials('A', expiryA));
    expect(notifications.last.persisted, isEmpty);
    expectCommitted(null, null);
  });

  test(
      'CHARACTERIZATION reused token sessions are distinguishable through intervening logout notifications',
      () async {
    await auth.logIn('same-token', expiryA);
    await auth.logOut();
    await auth.logIn('same-token', expiryB);
    expect(
        notifications.map((n) => n.token), ['same-token', null, 'same-token']);
    expect(notifications.map((n) => n.signedIn), [true, false, true]);
    expectCommitted('same-token', expiryB);
    // No session revision is currently exposed; notification transitions are
    // the existing observable distinction, not token inequality.
  });

  test(
      'CHARACTERIZATION valid credentials survive provider disposal and restart',
      () async {
    await auth.logIn('persistent-token', expiryB);
    auth.dispose();
    expect(storage.values, credentials('persistent-token', expiryB));
    auth = AuthProvider();
    auth.addListener(() => notifications.add(snapshot()));
    notifications.clear();
    await auth.loadStoredAuthData();
    expectCommitted('persistent-token', expiryB);
    expect(auth.isLoading, isFalse);
    expect(notifications.map((n) => n.loading), [true, false]);
    expect(storage.calls.where((c) => c.startsWith('delete:')), isEmpty);
  });

  for (final fixture in [
    <String, String>{},
    {'authToken': 'A'},
    {'tokenExpiry': '2099-01-01T00:00:00.000Z'},
    {'authToken': 'A', 'tokenExpiry': 'not-a-date'},
    {'authToken': 'A', 'tokenExpiry': '2000-01-01T00:00:00.000Z'},
  ]) {
    test(
        'CHARACTERIZATION missing/malformed/expired persisted pair does not authenticate: $fixture',
        () async {
      storage.values.addAll(fixture);
      await auth.loadStoredAuthData();
      expect(auth.isLoggedIn, isFalse);
      expect(auth.isLoading, isFalse);
      expect(storage.values, fixture,
          reason: 'Restoration must not destructively delete credentials');
      expect(storage.calls.where((c) => c.startsWith('delete:')), isEmpty);
    });
  }

  test('REGRESSION empty stored token cannot authenticate despite valid expiry',
      () async {
    storage.values.addAll(credentials('', expiryB));
    await auth.loadStoredAuthData();
    expect(auth.isLoading, isFalse);
    expect(storage.values, credentials('', expiryB));
    expect(auth.isLoggedIn, isFalse);
  });

  test(
      'REGRESSION every login completion notification describes persisted credentials',
      () async {
    final pause = storage.pauseFirst('write', 'authToken');
    final older = auth.logIn('A', expiryA);
    await pause.entered.future;
    final newer = auth.logIn('B', expiryB);
    await pumpEventQueue();
    pause.release.complete();
    await Future.wait([older, newer]);
    expect(notifications, isNotEmpty);
    for (final event in notifications.where((n) => n.signedIn)) {
      expect(event.persisted['authToken'], event.token,
          reason:
              'A notification must not publish one account with another account persisted');
    }
  });

  test(
      'CHARACTERIZATION restoration trusts stored expiry rather than validating token format',
      () async {
    storage.values.addAll(credentials('not-a-jwt', expiryB));
    await auth.loadStoredAuthData();
    expectCommitted('not-a-jwt', expiryB);
    // Do not silently introduce backend validation or stricter JWT contracts.
  });

  for (final status in <int?>[null, 401, 503]) {
    test(
        'CHARACTERIZATION score HTTP $status does not log out a valid persisted session',
        () async {
      dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
      addTearDown(dotenv.clean);
      await auth.logIn('A', expiryA);
      notifications.clear();
      final client = MockClient((request) async {
        expect(request.url.path, '/quiz-scores');
        expect(request.headers['authorization'], 'Bearer A');
        if (status == null) {
          throw http.ClientException('Controlled network failure');
        }
        return http.Response('{}', status);
      });
      final scores = QuizScoreProvider(clientFactory: () => client)
        ..syncAuthProvider(auth);
      addTearDown(scores.dispose);
      await scores.fetchQuizScores();
      expectCommitted('A', expiryA);
      expect(notifications, isEmpty);
      expect(storage.calls.where((c) => c.startsWith('delete:')), isEmpty);
    });
  }
  test('a queued login proceeds after the preceding queued operation fails',
      () async {
    await auth.logIn('A', expiryA);
    notifications.clear();
    final gate = _Pause();
    var first = true;
    storage.before = (call, key) async {
      if (call.method == 'write' && key == 'tokenExpiry' && first) {
        first = false;
        gate.entered.complete();
        await gate.release.future;
        throw PlatformException(code: 'first-write-failed');
      }
    };
    final failing = auth.logIn('B', expiryB);
    final failure = expectLater(failing, throwsA(isA<PlatformException>()));
    await gate.entered.future;
    final succeeding = auth.logIn('C', expiryB);
    gate.release.complete();
    await failure;
    await succeeding;
    expectCommitted('C', expiryB);
    expect(notifications.map((event) => event.token), ['C']);
  });

  for (final key in ['authToken', 'tokenExpiry']) {
    test('restoration $key read failure preserves an already committed session',
        () async {
      await auth.logIn('A', expiryA);
      storage.fail('read', key);
      await auth.loadStoredAuthData();
      expectCommitted('A', expiryA);
      expect(auth.isLoading, isFalse);
    });
  }

  for (final operation in ['login', 'logout', 'restoration']) {
    test(
        'disposal during $operation suppresses notifications and rejects queued work',
        () async {
      await auth.logIn('A', expiryA);
      notifications.clear();
      final method = operation == 'login'
          ? 'write'
          : operation == 'logout'
              ? 'delete'
              : 'read';
      final gate = storage.pauseFirst(method, 'authToken');
      final running = operation == 'login'
          ? auth.logIn('B', expiryB)
          : operation == 'logout'
              ? auth.logOut()
              : auth.loadStoredAuthData();
      await gate.entered.future;
      final queued = auth.logIn('never-written', expiryB);
      final rejection = expectLater(queued, throwsA(isA<StateError>()));
      final notificationCount = notifications.length;
      auth.dispose();
      disposed = true;
      gate.release.complete();
      await running;
      await rejection;
      expect(notifications, hasLength(notificationCount));
      expect(storage.values['authToken'], isNot('never-written'));
      // Finish the active storage operation; disposal must not create a new
      // partial pair by interrupting it between its two storage steps.
      if (operation == 'login') {
        expect(storage.values, credentials('B', expiryB));
      } else if (operation == 'logout') {
        expect(storage.values, isEmpty);
      } else {
        expect(storage.values, credentials('A', expiryA));
      }
    });
  }
  test(
      'conditional logout checks ownership inside the queue and skips without writes or notification',
      () async {
    await auth.logIn('A', expiryA);
    final gate = storage.pauseFirst('write', 'tokenExpiry');
    final login = auth.logIn('B', expiryB);
    await gate.entered.future;
    var conditionCalls = 0;
    notifications.clear();
    final logout = auth.logOut(ifOwned: () {
      conditionCalls++;
      return auth.authToken == 'A';
    });
    expect(conditionCalls, 0);
    gate.release.complete();
    await login;
    expect(await logout, isFalse);
    expect(conditionCalls, 1);
    expectCommitted('B', expiryB);
    expect(notifications.map((n) => n.token), ['B']);
    expect(storage.calls.where((c) => c.startsWith('delete:')), isEmpty);
    expect(await auth.logOut(), isTrue);
    expectCommitted(null, null);
  });

  test(
      'conditional logout accepts valid ownership and propagates storage failure',
      () async {
    await auth.logIn('A', expiryA);
    storage.fail('delete', 'tokenExpiry');
    await expectLater(
        auth.logOut(ifOwned: () => true), throwsA(isA<PlatformException>()));
    expect(auth.authToken, 'A');
    storage.before = null;
    expect(await auth.logOut(ifOwned: () => true), isTrue);
    expectCommitted(null, null);
  });
}
