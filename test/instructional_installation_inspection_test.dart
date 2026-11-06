import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/module_installation_registry.dart';
import 'package:wired_test/services/module_installation_status_service.dart';

void main() {
  late Directory root;
  late Directory hiveRoot;
  late ModuleInstallationRegistry registry;
  late ModuleInstallationStatusService service;
  String path(String relative) => p.normalize(p.join(root.path, relative));
  Future<void> write(String relative, String text) async {
    final file = File(path(relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<void> compiler({String folder = 'Old Title', String? id}) async {
    await write('modules/$folder/index.html', 'working');
    if (id != null) {
      await write('modules/$folder/module.json', jsonEncode({'module_id': id}));
    }
  }

  Future<void> story({String target = '../files/story/story.html'}) async {
    await write('files/story/story.html', 'working');
    await write(
        'modules/story.htm',
        '<meta name="module-title" content="Title">'
            '<meta http-equiv="refresh" content="0; url=$target">');
  }

  Future<void> save(
          {int id = 42,
          String contentId = '1565',
          bool storyline = false,
          String? content,
          String? entry,
          String? launcher}) =>
      registry.saveInstructionalInstallation(
          databaseId: id,
          moduleId: contentId,
          format: storyline ? 'storyline' : 'compiler',
          contentDirectory:
              content ?? path(storyline ? 'files/story' : 'modules/Old Title'),
          entryPointPath: entry ??
              path(storyline
                  ? 'files/story/story.html'
                  : 'modules/Old Title/index.html'),
          launcherPath:
              storyline ? launcher ?? path('modules/story.htm') : null,
          version: 'old-version',
          provenance: 'new-install');
  Future<InstructionalInstallationInspection> inspect(
          {int? id = 42, String contentId = '1565', String name = 'Title'}) =>
      service.inspectInstallation(
          databaseId: id, moduleId: contentId, moduleName: name);
  Future<void> expectState(InstructionalInstallationState state,
      {int? id = 42, String name = 'Title'}) async {
    final result = await inspect(id: id, name: name);
    expect(result.state, state, reason: result.reason);
    expect(result.reason, isNotEmpty);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('instructional_inspect_');
    hiveRoot =
        await Directory.systemTemp.createTemp('instructional_inspect_hive_');
    Hive.init(hiveRoot.path);
    registry = ModuleInstallationRegistry();
    service = ModuleInstallationStatusService(
        registry: registry, inspectionRoots: () async => [root]);
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
    await hiveRoot.delete(recursive: true);
  });

  test('compiler identity confirms renamed title and returns paths', () async {
    await compiler(id: '1565');
    await save();
    final result = await inspect(name: 'Renamed');
    expect(result.state, InstructionalInstallationState.confirmed);
    expect(result.paths, contains(path('modules/Old Title/index.html')));
  });
  test(
      'legacy Compiler confirms exact content ID regardless of names or catalog version',
      () async {
    await compiler(folder: 'Old Compiler Folder');
    await write(
        'modules/Old Compiler Folder/module.json',
        jsonEncode({
          'module_id': '1568',
          'module_title': 'Climate Adaptive Health Strategies',
          'version': '1.0',
        }));
    final before = await File(path('modules/Old Compiler Folder/module.json'))
        .readAsBytes();
    // Database ID 135 is intentionally different from content ID 1568. Catalog
    // version 1.1 is not an inspection input and must never replace local 1.0.
    final result =
        await inspect(id: 135, contentId: '1568', name: 'Module Compiler Test');
    expect(result.state, InstructionalInstallationState.confirmed,
        reason: result.reason);
    expect(result.installedVersion, '1.0');
    expect(
        result.paths, contains(path('modules/Old Compiler Folder/index.html')));
    expect(
        await File(path('modules/Old Compiler Folder/module.json'))
            .readAsBytes(),
        before);
    expect(await Hive.boxExists(ModuleInstallationRegistry.boxName), isFalse);
    expect(await hiveRoot.list().toList(), isEmpty);
  });
  test(
      'missing manifest stays candidate; missing or mismatched manifest IDs never confirm',
      () async {
    await compiler(folder: 'Title');
    await expectState(InstructionalInstallationState.legacyCandidate);
    for (final data in [
      {},
      {'module_id': ''},
      {'module_id': null},
      {'module_id': true}
    ]) {
      await write('modules/Title/module.json', jsonEncode(data));
      await expectState(InstructionalInstallationState.invalidRecord);
    }
    await write('modules/Title/module.json', '{"module_id":"9999"}');
    await expectState(InstructionalInstallationState.conflict);
  });
  test(
      'legacy Compiler missing version remains unknown, numeric content ID is exact',
      () async {
    await compiler(folder: 'Unrelated Folder');
    await write('modules/Unrelated Folder/module.json', '{"module_id":1565}');
    final result = await inspect();
    expect(result.state, InstructionalInstallationState.confirmed);
    expect(result.installedVersion, isNull);
  });
  test(
      'manifest-confirmed Compiler cannot override another database path claim',
      () async {
    await compiler(id: '1565');
    await save(id: 99, contentId: '1565');
    await expectState(InstructionalInstallationState.conflict);
  });
  test(
      'empty legacy index is rejected and mixed legacy candidates stay ambiguous',
      () async {
    await compiler(folder: 'Legacy', id: '1565');
    await write('modules/Legacy/index.html', '');
    await expectState(InstructionalInstallationState.conflict);
    await write('modules/Legacy/index.html', 'working');
    await story();
    await expectState(InstructionalInstallationState.ambiguous);
  });
  test(
      'explicit session initialization enables inspection without inspection opening files',
      () async {
    await compiler(id: '1565');
    await save();
    await Hive.close();
    await expectState(InstructionalInstallationState.unavailable);
    expect(Hive.isBoxOpen(ModuleInstallationRegistry.boxName), isFalse);
    await registry.initialize(storageDirectory: hiveRoot.path);
    await expectState(InstructionalInstallationState.confirmed);
    expect(Hive.isBoxOpen(ModuleInstallationRegistry.boxName), isTrue);
  });
  test('Storyline requires correct readable launcher and content', () async {
    await story();
    await save(storyline: true);
    await expectState(InstructionalInstallationState.confirmed);
    await write('modules/story.htm',
        '<meta http-equiv="refresh" content="0; url=../files/other/story.html">');
    await expectState(InstructionalInstallationState.conflict);
  });
  test('wrong content ID overrides matching title', () async {
    await compiler(folder: 'Title');
    await save(
        contentId: '999',
        content: path('modules/Title'),
        entry: path('modules/Title/index.html'));
    await expectState(InstructionalInstallationState.conflict);
  });
  test('manifest conflict overrides registry and sanitized title match',
      () async {
    await compiler(id: '999');
    await save();
    await expectState(InstructionalInstallationState.conflict);
    await registry.removeInstructionalInstallation(42);
    await compiler(folder: 'HIV_AIDS', id: '999');
    await expectState(InstructionalInstallationState.conflict,
        name: 'HIV/AIDS');
  });
  test('another database path claim blocks legacy fallback and confirmation',
      () async {
    await compiler(folder: 'Title');
    await save(
        id: 43,
        content: path('modules/Title'),
        entry: path('modules/Title/index.html'));
    await expectState(InstructionalInstallationState.conflict);
    await save(
        content: path('modules/Title'),
        entry: path('modules/Title/index.html'));
    await expectState(InstructionalInstallationState.conflict);
  });
  test(
      'missing record permits legacy candidate, missing file is stale conflict',
      () async {
    await compiler(folder: 'Title');
    await expectState(InstructionalInstallationState.legacyCandidate);
    await save();
    await expectState(InstructionalInstallationState.conflict);
  });
  test('malformed records and key/database mismatch are invalidRecord',
      () async {
    await compiler();
    await save();
    final box = await registry.openRegistry();
    final valid = await registry.getInstructionalInstallation(42);
    for (final record in [
      null,
      'bad',
      {...valid!, 'database_id': 43},
      {...valid, 'schema_version': 2}
    ]) {
      await box.put('instructional-db:42', record);
      await expectState(InstructionalInstallationState.invalidRecord);
    }
  });
  test('relative, unnormalized, wrong entry type and outside paths conflict',
      () async {
    for (final content in [
      'relative',
      p.join(root.parent.path, 'outside'),
      '${root.path}${p.separator}modules${p.separator}..${p.separator}Title'
    ]) {
      await save(content: content, entry: p.join(content, 'index.html'));
      await expectState(InstructionalInstallationState.conflict);
    }
    await compiler();
    await save(entry: path('modules/Old Title/story.html'));
    await expectState(InstructionalInstallationState.conflict);
  });
  test('reserved recovery and animation paths cannot confirm', () async {
    for (final folder in [
      'modules/Title.backup',
      'modules/Title.staging',
      'modules/animations/42',
      'module_downloads/42',
      'downloads/42'
    ]) {
      await write('$folder/index.html', 'working');
      await save(content: path(folder), entry: path('$folder/index.html'));
      await expectState(InstructionalInstallationState.conflict);
    }
  });
  test(
      'unique legacy manifest match confirms and multiple matches are ambiguous',
      () async {
    await compiler(folder: '1565', id: '1565');
    await expectState(InstructionalInstallationState.confirmed);
    await compiler(folder: 'Renamed', id: '1565');
    await expectState(InstructionalInstallationState.ambiguous);
  });
  test('legacy Storyline and package launchers are candidates', () async {
    await story();
    await expectState(InstructionalInstallationState.legacyCandidate, id: null);
    await write(
        'packages/bundle/module.htm',
        '<meta name="module-title" content="Title">'
            '<meta http-equiv="refresh" content="0; url=files/1234/story/story.html">');
    await write('packages/bundle/files/1234/story/story.html', 'working');
    await expectState(InstructionalInstallationState.ambiguous);
  });
  test('empty or missing entry/launcher prevents confirmation', () async {
    await story();
    await save(storyline: true);
    await File(path('modules/story.htm')).delete();
    await expectState(InstructionalInstallationState.conflict);
    await story();
    await write('files/story/story.html', '');
    await expectState(InstructionalInstallationState.conflict);
  });
  test(
      'unavailable root/provider and closed existing registry stay unavailable',
      () async {
    service = ModuleInstallationStatusService(
        registry: registry,
        inspectionRoots: () async =>
            throw const FileSystemException('access denied'));
    await expectState(InstructionalInstallationState.unavailable);
    service = ModuleInstallationStatusService(
        registry: registry,
        inspectionRoots: () async => [Directory(path('missing'))]);
    await expectState(InstructionalInstallationState.unavailable);
    service = ModuleInstallationStatusService(
        registry: registry, inspectionRoots: () async => [root]);
    await save();
    await Hive.close();
    await expectState(InstructionalInstallationState.unavailable);
  });
  test(
      'inspection creates no directories or registry and changes no file bytes',
      () async {
    await expectState(InstructionalInstallationState.notInstalled);
    expect(await root.list().toList(), isEmpty);
    expect(await hiveRoot.list().toList(), isEmpty);
    await compiler(folder: 'Title');
    final before = await File(path('modules/Title/index.html')).readAsBytes();
    await expectState(InstructionalInstallationState.legacyCandidate);
    expect(await File(path('modules/Title/index.html')).readAsBytes(), before);
    expect(await hiveRoot.list().toList(), isEmpty);
  });
  test('claims query ignores numeric records and diagnoses malformed claims',
      () async {
    await registry.saveInstallation(
        moduleId: '42', version: '1', installationPath: path('modules/Title'));
    expect(
        await registry
            .inspectInstructionalClaims(paths: [path('modules/Title')]),
        isEmpty);
    await (await registry.openRegistry()).put('instructional-db:bad', {});
    await expectState(InstructionalInstallationState.invalidRecord);
    expect(await registry.getInstallation('42'), isNotNull);
  });

  test('inspection preserves open registry records and published file bytes',
      () async {
    await compiler(id: '1565');
    await save();
    final box = await registry.openRegistry();
    await box.flush();
    final record = await registry.getInstructionalInstallation(42);
    final before = <String, List<int>>{};
    for (final directory in [root, hiveRoot]) {
      await for (final entity
          in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          // Hive holds a mandatory Windows lock; compare its presence only.
          before[entity.path] = p.extension(entity.path) == '.lock'
              ? []
              : await entity.readAsBytes();
        }
      }
    }
    await expectState(InstructionalInstallationState.confirmed);
    expect(await registry.getInstructionalInstallation(42), record);
    final after = <String, List<int>>{};
    for (final directory in [root, hiveRoot]) {
      await for (final entity
          in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          after[entity.path] = p.extension(entity.path) == '.lock'
              ? []
              : await entity.readAsBytes();
        }
      }
    }
    expect(after, before);
  });

  test('missing Storyline launcher metadata is candidate, never confirmed',
      () async {
    await story();
    await registry.saveInstructionalInstallation(
        databaseId: 42,
        moduleId: '1565',
        format: 'storyline',
        contentDirectory: path('files/story'),
        entryPointPath: path('files/story/story.html'),
        provenance: 'new-install');
    await expectState(InstructionalInstallationState.legacyCandidate);
  });

  test('invalid requested ID is rejected before resolving storage', () async {
    service = ModuleInstallationStatusService(inspectionRoots: () async {
      fail('Storage must not be resolved for an invalid request');
    });
    for (final id in [0, -1]) {
      await expectLater(inspect(id: id), throwsArgumentError);
    }
    await expectLater(inspect(contentId: ' '), throwsArgumentError);
  });
  test('legacy Compiler symbolic-link manifest never confirms', () async {
    await compiler(folder: 'Title');
    await write('external-manifest.json', '{"module_id":"1565"}');
    try {
      await Link(path('modules/Title/module.json'))
          .create(path('external-manifest.json'));
    } on FileSystemException catch (error) {
      if (Platform.isWindows && [5, 1314].contains(error.osError?.errorCode)) {
        markTestSkipped('Host does not permit creating symbolic links');
        return;
      }
      rethrow;
    }
    await expectState(InstructionalInstallationState.conflict);
    expect(await File(path('external-manifest.json')).readAsString(),
        '{"module_id":"1565"}');
  });
  test('symbolic links never confirm', () async {
    await compiler();
    final link = Link(path('modules/linked'));
    try {
      await link.create(path('modules/Old Title'));
    } on FileSystemException catch (error) {
      // Windows requires symlink privileges/Developer Mode.
      if (Platform.isWindows && [5, 1314].contains(error.osError?.errorCode)) {
        markTestSkipped('Host does not permit creating symbolic links');
        return;
      }
      rethrow;
    }
    await save(content: link.path, entry: p.join(link.path, 'index.html'));
    await expectState(InstructionalInstallationState.conflict);
  });
}
