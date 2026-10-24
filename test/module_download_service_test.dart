
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:wired_test/services/module_download_service.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
      if (methodCall.method == 'getExternalStorageDirectory' ||
          methodCall.method == 'getApplicationDocumentsDirectory') {
        return Directory.systemTemp.path;
      }

      return null;
    },
  );
  test('Validates a correctly structured HealthMAP module', () async {
    final stagingDirectory =
    await Directory.systemTemp.createTemp('healthmap_test_');

    try {
      final indexFile = File('${stagingDirectory.path}/index.html');
      await indexFile.writeAsString('<html><body>Test</body></html>');

      final manifestFile = File('${stagingDirectory.path}/module.json');
      await manifestFile.writeAsString(
        jsonEncode({
          'module_id': 1563,
          'version': '1.0.0',
        }),
      );

      final service = ModuleDownloadService();

      await service.validateExtractedModule(
        moduleId: '1563',
        stagingDirectory: stagingDirectory,
      );
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }
    }
  });


  test('Rejects a module with an incorrect module ID', () async {
    final stagingDirectory =
    await Directory.systemTemp.createTemp('healthmap_test_');

    try {
      final indexFile = File('${stagingDirectory.path}/index.html');
      await indexFile.writeAsString('<html><body>Test</body></html>');

      final manifestFile = File('${stagingDirectory.path}/module.json');
      await manifestFile.writeAsString(
        jsonEncode({
          'module_id': 9999,
          'version': '1.0.0',
        }),
      );

      final service = ModuleDownloadService();

      await expectLater(
        service.validateExtractedModule(
          moduleId: '1563',
          stagingDirectory: stagingDirectory,
        ),
        throwsA(isA<FormatException>()),
      );
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }
    }
  });


  test('Extracts a valid HealthMAP module ZIP', () async {
    final service = ModuleDownloadService();

    final downloadsDirectory = await service.getDownloadsDirectory();
    final stagingDirectory = await service.getStagingDirectory('1563');

    final zipFile = File(
      '${downloadsDirectory.path}/1563_test.zip',
    );

    // Ensure this test starts with a clean staging directory.
    if (await stagingDirectory.exists()) {
      await stagingDirectory.delete(recursive: true);
    }

    try {
      final archive = Archive();

      final indexBytes = utf8.encode(
        '<html><body>HealthMAP Test</body></html>',
      );

      final manifestBytes = utf8.encode(
        jsonEncode({
          'module_id': 1563,
          'version': '1.0.0',
        }),
      );

      archive.addFile(
        ArchiveFile('index.html', indexBytes.length, indexBytes),
      );

      archive.addFile(
        ArchiveFile('module.json', manifestBytes.length, manifestBytes),
      );

      final zipBytes = ZipEncoder().encode(archive);

      await zipFile.writeAsBytes(zipBytes);

      final extractedDirectory = await service.extractModuleZip(
        moduleId: '1563',
        zipFile: zipFile,
      );

      expect(
        await File('${extractedDirectory.path}/index.html').exists(),
        isTrue,
      );

      expect(
        await File('${extractedDirectory.path}/module.json').exists(),
        isTrue,
      );

      await service.validateExtractedModule(
        moduleId: '1563',
        stagingDirectory: extractedDirectory,
      );
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }

      if (await zipFile.exists()) {
        await zipFile.delete();
      }
    }
  });


  test('Rejects ZIP entries that escape the staging directory', () async {
    final service = ModuleDownloadService();

    final downloadsDirectory = await service.getDownloadsDirectory();
    final stagingDirectory = await service.getStagingDirectory('9998');

    final zipFile = File(
      '${downloadsDirectory.path}/9998_test.zip',
    );

    if (await stagingDirectory.exists()) {
      await stagingDirectory.delete(recursive: true);
    }

    try {
      final archive = Archive();
      final bytes = utf8.encode('Unsafe test content');

      archive.addFile(
        ArchiveFile('../outside.txt', bytes.length, bytes),
      );

      final zipBytes = ZipEncoder().encode(archive);
      await zipFile.writeAsBytes(zipBytes);

      await expectLater(
        service.extractModuleZip(
          moduleId: '9998',
          zipFile: zipFile,
        ),
        throwsA(isA<FormatException>()),
      );

      // A rejected archive must not leave a staging directory.
      expect(await stagingDirectory.exists(), isFalse);
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }

      if (await zipFile.exists()) {
        await zipFile.delete();
      }
    }
  });


  test('Rejects symbolic links in module ZIPs', () async {
    final service = ModuleDownloadService();

    final downloadsDirectory = await service.getDownloadsDirectory();
    final stagingDirectory = await service.getStagingDirectory('9997');

    final zipFile = File(
      '${downloadsDirectory.path}/9997_test.zip',
    );

    if (await stagingDirectory.exists()) {
      await stagingDirectory.delete(recursive: true);
    }

    try {
      final archive = Archive();

      final linkBytes = utf8.encode('../outside.txt');

      final linkEntry = ArchiveFile(
        'unsafe_link',
        linkBytes.length,
        linkBytes,
      );

      linkEntry.symbolicLink = '../outside.txt';

      archive.addFile(linkEntry);

      final zipBytes = ZipEncoder().encode(archive);
      await zipFile.writeAsBytes(zipBytes);

      await expectLater(
        service.extractModuleZip(
          moduleId: '9997',
          zipFile: zipFile,
        ),
        throwsA(isA<FormatException>()),
      );

      expect(await stagingDirectory.exists(), isFalse);
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }

      if (await zipFile.exists()) {
        await zipFile.delete();
      }
    }
  });

  test('Backs up and restores an installed module', () async {
    final service = ModuleDownloadService();
    const moduleId = '9996';

    final moduleDirectory =
    await service.getModuleDirectory(moduleId);
    final backupDirectory =
    await service.getModuleBackupDirectory(moduleId);

    // Avoid modifying any existing module or backup.
    expect(await moduleDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);

    try {
      await moduleDirectory.create(recursive: true);

      final indexFile = File(
        '${moduleDirectory.path}/index.html',
      );
      await indexFile.writeAsString('Original module content');

      final backedUp = await service.backupExistingModule(moduleId);

      expect(backedUp, isTrue);
      expect(await moduleDirectory.exists(), isFalse);
      expect(await backupDirectory.exists(), isTrue);

      final restored = await service.restoreModuleBackup(moduleId);

      expect(restored, isTrue);
      expect(await moduleDirectory.exists(), isTrue);
      expect(await backupDirectory.exists(), isFalse);

      final restoredContent = await File(
        '${moduleDirectory.path}/index.html',
      ).readAsString();

      expect(restoredContent, 'Original module content');
    } finally {
      if (await moduleDirectory.exists()) {
        await moduleDirectory.delete(recursive: true);
      }

      if (await backupDirectory.exists()) {
        await backupDirectory.delete(recursive: true);
      }
    }
  });

  test('Installs a validated staged module', () async {
    final service = ModuleDownloadService();
    const moduleId = '9995';

    final stagingDirectory =
    await service.getStagingDirectory(moduleId);
    final moduleDirectory =
    await service.getModuleDirectory(moduleId);

    expect(await stagingDirectory.exists(), isFalse);
    expect(await moduleDirectory.exists(), isFalse);

    try {
      await stagingDirectory.create(recursive: true);

      await File(
        '${stagingDirectory.path}/index.html',
      ).writeAsString('<html>Test module</html>');

      await File(
        '${stagingDirectory.path}/module.json',
      ).writeAsString('{"module_id": "9995"}');

      final installedDirectory =
      await service.installStagedModule(moduleId);

      expect(installedDirectory.path, moduleDirectory.path);
      expect(await moduleDirectory.exists(), isTrue);
      expect(await stagingDirectory.exists(), isFalse);

      final content = await File(
        '${moduleDirectory.path}/index.html',
      ).readAsString();

      expect(content, '<html>Test module</html>');
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }

      if (await moduleDirectory.exists()) {
        await moduleDirectory.delete(recursive: true);
      }
    }
  });

  test('Rejects installation with mismatched module ID', () async {
    final service = ModuleDownloadService();
    const moduleId = '9994';

    final stagingDirectory =
    await service.getStagingDirectory(moduleId);
    final moduleDirectory =
    await service.getModuleDirectory(moduleId);

    expect(await stagingDirectory.exists(), isFalse);
    expect(await moduleDirectory.exists(), isFalse);

    try {
      await stagingDirectory.create(recursive: true);

      await File(
        '${stagingDirectory.path}/index.html',
      ).writeAsString('<html>Invalid module</html>');

      // Deliberately use the wrong module ID.
      await File(
        '${stagingDirectory.path}/module.json',
      ).writeAsString('{"module_id": "1234"}');

      await expectLater(
        service.installStagedModule(moduleId),
        throwsA(isA<FormatException>()),
      );

      // Installation must not have occurred.
      expect(await moduleDirectory.exists(), isFalse);

      // The staged files should remain available for inspection.
      expect(await stagingDirectory.exists(), isTrue);
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }

      if (await moduleDirectory.exists()) {
        await moduleDirectory.delete(recursive: true);
      }
    }
  });

  test('Replaces a module and preserves its backup', () async {
    final service = ModuleDownloadService();
    const moduleId = '9993';

    final moduleDirectory =
    await service.getModuleDirectory(moduleId);
    final stagingDirectory =
    await service.getStagingDirectory(moduleId);
    final backupDirectory =
    await service.getModuleBackupDirectory(moduleId);

    expect(await moduleDirectory.exists(), isFalse);
    expect(await stagingDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);

    try {
      // Simulate an existing installation.
      await moduleDirectory.create(recursive: true);

      await File(
        '${moduleDirectory.path}/index.html',
      ).writeAsString('Original version');

      // Prepare the replacement module.
      await stagingDirectory.create(recursive: true);

      await File(
        '${stagingDirectory.path}/index.html',
      ).writeAsString('Updated version');

      await File(
        '${stagingDirectory.path}/module.json',
      ).writeAsString('{"module_id": "9993"}');

      await service.replaceModule(moduleId);

      // The new version should be installed.
      final installedContent = await File(
        '${moduleDirectory.path}/index.html',
      ).readAsString();

      expect(installedContent, 'Updated version');

      // The original version must still exist as a backup.
      expect(await backupDirectory.exists(), isTrue);

      final backupContent = await File(
        '${backupDirectory.path}/index.html',
      ).readAsString();

      expect(backupContent, 'Original version');

      // Staging should no longer exist.
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
    }
  });

  test('Invalid replacement preserves existing module', () async {
    final service = ModuleDownloadService();
    const moduleId = '9992';

    final moduleDirectory =
    await service.getModuleDirectory(moduleId);
    final stagingDirectory =
    await service.getStagingDirectory(moduleId);
    final backupDirectory =
    await service.getModuleBackupDirectory(moduleId);

    expect(await moduleDirectory.exists(), isFalse);
    expect(await stagingDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);

    try {
      // Create an existing installation.
      await moduleDirectory.create(recursive: true);

      await File(
        '${moduleDirectory.path}/index.html',
      ).writeAsString('Original working module');

      // Create a replacement with an incorrect module ID.
      await stagingDirectory.create(recursive: true);

      await File(
        '${stagingDirectory.path}/index.html',
      ).writeAsString('Invalid replacement');

      await File(
        '${stagingDirectory.path}/module.json',
      ).writeAsString('{"module_id": "1234"}');

      await expectLater(
        service.replaceModule(moduleId),
        throwsA(isA<FormatException>()),
      );

      // The original installation must remain untouched.
      expect(await moduleDirectory.exists(), isTrue);

      final originalContent = await File(
        '${moduleDirectory.path}/index.html',
      ).readAsString();

      expect(originalContent, 'Original working module');

      // No backup should have been necessary.
      expect(await backupDirectory.exists(), isFalse);

      // The invalid replacement should remain in staging.
      expect(await stagingDirectory.exists(), isTrue);
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

  test('Detects all module installation states', () async {
    final service = ModuleDownloadService();
    const moduleId = '9991';

    final moduleDirectory =
    await service.getModuleDirectory(moduleId);
    final backupDirectory =
    await service.getModuleBackupDirectory(moduleId);

    expect(await moduleDirectory.exists(), isFalse);
    expect(await backupDirectory.exists(), isFalse);

    try {
      // Neither directory exists.
      expect(
        await service.getModuleInstallationState(moduleId),
        'not_installed',
      );

      // Only the installed module exists.
      await moduleDirectory.create(recursive: true);

      expect(
        await service.getModuleInstallationState(moduleId),
        'installed',
      );

      // Both installation and backup exist.
      await backupDirectory.create(recursive: true);

      expect(
        await service.getModuleInstallationState(moduleId),
        'replacement_pending',
      );

      // Only the backup exists.
      await moduleDirectory.delete(recursive: true);

      expect(
        await service.getModuleInstallationState(moduleId),
        'restore_required',
      );
    } finally {
      if (await moduleDirectory.exists()) {
        await moduleDirectory.delete(recursive: true);
      }

      if (await backupDirectory.exists()) {
        await backupDirectory.delete(recursive: true);
      }
    }
  });

}
