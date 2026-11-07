import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wired_test/services/browse_catalog_repository.dart';

void main() {
  final uri = Uri.parse('https://example.invalid/modules/');
  test('fetch, fresh reuse, exact TTL expiry and forced refresh', () async {
    var now = DateTime.utc(2026);
    var calls = 0;
    final client = MockClient((request) async {
      expect(
          request.headers['Content-Type'], 'application/json; charset=utf-8');
      return http.Response('[${++calls}]', 200);
    });
    addTearDown(client.close);
    final repo = BrowseCatalogRepository(client: client, clock: () => now);
    expect(await repo.fetchListBody(uri), '[1]');
    now = now.add(const Duration(seconds: 59));
    expect(await repo.fetchListBody(uri), '[1]');
    now = now.add(const Duration(seconds: 1));
    expect(await repo.fetchListBody(uri), '[2]');
    expect(await repo.fetchListBody(uri, forceRefresh: true), '[3]');
    expect(calls, 3);
  });

  test('complete URI keys keep scheme host path and query separate', () async {
    var calls = 0;
    final client = MockClient((_) async => http.Response('[${++calls}]', 200));
    addTearDown(client.close);
    final repo = BrowseCatalogRepository(client: client);
    final uris = [
      uri,
      uri.replace(scheme: 'http'),
      uri.replace(host: 'other.invalid'),
      uri.replace(path: '/modules'),
      uri.replace(query: 'subcategoryId=7'),
      uri.replace(query: 'subcategoryId=8')
    ];
    for (var i = 0; i < uris.length; i++) {
      expect(await repo.fetchListBody(uris[i]), '[${i + 1}]');
    }
    for (var i = 0; i < uris.length; i++) {
      expect(await repo.fetchListBody(uris[i]), '[${i + 1}]');
    }
    expect(calls, uris.length);
  });

  test('concurrent loads share HTTP; forced refresh supersedes old work',
      () async {
    final responses = List.generate(2, (_) => Completer<http.Response>());
    var calls = 0;
    final client = MockClient((_) => responses[calls++].future);
    addTearDown(client.close);
    final repo = BrowseCatalogRepository(client: client);
    final old = repo.fetchListBody(uri);
    final shared = repo.fetchListBody(uri);
    final fresh = repo.fetchListBody(uri, forceRefresh: true);
    final freshShared = repo.fetchListBody(uri);
    responses[1].complete(http.Response('[2]', 200));
    expect(await fresh, '[2]');
    expect(await freshShared, '[2]');
    responses[0].complete(http.Response('[1]', 200));
    expect(await old, '[1]');
    expect(await shared, '[1]');
    expect(await repo.fetchListBody(uri), '[2]');
    expect(calls, 2);
  });

  for (final failure in ['http', 'invalid', 'non-list', 'timeout']) {
    test('$failure is not cached; failed refresh evicts stale data', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        if (calls == 2) {
          if (failure == 'timeout') throw TimeoutException('mock timeout');
          if (failure == 'http') return http.Response('Unavailable', 503);
          return http.Response(failure == 'invalid' ? '{' : '{}', 200);
        }
        return http.Response('[$calls]', 200);
      });
      addTearDown(client.close);
      final repo = BrowseCatalogRepository(client: client);
      expect(await repo.fetchListBody(uri), '[1]');
      await expectLater(
          repo.fetchListBody(uri, forceRefresh: true), throwsA(anything));
      expect(await repo.fetchListBody(uri), '[3]');
      expect(calls, 3);
    });
  }

  testWidgets('25-second deadline releases timed out in-flight request',
      (tester) async {
    var calls = 0;
    final pending = Completer<http.Response>();
    final client = MockClient((_) => ++calls == 1
        ? pending.future
        : Future.value(http.Response('[2]', 200)));
    addTearDown(client.close);
    final repo = BrowseCatalogRepository(client: client);
    final failed =
        expectLater(repo.fetchListBody(uri), throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 25));
    await failed;
    expect(await repo.fetchListBody(uri), '[2]');
    pending.complete(http.Response('[1]', 200));
    await tester.pump();
    expect(await repo.fetchListBody(uri), '[2]');
    expect(calls, 2);
  });

  test('failed refresh cannot be repopulated by older pending success',
      () async {
    final oldResponse = Completer<http.Response>();
    var calls = 0;
    final client = MockClient((_) {
      calls++;
      return calls == 1
          ? oldResponse.future
          : Future.value(http.Response(
              calls == 2 ? 'Unavailable' : '[3]', calls == 2 ? 503 : 200));
    });
    addTearDown(client.close);
    final repo = BrowseCatalogRepository(client: client);
    final old = repo.fetchListBody(uri);
    await expectLater(
        repo.fetchListBody(uri, forceRefresh: true), throwsStateError);
    oldResponse.complete(http.Response('[1]', 200));
    await old;
    expect(await repo.fetchListBody(uri), '[3]');
    expect(calls, 3);
  });

  test('cache evicts oldest entries at its fixed bound', () async {
    var calls = 0;
    final client = MockClient((_) async => http.Response('[${++calls}]', 200));
    addTearDown(client.close);
    final repo = BrowseCatalogRepository(client: client);
    for (var i = 0; i <= BrowseCatalogRepository.maxEntries; i++) {
      await repo.fetchListBody(uri.replace(query: 'entry=$i'));
    }
    await repo.fetchListBody(uri.replace(query: 'entry=8'));
    expect(calls, 9);
    await repo.fetchListBody(uri.replace(query: 'entry=0'));
    expect(calls, 10);
  });
}
