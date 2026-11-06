import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;

import 'legacy_module_installation_service.dart';
import 'module_download_service.dart';
import 'module_installation_registry.dart';

enum InstructionalInstallationState {
  confirmed,
  legacyCandidate,
  ambiguous,
  conflict,
  notInstalled,
  unavailable,
  invalidRecord,
}

class _InspectionIssue implements Exception {
  _InspectionIssue(this.state, this.reason);
  final InstructionalInstallationState state;
  final String reason;
}

class _InstructionalInspector {
  _InstructionalInspector(
      this.registry, this.databaseId, this.moduleId, this.name);
  final ModuleInstallationRegistry registry;
  final int? databaseId;
  final String moduleId;
  final String name;
  final evidence = <String>{};
  final _legacyCompilerVersions = <String, String?>{};
  late List<String> roots;

  Never issue(InstructionalInstallationState state, String reason) =>
      throw _InspectionIssue(state, reason);
  Never conflict(String reason) =>
      issue(InstructionalInstallationState.conflict, reason);

  Future<InstructionalInstallationInspection> inspect(
      List<Directory> directories) async {
    roots = directories.map((directory) => directory.path).toSet().toList();
    if (roots.isEmpty) {
      issue(InstructionalInstallationState.unavailable,
          'No storage roots available');
    }
    for (final root in roots) {
      if (!p.isAbsolute(root) || root != p.normalize(root)) {
        issue(InstructionalInstallationState.unavailable,
            'Invalid storage root: $root');
      }
      if (await FileSystemEntity.type(root, followLinks: false) !=
          FileSystemEntityType.directory) {
        issue(InstructionalInstallationState.unavailable,
            'Storage root unavailable: $root');
      }
      await Directory(root).list(followLinks: false).drain<void>();
    }
    final records =
        await registry.inspectInstructionalClaims(databaseId: databaseId);
    if (records.isNotEmpty) {
      final record = records.single;
      evidence.addAll(['content_directory', 'entry_point_path', 'launcher_path']
          .map((field) => record[field])
          .whereType<String>());
      if (record['database_id'] != databaseId ||
          record['module_id'] != moduleId) {
        conflict(
            'Registry identity does not match requested database/content IDs');
      }
      final content = record['content_directory'] as String;
      final entry = record['entry_point_path'] as String;
      final compiler = record['format'] == 'compiler';
      String? installedVersion = record['version'] as String?;
      await requirePath(content, FileSystemEntityType.directory);
      if (!p.equals(p.dirname(entry), content) ||
          p.basename(entry) != (compiler ? 'index.html' : 'story.html')) {
        conflict('Entry point does not match content directory or format');
      }
      await readFile(entry);
      if (compiler) {
        final identity = await manifest(content);
        if (identity != null && identity.moduleId != moduleId) {
          conflict('Compiler manifest contradicts registry/request identity');
        }
        installedVersion = identity?.version ?? installedVersion;
      }
      final launcher = record['launcher_path'] as String?;
      if (!compiler) {
        if (launcher == null) {
          await claims([content, entry]);
          return result(InstructionalInstallationState.legacyCandidate,
              'Storyline content exists but no launch path was recorded');
        }
        await verifyLauncher(launcher, entry);
      }
      await claims([content, entry, if (launcher != null) launcher]);
      return result(InstructionalInstallationState.confirmed,
          'Matching registry identity and readable published paths',
          installedVersion: installedVersion);
    }

    final candidates = <String>{};
    for (final root in roots) {
      for (final bucket in ['modules', 'packages']) {
        final base = p.join(root, bucket);
        final type = await FileSystemEntity.type(base, followLinks: false);
        if (type == FileSystemEntityType.notFound) continue;
        await requirePath(base, FileSystemEntityType.directory,
            allowBucket: true);
        await scan(base, candidates, recursive: bucket == 'packages');
      }
    }
    if (candidates.isEmpty) {
      return result(InstructionalInstallationState.notInstalled,
          'No matching installation found');
    }
    if (candidates.length > 1) {
      return result(InstructionalInstallationState.ambiguous,
          'Multiple legacy installations match');
    }
    if (_legacyCompilerVersions.containsKey(candidates.single)) {
      // WiRED guarantees content module IDs are unique. A valid manifest is
      // identity evidence independent of folder/title and registry presence.
      return result(InstructionalInstallationState.confirmed,
          'Matching unique Compiler content ID and readable legacy files',
          installedVersion: _legacyCompilerVersions[candidates.single]);
    }
    return result(InstructionalInstallationState.legacyCandidate,
        'Legacy files match; database identity is unverified');
  }

  InstructionalInstallationInspection result(
          InstructionalInstallationState state, String reason,
          {String? installedVersion}) =>
      InstructionalInstallationInspection(state, reason, evidence,
          installedVersion: installedVersion);

  bool excluded(String path) => p.split(path).any((part) {
        final value = part.toLowerCase();
        return value.endsWith('.backup') ||
            value.endsWith('.staging') ||
            [
              'animations',
              'animation_installations',
              'module_downloads',
              'downloads'
            ].contains(value);
      });

  String rootFor(String path, {bool allowBucket = false}) {
    if (!p.isAbsolute(path) || path != p.normalize(path)) {
      conflict('Path is not normalized and absolute: $path');
    }
    for (final root in roots) {
      if (!p.isWithin(root, path)) continue;
      final parts = p.split(p.relative(path, from: root));
      if (parts.isEmpty ||
          !['modules', 'files', 'packages'].contains(parts.first) ||
          (!allowBucket && parts.length < 2) ||
          excluded(p.relative(path, from: root))) {
        conflict('Path is not published instructional content: $path');
      }
      return root;
    }
    conflict('Path escapes recognized storage roots: $path');
  }

  Future<void> requirePath(String path, FileSystemEntityType expected,
      {bool allowBucket = false}) async {
    final root = rootFor(path, allowBucket: allowBucket);
    var cursor = root;
    final parts = p.split(p.relative(path, from: root));
    for (var index = 0; index < parts.length; index++) {
      // Listing the parent surfaces access errors; absence must not hide them.
      await Directory(cursor).list(followLinks: false).drain<void>();
      cursor = p.join(cursor, parts[index]);
      final type = await FileSystemEntity.type(cursor, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        conflict('Recorded or candidate path is missing: $cursor');
      }
      final wanted =
          index == parts.length - 1 ? expected : FileSystemEntityType.directory;
      if (type != wanted) {
        conflict('Unsafe path type (including links): $cursor');
      }
    }
  }

  Future<String> readFile(String path) async {
    await requirePath(path, FileSystemEntityType.file);
    final text = await File(path).readAsString();
    if (text.isEmpty) conflict('Empty published file: $path');
    return text;
  }

  Future<({String moduleId, String? version})?> manifest(
      String directory) async {
    final path = p.join(directory, 'module.json');
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    final data = jsonDecode(await readFile(path));
    if (data is! Map ||
        (data['module_id'] is! String && data['module_id'] is! int) ||
        data['module_id'].toString().trim().isEmpty) {
      throw FormatException('Invalid compiler manifest: $path');
    }
    final version = data['version'];
    if (version != null && version is! String && version is! num) {
      throw FormatException('Invalid compiler manifest version: $path');
    }
    return (
      moduleId: data['module_id'].toString(),
      version: version == null || version.toString().trim().isEmpty
          ? null
          : version.toString()
    );
  }

  static String decode(String text) => text
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  List<Map<String, String>> meta(String html) =>
      RegExp(r'''<meta\b((?:[^"'<>]|"[^"]*"|'[^']*')*)>''',
              caseSensitive: false)
          .allMatches(html)
          .map((tag) {
        final attributes = <String, String>{};
        for (final item
            in RegExp(r'''(?:^|\s)([^\s=/>]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''')
                .allMatches(tag.group(1)!)) {
          attributes[item.group(1)!.toLowerCase()] =
              decode(item.group(2) ?? item.group(3)!);
        }
        return attributes;
      }).toList();

  String redirect(String html, String launcher) {
    final tags = meta(html)
        .where((tag) => tag['http-equiv']?.toLowerCase() == 'refresh')
        .toList();
    if (tags.length != 1) {
      conflict('Expected exactly one Storyline redirect: $launcher');
    }
    final match =
        RegExp(r'^\s*0\s*;\s*url\s*=\s*(.+?)\s*$', caseSensitive: false)
            .firstMatch(tags.single['content'] ?? '');
    if (match == null) conflict('Invalid Storyline redirect: $launcher');
    final target = Uri.tryParse(match.group(1)!);
    if (target == null ||
        target.hasScheme ||
        target.hasAuthority ||
        target.hasQuery ||
        target.hasFragment) {
      conflict('Nonlocal Storyline redirect: $launcher');
    }
    return p.normalize(
        p.join(p.dirname(launcher), Uri.decodeComponent(target.path)));
  }

  Future<void> verifyLauncher(String launcher, String entry) async {
    if (!['.htm', '.html'].contains(p.extension(launcher).toLowerCase())) {
      conflict('Invalid launcher extension');
    }
    final target = redirect(await readFile(launcher), launcher);
    if (!p.equals(target, entry) || rootFor(launcher) != rootFor(entry)) {
      conflict('Storyline launcher targets different content');
    }
  }

  Future<void> claims(List<String> paths) async {
    final owners = await registry.inspectInstructionalClaims(paths: paths);
    if (owners.any((record) =>
        record['database_id'] != databaseId ||
        record['module_id'] != moduleId)) {
      conflict(
          'Candidate paths are claimed by another database/content identity');
    }
  }

  Future<void> scan(String directory, Set<String> candidates,
      {required bool recursive}) async {
    await for (final entity in Directory(directory).list(followLinks: false)) {
      if (excluded(entity.path)) continue;
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link &&
          p.basename(entity.path) == legacyModuleFolderName(name)) {
        conflict('Legacy candidate is a symbolic link');
      }
      if (type == FileSystemEntityType.directory) {
        final index = p.join(entity.path, 'index.html');
        if (await FileSystemEntity.type(index, followLinks: false) !=
            FileSystemEntityType.notFound) {
          final identity = await manifest(entity.path);
          final id = identity?.moduleId;
          final titleMatch =
              p.basename(entity.path) == legacyModuleFolderName(name) ||
                  p.basename(entity.path) == name.trim();
          if (titleMatch || id == moduleId) {
            evidence.add(index);
            if (id != null && id != moduleId) {
              conflict(
                  'Legacy compiler manifest contradicts requested content ID');
            }
            await readFile(index);
            await claims([entity.path, index]);
            candidates.add(index);
            if (id == moduleId) {
              _legacyCompilerVersions[index] = identity!.version;
            }
          }
        } else if (recursive) {
          await requirePath(entity.path, FileSystemEntityType.directory);
          await scan(entity.path, candidates, recursive: true);
        }
      } else if (['.htm', '.html']
          .contains(p.extension(entity.path).toLowerCase())) {
        final html = await readFile(entity.path);
        final titleMatches = meta(html).any((tag) =>
            tag['name']?.toLowerCase() == 'module-title' &&
            tag['content']?.trim() == name.trim());
        if (!titleMatches) continue;
        evidence.add(entity.path);
        final target = redirect(html, entity.path);
        if (p.basename(target) != 'story.html') {
          conflict('Legacy launcher does not target story.html');
        }
        await verifyLauncher(entity.path, target);
        await readFile(target);
        await claims([entity.path, p.dirname(target), target]);
        candidates.add(target);
      }
    }
  }
}

class InstructionalInstallationInspection {
  InstructionalInstallationInspection(
      this.state, this.reason, Iterable<String> paths,
      {this.installedVersion})
      : paths = List.unmodifiable(paths);
  final InstructionalInstallationState state;
  final String reason;
  final List<String> paths;

  /// Read from installed metadata, never from the current catalog version.
  final String? installedVersion;
}

/// Checks installations created by HealthMAP's legacy-compatible installer.
///
/// The legacy boolean API is retained. Identity inspection is read-only and
/// never opens/repairs registry storage or creates installation directories.
class ModuleInstallationStatusService {
  ModuleInstallationStatusService({
    ModuleDownloadService? downloadService,
    ModuleInstallationRegistry? registry,
    // Trusted, non-creating resolver. Defaults to the active instructional
    // storage root; callers may explicitly supply additional historical roots.
    Future<List<Directory>> Function()? inspectionRoots,
  })  : _downloads = downloadService ?? ModuleDownloadService(),
        _registry = registry ?? ModuleInstallationRegistry(),
        _inspectionRoots = inspectionRoots;

  final ModuleDownloadService _downloads;
  final ModuleInstallationRegistry _registry;
  final Future<List<Directory>> Function()? _inspectionRoots;

  /// Confirms validated registry associations or one legacy Compiler installation
  /// with the exact unique content ID. Title-only and uncertain Storyline matches
  /// remain candidates. Inspection never writes registry records.
  Future<InstructionalInstallationInspection> inspectInstallation({
    int? databaseId,
    required String moduleId,
    required String moduleName,
  }) async {
    if (databaseId != null && databaseId <= 0) {
      throw ArgumentError.value(databaseId, 'databaseId');
    }
    if (moduleId.trim().isEmpty) {
      throw ArgumentError.value(moduleId, 'moduleId');
    }
    final inspector =
        _InstructionalInspector(_registry, databaseId, moduleId, moduleName);
    try {
      final roots = _inspectionRoots != null
          ? await _inspectionRoots()
          : [await _downloads.getBaseDirectory()];
      return await inspector.inspect(roots);
    } on _InspectionIssue catch (issue) {
      return InstructionalInstallationInspection(
          issue.state, issue.reason, inspector.evidence);
    } on FormatException catch (error) {
      return InstructionalInstallationInspection(
          InstructionalInstallationState.invalidRecord,
          error.toString(),
          inspector.evidence);
    } catch (error) {
      return InstructionalInstallationInspection(
          InstructionalInstallationState.unavailable,
          'Inspection could not complete: $error',
          inspector.evidence);
    }
  }

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
