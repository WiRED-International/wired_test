
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wired_test/services/module_installation_registry.dart';
import 'package:wired_test/services/module_installation_coordinator.dart';
import 'package:flutter/services.dart';
import 'package:wired_test/services/module_download_service.dart';


class FailingInstallationRegistry extends ModuleInstallationRegistry {
  @override
  Future<void> saveInstallation({
    required String moduleId,
    required String version,
    required String installationPath,
  }) async {
    throw StateError('Simulated Hive write failure');
  }
}

class FailingRollbackRegistry extends ModuleInstallationRegistry {
  @override
  Future<void> saveInstallation({
    required String moduleId,
    required String version,
    required String installationPath,
  }) async {
    throw StateError('Simulated Hive write failure');
  }

  @override
  Future<void> restoreInstallationRecord({
    required String moduleId,
    required Map<String, dynamic>? previousRecord,
  }) async {
    throw StateError('Simulated Hive rollback failure');
  }
}

class MissingBackupRegistry extends ModuleInstallationRegistry {
  final Directory backupDirectory;

  MissingBackupRegistry(this.backupDirectory);

  @override
  Future<void> saveInstallation({
    required String moduleId,
    required String version,
    required String installationPath,
  }) async {
    // Simulate the backup disappearing before Hive fails.
    if (await backupDirectory.exists()) {
      await backupDirectory.delete(recursive: true);
    }

    throw StateError('Simulated Hive failure with missing backup');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDirectory;

  setUpAll(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'healthmap_registry_test_',
    );

    Hive.init(testDirectory.path);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async {
        if (call.method == 'getExternalStorageDirectory' ||
            call.method == 'getApplicationDocumentsDirectory') {
          return testDirectory.path;
        }
        return null;
      },
    );
  });

  tearDownAll(() async {
    await Hive.close();

    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  test('Saves and retrieves a module installation', () async {
    final registry = ModuleInstallationRegistry();

    await registry.saveInstallation(
      moduleId: '9990',
      version: '1.0',
      installationPath: '/modules/9990',
    );

    final record = await registry.getInstallation('9990');

    expect(record, isNotNull);
    expect(record!['module_id'], '9990');
    expect(record['version'], '1.0');
    expect(record['installation_path'], '/modules/9990');
    expect(record['installed_at'], isNotNull);
  });

  test('Updates an existing module installation record', () async {
    final registry = ModuleInstallationRegistry();
    const moduleId = '9989';

    // Record the original installation.
    await registry.saveInstallation(
      moduleId: moduleId,
      version: '1.0',
      installationPath: '/modules/9989',
    );

    // Simulate installing an updated version.
    await registry.saveInstallation(
      moduleId: moduleId,
      version: '1.1',
      installationPath: '/modules/9989',
    );

    final record = await registry.getInstallation(moduleId);

    expect(record, isNotNull);
    expect(record!['module_id'], moduleId);
    expect(record['version'], '1.1');
    expect(record['installation_path'], '/modules/9989');

    // Confirm that Hive contains only one record for this module.
    final box = await registry.openRegistry();

    expect(
      box.keys.where((key) => key == moduleId).length,
      1,
    );
  });

  test('Restores the previous installation record', () async {
    final registry = ModuleInstallationRegistry();
    const moduleId = '9988';

    // Save the original installation.
    await registry.saveInstallation(
      moduleId: moduleId,
      version: '1.0',
      installationPath: '/modules/9988',
    );

    // Preserve the original record before updating.
    final previousRecord =
    await registry.getInstallation(moduleId);

    expect(previousRecord, isNotNull);

    // Simulate installing a newer version.
    await registry.saveInstallation(
      moduleId: moduleId,
      version: '1.1',
      installationPath: '/modules/9988',
    );

    // Roll back the registry to the original version.
    await registry.restoreInstallationRecord(
      moduleId: moduleId,
      previousRecord: previousRecord,
    );

    final restoredRecord =
    await registry.getInstallation(moduleId);

    expect(restoredRecord, isNotNull);
    expect(restoredRecord!['version'], '1.0');
    expect(restoredRecord, previousRecord);
  });

  test('Removes registry record after failed first installation', () async {
    final registry = ModuleInstallationRegistry();
    const moduleId = '9987';

    // Confirm this module has no existing registry record.
    final previousRecord =
    await registry.getInstallation(moduleId);

    expect(previousRecord, isNull);

    // Simulate recording a first-time installation.
    await registry.saveInstallation(
      moduleId: moduleId,
      version: '1.0',
      installationPath: '/modules/9987',
    );

    expect(
      await registry.getInstallation(moduleId),
      isNotNull,
    );

    // Simulate rolling back the installation.
    await registry.restoreInstallationRecord(
      moduleId: moduleId,
      previousRecord: previousRecord,
    );

    // The incomplete installation record must be removed.
    expect(
      await registry.getInstallation(moduleId),
      isNull,
    );
  });

  test('Blocks installation when a backup requires recovery', () async {
    final coordinator = ModuleInstallationCoordinator();
    const moduleId = '9986';

    final moduleDirectory =
    await coordinator.downloadService.getModuleDirectory(moduleId);

    final backupDirectory =
    await coordinator.downloadService.getModuleBackupDirectory(moduleId);

    expect(await moduleDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);

    try {
      // Simulate an interrupted replacement:
      // the original module has been moved into backup.
      await backupDirectory.create(recursive: true);

      await expectLater(
        coordinator.ensureReadyForInstallation(moduleId),
        throwsA(isA<StateError>()),
      );

      // The coordinator must not modify either directory.
      expect(await backupDirectory.exists(), isTrue);
      expect(await moduleDirectory.exists(), isFalse);
    } finally {
      if (await backupDirectory.exists()) {
        await backupDirectory.delete(recursive: true);
      }
    }
  });

  test('Blocks installation when registered module files are missing',
      () async {
    final coordinator = ModuleInstallationCoordinator();
    const moduleId = '9985';

    final moduleDirectory =
    await coordinator.downloadService.getModuleDirectory(moduleId);

    final backupDirectory =
    await coordinator.downloadService.getModuleBackupDirectory(moduleId);

    expect(await moduleDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);

    try {
      // Hive records an installation, but its files are missing.
      await coordinator.registry.saveInstallation(
        moduleId: moduleId,
        version: '1.0',
        installationPath: moduleDirectory.path,
      );

      await expectLater(
        coordinator.ensureReadyForInstallation(moduleId),
        throwsA(isA<StateError>()),
      );

      // The safety check must not create or modify module files.
      expect(await moduleDirectory.exists(), isFalse);
      expect(await backupDirectory.exists(), isFalse);
    } finally {
      // Remove the test registry record.
      await coordinator.registry.restoreInstallationRecord(
        moduleId: moduleId,
        previousRecord: null,
      );
    }
  });

  test('Allows installation when module state is clean', () async {
    final coordinator = ModuleInstallationCoordinator();
    const moduleId = '9984';

    final moduleDirectory =
    await coordinator.downloadService.getModuleDirectory(moduleId);
    final backupDirectory =
    await coordinator.downloadService.getModuleBackupDirectory(moduleId);

    expect(await moduleDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);
    expect(
      await coordinator.registry.getInstallation(moduleId),
      isNull,
    );

    // A first-time installation should be allowed.
    await coordinator.ensureReadyForInstallation(moduleId);

    try {
      // Simulate an existing, registered installation.
      await moduleDirectory.create(recursive: true);

      await coordinator.registry.saveInstallation(
        moduleId: moduleId,
        version: '1.0',
        installationPath: moduleDirectory.path,
      );

      // An update should also be allowed when no backup exists.
      await coordinator.ensureReadyForInstallation(moduleId);
    } finally {
      if (await moduleDirectory.exists()) {
        await moduleDirectory.delete(recursive: true);
      }

      await coordinator.registry.restoreInstallationRecord(
        moduleId: moduleId,
        previousRecord: null,
      );
    }
  });

  test('Prepares a valid module without installing it', () async {
    final coordinator = ModuleInstallationCoordinator();
    const moduleId = '9983';

    final stagingDirectory =
    await coordinator.downloadService.getStagingDirectory(moduleId);
    final moduleDirectory =
    await coordinator.downloadService.getModuleDirectory(moduleId);
    final backupDirectory =
    await coordinator.downloadService.getModuleBackupDirectory(moduleId);

    expect(await stagingDirectory.exists(), isFalse);
    expect(await moduleDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);

    try {
      // Create a valid staged module.
      await stagingDirectory.create(recursive: true);

      await File(
        '${stagingDirectory.path}/index.html',
      ).writeAsString('<html>Test module</html>');

      await File(
        '${stagingDirectory.path}/module.json',
      ).writeAsString('{"module_id": "9983"}');

      // Preparation should succeed without installing anything.
      await coordinator.prepareInstallation(moduleId);

      expect(await stagingDirectory.exists(), isTrue);
      expect(await moduleDirectory.exists(), isFalse);
      expect(await backupDirectory.exists(), isFalse);

      // No installation record should have been created.
      expect(
        await coordinator.registry.getInstallation(moduleId),
        isNull,
      );
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }

      if (await moduleDirectory.exists()) {
        await moduleDirectory.delete(recursive: true);
      }

      if (await backupDirectory.exists()) {
        await backupDirectory.delete(recursive: true);
      }
    }
  });

  test('Installs a module and records it in Hive', () async {
    final coordinator = ModuleInstallationCoordinator();
    const moduleId = '9982';

    final stagingDirectory =
    await coordinator.downloadService.getStagingDirectory(moduleId);
    final moduleDirectory =
    await coordinator.downloadService.getModuleDirectory(moduleId);
    final backupDirectory =
    await coordinator.downloadService.getModuleBackupDirectory(moduleId);

    expect(await stagingDirectory.exists(), isFalse);
    expect(await moduleDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);
    expect(
      await coordinator.registry.getInstallation(moduleId),
      isNull,
    );

    try {
      // Create a valid staged module.
      await stagingDirectory.create(recursive: true);

      await File(
        '${stagingDirectory.path}/index.html',
      ).writeAsString('<html>Installed module</html>');

      await File(
        '${stagingDirectory.path}/module.json',
      ).writeAsString('{"module_id": "9982"}');

      // Install the module and record its version.
      final installedDirectory = await coordinator.installModule(
        moduleId: moduleId,
        version: '1.0',
      );

      expect(installedDirectory.path, moduleDirectory.path);
      expect(await moduleDirectory.exists(), isTrue);
      expect(await stagingDirectory.exists(), isFalse);

      // First-time installation should not create a backup.
      expect(await backupDirectory.exists(), isFalse);

      // Verify the installed files.
      final content = await File(
        '${moduleDirectory.path}/index.html',
      ).readAsString();

      expect(content, '<html>Installed module</html>');

      // Verify the Hive installation record.
      final record = await coordinator.registry.getInstallation(moduleId);

      expect(record, isNotNull);
      expect(record!['module_id'], moduleId);
      expect(record['version'], '1.0');
      expect(record['installation_path'], moduleDirectory.path);
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }

      if (await moduleDirectory.exists()) {
        await moduleDirectory.delete(recursive: true);
      }

      if (await backupDirectory.exists()) {
        await backupDirectory.delete(recursive: true);
      }

      await coordinator.registry.restoreInstallationRecord(
        moduleId: moduleId,
        previousRecord: null,
      );
    }
  });

  test('Updates an installed module and removes its backup', () async {
    final coordinator = ModuleInstallationCoordinator();
    const moduleId = '9981';

    final moduleDirectory =
    await coordinator.downloadService.getModuleDirectory(moduleId);
    final stagingDirectory =
    await coordinator.downloadService.getStagingDirectory(moduleId);
    final backupDirectory =
    await coordinator.downloadService.getModuleBackupDirectory(moduleId);

    expect(await moduleDirectory.exists(), isFalse);
    expect(await stagingDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);
    expect(
      await coordinator.registry.getInstallation(moduleId),
      isNull,
    );

    try {
      // Simulate an existing module installation.
      await moduleDirectory.create(recursive: true);

      await File(
        '${moduleDirectory.path}/index.html',
      ).writeAsString('Original version');

      await coordinator.registry.saveInstallation(
        moduleId: moduleId,
        version: '1.0',
        installationPath: moduleDirectory.path,
      );

      // Prepare an updated module.
      await stagingDirectory.create(recursive: true);

      await File(
        '${stagingDirectory.path}/index.html',
      ).writeAsString('Updated version');

      await File(
        '${stagingDirectory.path}/module.json',
      ).writeAsString('{"module_id": "9981"}');

      // Install the updated version.
      await coordinator.installModule(
        moduleId: moduleId,
        version: '1.1',
      );

      // Confirm the new version is installed.
      final installedContent = await File(
        '${moduleDirectory.path}/index.html',
      ).readAsString();

      expect(installedContent, 'Updated version');

      // Confirm the temporary backup was removed.
      expect(await backupDirectory.exists(), isFalse);

      // Confirm Hive records the updated version.
      final record = await coordinator.registry.getInstallation(moduleId);

      expect(record, isNotNull);
      expect(record!['version'], '1.1');
      expect(record['installation_path'], moduleDirectory.path);

      expect(await stagingDirectory.exists(), isFalse);
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }

      if (await moduleDirectory.exists()) {
        await moduleDirectory.delete(recursive: true);
      }

      if (await backupDirectory.exists()) {
        await backupDirectory.delete(recursive: true);
      }

      await coordinator.registry.restoreInstallationRecord(
        moduleId: moduleId,
        previousRecord: null,
      );
    }
  });

  test('Restores existing module when Hive update fails', () async {
    final coordinator = ModuleInstallationCoordinator(
      registry: FailingInstallationRegistry(),
    );

    const moduleId = '9980';

    final moduleDirectory =
    await coordinator.downloadService.getModuleDirectory(moduleId);
    final stagingDirectory =
    await coordinator.downloadService.getStagingDirectory(moduleId);
    final backupDirectory =
    await coordinator.downloadService.getModuleBackupDirectory(moduleId);

    expect(await moduleDirectory.exists(), isFalse);
    expect(await stagingDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);

    try {
      // Create the original installation.
      await moduleDirectory.create(recursive: true);

      await File(
        '${moduleDirectory.path}/index.html',
      ).writeAsString('Original working module');

      // Use the normal registry to record the original version.
      final normalRegistry = ModuleInstallationRegistry();

      await normalRegistry.saveInstallation(
        moduleId: moduleId,
        version: '1.0',
        installationPath: moduleDirectory.path,
      );

      // Prepare the replacement.
      await stagingDirectory.create(recursive: true);

      await File(
        '${stagingDirectory.path}/index.html',
      ).writeAsString('Updated module');

      await File(
        '${stagingDirectory.path}/module.json',
      ).writeAsString('{"module_id": "9980"}');

      // The simulated Hive failure should trigger rollback.
      await expectLater(
        coordinator.installModule(
          moduleId: moduleId,
          version: '1.1',
        ),
        throwsA(isA<StateError>()),
      );

      // The original module must be restored.
      expect(await moduleDirectory.exists(), isTrue);

      final restoredContent = await File(
        '${moduleDirectory.path}/index.html',
      ).readAsString();

      expect(restoredContent, 'Original working module');

      // The backup should have been moved back into place.
      expect(await backupDirectory.exists(), isFalse);

      // Hive must still contain the original version.
      final record = await normalRegistry.getInstallation(moduleId);

      expect(record, isNotNull);
      expect(record!['version'], '1.0');
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }

      if (await moduleDirectory.exists()) {
        await moduleDirectory.delete(recursive: true);
      }

      if (await backupDirectory.exists()) {
        await backupDirectory.delete(recursive: true);
      }

      await ModuleInstallationRegistry().restoreInstallationRecord(
        moduleId: moduleId,
        previousRecord: null,
      );
    }
  });

  test('Restores module files even when Hive rollback fails', () async {
    final coordinator = ModuleInstallationCoordinator(
      registry: FailingRollbackRegistry(),
    );

    const moduleId = '9979';

    final moduleDirectory =
    await coordinator.downloadService.getModuleDirectory(moduleId);
    final stagingDirectory =
    await coordinator.downloadService.getStagingDirectory(moduleId);
    final backupDirectory =
    await coordinator.downloadService.getModuleBackupDirectory(moduleId);

    expect(await moduleDirectory.exists(), isFalse);
    expect(await stagingDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);

    final normalRegistry = ModuleInstallationRegistry();

    try {
      // Create an existing installation.
      await moduleDirectory.create(recursive: true);

      await File(
        '${moduleDirectory.path}/index.html',
      ).writeAsString('Original working module');

      await normalRegistry.saveInstallation(
        moduleId: moduleId,
        version: '1.0',
        installationPath: moduleDirectory.path,
      );

      // Prepare the replacement.
      await stagingDirectory.create(recursive: true);

      await File(
        '${stagingDirectory.path}/index.html',
      ).writeAsString('Updated module');

      await File(
        '${stagingDirectory.path}/module.json',
      ).writeAsString('{"module_id": "9979"}');

      // Both the Hive write and Hive rollback will fail.
      await expectLater(
        coordinator.installModule(
          moduleId: moduleId,
          version: '1.1',
        ),
        throwsA(isA<StateError>()),
      );

      // The original module should still be restored.
      final restoredContent = await File(
        '${moduleDirectory.path}/index.html',
      ).readAsString();

      expect(restoredContent, 'Original working module');

      // The backup should have been restored into place.
      expect(await backupDirectory.exists(), isFalse);

      // The original Hive record should remain unchanged.
      final record = await normalRegistry.getInstallation(moduleId);

      expect(record, isNotNull);
      expect(record!['version'], '1.0');
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }

      if (await moduleDirectory.exists()) {
        await moduleDirectory.delete(recursive: true);
      }

      if (await backupDirectory.exists()) {
        await backupDirectory.delete(recursive: true);
      }

      await normalRegistry.restoreInstallationRecord(
        moduleId: moduleId,
        previousRecord: null,
      );
    }
  });

  test('Preserves installed files when backup disappears', () async {
    const moduleId = '9978';

    final downloadService = ModuleDownloadService();

    final moduleDirectory =
    await downloadService.getModuleDirectory(moduleId);
    final stagingDirectory =
    await downloadService.getStagingDirectory(moduleId);
    final backupDirectory =
    await downloadService.getModuleBackupDirectory(moduleId);

    final normalRegistry = ModuleInstallationRegistry();

    final coordinator = ModuleInstallationCoordinator(
      downloadService: downloadService,
      registry: MissingBackupRegistry(backupDirectory),
    );

    expect(await moduleDirectory.exists(), isFalse);
    expect(await stagingDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);
    expect(await normalRegistry.getInstallation(moduleId), isNull);

    try {
      // Create an existing installation.
      await moduleDirectory.create(recursive: true);

      await File(
        '${moduleDirectory.path}/index.html',
      ).writeAsString('Original version');

      await normalRegistry.saveInstallation(
        moduleId: moduleId,
        version: '1.0',
        installationPath: moduleDirectory.path,
      );

      // Prepare the replacement.
      await stagingDirectory.create(recursive: true);

      await File(
        '${stagingDirectory.path}/index.html',
      ).writeAsString('Updated version');

      await File(
        '${stagingDirectory.path}/module.json',
      ).writeAsString('{"module_id": "9978"}');

      // Simulate backup loss followed by Hive failure.
      await expectLater(
        coordinator.installModule(
          moduleId: moduleId,
          version: '1.1',
        ),
        throwsA(isA<StateError>()),
      );

      // The replacement files must not be deleted.
      expect(await moduleDirectory.exists(), isTrue);

      final content = await File(
        '${moduleDirectory.path}/index.html',
      ).readAsString();

      expect(content, 'Updated version');

      // The simulated failure removed the backup.
      expect(await backupDirectory.exists(), isFalse);

      // Hive still records the previous version.
      final record = await normalRegistry.getInstallation(moduleId);

      expect(record, isNotNull);
      expect(record!['version'], '1.0');
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }

      if (await moduleDirectory.exists()) {
        await moduleDirectory.delete(recursive: true);
      }

      if (await backupDirectory.exists()) {
        await backupDirectory.delete(recursive: true);
      }

      await normalRegistry.restoreInstallationRecord(
        moduleId: moduleId,
        previousRecord: null,
      );
    }
  });

  test('Blocks installation when files exist without a registry record',
          () async {
        const moduleId = '9977';

        final downloadService = ModuleDownloadService();
        final registry = ModuleInstallationRegistry();

        final coordinator = ModuleInstallationCoordinator(
          downloadService: downloadService,
          registry: registry,
        );

        final moduleDirectory =
        await downloadService.getModuleDirectory(moduleId);

        try {
          // Simulate module files existing without a Hive record.
          await moduleDirectory.create(recursive: true);

          await File(
            '${moduleDirectory.path}/index.html',
          ).writeAsString('Existing untracked module');

          expect(await registry.getInstallation(moduleId), isNull);

          // The coordinator must refuse to overwrite these files.
          await expectLater(
            coordinator.ensureReadyForInstallation(moduleId),
            throwsA(isA<StateError>()),
          );

          // Verify the original files remain untouched.
          final content = await File(
            '${moduleDirectory.path}/index.html',
          ).readAsString();

          expect(content, 'Existing untracked module');
        } finally {
          if (await moduleDirectory.exists()) {
            await moduleDirectory.delete(recursive: true);
          }
        }
      });

}
