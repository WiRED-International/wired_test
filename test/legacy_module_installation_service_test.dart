import 'dart:io';
import 'dart:async';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/module_download_service.dart';
import 'package:wired_test/services/legacy_module_installation_service.dart';
import 'package:wired_test/services/module_installation_registry.dart';
import 'package:wired_test/services/module_installation_status_service.dart';
import 'package:wired_test/services/program_download_service.dart';
import 'package:wired_test/models/downloadable_module.dart';
import 'package:hive/hive.dart';

class _FailingRegistry extends ModuleInstallationRegistry {
  final gate = Completer<void>();
  final entered = Completer<void>();
  bool block = false;
  int calls = 0;
  @override
  Future<void> saveInstructionalInstallation({
    required int databaseId,
    required String moduleId,
    required String format,
    required String contentDirectory,
    required String entryPointPath,
    String? launcherPath,
    String? version,
    required String provenance,
  }) async {
    calls++;
    expect(await File(entryPointPath).exists(), isTrue);
    if (launcherPath != null) {
      expect(await File(launcherPath).readAsString(), contains('story.html'));
    }
    if (!entered.isCompleted) entered.complete();
    if (block) await gate.future;
    throw StateError('tracking unavailable');
  }
}

class _DeleteFailFile implements File {
  _DeleteFailFile(this.original);
  final File original;
  @override
  String get path => original.path;
  @override
  Future<bool> exists() => original.exists();
  @override
  Future<File> delete({bool recursive = false}) async =>
      throw const FileSystemException('cleanup denied');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeleteFailDirectory implements Directory {
  _DeleteFailDirectory(this.original);
  final Directory original;
  @override
  String get path => original.path;
  @override
  Future<bool> exists() => original.exists();
  @override
  Stream<FileSystemEntity> list(
          {bool recursive = false, bool followLinks = true}) =>
      original.list(recursive: recursive, followLinks: followLinks);
  @override
  Future<Directory> create({bool recursive = false}) =>
      original.create(recursive: recursive);
  @override
  Future<Directory> delete({bool recursive = false}) async =>
      throw const FileSystemException('staging cleanup denied');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StagingCleanupDownloader extends _FixtureDownloader {
  _StagingCleanupDownloader(super.root, super.zip);
  @override
  Future<Directory> getStagingDirectory(String moduleId) async =>
      _DeleteFailDirectory(await super.getStagingDirectory(moduleId));
}

/// Uses local ZIP fixtures only: no network, S3, or existing device files.
class _FixtureDownloader extends ModuleDownloadService {
  _FixtureDownloader(this.root, this.zip);

  final Directory root;
  final File zip;
  int downloadCalls = 0;

  @override
  Future<Directory> getBaseDirectory() async => root;

  @override
  Future<Directory> getModulesDirectory() async {
    final dir = Directory(p.join(root.path, 'modules'));
    await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<Directory> getDownloadsDirectory() async {
    final dir = Directory(p.join(root.path, 'module_downloads'));
    await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<Directory> getStagingDirectory(String moduleId) async => Directory(
      p.join((await getDownloadsDirectory()).path, '$moduleId.staging'));

  @override
  Future<File> downloadModuleZip({
    required String moduleId,
    required String downloadUrl,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    downloadCalls++;
    onProgress?.call(1.0);
    return zip;
  }
}

Future<File> _zipFixture(Directory root, Map<String, String> files) async {
  final source = Directory(p.join(root.path, 'source'));
  await source.create(recursive: true);
  for (final entry in files.entries) {
    final file = File(p.join(source.path, entry.key));
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
  }
  final zip = File(p.join(root.path, 'fixture.zip'));
  final encoder = ZipFileEncoder();
  encoder.create(zip.path);
  for (final entry in files.keys) {
    await encoder.addFile(File(p.join(source.path, entry)), entry);
  }
  encoder.close();
  return zip;
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('healthmap-install-test-');
    Hive.init(root.path);
  });

  tearDown(() async {
    await Hive.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  for (final storyline in [false, true]) {
    test('publication result and persisted identity: storyline=$storyline',
        () async {
      final zip = await _zipFixture(
          root,
          storyline
              ? {'wrapper/story/story.html': 'story'}
              : {'index.html': 'compiler'});
      final registry = ModuleInstallationRegistry();
      final service = LegacyModuleInstallationService(
          downloadService: _FixtureDownloader(root, zip), registry: registry);
      final result = await service.downloadAndInstallWithResult(
          databaseId: 42,
          moduleId: '1565',
          moduleName: 'Title',
          version: '3',
          downloadUrl: 'https://example.com/module.zip');
      expect(result.format, storyline ? 'storyline' : 'compiler');
      expect(
          result.contentDirectory,
          p.join(root.path, storyline ? 'files' : 'modules',
              storyline ? 'story' : 'Title'));
      expect(
          result.entryPointPath,
          p.join(result.contentDirectory,
              storyline ? 'story.html' : 'index.html'));
      expect(result.launcherPath,
          storyline ? p.join(root.path, 'modules', 'story.htm') : null);
      expect(result.trackingOutcome, InstructionalTrackingOutcome.saved);
      expect(result.hasWarnings, isFalse);
      final record = (await registry.getInstructionalInstallation(42))!;
      expect(record['module_id'], '1565');
      expect(record['database_id'], 42);
      expect(record['content_directory'], result.contentDirectory);
      expect(record['entry_point_path'], result.entryPointPath);
      expect(record['launcher_path'], result.launcherPath);
      expect(record['version'], '3');
      expect(record['provenance'], 'new-install');
      expect(record['installed_at'], isNotNull);
      await Hive.close();
      expect(await registry.getInstructionalInstallation(42), record);
    });

    test('tracking failure preserves publication: storyline=$storyline',
        () async {
      final zip = await _zipFixture(
          root,
          storyline
              ? {'story/story.html': 'working'}
              : {'index.html': 'working'});
      final registry = _FailingRegistry();
      final service = LegacyModuleInstallationService(
          downloadService: _FixtureDownloader(root, zip), registry: registry);
      final result = await service.downloadAndInstallWithResult(
          databaseId: 42,
          moduleId: '1565',
          moduleName: 'Title',
          downloadUrl: 'https://example.com/module.zip');
      expect(result.trackingOutcome, InstructionalTrackingOutcome.failed);
      expect(result.trackingError, isA<StateError>());
      expect(await File(result.entryPointPath).readAsString(), 'working');
      if (storyline) expect(await File(result.launcherPath!).exists(), isTrue);
      // A subsequent operation reaches extraction, rather than a held lock.
      await expectLater(
          service.downloadAndInstall(
              moduleId: '1565',
              moduleName: 'Title',
              downloadUrl: 'https://example.com/module.zip'),
          throwsFormatException);
    });
  }

  test('cleanup failure returns warning and releases lock', () async {
    final zip = await _zipFixture(root, {'index.html': 'working'});
    final service = LegacyModuleInstallationService(
        downloadService: _FixtureDownloader(root, _DeleteFailFile(zip)));
    final result = await service.downloadAndInstallWithResult(
        moduleId: '1',
        moduleName: 'One',
        downloadUrl: 'https://example.com/module.zip');
    expect(result.cleanupWarnings.single, isA<FileSystemException>());
    expect(result.trackingOutcome, InstructionalTrackingOutcome.skipped);
    expect(await File(result.entryPointPath).readAsString(), 'working');
    final next = await service.downloadAndInstallWithResult(
        moduleId: '2',
        moduleName: 'Two',
        downloadUrl: 'https://example.com/module.zip');
    expect(await File(next.entryPointPath).exists(), isTrue);
  });

  test('Storyline staging cleanup failure preserves launcher and tracking',
      () async {
    final zip = await _zipFixture(root, {'story/story.html': 'working'});
    final registry = ModuleInstallationRegistry();
    final result = await LegacyModuleInstallationService(
      downloadService: _StagingCleanupDownloader(root, zip),
      registry: registry,
    ).downloadAndInstallWithResult(
        databaseId: 42,
        moduleId: '1565',
        moduleName: 'Story',
        downloadUrl: 'https://example.com/module.zip');
    expect(result.cleanupWarnings.single, isA<FileSystemException>());
    expect(result.trackingOutcome, InstructionalTrackingOutcome.saved);
    expect(await File(result.entryPointPath).readAsString(), 'working');
    expect(await File(result.launcherPath!).exists(), isTrue);
    expect(await registry.getInstructionalInstallation(42), isNotNull);
  });

  test('pre-publication failure writes no record and releases lock', () async {
    final zip = await _zipFixture(root, {'readme.txt': 'invalid'});
    final registry = ModuleInstallationRegistry();
    final downloader = _FixtureDownloader(root, zip);
    final service = LegacyModuleInstallationService(
        downloadService: downloader, registry: registry);
    await expectLater(
        service.downloadAndInstallWithResult(
            databaseId: 42,
            moduleId: '1',
            moduleName: 'Invalid',
            downloadUrl: 'https://example.com/module.zip'),
        throwsFormatException);
    expect(await registry.getInstructionalInstallation(42), isNull);
    await _zipFixture(root, {'index.html': 'working'});
    await service.downloadAndInstall(
        databaseId: 42,
        moduleId: '2',
        moduleName: 'Valid',
        downloadUrl: 'https://example.com/module.zip');
    expect(await registry.getInstructionalInstallation(42), isNotNull);
  });

  test('invalid database IDs fail before download; absent ID skips tracking',
      () async {
    final zip = await _zipFixture(root, {'index.html': 'working'});
    final downloader = _FixtureDownloader(root, zip);
    final registry = _FailingRegistry();
    final service = LegacyModuleInstallationService(
        downloadService: downloader, registry: registry);
    for (final id in [0, -1]) {
      await expectLater(
          service.downloadAndInstall(
              databaseId: id,
              moduleId: '1',
              moduleName: 'Title',
              downloadUrl: 'https://example.com/module.zip'),
          throwsArgumentError);
    }
    expect(downloader.downloadCalls, 0);
    final result = await service.downloadAndInstallWithResult(
        moduleId: '1',
        moduleName: 'Title',
        downloadUrl: 'https://example.com/module.zip');
    expect(result.trackingOutcome, InstructionalTrackingOutcome.skipped);
    expect(registry.calls, 0);
  });

  test('lock covers tracking, rejects overlap, and releases after warning',
      () async {
    final zip = await _zipFixture(root, {'index.html': 'working'});
    final registry = _FailingRegistry()..block = true;
    final service = LegacyModuleInstallationService(
        downloadService: _FixtureDownloader(root, zip), registry: registry);
    final pending = service.downloadAndInstallWithResult(
        databaseId: 42,
        moduleId: '1',
        moduleName: 'One',
        downloadUrl: 'https://example.com/module.zip');
    await registry.entered.future;
    await expectLater(
        service.downloadAndInstall(
            moduleId: '2',
            moduleName: 'Two',
            downloadUrl: 'https://example.com/module.zip'),
        throwsStateError);
    registry.gate.complete();
    expect(
        (await pending).trackingOutcome, InstructionalTrackingOutcome.failed);
    final replacement = await _zipFixture(root, {'index.html': 'next'});
    await LegacyModuleInstallationService(
            downloadService: _FixtureDownloader(root, replacement))
        .downloadAndInstall(
            moduleId: '2',
            moduleName: 'Two',
            downloadUrl: 'https://example.com/module.zip');
  });

  test(
      'program continues after tracking failure using real publication and status',
      () async {
    final registry = _FailingRegistry();
    final zip = await _zipFixture(root, {'index.html': 'working'});
    // Keep the fixture ZIP so both sequential modules can use it.
    final downloader = _FixtureDownloader(root, _DeleteFailFile(zip));
    final warnings = <int?>[];
    final completed = <int?>[];
    await ProgramDownloadService(
      installer: LegacyModuleInstallationService(
          downloadService: downloader, registry: registry),
      installationStatus:
          ModuleInstallationStatusService(downloadService: downloader),
    ).downloadProgram(
        modules: [
          for (final id in [42, 43])
            DownloadableModule(
                id: id,
                moduleId: '${id + 100}',
                name: 'Module $id',
                version: '1',
                downloadLink: 'https://example.com/module.zip',
                programs: []),
        ],
        onInstallationWarning: (module, result) {
          expect(result.trackingOutcome, InstructionalTrackingOutcome.failed);
          warnings.add(module.id);
        },
        onModuleInstalled: (module) async {
          completed.add(module.id);
        });
    expect(completed, [42, 43]);
    expect(warnings, [42, 43]);
    expect(registry.calls, 2);
  });

  test('compiler ZIP installs into the existing named library folder',
      () async {
    final zip = await _zipFixture(root, {
      'index.html': '<html>Compiler</html>',
      'module.json': '{"module_id":1565}',
      'assets/data.txt': 'asset',
    });
    final service = LegacyModuleInstallationService(
      downloadService: _FixtureDownloader(root, zip),
    );
    await service.downloadAndInstall(
      moduleId: '1565',
      moduleName: 'Module Compiler Test',
      downloadUrl: 'https://example.com/compiler.zip',
    );
    expect(
        await File(p.join(
                root.path, 'modules', 'Module Compiler Test', 'index.html'))
            .exists(),
        isTrue);
    expect(
        await File(p.join(root.path, 'modules', 'Module Compiler Test',
                'assets', 'data.txt'))
            .readAsString(),
        'asset');
    expect(await zip.exists(), isFalse);
  });

  test('Storyline ZIP creates files folder and matching .htm launcher',
      () async {
    final zip = await _zipFixture(root, {
      'wrapper/story-content/story.html': '<html>Storyline</html>',
      'wrapper/story-content/story_content/file.js': 'test',
    });
    final service = LegacyModuleInstallationService(
      downloadService: _FixtureDownloader(root, zip),
    );
    await service.downloadAndInstall(
      moduleId: '1001',
      moduleName: 'Storyline Test',
      downloadUrl: 'https://example.com/storyline.zip',
    );
    expect(
        await File(p.join(root.path, 'files', 'story-content', 'story.html'))
            .exists(),
        isTrue);
    final launcher = File(p.join(root.path, 'modules', 'story-content.htm'));
    expect(await launcher.exists(), isTrue);
    expect(await launcher.readAsString(),
        contains('../files/story-content/story.html'));
  });

  test('existing compiler installation is not overwritten', () async {
    final existing =
        File(p.join(root.path, 'modules', 'Existing', 'index.html'));
    await existing.parent.create(recursive: true);
    await existing.writeAsString('original');
    final zip = await _zipFixture(root, {'index.html': 'replacement'});
    final service = LegacyModuleInstallationService(
      downloadService: _FixtureDownloader(root, zip),
    );
    await expectLater(
      service.downloadAndInstall(
        moduleId: '1002',
        moduleName: 'Existing',
        downloadUrl: 'https://example.com/replacement.zip',
      ),
      throwsStateError,
    );
    expect(await existing.readAsString(), 'original');
    expect(
        await Directory(p.join(root.path, 'module_downloads', '1002.staging'))
            .exists(),
        isFalse);
  });

  test('module title with colon and slash installs safely', () async {
    final zip = await _zipFixture(root, {
      'index.html': '<html>Compiler</html>',
    });
    final service = LegacyModuleInstallationService(
      downloadService: _FixtureDownloader(root, zip),
    );
    const title = 'When ARVs Are Gone: HIV/AIDS Symptoms Management';
    await service.downloadAndInstall(
      moduleId: '1010',
      moduleName: title,
      downloadUrl: 'https://example.com/module.zip',
    );
    final folder = legacyModuleFolderName(title);
    expect(folder.contains('/'), isFalse);
    expect(
        await File(p.join(root.path, 'modules', folder, 'index.html')).exists(),
        isTrue);
  });

  test('unknown ZIP format fails without installing an empty module', () async {
    final zip = await _zipFixture(root, {'readme.txt': 'not a module'});
    final service = LegacyModuleInstallationService(
      downloadService: _FixtureDownloader(root, zip),
    );
    await expectLater(
      service.downloadAndInstall(
        moduleId: '1003',
        moduleName: 'Invalid Module',
        downloadUrl: 'https://example.com/invalid.zip',
      ),
      throwsFormatException,
    );
    expect(
        await Directory(p.join(root.path, 'modules', 'Invalid Module'))
            .exists(),
        isFalse);
    expect(
        await Directory(p.join(root.path, 'module_downloads', '1003.staging'))
            .exists(),
        isFalse);
  });
}
