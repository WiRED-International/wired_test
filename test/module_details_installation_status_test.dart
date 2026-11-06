import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wired_test/models/downloadable_module.dart';
import 'package:wired_test/pages/module_details_page.dart';
import 'package:wired_test/providers/cme_award_provider.dart';
import 'package:wired_test/services/legacy_module_installation_service.dart';
import 'package:wired_test/services/module_installation_status_service.dart';

class _Status extends ModuleInstallationStatusService {
  _Status(this.states);
  final List<InstructionalInstallationState> states;
  int calls = 0;
  @override
  Future<InstructionalInstallationInspection> inspectInstallation(
      {int? databaseId,
      required String moduleId,
      required String moduleName}) async {
    expect(databaseId, 42);
    expect(moduleId, '1565');
    expect(moduleName, 'Test Module');
    final state = states[calls < states.length ? calls : states.length - 1];
    calls++;
    return InstructionalInstallationInspection(
        state, 'test evidence', const []);
  }

  @override
  Future<bool> isInstalled({required String moduleName}) async =>
      throw StateError('Page must not use name-only checks');
}

class _Installer extends LegacyModuleInstallationService {
  InstructionalInstallationResult? result;
  int calls = 0;
  @override
  Future<InstructionalInstallationResult> downloadAndInstallWithResult({
    int? databaseId,
    String? version,
    required String moduleId,
    required String moduleName,
    required String downloadUrl,
    void Function(double)? onDownloadProgress,
    void Function(double)? onExtractionProgress,
  }) async {
    calls++;
    expect(databaseId, 42);
    expect(moduleId, '1565');
    expect(version, '2');
    onDownloadProgress?.call(0.5);
    onExtractionProgress?.call(1);
    return result!;
  }
}

class _Cme extends CmeAwardProvider {
  int refreshes = 0;
  @override
  bool hasEarnedCredit(int moduleId) => moduleId == 42;
  @override
  Future<void> fetchAwardedModules({bool forceRefresh = false}) async {
    refreshes++;
  }
}

void main() {
  const module = DownloadableModule(
      id: 42,
      moduleId: '1565',
      name: 'Test Module',
      version: '2',
      downloadLink: 'https://example.com/module.zip',
      programs: []);
  Future<void> mount(WidgetTester tester, _Status status, _Installer installer,
      {_Cme? cme}) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget page = ModuleDetailsPage(
        module: cme == null
            ? module
            : const DownloadableModule(
                id: 42,
                moduleId: '1565',
                name: 'Test Module',
                version: '2',
                downloadLink: 'https://example.com/module.zip',
                creditType: 'cme',
                programs: []),
        installationStatus: status,
        installer: installer);
    if (cme != null) {
      page = ChangeNotifierProvider<CmeAwardProvider>.value(
          value: cme, child: page);
    }
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  final cases = <InstructionalInstallationState, String>{
    InstructionalInstallationState.confirmed: 'Installed',
    InstructionalInstallationState.legacyCandidate:
        'Existing offline content detected.',
    InstructionalInstallationState.ambiguous:
        'Installation status needs verification.',
    InstructionalInstallationState.conflict: 'Installation identity conflict.',
    InstructionalInstallationState.invalidRecord:
        'Installation tracking needs attention.',
    InstructionalInstallationState.unavailable:
        'Installation status could not be checked.',
    InstructionalInstallationState.notInstalled: 'Not downloaded',
  };
  for (final entry in cases.entries) {
    testWidgets('${entry.key.name} displays status and gates download',
        (tester) async {
      final status = _Status([entry.key]);
      final installer = _Installer();
      await mount(tester, status, installer);
      expect(find.textContaining(entry.value), findsWidgets);
      final button = find.widgetWithText(
          ElevatedButton,
          entry.key == InstructionalInstallationState.confirmed
              ? 'Installed'
              : 'Download Module');
      expect(button, findsOneWidget);
      final enabled = entry.key == InstructionalInstallationState.notInstalled;
      expect(tester.widget<ElevatedButton>(button).onPressed != null, enabled);
      expect(installer.calls, 0);
      expect(status.calls, 1);
      if (entry.key == InstructionalInstallationState.legacyCandidate) {
        expect(find.text('Installed'), findsNothing);
        expect(find.text('Open My Library'), findsOneWidget);
      }
    });
  }

  testWidgets('unavailable check retries safely without installing',
      (tester) async {
    final status = _Status([
      InstructionalInstallationState.unavailable,
      InstructionalInstallationState.notInstalled
    ]);
    final installer = _Installer();
    await mount(tester, status, installer);
    await tester.ensureVisible(find.text('Retry installation check'));
    await tester.tap(find.text('Retry installation check'));
    await tester.pumpAndSettle();
    expect(status.calls, 2);
    expect(installer.calls, 0);
    expect(find.text('Not downloaded'), findsOneWidget);
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Download Module'))
            .onPressed,
        isNotNull);
  });

  testWidgets(
      'published files establish success despite tracking and cleanup warnings',
      (tester) async {
    final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('details_publication_')))!;
    addTearDown(() async => root.delete(recursive: true));
    final entry = File('${root.path}/index.html');
    await tester.runAsync(() => entry.writeAsString('working offline content'));
    SharedPreferences.setMockInitialValues(
        {'location_permission_choice': false});
    final status = _Status([
      InstructionalInstallationState.notInstalled,
      InstructionalInstallationState.unavailable
    ]);
    final installer = _Installer()
      ..result = InstructionalInstallationResult(
          format: 'compiler',
          contentDirectory: root.path,
          entryPointPath: entry.path,
          trackingOutcome: InstructionalTrackingOutcome.failed,
          trackingError: StateError('registry unavailable'),
          cleanupWarnings: [const FileSystemException('cleanup failed')]);
    await mount(tester, status, installer);
    await tester.ensureVisible(find.text('Download Module'));
    await tester.tap(find.text('Download Module'));
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
      if (find.text('Module downloaded successfully!').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Module downloaded successfully!'), findsOneWidget);
    expect(find.textContaining('Installed on this device.'), findsOneWidget);
    expect(find.text('Download Module'), findsNothing);
    expect(find.text('Open My Library'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(installer.calls, 1);
    expect(status.calls, 2);
    expect(
        await tester.runAsync(entry.readAsString), 'working offline content');
  });

  testWidgets(
      'confirmed status preserves previously earned CME indicator and refresh',
      (tester) async {
    final cme = _Cme();
    addTearDown(cme.dispose);
    await mount(tester, _Status([InstructionalInstallationState.confirmed]),
        _Installer(),
        cme: cme);
    expect(find.text('CME Credit Previously Earned'), findsOneWidget);
    expect(cme.refreshes, 1);
  });
}
