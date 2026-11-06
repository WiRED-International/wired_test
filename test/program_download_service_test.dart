import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:hive/hive.dart';
import 'package:wired_test/services/module_installation_registry.dart';
import 'package:wired_test/models/downloadable_module.dart';
import 'package:wired_test/services/legacy_module_installation_service.dart';
import 'package:wired_test/services/module_installation_status_service.dart';
import 'package:wired_test/services/program_download_service.dart';

DownloadableModule module(int id, {String name = 'Shared title'}) =>
    DownloadableModule(
        id: id,
        moduleId: '${id + 100}',
        name: name,
        version: '2',
        downloadLink: 'https://example.com/$id.zip',
        programs: []);

class _Status extends ModuleInstallationStatusService {
  final responses = <int, List<Object>>{};
  final requests = <int>[];
  final contentIds = <String>[];
  final names = <String>[];
  final counts = <int, int>{};
  @override
  Future<InstructionalInstallationInspection> inspectInstallation(
      {int? databaseId,
      required String moduleId,
      required String moduleName}) async {
    final id = databaseId!;
    requests.add(id);
    contentIds.add(moduleId);
    names.add(moduleName);
    final count = counts.update(id, (value) => value + 1, ifAbsent: () => 1);
    final choices =
        responses[id] ?? [InstructionalInstallationState.notInstalled];
    final response =
        choices[count <= choices.length ? count - 1 : choices.length - 1];
    if (response is! InstructionalInstallationState) throw response;
    return InstructionalInstallationInspection(
        response, 'Evidence for $id: ${response.name}', const []);
  }

  @override
  Future<bool> isInstalled({required String moduleName}) async =>
      throw StateError('Name-only API must not be called');
}

class _Installer extends LegacyModuleInstallationService {
  _Installer(this.root);
  final Directory root;
  final requests = <int>[];
  Future<InstructionalInstallationResult> Function(int id)? operation;
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
    final id = databaseId!;
    requests.add(id);
    expect(moduleId, '${id + 100}');
    expect(version, '2');
    expect(downloadUrl, 'https://example.com/$id.zip');
    onDownloadProgress?.call(0.5);
    onDownloadProgress?.call(1);
    onExtractionProgress?.call(1);
    return operation != null ? await operation!(id) : await publish(id);
  }

  Future<InstructionalInstallationResult> publish(int id,
      {bool storyline = false, bool warning = false}) async {
    final content = Directory(p.join(root.path, '$id'));
    await content.create();
    final entry =
        File(p.join(content.path, storyline ? 'story.html' : 'index.html'));
    await entry.writeAsString('working $id');
    final launcher = storyline ? File(p.join(root.path, '$id.htm')) : null;
    await launcher?.writeAsString('redirect to ${entry.path}');
    return InstructionalInstallationResult(
        format: storyline ? 'storyline' : 'compiler',
        contentDirectory: content.path,
        entryPointPath: entry.path,
        launcherPath: launcher?.path,
        trackingOutcome: warning
            ? InstructionalTrackingOutcome.failed
            : InstructionalTrackingOutcome.saved,
        trackingError: warning ? StateError('registry failed') : null,
        cleanupWarnings:
            warning ? [const FileSystemException('ZIP cleanup failed')] : []);
  }
}

void main() {
  late Directory root;
  late _Status status;
  late _Installer installer;
  late ProgramDownloadService service;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('program_download_');
    status = _Status();
    installer = _Installer(root);
    service = ProgramDownloadService(
        installer: installer, installationStatus: status);
  });
  tearDown(() => root.delete(recursive: true));

  test(
      'real manifest inspection skips legacy Compiler and lets missing modules download',
      () async {
    Hive.init(root.path);
    final content =
        Directory(p.join(root.path, 'modules', 'Different installed title'));
    await content.create(recursive: true);
    await File(p.join(content.path, 'index.html'))
        .writeAsString('existing working module');
    final manifest = File(p.join(content.path, 'module.json'));
    const manifestText =
        '{"module_id":"142","module_title":"Internal title","version":"1.0"}';
    await manifest.writeAsString(manifestText);
    final realStatus =
        ModuleInstallationStatusService(inspectionRoots: () async => [root]);
    final progress = <ProgramDownloadProgress>[];
    final realService = ProgramDownloadService(
        installer: installer, installationStatus: realStatus);
    await realService.downloadProgram(
        modules: [module(42), module(43)], onProgress: progress.add);
    expect(installer.requests, [43]);
    expect(progress.last.completed, 1);
    expect(progress.last.total, 1);
    expect(progress.last.phase, 'Program download complete');
    progress.clear();
    await realService
        .downloadProgram(modules: [module(42)], onProgress: progress.add);
    expect(progress.single.phase, 'All modules already installed');
    final inspection = await realStatus.inspectInstallation(
        databaseId: 42, moduleId: '142', moduleName: 'Renamed catalog title');
    expect(
        inspection.installedVersion, '1.0'); // Catalog module(42).version is 2.
    expect(await manifest.readAsString(), manifestText);
    expect(await Hive.boxExists(ModuleInstallationRegistry.boxName), isFalse);
    await Hive.close();
  });

  test(
      'same-title identities are independent; confirmed skipped and missing installed',
      () async {
    status.responses[42] = [InstructionalInstallationState.confirmed];
    final progress = <ProgramDownloadProgress>[];
    installer.operation = (id) async {
      expect(
          status.requests, [42, 43, 43]); // Full preflight before publication.
      return installer.publish(id);
    };
    Future<void> existingCaller = service.downloadProgram(
        modules: [module(42), module(43)], onProgress: progress.add);
    await existingCaller;
    expect(installer.requests, [43]);
    expect(status.contentIds, ['142', '143', '143']);
    expect(status.names.toSet(), {'Shared title'});
    expect(progress.last.completed, 1);
    expect(progress.last.total, 1);
    expect(progress.last.phase, 'Program download complete');
  });

  test('all confirmed and empty input retain existing caller behavior',
      () async {
    final progress = <ProgramDownloadProgress>[];
    status.responses[42] = [InstructionalInstallationState.confirmed];
    await service
        .downloadProgram(modules: [module(42)], onProgress: progress.add);
    expect(progress.single.phase, 'All modules already installed');
    expect(progress.single.overallProgress, 1);
    await service.downloadProgram(modules: [], onProgress: progress.add);
    expect(progress.length, 1);
    expect(installer.requests, isEmpty);
  });

  for (final state in [
    InstructionalInstallationState.legacyCandidate,
    InstructionalInstallationState.ambiguous,
    InstructionalInstallationState.conflict,
    InstructionalInstallationState.invalidRecord,
    InstructionalInstallationState.unavailable
  ]) {
    test(
        '$state blocks full preflight without downloading an earlier missing module',
        () async {
      status.responses[43] = [state];
      final progress = <ProgramDownloadProgress>[];
      try {
        await service.downloadProgram(
            modules: [module(42), module(43), module(44)],
            onProgress: progress.add);
        fail('Expected structured preflight failure');
      } on ProgramDownloadBlockedException catch (error) {
        expect(error.phase, 'preflight');
        expect(error.issues.single.module.id, 43);
        expect(error.issues.single.inspection.state, state);
        expect(
            error.issues.single.inspection.reason, contains('Evidence for 43'));
        expect(error.completedModules, isEmpty);
        expect(error.remainingModules.map((module) => module.id), [42, 43, 44]);
      }
      expect(status.requests, [42, 43, 44]);
      expect(installer.requests, isEmpty);
      expect(progress, isEmpty);
      expect(await root.list().toList(), isEmpty);
    });
  }

  test('thrown inspection is aggregated with other unresolved identities',
      () async {
    status.responses[42] = [StateError('storage unavailable')];
    status.responses[43] = [InstructionalInstallationState.conflict];
    await expectLater(
        service.downloadProgram(modules: [module(42), module(43), module(44)]),
        throwsA(isA<ProgramDownloadBlockedException>()
            .having((e) => e.issues.length, 'issues', 2)
            .having((e) => e.issues.first.inspection.state, 'failed check',
                InstructionalInstallationState.unavailable)));
    expect(status.requests, [42, 43, 44]);
    expect(installer.requests, isEmpty);
  });

  test(
      'fresh inspection stops mid-run and reports completed and remaining identities',
      () async {
    status.responses[43] = [
      InstructionalInstallationState.notInstalled,
      InstructionalInstallationState.conflict
    ];
    final progress = <ProgramDownloadProgress>[];
    try {
      await service.downloadProgram(
          modules: [module(42), module(43), module(44)],
          onProgress: progress.add);
      fail('Expected changed-identity failure');
    } on ProgramDownloadBlockedException catch (error) {
      expect(error.phase, 'before installation');
      expect(error.completedModules.map((module) => module.id), [42]);
      expect(error.remainingModules.map((module) => module.id), [43, 44]);
      expect(error.issues.single.module.id, 43);
    }
    expect(installer.requests, [42]);
    expect(await File(p.join(root.path, '42', 'index.html')).readAsString(),
        'working 42');
    expect(progress.any((event) => event.phase == 'Program download complete'),
        isFalse);
    expect(status.requests, [42, 43, 44, 42, 43]);
  });

  test('newly confirmed module is skipped during fresh inspection and counted',
      () async {
    status.responses[42] = [
      InstructionalInstallationState.notInstalled,
      InstructionalInstallationState.confirmed
    ];
    final progress = <ProgramDownloadProgress>[];
    await service
        .downloadProgram(modules: [module(42)], onProgress: progress.add);
    expect(installer.requests, isEmpty);
    expect(progress.last.completed, 1);
    expect(progress.last.overallProgress, 1);
  });

  test(
      'publication warnings continue without registry reinspection; observers are nonfatal',
      () async {
    installer.operation =
        (id) => installer.publish(id, storyline: id == 43, warning: true);
    final warnings = <int?>[], statistics = <int?>[];
    await service.downloadProgram(
        modules: [module(42), module(43)],
        onInstallationWarning: (module, result) {
          warnings.add(module.id);
          expect(result.cleanupWarnings, isNotEmpty);
          throw StateError('observer failure');
        },
        onModuleInstalled: (module) async {
          statistics.add(module.id);
          throw StateError('statistics unavailable');
        });
    expect(installer.requests, [42, 43]);
    expect(status.requests, [42, 43, 42, 43]);
    expect(warnings, [42, 43]);
    expect(statistics, [42, 43]);
  });

  for (final failure in [
    'directory',
    'entry',
    'empty entry',
    'launcher',
    'empty launcher'
  ]) {
    test(
        'missing published $failure prevents completion and preserves other files',
        () async {
      installer.operation = (id) async {
        final result = await installer.publish(id,
            storyline: failure.contains('launcher'));
        if (failure == 'directory') {
          await Directory(result.contentDirectory).delete(recursive: true);
        }
        if (failure == 'entry') await File(result.entryPointPath).delete();
        if (failure == 'empty entry') {
          await File(result.entryPointPath).writeAsString('');
        }
        if (failure == 'launcher') await File(result.launcherPath!).delete();
        if (failure == 'empty launcher') {
          await File(result.launcherPath!).writeAsString('');
        }
        return result;
      };
      final progress = <ProgramDownloadProgress>[];
      final completed = <int?>[];
      await expectLater(
          service.downloadProgram(
              modules: [module(42), module(43)],
              onProgress: progress.add,
              onModuleInstalled: (module) async {
                completed.add(module.id);
              }),
          throwsStateError);
      expect(installer.requests, [42]);
      expect(completed, isEmpty);
      expect(
          progress.any((event) => event.phase == 'Program download complete'),
          isFalse);
    });
  }

  test('downloads remain sequential and progress keeps 90/10 weighting',
      () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    installer.operation = (id) async {
      if (id == 42) {
        entered.complete();
        await gate.future;
      }
      return installer.publish(id);
    };
    final progress = <ProgramDownloadProgress>[];
    final operation = service.downloadProgram(
        modules: [module(42), module(43)], onProgress: progress.add);
    await entered.future;
    expect(installer.requests, [42]);
    gate.complete();
    await operation;
    expect(installer.requests, [42, 43]);
    expect(
        progress
            .firstWhere((event) => event.phase == 'Downloading module')
            .moduleProgress,
        0.45);
    expect(
        progress
            .firstWhere((event) => event.phase == 'Installing module')
            .moduleProgress,
        1);
    expect(progress.last.completed, 2);
    expect(progress.last.total, 2);
    expect(progress.last.overallProgress, 1);
    expect(
        progress.every((event) =>
            event.overallProgress >= 0 && event.overallProgress <= 1),
        isTrue);
  });
}
