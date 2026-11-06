import 'dart:async';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wired_test/models/downloadable_module.dart';
import 'package:wired_test/pages/program_modules_page.dart';
import 'package:wired_test/pages/module_details_page.dart';
import 'package:wired_test/pages/module_library.dart';
import 'package:wired_test/services/module_catalog_service.dart';
import 'package:wired_test/services/module_installation_status_service.dart';
import 'package:wired_test/services/program_download_service.dart';
import 'package:wired_test/services/legacy_module_installation_service.dart';
import 'package:wired_test/services/location_service.dart';

DownloadableModule module(int id, {String? name}) => DownloadableModule(
        id: id,
        moduleId: '${id + 100}',
        name: name ?? 'Module $id',
        downloadLink: 'https://example.com/$id.zip',
        programs: const [
          DownloadableProgram(id: 1, name: 'Basic', trainingType: 'basic')
        ]);

class _Catalog extends ModuleCatalogService {
  _Catalog(this.modules);
  final List<DownloadableModule> modules;
  @override
  Future<List<DownloadableModule>> fetchModules() async => modules;
}

class _Status extends ModuleInstallationStatusService {
  final states = <int, Object>{};
  final calls = <int, int>{};
  @override
  Future<InstructionalInstallationInspection> inspectInstallation(
      {int? databaseId,
      required String moduleId,
      required String moduleName}) async {
    expect(moduleId, '${databaseId! + 100}');
    calls.update(databaseId, (count) => count + 1, ifAbsent: () => 1);
    final state =
        states[databaseId] ?? InstructionalInstallationState.notInstalled;
    if (state is! InstructionalInstallationState) throw state;
    return InstructionalInstallationInspection(
        state, 'Evidence for $moduleName', const []);
  }

  @override
  Future<bool> isInstalled({required String moduleName}) async =>
      throw StateError('No name-only checks');
}

class _Location extends LocationService {
  @override
  Future<void> saveDownload(
      int moduleId, Map<String, double?>? location) async {}
}

class _Downloader extends ProgramDownloadService {
  int calls = 0;
  Future<void> Function(
      List<DownloadableModule> modules,
      void Function(ProgramDownloadProgress)? progress,
      Future<void> Function(DownloadableModule)? installed,
      void Function(DownloadableModule, InstructionalInstallationResult)?
          warning)? operation;
  @override
  Future<void> downloadProgram(
      {required List<DownloadableModule> modules,
      void Function(ProgramDownloadProgress)? onProgress,
      Future<void> Function(DownloadableModule)? onModuleInstalled,
      void Function(DownloadableModule, InstructionalInstallationResult)?
          onInstallationWarning}) async {
    calls++;
    await operation?.call(
        modules, onProgress, onModuleInstalled, onInstallationWarning);
  }
}

// Pop actual destination routes without building plugin-backed content. This
// tests the page's real navigation-return callbacks, not a replacement page API.
class _ReturningObserver extends NavigatorObserver {
  Widget? destination;
  VoidCallback? beforeReturn;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is! MaterialPageRoute) return;
    destination = route.builder(navigator!.context);
    Future<void>.microtask(() {
      beforeReturn?.call();
      navigator!.pop();
    });
  }
}

void main() {
  late _Status status;
  late _Downloader downloader;
  setUp(() {
    status = _Status();
    downloader = _Downloader();
  });
  Future<void> mount(WidgetTester tester, List<DownloadableModule> modules,
      {_ReturningObserver? observer,
      ModuleInstallationStatusService? inspectionService}) async {
    tester.view.physicalSize = const Size(1100, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        navigatorObservers: [if (observer != null) observer],
        home: ProgramModulesPage(
            title: 'Basic Training',
            trainingType: 'basic',
            catalogService: _Catalog(modules),
            installationStatus: inspectionService ?? status,
            programDownloader: downloader,
            locationService: _Location())));
    if (inspectionService != null) {
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  final labels = <InstructionalInstallationState, String>{
    InstructionalInstallationState.confirmed: 'Installed',
    InstructionalInstallationState.notInstalled: 'Not downloaded',
    InstructionalInstallationState.legacyCandidate:
        'Existing offline content; identity unverified',
    InstructionalInstallationState.ambiguous:
        'Needs verification: multiple matches',
    InstructionalInstallationState.conflict: 'Installation identity conflict',
    InstructionalInstallationState.invalidRecord:
        'Installation tracking needs attention',
    InstructionalInstallationState.unavailable:
        'Installation status unavailable',
  };
  testWidgets(
      'real legacy Compiler manifest contributes installed count without a registry',
      (tester) async {
    final root = (await tester.runAsync(() async {
      final root =
          await Directory.systemTemp.createTemp('program_legacy_compiler_');
      final hiveRoot = Directory('${root.path}/hive');
      await hiveRoot.create();
      Hive.init(hiveRoot.path);
      final content = Directory('${root.path}/modules/Old Folder');
      await content.create(recursive: true);
      await File('${content.path}/index.html').writeAsString('working');
      await File('${content.path}/module.json').writeAsString(
          '{"module_id":"142","module_title":"Different internal title","version":"1.0"}');
      return root;
    }))!;
    addTearDown(() async {
      await Hive.close();
      await root.delete(recursive: true);
    });
    final realStatus =
        ModuleInstallationStatusService(inspectionRoots: () async => [root]);
    await mount(tester, [module(42), module(43)],
        inspectionService: realStatus);
    expect(find.text('1 of 2 modules installed'), findsOneWidget);
    expect(find.text('1 missing; 0 legacy; 0 need attention'), findsOneWidget);
    expect(find.text('All Modules Installed'), findsNothing);
    expect(find.text('Download Remaining 1 Modules'), findsOneWidget);
    expect(downloader.calls, 0);
  });
  for (final entry in labels.entries) {
    testWidgets(
        '${entry.key.name} has distinct status and safe counts/controls',
        (tester) async {
      status.states[42] = entry.key;
      await mount(tester, [module(42)]);
      expect(find.byTooltip(entry.value), findsOneWidget);
      final confirmed = entry.key == InstructionalInstallationState.confirmed;
      expect(find.text('${confirmed ? 1 : 0} of 1 modules installed'),
          findsOneWidget);
      expect(find.text('All Modules Installed'),
          confirmed ? findsOneWidget : findsNothing);
      expect(status.calls[42], 1);
      if (entry.key == InstructionalInstallationState.notInstalled) {
        expect(
            tester
                .widget<ElevatedButton>(find.ancestor(
                    of: find.text('Download Remaining 1 Modules'),
                    matching: find.byWidgetPredicate(
                        (widget) => widget is ElevatedButton)))
                .onPressed,
            isNotNull);
      } else if (!confirmed) {
        expect(
            tester
                .widget<ElevatedButton>(find.ancestor(
                    of: find.text('Installation Needs Verification'),
                    matching: find.byWidgetPredicate(
                        (widget) => widget is ElevatedButton)))
                .onPressed,
            isNull);
      }
    });
  }

  testWidgets(
      'same-name IDs are separate and mixed counts never claim completion',
      (tester) async {
    status.states.addAll({
      42: InstructionalInstallationState.confirmed,
      43: InstructionalInstallationState.notInstalled,
      44: InstructionalInstallationState.legacyCandidate,
      45: InstructionalInstallationState.conflict
    });
    await mount(tester, [
      for (final id in [42, 43, 44, 45]) module(id, name: 'Same title')
    ]);
    expect(find.text('1 of 4 modules installed'), findsOneWidget);
    expect(find.text('1 missing; 1 legacy; 1 need attention'), findsOneWidget);
    expect(find.text('All Modules Installed'), findsNothing);
    expect(status.calls, {42: 1, 43: 1, 44: 1, 45: 1});
  });

  for (final failure in [
    InstructionalInstallationState.unavailable,
    StateError('check failed')
  ]) {
    testWidgets('retry resolves $failure without downloading', (tester) async {
      status.states[42] = failure;
      await mount(tester, [module(42)]);
      expect(
          find.text('0 missing; 0 legacy; 1 need attention'), findsOneWidget);
      status.states[42] = InstructionalInstallationState.confirmed;
      await tester.tap(find.text('Retry installation checks'));
      await tester.pumpAndSettle();
      expect(find.text('All Modules Installed'), findsOneWidget);
      expect(status.calls[42], 2);
      expect(downloader.calls, 0);
    });
  }

  for (final library in [false, true]) {
    testWidgets(
        'returning from ${library ? 'library' : 'details'} refreshes cache',
        (tester) async {
      status.states[42] = InstructionalInstallationState.confirmed;
      final observer = _ReturningObserver()
        ..beforeReturn = () {
          status.states[42] = InstructionalInstallationState.notInstalled;
        };
      await mount(tester, [module(42)], observer: observer);
      if (library) {
        await tester.tap(find.text('Library'));
      } else {
        await tester.ensureVisible(find.text('Module 42'));
        await tester.tap(find.text('Module 42'));
      }
      await tester.pumpAndSettle();
      expect(observer.destination,
          library ? isA<ModuleLibrary>() : isA<ModuleDetailsPage>());
      expect(status.calls[42], 2);
      expect(find.text('All Modules Installed'), findsNothing);
      expect(
          find.text('1 missing; 0 legacy; 0 need attention'), findsOneWidget);
    });
  }

  testWidgets(
      'structured blocked result identifies affected module and reason without success',
      (tester) async {
    downloader.operation = (modules, progress, installed, warning) async {
      status.states[42] = InstructionalInstallationState.conflict;
      throw ProgramDownloadBlockedException(
          phase: 'before installation',
          issues: [
            ProgramInstallationIssue(
                modules.single,
                InstructionalInstallationInspection(
                    InstructionalInstallationState.conflict,
                    'Another offline installation claims this module.',
                    const []))
          ],
          remainingModules: modules);
    };
    await mount(tester, [module(42)]);
    await tester.tap(find.text('Download Remaining 1 Modules'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Module 42: Installation identity conflict.'),
        findsOneWidget);
    expect(
        find.textContaining('Another offline installation claims this module.'),
        findsOneWidget);
    expect(find.text('Program download completed successfully.'), findsNothing);
    expect(find.text('All Modules Installed'), findsNothing);
    expect(status.calls[42], 3);
  });

  testWidgets(
      'verified session publication tolerates warnings and refreshes registry checks',
      (tester) async {
    final observer = _ReturningObserver()
      ..beforeReturn = () {
        status.states[42] = InstructionalInstallationState.notInstalled;
      };
    downloader.operation = (modules, progress, installed, warning) async {
      progress?.call(ProgramDownloadProgress(
          completed: 0,
          total: 1,
          currentModule: modules.single.name,
          phase: 'Installing module',
          moduleProgress: 1));
      warning?.call(
          modules.single,
          InstructionalInstallationResult(
              format: 'compiler',
              contentDirectory: '/verified-by-service',
              entryPointPath: '/verified-by-service/index.html',
              trackingOutcome: InstructionalTrackingOutcome.failed,
              trackingError: StateError('registry unavailable')));
      // The real service emits this callback only after verifying published files.
      await installed?.call(modules.single);
      status.states[42] = InstructionalInstallationState.legacyCandidate;
    };
    await mount(tester, [module(42)], observer: observer);
    await tester.tap(find.text('Download Remaining 1 Modules'));
    await tester.pumpAndSettle();
    expect(find.text('All Modules Installed'), findsOneWidget);
    expect(find.text('1 of 1 modules installed'), findsOneWidget);
    expect(find.textContaining('completed with warnings for 1 module(s)'),
        findsOneWidget);
    expect(find.text('Program download completed successfully.'), findsNothing);
    expect(
        find.byTooltip(
            'Installed during this session; identity tracking unconfirmed'),
        findsOneWidget);
    expect(status.calls[42], 3);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('All Modules Installed'), findsNothing);
    expect(find.text('0 of 1 modules installed'), findsOneWidget);
    expect(find.text('1 missing; 0 legacy; 0 need attention'), findsOneWidget);
    expect(status.calls[42], 4);
  });

  testWidgets(
      'progress is preserved while downloading and completion refreshes cache',
      (tester) async {
    final gate = Completer<void>();
    downloader.operation = (modules, progress, installed, warning) async {
      progress?.call(ProgramDownloadProgress(
          completed: 0,
          total: 1,
          currentModule: modules.single.name,
          phase: 'Downloading module',
          moduleProgress: 0.45));
      await gate.future;
      await installed?.call(modules.single);
      status.states[42] = InstructionalInstallationState.confirmed;
    };
    await mount(tester, [module(42)]);
    await tester.tap(find.text('Download Remaining 1 Modules'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Downloading module'), findsOneWidget);
    expect(find.text('0 of 1 remaining modules completed'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('All Modules Installed'), findsOneWidget);
    expect(status.calls[42], 3);
  });

  testWidgets(
      'mid-run block preserves completed session evidence and identifies remaining conflict',
      (tester) async {
    downloader.operation = (modules, progress, installed, warning) async {
      await installed?.call(modules.first);
      status.states[43] = InstructionalInstallationState.conflict;
      throw ProgramDownloadBlockedException(
          phase: 'before installation',
          completedModules: [
            modules.first
          ],
          remainingModules: [
            modules.last
          ],
          issues: [
            ProgramInstallationIssue(
                modules.last,
                InstructionalInstallationInspection(
                    InstructionalInstallationState.conflict,
                    'Content identity changed.', const []))
          ]);
    };
    await mount(tester, [module(42), module(43)]);
    await tester.tap(find.text('Download Remaining 2 Modules'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 modules installed'), findsOneWidget);
    expect(find.textContaining('1 module(s) completed during this download.'),
        findsOneWidget);
    expect(find.textContaining('Module 43: Installation identity conflict.'),
        findsOneWidget);
    expect(find.text('All Modules Installed'), findsNothing);
    expect(find.text('Program download completed successfully.'), findsNothing);
  });

  testWidgets(
      'warning alone without verified publication callback cannot claim all installed',
      (tester) async {
    downloader.operation = (modules, progress, installed, warning) async {
      status.states[42] = InstructionalInstallationState.legacyCandidate;
      warning?.call(
          modules.single,
          InstructionalInstallationResult(
              format: 'compiler',
              contentDirectory: '/unknown',
              entryPointPath: '/unknown/index.html',
              trackingOutcome: InstructionalTrackingOutcome.failed));
      throw StateError('no verified publication');
    };
    await mount(tester, [module(42)]);
    await tester.tap(find.text('Download Remaining 1 Modules'));
    await tester.pumpAndSettle();
    expect(find.text('All Modules Installed'), findsNothing);
    expect(find.text('0 of 1 modules installed'), findsOneWidget);
  });
}
