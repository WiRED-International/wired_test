import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/legacy_module_installation_service.dart';
import 'package:wired_test/services/module_download_service.dart';
import 'package:wired_test/services/module_installation_status_service.dart';

// Use the service's existing constructor injection, never device storage APIs.
class _FixtureStorage extends ModuleDownloadService {
  _FixtureStorage(this.root);

  final Directory root;

  @override
  Future<Directory> getBaseDirectory() async => root;

  @override
  Future<Directory> getModulesDirectory() async =>
      Directory(p.join(root.path, 'modules'));
}

void main() {
  late Directory root;
  late File sentinel;
  late ModuleInstallationStatusService service;
  const sentinelContents = 'unrelated download must remain unchanged';

  Future<File> writeFixture(String relativePath, String contents) async {
    final target = p.normalize(p.join(root.path, relativePath));
    expect(p.isWithin(root.path, target), isTrue);
    final file = File(target);
    await file.parent.create(recursive: true);
    return file.writeAsString(contents, flush: true);
  }

  Future<void> compiler(String folder,
      {String? moduleId, String? title}) async {
    await writeFixture('modules/$folder/index.html', '<html>Compiler</html>');
    if (moduleId != null) {
      await writeFixture(
          'modules/$folder/module.json',
          jsonEncode({
            'module_id': moduleId,
            if (title != null) 'module_title': title,
          }));
    }
  }

  Future<void> storyline(String launcher, String metadata,
      {bool destination = true}) async {
    // Stable archive folder, independent of both the title and content ID.
    await writeFixture('modules/$launcher', '''<html><head>
$metadata
<meta http-equiv="refresh" content="0; url=../files/story-folder/story.html">
</head></html>''');
    if (destination) {
      await writeFixture(
          'files/story-folder/story.html', '<html>Storyline</html>');
    }
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('healthmap-status-test-');
    sentinel = await writeFixture('modules/unrelated.keep', sentinelContents);
    final storage = _FixtureStorage(root);
    expect((await storage.getBaseDirectory()).path, root.path);
    expect((await storage.getModulesDirectory()).path,
        p.join(root.path, 'modules'));
    service = ModuleInstallationStatusService(downloadService: storage);
  });

  tearDown(() async {
    try {
      expect(await sentinel.readAsString(), sentinelContents);
    } finally {
      final tempRoot = p.normalize(Directory.systemTemp.absolute.path);
      final target = p.normalize(root.absolute.path);
      expect(p.isWithin(tempRoot, target), isTrue);
      expect(p.basename(target), startsWith('healthmap-status-test-'));
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  group('Current title-based behavior', () {
    test('compiler index under sanitized catalog title is installed', () async {
      const title = 'HIV/AIDS: Care';
      await compiler(legacyModuleFolderName(title));
      expect(await service.isInstalled(moduleName: title), isTrue);
    });

    test('current .htm Storyline launcher and destination are installed',
        () async {
      await storyline('story-folder.htm',
          '<meta name="module-title" content="Storyline Test">');
      expect(await service.isInstalled(moduleName: 'Storyline Test'), isTrue);
    });

    test('compiler directory without index is not installed', () async {
      await writeFixture('modules/Compiler Test/assets/data.txt', 'resource');
      expect(await service.isInstalled(moduleName: 'Compiler Test'), isFalse);
    });

    test('Storyline launcher without destination is not installed', () async {
      await storyline('story-folder.htm',
          '<meta name="module-title" content="Storyline Test">',
          destination: false);
      expect(await service.isInstalled(moduleName: 'Storyline Test'), isFalse);
    });

    test('existing title-based detection decodes HTML entities', () async {
      await storyline('story-folder.htm',
          '<meta name="module-title" content="Health &amp; &quot;Safety&quot;">');
      expect(
          await service.isInstalled(moduleName: 'Health & "Safety"'), isTrue);
    });
  });

  group('Compatibility regressions (expected failures before correction)', () {
    test('valid .html Storyline launcher is installed', () async {
      await storyline('story-folder.html',
          '<meta name="module-title" content="Storyline Test">');
      expect(await service.isInstalled(moduleName: 'Storyline Test'), isTrue);
    });

    test('single-quoted title metadata is installed', () async {
      await storyline('story-folder.htm',
          "<meta name='module-title' content='Storyline Test'>");
      expect(await service.isInstalled(moduleName: 'Storyline Test'), isTrue);
    });

    test('equivalent reordered metadata attributes are installed', () async {
      await storyline('story-folder.htm',
          '<meta content="Storyline Test" name="module-title">');
      expect(await service.isInstalled(moduleName: 'Storyline Test'), isTrue);
    });
  });

  group('Safety', () {
    test('recovery backup directory does not count as installed', () async {
      await compiler('Compiler Test.backup',
          moduleId: '1565', title: 'Compiler Test');
      expect(await service.isInstalled(moduleName: 'Compiler Test'), isFalse);
    });

    test('similar but unrelated title does not match', () async {
      await compiler('Malaria Treatment Advanced');
      await storyline('story-folder.htm',
          '<meta name="module-title" content="Malaria Treatment Advanced">');
      expect(
          await service.isInstalled(moduleName: 'Malaria Treatment'), isFalse);
    });
  });
}
