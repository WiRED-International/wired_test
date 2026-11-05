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
      if (entity is! File ||
          !RegExp(r'\.html?$', caseSensitive: false).hasMatch(entity.path)) {
        continue;
      }

      final content = await entity.readAsString();

      String? rawTitle;
      final metaTags = RegExp(
        r'''<meta\b((?:[^"'<>]|"[^"]*"|'[^']*')*)>''',
        caseSensitive: false,
      ).allMatches(content);
      for (final tag in metaTags) {
        final attributes = <String, String>{};
        for (final attribute in RegExp(
          r'''(?:^|\s)([^\s=/>]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
        ).allMatches(tag.group(1)!)) {
          attributes[attribute.group(1)!.toLowerCase()] =
              attribute.group(2) ?? attribute.group(3)!;
        }
        if (attributes['name']?.toLowerCase() == 'module-title') {
          rawTitle = attributes['content'];
          if (rawTitle != null) break;
        }
      }

      if (rawTitle == null) continue;

      final title = rawTitle
          .replaceAll('&quot;', '"')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&');

      if (title != name) continue;

      final folderName = p.basenameWithoutExtension(entity.path);

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
