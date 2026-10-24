import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/module_download_service.dart';
import 'package:wired_test/services/legacy_module_installation_service.dart';

/// Uses local ZIP fixtures only: no network, S3, or existing device files.
class _FixtureDownloader extends ModuleDownloadService {
  _FixtureDownloader(this.root, this.zip);

  final Directory root;
  final File zip;

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
  Future<Directory> getStagingDirectory(String moduleId) async =>
      Directory(p.join((await getDownloadsDirectory()).path, '$moduleId.staging'));

  @override
  Future<File> downloadModuleZip({
    required String moduleId,
    required String downloadUrl,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
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
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('compiler ZIP installs into the existing named library folder', () async {
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
    expect(await File(p.join(root.path, 'modules', 'Module Compiler Test', 'index.html')).exists(), isTrue);
    expect(await File(p.join(root.path, 'modules', 'Module Compiler Test', 'assets', 'data.txt')).readAsString(), 'asset');
    expect(await zip.exists(), isFalse);
  });

  test('Storyline ZIP creates files folder and matching .htm launcher', () async {
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
    expect(await File(p.join(root.path, 'files', 'story-content', 'story.html')).exists(), isTrue);
    final launcher = File(p.join(root.path, 'modules', 'story-content.htm'));
    expect(await launcher.exists(), isTrue);
    expect(await launcher.readAsString(), contains('../files/story-content/story.html'));
  });

  test('existing compiler installation is not overwritten', () async {
    final existing = File(p.join(root.path, 'modules', 'Existing', 'index.html'));
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
    expect(await Directory(p.join(root.path, 'module_downloads', '1002.staging')).exists(), isFalse);
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
    expect(await File(p.join(root.path, 'modules', folder, 'index.html')).exists(), isTrue);
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
    expect(await Directory(p.join(root.path, 'modules', 'Invalid Module')).exists(), isFalse);
    expect(await Directory(p.join(root.path, 'module_downloads', '1003.staging')).exists(), isFalse);
  });
}
