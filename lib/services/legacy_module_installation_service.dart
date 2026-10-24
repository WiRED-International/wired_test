import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'module_download_service.dart';

/// Maps a display title to a safe folder name while retaining its wording.
String legacyModuleFolderName(String title) {
  final name = title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (name.isEmpty || name == '.' || name == '..') {
    throw ArgumentError.value(title, 'moduleName', 'Invalid module name');
  }
  return name;
}

/// Installs both existing HealthMAP module formats into their current
/// offline-library locations. Does not use the new Hive installation registry.
///
/// Compiler: `modules/<module name>/index.html`
/// Storyline: `files/<story folder>/story.html` and `modules/<story folder>.htm`
class LegacyModuleInstallationService {
  LegacyModuleInstallationService({ModuleDownloadService? downloadService})
      : _downloads = downloadService ?? ModuleDownloadService();

  final ModuleDownloadService _downloads;

  // Shared across every LegacyModuleInstallationService instance.
  static bool _installationInProgress = false;

  Future<void> downloadAndInstall({
    required String moduleId,
    required String moduleName,
    required String downloadUrl,
    void Function(double)? onDownloadProgress,
    void Function(double)? onExtractionProgress,
  }) async {
    if (_installationInProgress) {
      throw StateError(
        'Another module installation is already in progress.',
      );
    }

    _installationInProgress = true;

    try {
      await _performDownloadAndInstall(
        moduleId: moduleId,
        moduleName: moduleName,
        downloadUrl: downloadUrl,
        onDownloadProgress: onDownloadProgress,
        onExtractionProgress: onExtractionProgress,
      );
    } finally {
      _installationInProgress = false;
    }
  }

  Future<void> _performDownloadAndInstall({
    required String moduleId,
    required String moduleName,
    required String downloadUrl,
    void Function(double)? onDownloadProgress,
    void Function(double)? onExtractionProgress,
  }) async {
    if (!RegExp(r'^[0-9]+$').hasMatch(moduleId)) {
      throw ArgumentError.value(moduleId, 'moduleId', 'Expected numeric ID');
    }
    final name = moduleName.trim();
    final folderNameForCompiler = legacyModuleFolderName(name);

    final zip = await _downloads.downloadModuleZip(
      moduleId: moduleId,
      downloadUrl: downloadUrl,
      onProgress: onDownloadProgress,
    );

    final modulesDir = await _downloads.getModulesDirectory();
    final baseDir = await _downloads.getBaseDirectory();
    // Extract on a background isolate using only sendable path strings.
    // ModuleDownloadService.extractModuleZip currently captures Flutter state
    // in its isolate closure on device; avoid that runtime failure here.
    final staging = await _downloads.getStagingDirectory(moduleId);

    if (await staging.exists()) {
      // The shared installation lock is held.
      // Remove temporary files left by an interrupted extraction.
      // This does not touch permanent installed modules or partial ZIPs.
      await staging.delete(recursive: true);
    }

    await staging.create(recursive: true);
    try {
      final result = ReceivePort();
      await Isolate.spawn(
          _legacyExtractWorker, [zip.path, staging.path, result.sendPort]);
      final outcome = await result.first;
      result.close();
      if (outcome != 'ok') {
        throw FormatException('ZIP extraction failed: $outcome');
      }
      onExtractionProgress?.call(1.0);

      File? story;
      await for (final entity
          in staging.list(recursive: true, followLinks: false)) {
        if (entity is File && p.basename(entity.path) == 'story.html') {
          story = entity;
          break;
        }
      }

      if (story != null) {
        final storyFolder = story.parent;
        final folderName = p.basename(storyFolder.path);
        final filesDir = Directory(p.join(baseDir.path, 'files'));
        final destination = Directory(p.join(filesDir.path, folderName));
        final launcher = File(p.join(modulesDir.path, '$folderName.htm'));

        // Existing offline modules must never be overwritten silently.
        if (await destination.exists() || await launcher.exists()) {
          throw StateError(
              'Storyline module "$folderName" is already installed.');
        }
        await filesDir.create(recursive: true);
        await storyFolder.rename(destination.path);
        try {
          final escapedName = name
              .replaceAll('&', '&amp;')
              .replaceAll('"', '&quot;')
              .replaceAll('<', '&lt;')
              .replaceAll('>', '&gt;');
          // Match the existing launcher format used by My Library.
          await launcher.writeAsString('''
<html>
<head>
<meta name="module-title" content="$escapedName">
<meta http-equiv="refresh" content="0; url=../files/$folderName/story.html">
</head>
<body></body>
</html>
''', flush: true);
        } catch (_) {
          if (await destination.exists()) {
            await destination.rename(storyFolder.path);
          }
          rethrow;
        }
      } else if (await File(p.join(staging.path, 'index.html')).exists()) {
        final destination =
            Directory(p.join(modulesDir.path, folderNameForCompiler));
        if (await destination.exists()) {
          throw StateError('Compiler module "$name" is already installed.');
        }
        await staging.rename(destination.path);
      } else {
        throw const FormatException(
          'ZIP contains neither a Storyline story.html nor a root index.html.',
        );
      }

      if (await zip.exists()) await zip.delete();
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }
}

/// Top-level worker: accepts paths only and does not capture Flutter objects.
void _extractLegacyZip(String zipPath, String outputPath) {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    if (archive.isEmpty || archive.length > 10000) {
      throw const FormatException('Invalid ZIP entry count');
    }
    final root = p.normalize(p.absolute(outputPath));
    var totalBytes = 0;
    for (final entry in archive) {
      if (entry.isSymbolicLink) {
        throw const FormatException('ZIP contains a symbolic link');
      }
      final name = entry.name.replaceAll('\\', '/');
      final parts = name.split('/');
      if (name.isEmpty ||
          name.startsWith('/') ||
          name.contains(':') ||
          parts.any((part) => part == '..' || part == '.')) {
        throw const FormatException('Unsafe ZIP entry path');
      }
      final target = p.normalize(p.joinAll([root, ...parts]));
      if (!p.isWithin(root, target)) {
        throw const FormatException('ZIP entry escapes extraction directory');
      }
      if (entry.isFile) {
        totalBytes += entry.size;
        if (totalBytes > 1024 * 1024 * 1024) {
          throw const FormatException('ZIP exceeds 1 GB extracted limit');
        }
        Directory(p.dirname(target)).createSync(recursive: true);
        final output = OutputFileStream(target);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
      } else {
        Directory(target).createSync(recursive: true);
      }
    }
  } finally {
    input.closeSync();
  }
}

void _legacyExtractWorker(List<dynamic> args) {
  final port = args[2] as SendPort;
  try {
    _extractLegacyZip(args[0] as String, args[1] as String);
    port.send('ok');
  } catch (error) {
    port.send(error.toString());
  }
}
