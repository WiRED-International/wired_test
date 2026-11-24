import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wired_test/services/download_event_outbox.dart';
import 'package:wired_test/services/download_installation_reporting.dart';
import 'package:wired_test/services/location_service.dart';
import 'package:wired_test/services/module_installation_registry.dart';

class _Legacy extends LocationService {
  int calls = 0;
  @override
  Future<void> saveDownload(
      int moduleId, Map<String, double?>? location) async {
    calls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Box<String> box;
  late DateTime now;
  final owners = <DownloadEventOutbox>[];
  DownloadEventOutbox owner(http.Client client,
      {bool enabled = true, Duration timeout = const Duration(seconds: 15)}) {
    final result = DownloadEventOutbox(box,
        endpoint: Uri.parse('https://example.invalid/api/downloads'),
        client: client,
        now: () => now,
        enabled: enabled,
        timeout: timeout);
    owners.add(result);
    return result;
  }

  Map entry() => jsonDecode(box.get('event:publication')!) as Map;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('download-outbox-test');
    Hive.init(directory.path);
    box = await Hive.openBox<String>(DownloadEventOutbox.boxName);
    now = DateTime.utc(2026, 11, 21);
  });
  tearDown(() async {
    DownloadEventOutbox.current = null;
    initializeDownloadOutbox = null;
    for (final service in owners) {
      service.dispose();
    }
    owners.clear();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
      'failed initialization is explicit and concurrent retry shares one owner',
      () async {
    var attempts = 0;
    final ready = Completer<DownloadEventOutbox>();
    initializeDownloadOutbox = () async {
      attempts++;
      if (attempts == 1) throw StateError('storage unavailable');
      return ready.future;
    };
    await expectLater(
        queueInstalledDownload(42, null, publicationKey: 'publication'),
        throwsStateError);
    expect(box.isEmpty, true);
    expect(DownloadEventOutbox.current, isNull);
    final retry =
        queueInstalledDownload(42, null, publicationKey: 'publication');
    final concurrent =
        queueInstalledDownload(42, null, publicationKey: 'publication');
    final outbox = owner(MockClient((_) async => http.Response('', 200)));
    ready.complete(outbox);
    await Future.wait([retry, concurrent]);
    expect(attempts, 2);
    expect(box.length, 1);
    expect(DownloadEventOutbox.current, same(outbox));
  });

  test(
      'missing identity and failed persistence never acknowledge a queue write',
      () async {
    DownloadEventOutbox.current =
        owner(MockClient((_) async => http.Response('', 200)));
    await expectLater(
        queueInstalledDownload(42, null, publicationKey: ''), throwsStateError);
    expect(box.isEmpty, true);
    await box.close();
    await expectLater(
        queueInstalledDownload(42, null, publicationKey: 'publication'),
        throwsA(isA<HiveError>()));
  });

  test('new publication ignores readable stale registry and old receipt',
      () async {
    final outbox = owner(MockClient((_) async => http.Response('', 200)));
    DownloadEventOutbox.current = outbox;
    final registry = await Hive.openBox(ModuleInstallationRegistry.boxName);
    await registry.put('instructional-db:42', {
      'database_id': 42,
      'installed_at': '2026-01-01T00:00:00.000Z',
    });
    final oldKey =
        instructionalPublicationKey(registry.get('instructional-db:42') as Map);
    await outbox.enqueue(42, null, installationKey: oldKey);
    await outbox.deliver();
    await queueInstalledDownload(42, null,
        publicationKey: 'instructional:42:2026-11-22T00:00:00.000Z');
    final events = box.values.map((v) => jsonDecode(v) as Map).toList();
    expect(events.length, 2);
    expect(events.where((e) => e['status'] == 'pending').length, 1);
    expect(events.map((e) => e['event_id']).toSet().length, 2);
  });

  test(
      'registry unavailable at reporting then reconciliation uses same receipt',
      () async {
    final outbox = owner(MockClient((_) async => http.Response('', 200)));
    DownloadEventOutbox.current = outbox;
    await reconcileDownloadInstallations(outbox);
    final registry = ModuleInstallationRegistry();
    final installedAt = DateTime.now()
        .toUtc()
        .add(const Duration(seconds: 1))
        .toIso8601String();
    await registry.saveInstructionalInstallation(
        databaseId: 42,
        moduleId: '142',
        format: 'compiler',
        contentDirectory: directory.path,
        entryPointPath: '${directory.path}/index.html',
        provenance: 'new-install',
        installedAt: installedAt);
    final record = (await registry.getInstructionalInstallation(42))!;
    final key = instructionalPublicationKey(record);
    final records = Hive.box(ModuleInstallationRegistry.boxName);
    // A malformed/unreadable registry record must not force a fallback key.
    await records.put('instructional-db:42', 'temporarily unreadable');
    await expectLater(
        registry.getInstructionalInstallation(42), throwsStateError);
    // The confirmed installation result is sufficient, without a registry read.
    await queueInstalledDownload(42, null, publicationKey: key);
    final original = box.get('event:$key');
    await reconcileDownloadInstallations(outbox, verify: (_) async => true);
    await records.put('instructional-db:42', record);
    await reconcileDownloadInstallations(outbox, verify: (_) async => true);
    expect(box.get('event:$key'), original);
    await outbox.deliver();
    await reconcileDownloadInstallations(outbox, verify: (_) async => true);
    await queueInstalledDownload(42, null, publicationKey: key);
    expect(box.keys.where((k) => k.startsWith('event:')).length, 1);
    expect((jsonDecode(box.get('event:$key')!) as Map)['status'], 'delivered');
  });

  test('UUID v4 and original anonymous body persist together; one publication',
      () async {
    final outbox = owner(MockClient((_) async => http.Response('', 200)));
    final coordinates = <String, double?>{'latitude': 1, 'longitude': 2};
    await outbox.enqueue(42, coordinates, installationKey: 'publication');
    final original = entry();
    expect(
        original['event_id'],
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    coordinates['latitude'] = 99;
    await outbox.enqueue(42, null, installationKey: 'publication');
    expect(box.length, 1);
    expect(entry(), original);
    await box.close();
    box = await Hive.openBox<String>(DownloadEventOutbox.boxName);
    expect(entry(), original);
    final payload = jsonDecode(entry()['payload_json'] as String) as Map;
    expect(payload, {
      'event_id': original['event_id'],
      'module_id': 42,
      'latitude': 1.0,
      'longitude': 2.0
    });
    expect(payload.containsKey('user_id'), false);
  });

  test(
      'network failure, restart, frozen retry, 200 acknowledgement and receipt',
      () async {
    final bodies = <String>[];
    final first = owner(MockClient((request) async {
      bodies.add(request.body);
      throw const SocketException('offline');
    }));
    await first.enqueue(7, null, installationKey: 'publication');
    await first.deliver();
    expect(entry()['status'], 'pending');
    expect(entry()['attempts'], 1);
    first.dispose();
    await box.close();
    box = await Hive.openBox<String>(DownloadEventOutbox.boxName);
    final restarted = owner(MockClient((request) async {
      bodies.add(request.body);
      expect(request.method, 'POST');
      expect(request.headers.containsKey('authorization'), false);
      return http.Response('', 200);
    }));
    await restarted.deliver();
    expect(bodies.length, 1); // persisted backoff respected
    now = now.add(const Duration(seconds: 5));
    await restarted.deliver();
    expect(bodies.length, 2);
    expect(bodies[0], bodies[1]);
    expect(jsonDecode(bodies[0]), containsPair('latitude', null));
    expect(entry()['status'], 'delivered');
    await restarted.enqueue(7, null, installationKey: 'publication');
    await restarted.deliver();
    expect(bodies.length, 2);
  });

  for (final code in [400, 409]) {
    test('HTTP $code is permanent and retained for inspection', () async {
      var calls = 0;
      final outbox = owner(MockClient((_) async {
        calls++;
        return http.Response('', code);
      }));
      await outbox.enqueue(1, null, installationKey: 'publication');
      await outbox.deliver();
      now = now.add(const Duration(days: 2));
      await outbox.deliver();
      expect(calls, 1);
      expect(entry()['status'], 'permanent_failure');
      expect(entry()['last_status'], code);
    });
  }

  test('transient server errors back off with a one hour bound', () async {
    final outbox = owner(MockClient((_) async => http.Response('', 503)));
    await outbox.enqueue(1, null, installationKey: 'publication');
    for (var i = 0; i < 14; i++) {
      await outbox.deliver();
      final due = DateTime.parse(entry()['next_attempt_at'] as String);
      expect(due.difference(now).inSeconds, lessThanOrEqualTo(3600));
      expect(due.isAfter(now), true);
      now = due;
    }
  });

  test('concurrent drain has only one in-flight attempt', () async {
    final response = Completer<http.Response>();
    final entered = Completer<void>();
    var calls = 0;
    final outbox = owner(MockClient((_) {
      calls++;
      entered.complete();
      return response.future;
    }));
    await outbox.enqueue(1, null, installationKey: 'publication');
    final sending = outbox.deliver();
    await entered.future;
    await outbox.deliver();
    expect(calls, 1);
    response.complete(http.Response('', 200));
    await sending;
  });

  test('explicit timeout retains retryable event', () async {
    final response = Completer<http.Response>();
    final outbox = owner(MockClient((_) => response.future),
        timeout: const Duration(milliseconds: 5));
    await outbox.enqueue(1, null, installationKey: 'publication');
    await outbox.deliver();
    expect(entry()['status'], 'pending');
    expect(entry()['last_error'], 'TimeoutException');
    response.complete(http.Response('', 200));
  });

  test(
      'decline never locates; consent includes available coordinates; failures null',
      () async {
    var calls = 0;
    Future<Map<String, double?>?> locate() async {
      calls++;
      return {'latitude': 3, 'longitude': 4};
    }

    expect(await optionalDownloadCoordinates(consent: false, locate: locate),
        null);
    expect(calls, 0);
    expect(await optionalDownloadCoordinates(consent: true, locate: locate),
        {'latitude': 3.0, 'longitude': 4.0});
    expect(
        await optionalDownloadCoordinates(
            consent: true, locate: () async => throw StateError('denied')),
        null);
    expect(
        await optionalDownloadCoordinates(
            consent: true, locate: () async => null),
        null);
  });

  test('gate off sends no outbox requests or queued backlog; legacy only',
      () async {
    expect(downloadEventOutboxEnabled, false);
    var calls = 0;
    final outbox = owner(MockClient((_) async {
      calls++;
      return http.Response('', 200);
    }), enabled: false);
    await outbox.enqueue(1, null, installationKey: 'publication');
    await outbox.deliver();
    expect(box.isEmpty, true);
    expect(calls, 0);
    final legacy = _Legacy();
    await legacy.reportSuccessfulInstallation(1, null,
        publicationKey: 'publication');
    expect(legacy.calls, 1);
  });

  test(
      'enabled facade queues without legacy POST, duplicate publication deduplicates',
      () async {
    DownloadEventOutbox.current =
        owner(MockClient((_) async => http.Response('', 200)));
    final legacy = _Legacy();
    await legacy.reportSuccessfulInstallation(1, null,
        publicationKey: 'publication');
    await legacy.reportSuccessfulInstallation(1, null,
        publicationKey: 'publication');
    expect(legacy.calls, 0);
    expect(box.length, 1);
  });

  test(
      'reconciliation excludes history, verifies new records, retains receipts',
      () async {
    final outbox = owner(MockClient((_) async => http.Response('', 200)));
    final registry = ModuleInstallationRegistry();
    await Hive.openBox(ModuleInstallationRegistry.boxName);
    Future<void> record(int id) => registry.saveInstructionalInstallation(
        databaseId: id,
        moduleId: '$id',
        format: 'compiler',
        contentDirectory: directory.path,
        entryPointPath: '${directory.path}/index.html',
        provenance: 'new-install',
        installedAt:
            id == 1 ? '2020-01-01T00:00:00.000Z' : '2099-01-01T00:00:00.000Z');
    await record(1);
    await box.put('activated_at', DateTime.now().toUtc().toIso8601String());
    await record(2);
    await record(3);
    await reconcileDownloadInstallations(outbox,
        verify: (record) async => record['database_id'] == 2);
    expect(box.keys.where((key) => key.startsWith('event:')).length, 1);
    await outbox.deliver();
    await reconcileDownloadInstallations(outbox, verify: (_) async => true);
    // Third record now verifies; the delivered second record is not recreated.
    expect(box.keys.where((key) => key.startsWith('event:')).length, 2);
    final entries = box.keys
        .where((k) => k.startsWith('event:'))
        .map((k) => jsonDecode(box.get(k)!) as Map)
        .toList();
    expect(entries.where((e) => e['status'] == 'delivered').length, 1);
  });

  test(
      'activation and re-enable exclude existing publications with future dates',
      () async {
    final outbox = owner(MockClient((_) async => http.Response('', 200)));
    final registry = await Hive.openBox(ModuleInstallationRegistry.boxName);
    await registry.put('instructional-db:9', {
      'schema_version': 1,
      'database_id': 9,
      'module_id': '109',
      'format': 'compiler',
      'content_directory': directory.path,
      'entry_point_path': '${directory.path}/index.html',
      'installed_at': '2099-01-01T00:00:00.000Z',
      'provenance': 'new-install',
    });
    await reconcileDownloadInstallations(outbox, verify: (_) async => true);
    expect(box.keys.where((k) => k.startsWith('event:')), isEmpty);
    // A gate-off run may have reported these through legacy POST.
    await box.put('paused', 'true');
    final next =
        Map<String, dynamic>.from(registry.get('instructional-db:9') as Map)
          ..['database_id'] = 10;
    await registry.put('instructional-db:10', next);
    await reconcileDownloadInstallations(outbox, verify: (_) async => true);
    expect(box.keys.where((k) => k.startsWith('event:')), isEmpty);
  });
}
