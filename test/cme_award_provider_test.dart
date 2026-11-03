import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wired_test/providers/cme_award_provider.dart';

void main() {
  setUp(() =>
      dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid'));

  test('normal requests share storage/network work and then use cache',
      () async {
    final token = Completer<String?>();
    var reads = 0, calls = 0;
    final provider = CmeAwardProvider(
        readToken: () {
          reads++;
          return token.future;
        },
        clientFactory: () => MockClient((_) async {
              calls++;
              return http.Response('{"credited_module_ids":[42,42]}', 200);
            }));
    addTearDown(provider.dispose);
    provider.syncAuthToken('A');
    final first = provider.fetchAwardedModules();
    expect(identical(first, provider.fetchAwardedModules()), isTrue);
    expect(provider.isLoading, isTrue);
    expect(reads, 1);
    token.complete('A');
    await first;
    await provider.fetchAwardedModules();
    expect(calls, 1);
    expect(provider.hasEarnedCredit(42), isTrue);
    expect(provider.hasLoaded, isTrue);
    expect(provider.isLoading, isFalse);
  });

  test('overlapping forced requests coalesce into a subsequent snapshot',
      () async {
    final entered = Completer<void>(),
        firstResponse = Completer<http.Response>();
    var calls = 0;
    final provider = CmeAwardProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient((_) async {
              calls++;
              if (calls == 1) {
                entered.complete();
                return firstResponse.future;
              }
              return http.Response('{"credited_module_ids":[42]}', 200);
            }));
    addTearDown(provider.dispose);
    provider.syncAuthToken('A');
    final first = provider.fetchAwardedModules();
    await entered.future;
    final forced = provider.fetchAwardedModules(forceRefresh: true);
    expect(identical(forced, provider.fetchAwardedModules(forceRefresh: true)),
        isTrue);
    expect(identical(first, provider.fetchAwardedModules()), isTrue);
    firstResponse.complete(http.Response('{"credited_module_ids":[1]}', 200));
    await forced;
    expect(calls, 2);
    expect(provider.hasEarnedCredit(42), isTrue);
    expect(provider.hasEarnedCredit(1), isFalse);
    expect(provider.isLoading, isFalse);
  });

  test('account switch queues a new lookup and rejects the old response',
      () async {
    var token = 'A';
    final entered = Completer<void>(), oldResponse = Completer<http.Response>();
    final headers = <String?>[];
    final provider = CmeAwardProvider(
        readToken: () async => token,
        clientFactory: () => MockClient((request) async {
              headers.add(request.headers['Authorization']);
              if (headers.length == 1) {
                entered.complete();
                return oldResponse.future;
              }
              return http.Response('{"credited_module_ids":[2]}', 200);
            }));
    addTearDown(provider.dispose);
    provider.syncAuthToken(token);
    final operation = provider.fetchAwardedModules();
    await entered.future;
    token = 'B';
    provider.syncAuthToken(token);
    final newRequest = provider.fetchAwardedModules();
    oldResponse.complete(http.Response('{"credited_module_ids":[1]}', 200));
    await Future.wait([operation, newRequest]);
    expect(headers, ['Bearer A', 'Bearer B']);
    expect(provider.hasEarnedCredit(1), isFalse);
    expect(provider.hasEarnedCredit(2), isTrue);
  });

  test(
      'reusing a token after switching sessions never accepts its old snapshot',
      () async {
    final entered = Completer<void>(), response = Completer<http.Response>();
    var calls = 0;
    final provider = CmeAwardProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient((_) async {
              if (++calls == 1) {
                entered.complete();
                return response.future;
              }
              return http.Response('{"credited_module_ids":[2]}', 200);
            }));
    addTearDown(provider.dispose);
    provider.syncAuthToken('A');
    final operation = provider.fetchAwardedModules();
    await entered.future;
    provider.syncAuthToken('B');
    provider.syncAuthToken('A');
    response.complete(http.Response('{"credited_module_ids":[1]}', 200));
    await operation;
    expect(provider.hasEarnedCredit(1), isFalse);
    expect(provider.hasEarnedCredit(2), isTrue);
    expect(calls, 2);
  });

  test('storage failure is contained and a later request recovers', () async {
    var fail = true;
    final provider = CmeAwardProvider(
        readToken: () async {
          if (fail) throw StateError('storage unavailable');
          return 'A';
        },
        clientFactory: () => MockClient(
            (_) async => http.Response('{"credited_module_ids":[42]}', 200)));
    addTearDown(provider.dispose);
    provider.syncAuthToken('A');
    await provider.fetchAwardedModules();
    expect(provider.isLoading, isFalse);
    expect(provider.hasLoaded, isFalse);
    fail = false;
    await provider.fetchAwardedModules();
    expect(provider.hasEarnedCredit(42), isTrue);
  });

  test('storage deadline prevents a late read from starting network work',
      () async {
    final token = Completer<String?>();
    var calls = 0;
    final provider = CmeAwardProvider(
        readToken: () => token.future,
        requestTimeout: const Duration(milliseconds: 20),
        clientFactory: () => MockClient((_) async {
              calls++;
              return http.Response('{}', 200);
            }));
    addTearDown(provider.dispose);
    provider.syncAuthToken('A');
    await provider.fetchAwardedModules();
    expect(provider.isLoading, isFalse);
    token.complete('A');
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);
  });

  test('network timeout ignores late response and permits recovery', () async {
    final oldResponse = Completer<http.Response>();
    var calls = 0;
    final provider = CmeAwardProvider(
        readToken: () async => 'A',
        requestTimeout: const Duration(milliseconds: 20),
        clientFactory: () => MockClient((_) async {
              if (++calls == 1) return oldResponse.future;
              return http.Response('{"credited_module_ids":[42]}', 200);
            }));
    addTearDown(provider.dispose);
    provider.syncAuthToken('A');
    await provider.fetchAwardedModules();
    expect(provider.isLoading, isFalse);
    expect(provider.hasLoaded, isFalse);
    await provider.fetchAwardedModules();
    oldResponse.complete(http.Response('{"credited_module_ids":[1]}', 200));
    await Future<void>.delayed(Duration.zero);
    expect(provider.hasEarnedCredit(1), isFalse);
    expect(provider.hasEarnedCredit(42), isTrue);
  });

  test('HTTP failure releases loading state and normal refresh retries lookup',
      () async {
    var calls = 0;
    final provider = CmeAwardProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient((_) async => ++calls == 1
            ? http.Response('unavailable', 503)
            : http.Response('{"credited_module_ids":[42]}', 200)));
    addTearDown(provider.dispose);
    provider.syncAuthToken('A');
    await provider.fetchAwardedModules();
    expect(provider.isLoading, isFalse);
    await provider.fetchAwardedModules();
    expect(provider.hasEarnedCredit(42), isTrue);
    expect(calls, 2);
  });

  test(
      'account switch is serviced after an old request times out without a new caller',
      () async {
    var token = 'A';
    final entered = Completer<void>(), oldResponse = Completer<http.Response>();
    final headers = <String?>[];
    final provider = CmeAwardProvider(
        readToken: () async => token,
        requestTimeout: const Duration(milliseconds: 20),
        clientFactory: () => MockClient((request) async {
              headers.add(request.headers['Authorization']);
              if (headers.length == 1) {
                entered.complete();
                return oldResponse.future;
              }
              return http.Response('{"credited_module_ids":[2]}', 200);
            }));
    addTearDown(provider.dispose);
    provider.syncAuthToken(token);
    final operation = provider.fetchAwardedModules();
    await entered.future;
    token = 'B';
    provider.syncAuthToken(token);
    await operation;
    expect(headers, ['Bearer A', 'Bearer B']);
    expect(provider.hasEarnedCredit(2), isTrue);
    expect(provider.isLoading, isFalse);
    oldResponse.complete(http.Response('{"credited_module_ids":[1]}', 200));
    await Future<void>.delayed(Duration.zero);
    expect(provider.hasEarnedCredit(1), isFalse);
  });

  test('forced refresh queued behind a failed request still executes',
      () async {
    final entered = Completer<void>(), response = Completer<http.Response>();
    var calls = 0;
    final provider = CmeAwardProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient((_) async {
              if (++calls == 1) {
                entered.complete();
                return response.future;
              }
              return http.Response('{"credited_module_ids":[42]}', 200);
            }));
    addTearDown(provider.dispose);
    provider.syncAuthToken('A');
    final operation = provider.fetchAwardedModules();
    await entered.future;
    final forced = provider.fetchAwardedModules(forceRefresh: true);
    response.completeError(StateError('request failed'));
    await Future.wait([operation, forced]);
    expect(calls, 2);
    expect(provider.hasEarnedCredit(42), isTrue);
    expect(provider.isLoading, isFalse);
  });

  test('failed forced refresh invalidates cache so a normal request recovers',
      () async {
    var calls = 0;
    final provider = CmeAwardProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient((_) async {
              calls++;
              if (calls == 2) return http.Response('unavailable', 503);
              return http.Response('{"credited_module_ids":[42]}', 200);
            }));
    addTearDown(provider.dispose);
    provider.syncAuthToken('A');
    await provider.fetchAwardedModules();
    expect(provider.hasLoaded, isTrue);
    await provider.fetchAwardedModules(forceRefresh: true);
    expect(provider.hasLoaded, isFalse);
    expect(
        provider.hasEarnedCredit(42), isTrue); // Last known data stays visible.
    await provider.fetchAwardedModules();
    expect(provider.hasLoaded, isTrue);
    expect(calls, 3);
  });

  test('logout/disposal prevent late notification or credited data', () async {
    final entered = Completer<void>(), response = Completer<http.Response>();
    final provider = CmeAwardProvider(
        readToken: () async => 'A',
        clientFactory: () => MockClient((_) {
              entered.complete();
              return response.future;
            }));
    provider.syncAuthToken('A');
    final operation = provider.fetchAwardedModules();
    await entered.future;
    provider.syncAuthToken(null);
    provider.dispose();
    response.complete(http.Response('{"credited_module_ids":[42]}', 200));
    await operation;
    expect(provider.hasEarnedCredit(42), isFalse);
    expect(provider.isLoading, isFalse);
  });
}
