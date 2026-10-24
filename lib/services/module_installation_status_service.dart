import 'dart:io';

import 'package:path/path.dart' as p;

import 'legacy_module_installation_service.dart';
import 'module_download_service.dart';

/// Checks installations created by HealthMAP's legacy-compatible installer.
///
/// This service does not modify installed files or use the Hive registry.
class ModuleInstallationStatusService {
  ModuleInstallationStatusService({
    ModuleDownloadService? downloadService,
  }) : _downloads = downloadService ?? ModuleDownloadService();

  final ModuleDownloadService _downloads;

  Future<bool> isInstalled({
    required String moduleName,
  }) async {
    final name = moduleName.trim();
    final safeName = legacyModuleFolderName(name);

    final modulesDir = await _downloads.getModulesDirectory();
    final baseDir = await _downloads.getBaseDirectory();

    // Compiler-generated modules.
    final compilerIndex = File(
      p.join(modulesDir.path, safeName, 'index.html'),
    );

    if (await compilerIndex.exists()) {
      return true;
    }

    // Recognize older compiler installations using the original title.
    if (safeName != name && !name.contains('/') && !name.contains('\\')) {
      final originalIndex = File(
        p.join(modulesDir.path, name, 'index.html'),
      );

      if (await originalIndex.exists()) {
        return true;
      }
    }

    // Storyline modules.
    //
    // Their launcher filename may differ from the displayed module name.
    // Read the title metadata and verify that the actual content exists.
    await for (final entity in modulesDir.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.htm')) {
        continue;
      }

      final content = await entity.readAsString();

      final match = RegExp(
        r'<meta\s+name="module-title"\s+content="([^"]*)"',
        caseSensitive: false,
      ).firstMatch(content);

      if (match == null) continue;

      final title = match
          .group(1)!
          .replaceAll('&quot;', '"')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&');

      if (title != name) continue;

      final launcherName = p.basename(entity.path);
      final folderName = launcherName.substring(
        0,
        launcherName.length - 4,
      );

      final storyFile = File(
        p.join(baseDir.path, 'files', folderName, 'story.html'),
      );

      if (await storyFile.exists()) {
        return true;
      }
    }

    return false;
  }
}
