import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wired_test/services/module_installation_registry.dart';

void main() {
  late Directory directory;
  late ModuleInstallationRegistry registry;

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('instructional_registry_');
    Hive.init(directory.path);
    registry = ModuleInstallationRegistry();
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> save({
    int databaseId = 42,
    String moduleId = '1565',
    String format = 'compiler',
    String contentDirectory = '/offline/Old Title',
    String entryPointPath = '/offline/Old Title/index.html',
    String? launcherPath,
    String? version,
    String provenance = 'new-install',
  }) =>
      registry.saveInstructionalInstallation(
        databaseId: databaseId,
        moduleId: moduleId,
        format: format,
        contentDirectory: contentDirectory,
        entryPointPath: entryPointPath,
        launcherPath: launcherPath,
        version: version,
        provenance: provenance,
      );

  test(
      'explicit initialization creates the registry in the configured directory',
      () async {
    expect(Hive.isBoxOpen(ModuleInstallationRegistry.boxName), isFalse);
    final box = await registry.initialize(storageDirectory: directory.path);
    expect(box.isOpen, isTrue);
    expect(Hive.isBoxOpen(ModuleInstallationRegistry.boxName), isTrue);
    expect(box.path,
        '${directory.path}${Platform.pathSeparator}module_installations.hive');
    expect(
        await registry.initialize(storageDirectory: directory.path), same(box));
  });

  test('concurrent instances share initialization, including legacy access',
      () async {
    final first = registry.initialize(storageDirectory: directory.path);
    final second = ModuleInstallationRegistry()
        .initialize(storageDirectory: directory.path);
    expect(second, same(first));
    final legacy = ModuleInstallationRegistry().openRegistry();
    final box = await first;
    expect(await second, same(box));
    expect(await legacy, same(box));
  });

  test(
      'initialization preserves numeric and instructional records across restart',
      () async {
    await registry.saveInstallation(
        moduleId: '42', version: 'legacy', installationPath: '/legacy');
    await save();
    final numeric = await registry.getInstallation('42');
    final instructional = await registry.getInstructionalInstallation(42);
    await Hive.close();
    Hive.init(directory.path);
    await ModuleInstallationRegistry()
        .initialize(storageDirectory: directory.path);
    expect(await registry.getInstallation('42'), numeric);
    expect(await registry.getInstructionalInstallation(42), instructional);
  });

  test('recovery artifacts are not deleted or restored; failure permits retry',
      () async {
    final artifact = File(
        '${directory.path}${Platform.pathSeparator}module_installations.hivec');
    await artifact.writeAsString('preserve recovery artifact');
    final first = registry.initialize(storageDirectory: directory.path);
    final second = ModuleInstallationRegistry()
        .initialize(storageDirectory: directory.path);
    expect(second, same(first));
    await Future.wait([
      expectLater(first, throwsA(isA<HiveError>())),
      expectLater(second, throwsA(isA<HiveError>())),
    ]);
    expect(await artifact.readAsString(), 'preserve recovery artifact');
    expect(
        await File(
                '${directory.path}${Platform.pathSeparator}module_installations.hive')
            .exists(),
        isFalse);
    expect(Hive.isBoxOpen(ModuleInstallationRegistry.boxName), isFalse);
    // Test-only manual resolution. Production initialization never does this.
    await expectLater(
        ModuleInstallationRegistry().openRegistry(), throwsA(isA<HiveError>()));
    expect(await artifact.readAsString(), 'preserve recovery artifact');
    await artifact.rename('${artifact.path}.retained');
    final box = await registry.initialize(storageDirectory: directory.path);
    expect(box.isOpen, isTrue);
    expect(await File('${artifact.path}.retained').readAsString(),
        'preserve recovery artifact');
  });

  test('existing data and malformed records are never reset during startup',
      () async {
    final box = await registry.openRegistry();
    await box.put('instructional-db:42', 'malformed but preserved');
    await Hive.close();
    final data = File(
        '${directory.path}${Platform.pathSeparator}module_installations.hive');
    final before = await data.readAsBytes();
    await registry.initialize(storageDirectory: directory.path);
    expect(
        Hive.box(ModuleInstallationRegistry.boxName).get('instructional-db:42'),
        'malformed but preserved');
    await Hive.close();
    expect(await data.readAsBytes(), before);
  });

  test('corrupt data is rejected without truncation or automatic recovery',
      () async {
    await save();
    await Hive.close();
    final data = File(
        '${directory.path}${Platform.pathSeparator}module_installations.hive');
    await data.writeAsBytes([1, 2, 3], mode: FileMode.append);
    final before = await data.readAsBytes();
    await expectLater(registry.initialize(storageDirectory: directory.path),
        throwsA(isA<HiveError>()));
    expect(await data.readAsBytes(), before);
    expect(Hive.isBoxOpen(ModuleInstallationRegistry.boxName), isFalse);
    await expectLater(registry.openRegistry(), throwsA(isA<HiveError>()));
    // Keep damaged bytes for review; restore only this test's original fixture.
    await data.rename('${data.path}.retained');
    await registry.initialize(storageDirectory: directory.path);
  });

  test(
      'a recovery artifact alongside valid data also blocks destructive opening',
      () async {
    await save();
    await Hive.close();
    final data = File(
        '${directory.path}${Platform.pathSeparator}module_installations.hive');
    final before = await data.readAsBytes();
    final artifact = File(
        '${directory.path}${Platform.pathSeparator}module_installations.hivec');
    await artifact.writeAsString('leftover');
    await expectLater(registry.initialize(storageDirectory: directory.path),
        throwsA(isA<HiveError>()));
    expect(await artifact.readAsString(), 'leftover');
    expect(await data.readAsBytes(), before);
    await expectLater(save(), throwsA(isA<HiveError>()));
    expect(await data.readAsBytes(), before);
    // End this test's failed session with explicit, test-only resolution.
    await artifact.rename('${artifact.path}.retained');
    await registry.initialize(storageDirectory: directory.path);
  });

  test('compiler save/retrieve preserves distinct IDs and actual locators',
      () async {
    await save(version: '2.1');
    final record = (await registry.getInstructionalInstallation(42))!;
    expect(record, {
      'schema_version': 1,
      'database_id': 42,
      'module_id': '1565',
      'format': 'compiler',
      'content_directory': '/offline/Old Title',
      'entry_point_path': '/offline/Old Title/index.html',
      'version': '2.1',
      'installed_at': record['installed_at'],
      'provenance': 'new-install',
    });
    expect(DateTime.parse(record['installed_at'] as String).isUtc, isTrue);
    expect((await registry.openRegistry()).containsKey('instructional-db:42'),
        isTrue);
    expect(await registry.getInstructionalInstallation(1565), isNull);
    // Locators need not exist: this API is metadata storage, not status checking.
    expect(record.containsKey('launcher_path'), isFalse);
  });

  for (final launcher in <String?>[null, '/offline/modules/story.htm']) {
    test('Storyline supports optional launcher $launcher', () async {
      await save(
        format: 'storyline',
        contentDirectory: '/offline/files/story',
        entryPointPath: '/offline/files/story/story.html',
        launcherPath: launcher,
        provenance: 'verified-legacy-import',
      );
      final record = (await registry.getInstructionalInstallation(42))!;
      expect(record['format'], 'storyline');
      expect(record['launcher_path'], launcher);
      expect(record.containsKey('version'), isFalse);
      expect(record['provenance'], 'verified-legacy-import');
    });
  }

  test('removal is idempotent and preserves numeric records', () async {
    await registry.saveInstallation(
        moduleId: '42', version: 'old', installationPath: '/legacy');
    final legacy = await registry.getInstallation('42');
    await save();
    await save(databaseId: 43);
    expect(await registry.getInstallation('42'), legacy);
    await registry.removeInstructionalInstallation(42);
    await registry.removeInstructionalInstallation(42);
    expect(await registry.getInstructionalInstallation(42), isNull);
    expect(await registry.getInstructionalInstallation(43), isNotNull);
    expect(await registry.getInstallation('42'), legacy);
  });

  test('all operations reject nonpositive database IDs', () async {
    for (final id in [0, -1]) {
      await expectLater(save(databaseId: id), throwsArgumentError);
      await expectLater(
          registry.getInstructionalInstallation(id), throwsArgumentError);
      await expectLater(
          registry.removeInstructionalInstallation(id), throwsArgumentError);
    }
  });

  test('rejects blank required and optional fields and unknown formats',
      () async {
    for (final attempt in <Future<void> Function()>[
      () => save(moduleId: ' '),
      () => save(format: ''),
      () => save(format: 'other'),
      () => save(contentDirectory: ' '),
      () => save(entryPointPath: ''),
      () => save(provenance: ' '),
      () => save(version: ''),
      () => save(format: 'storyline', launcherPath: ' '),
      () => save(launcherPath: '/compiler-launcher.htm'),
    ]) {
      await expectLater(attempt(), throwsArgumentError);
    }
    expect(await registry.getInstructionalInstallation(42), isNull);
  });

  test('rejects malformed stored records without changing them', () async {
    await save();
    final valid = (await registry.getInstructionalInstallation(42))!;
    final box = await registry.openRegistry();
    final malformed = <dynamic>[
      null,
      'invalid',
      <String, dynamic>{},
      {...valid, 'schema_version': 2},
      {...valid, 'schema_version': 1.0},
      {...valid, 'database_id': 43},
      {...valid, 'database_id': '42'},
      {...valid, 'module_id': 1565},
      {...valid, 'format': 'unknown'},
      {...valid, 'content_directory': ''},
      {...valid, 'entry_point_path': null},
      {...valid, 'provenance': false},
      {...valid, 'installed_at': 'yesterday'},
      {...valid, 'launcher_path': null},
      {...valid, 'version': 2},
      {...valid, 123: 'non-string key'},
    ];
    for (final record in malformed) {
      await box.put('instructional-db:42', record);
      await expectLater(
          registry.getInstructionalInstallation(42), throwsStateError);
      expect(box.get('instructional-db:42'), record);
    }
  });

  test('records persist across Hive and registry reinitialization', () async {
    await save(version: '1');
    final before = await registry.getInstructionalInstallation(42);
    await Hive.close();
    Hive.init(directory.path);
    registry = ModuleInstallationRegistry();
    expect(await registry.getInstructionalInstallation(42), before);
    await save(version: '2');
    expect((await registry.getInstructionalInstallation(42))!['version'], '2');
  });
}
