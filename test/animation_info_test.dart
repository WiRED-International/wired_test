import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wired_test/pages/animations/animation_info.dart';
import 'package:wired_test/pages/animations/animation_list.dart' as catalog;
import 'package:wired_test/services/animation_installation_coordinator.dart';
import 'package:wired_test/services/animation_preparation_service.dart';
import 'package:wired_test/services/animation_private_download_service.dart';
import 'package:wired_test/services/animation_storage_service.dart';
import 'package:wired_test/services/location_service.dart';

class _Statistics extends LocationService {
  final ids = <int>[];
  bool fail = false;
  @override
  Future<void> saveDownload(
      int moduleId, Map<String, double?>? location) async {
    ids.add(moduleId);
    if (fail) throw StateError('tracking unavailable');
  }
}

class _Transport implements AnimationDownloadTransport {
  _Transport(this.gate);
  final Future<void>? gate;
  @override
  Future<AnimationDownloadResponse> open(Uri uri) async {
    final zip = ZipEncoder().encode(
        Archive()..addFile(ArchiveFile('topic/clip.MP4', 3, [1, 2, 3])));
    return AnimationDownloadResponse(
        statusCode: 200, contentLength: zip.length, body: body(zip));
  }

  Stream<List<int>> body(List<int> zip) async* {
    yield zip.sublist(0, 10);
    if (gate != null) await gate;
    yield zip.sublist(10);
  }

  @override
  void close() {}
}

class _PhaseInstaller extends AnimationPreparationService {
  _PhaseInstaller() : super(coordinator: AnimationInstallationCoordinator());
  final release = Completer<void>();
  void Function(AnimationPreparationProgress)? report;
  @override
  Future<T> withPrepared<T>(
      {required int animationId,
      required Directory canonicalRoot,
      required Uri downloadUri,
      required Future<T> Function(PreparedAnimation) use,
      AnimationPreparationCancellation? cancellation,
      void Function(AnimationPreparationProgress)? onProgress}) async {
    report = onProgress;
    await release.future;
    throw const AnimationPreparationCancelled();
  }
}

void main() {
  late Directory root;
  late AnimationInstallationCoordinator coordinator;
  late _Statistics statistics;
  late AnimationPreparationService installer;
  var downloads = 0;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('animation-info-');
    coordinator = AnimationInstallationCoordinator();
    statistics = _Statistics();
    downloads = 0;
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  AnimationPreparationService service(
          {Future<void>? gate, bool warning = false, bool fail = false}) =>
      AnimationPreparationService(
        coordinator: coordinator,
        downloader: AnimationPrivateDownloadService(
            progressInterval: Duration.zero,
            transportFactory: () {
              downloads++;
              if (fail) throw StateError('network failure');
              return _Transport(gate);
            }),
        renamePayload: warning
            ? (source, destination) async {
                await source.rename(destination);
                await File('${source.parent.path}/unexpected.keep')
                    .writeAsString('keep');
              }
            : null,
      );

  Future<void> mount(WidgetTester tester,
      {int id = 42,
      String url = 'https://example.invalid/clip.zip',
      bool pushed = false}) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final page = AnimationInfo(
        animationId: id,
        animationName: 'Original name',
        animationDescription: 'Original description',
        downloadLink: url);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<AnimationPreparationService>.value(value: installer),
          Provider<AnimationStorageService>.value(
              value: AnimationStorageService(
                  operatingSystem: 'ios', supportDirectory: () async => root)),
          Provider<LocationService>.value(value: statistics),
        ],
        child: MaterialApp(
            home: pushed
                ? Builder(
                    builder: (context) => Scaffold(
                          body: TextButton(
                              onPressed: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => page)),
                              child: const Text('Details')),
                        ))
                : page)));
    if (pushed) {
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> start(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Download Animation'));
    await tester.runAsync(() => tester.tap(find.text('Download Animation')));
    await tester.pump();
  }

  Future<void> waitFor(WidgetTester tester, String text) async {
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (find.text(text).evaluate().isNotEmpty) return;
    }
    fail('Did not display $text');
  }

  test('catalog parses missing and malformed IDs without inventing identity',
      () {
    for (final value in [null, 'bad', 0, -1]) {
      final animation =
          catalog.Animation.fromJson({'id': value, 'name': 'Name'});
      expect(animation.id == null || animation.id! <= 0, isTrue);
    }
    expect(catalog.Animation.fromJson({'id': '42'}).id, 42);
  });
  for (final id in [null, 0, -1, 'invalid']) {
    testWidgets('catalog refuses navigation for ID $id', (tester) async {
      dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await http.runWithClient(() async {
        await tester
            .pumpWidget(const MaterialApp(home: catalog.AnimationList()));
        await tester.pump();
        await tester.tap(find.text('Catalog name'));
        await tester.pump();
        expect(find.byType(AnimationInfo), findsNothing);
        expect(find.text('A valid animation ID is not available.'),
            findsOneWidget);
      },
          () => MockClient((_) async => http.Response(
              '[{"id":${id == null ? 'null' : id is String ? '"$id"' : id},"name":"Catalog name"}]',
              200)));
    });
  }

  for (final id in [0, -1]) {
    testWidgets('invalid ID $id never installs', (tester) async {
      installer = service();
      await mount(tester, id: id);
      await start(tester);
      expect(
          find.text('A valid animation ID is not available.'), findsOneWidget);
      expect(downloads, 0);
    });
  }
  for (final url in [
    '',
    'http://example.com/a.zip',
    '/a.zip',
    'https://user:pass@example.com/a.zip',
    'https://example.com/a.zip#part'
  ]) {
    testWidgets('invalid URL $url never installs', (tester) async {
      installer = service();
      await mount(tester, url: url);
      await start(tester);
      expect(find.text('A valid HTTPS download link is not available.'),
          findsOneWidget);
      expect(downloads, 0);
    });
  }
  for (final warning in [false, true]) {
    testWidgets('publication retains installed state; warning $warning',
        (tester) async {
      installer = service(warning: warning);
      await mount(tester);
      expect(find.text('Original name'), findsOneWidget);
      expect(find.text('Original description'), findsOneWidget);
      await start(tester);
      await waitFor(tester, 'Downloaded');
      expect(find.text('Download Animation'), findsNothing);
      expect(find.text('Open My Library'), findsOneWidget);
      expect(
          await tester.runAsync(() =>
              File('${root.path}/modules/animations/42/topic/clip.MP4')
                  .exists()),
          isTrue);
      expect(statistics.ids, [42]);
      if (warning) {
        expect(
            find.text(
                'Animation installed, but a follow-up operation could not finish.'),
            findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final installed in [false, true]) {
    testWidgets('existing destination installed=$installed is preserved',
        (tester) async {
      final target = await tester.runAsync(() async {
        final directory = await Directory('${root.path}/modules/animations/42')
            .create(recursive: true);
        if (installed) {
          await File('${directory.path}/old.mp4').writeAsString('old');
        }
        return directory;
      });
      installer = service();
      await mount(tester);
      await start(tester);
      await waitFor(
          tester,
          installed
              ? 'This animation is already installed.'
              : 'Existing content prevents installation. Open My Library to review it.');
      expect(downloads, 0);
      expect(statistics.ids, isEmpty);
      expect(await tester.runAsync(() => target!.exists()), isTrue);
    });
  }
  testWidgets('shared coordinator refuses an existing same-ID owner',
      (tester) async {
    final release = Completer<void>();
    final owner =
        coordinator.run(animationId: 42, operation: () => release.future);
    installer = service();
    await mount(tester);
    await start(tester);
    await waitFor(tester, 'This animation is already being installed.');
    expect(downloads, 0);
    release.complete();
    await owner;
  });
  for (final dispose in [false, true]) {
    testWidgets('cancellation joins download, disposal=$dispose',
        (tester) async {
      final release = Completer<void>();
      installer = service(gate: release.future);
      await mount(tester);
      await start(tester);
      await waitFor(tester, 'Downloading animation');
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      final indicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(indicator.value, greaterThan(0));
      if (dispose) {
        await tester.pumpWidget(const SizedBox());
      } else {
        // System back requests cancellation and keeps the owner on screen.
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('Cancelling...'), findsOneWidget);
        expect(
            tester
                .widget<LinearProgressIndicator>(
                    find.byType(LinearProgressIndicator))
                .value,
            isNull);
      }
      await expectLater(
          coordinator.run(animationId: 42, operation: () async {}),
          throwsA(isA<AnimationInstallationInProgressException>()));
      release.complete();
      if (!dispose) await waitFor(tester, 'Download cancelled.');
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      await coordinator.run(animationId: 42, operation: () async {});
      expect(statistics.ids, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('verification is named and indeterminate; Cancel stays pending',
      (tester) async {
    final entered = Completer<void>(), release = Completer<void>();
    installer = AnimationPreparationService(
      coordinator: coordinator,
      downloader: AnimationPrivateDownloadService(
          transportFactory: () => _Transport(null)),
      verifyZip: (path, descriptor, limits) async {
        entered.complete();
        await release.future;
      },
    );
    await mount(tester);
    await start(tester);
    await waitFor(tester, 'Verifying archive');
    expect(entered.isCompleted, isTrue);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        isNull);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Cancelling...'), findsOneWidget);
    expect(find.text('Download cancelled.'), findsNothing);
    release.complete();
    await waitFor(tester, 'Download cancelled.');
  });

  testWidgets('cancel after rename submission cannot offer a false retry',
      (tester) async {
    final release = Completer<void>(), entered = Completer<void>();
    installer = AnimationPreparationService(
      coordinator: coordinator,
      downloader: AnimationPrivateDownloadService(
          transportFactory: () => _Transport(null)),
      renamePayload: (source, destination) async {
        entered.complete();
        await release.future;
        await source.rename(destination);
      },
    );
    await mount(tester);
    await start(tester);
    await waitFor(tester, 'Installing animation');
    for (var i = 0; i < 300 && !entered.isCompleted; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(entered.isCompleted, isTrue);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Cancelling...'), findsOneWidget);
    release.complete();
    await waitFor(tester, 'Downloaded');
    expect(find.text('Download Animation'), findsNothing);
    expect(find.text('Download cancelled.'), findsNothing);
    expect(statistics.ids, [42]);
  });

  testWidgets('back waits for cancellation and cleanup before leaving',
      (tester) async {
    final release = Completer<void>();
    installer = service(gate: release.future);
    await mount(tester, pushed: true);
    await start(tester);
    await waitFor(tester, 'Downloading animation');
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Cancelling...'), findsOneWidget);
    await expectLater(coordinator.run(animationId: 42, operation: () async {}),
        throwsA(isA<AnimationInstallationInProgressException>()));
    release.complete();
    await waitFor(tester, 'Details');
    await tester.pumpAndSettle();
    expect(find.byType(AnimationInfo), findsNothing);
    await coordinator.run(animationId: 42, operation: () async {});
    expect(statistics.ids, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all work phases have named indeterminate progress',
      (tester) async {
    final phases = _PhaseInstaller();
    installer = phases;
    await mount(tester);
    await start(tester);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    for (final entry in {
      AnimationPreparationPhase.inspectingDestination: 'Checking installation',
      AnimationPreparationPhase.creatingWorkspace: 'Preparing download',
      AnimationPreparationPhase.inspectingZip: 'Inspecting archive',
      AnimationPreparationPhase.verifyingZip: 'Verifying archive',
      AnimationPreparationPhase.extracting: 'Extracting animation',
      AnimationPreparationPhase.verifyingStaged: 'Verifying animation',
      AnimationPreparationPhase.prepared: 'Ready to install',
      AnimationPreparationPhase.publishing: 'Installing animation',
      AnimationPreparationPhase.cleaningUp: 'Cleaning up',
    }.entries) {
      phases.report!(AnimationPreparationProgress(entry.key));
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          isNull);
    }
    phases.release.complete();
    await waitFor(tester, 'Download cancelled.');
  });

  testWidgets('tracking failure cannot undo publication', (tester) async {
    statistics.fail = true;
    installer = service();
    await mount(tester);
    await start(tester);
    await waitFor(tester, 'Downloaded');
    expect(statistics.ids, [42]);
    expect(find.text('Download Animation'), findsNothing);
    expect(find.text('Download could not be completed. Please try again.'),
        findsNothing);
  });

  testWidgets('failure permits retry without claiming success', (tester) async {
    installer = service(fail: true);
    await mount(tester);
    await start(tester);
    await waitFor(tester, 'Download could not be completed. Please try again.');
    expect(find.text('Downloaded'), findsNothing);
    expect(find.text('Download Animation'), findsOneWidget);
    expect(statistics.ids, isEmpty);
  });
}
