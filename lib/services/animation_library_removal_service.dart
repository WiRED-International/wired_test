import 'dart:io';

import 'package:path/path.dart' as p;

import 'animation_installation_coordinator.dart';

/// The selected MP4 was deleted, but subsequent directory cleanup failed.
/// The deletion is not rolled back; retain the original cleanup error and stack.
class AnimationLibraryPartialRemovalException implements Exception {
  const AnimationLibraryPartialRemovalException({
    required this.animationId,
    required this.deletedVideoPath,
    required this.cleanupError,
    required this.cleanupStack,
  });

  final int animationId;
  final String deletedVideoPath;
  final Object cleanupError;
  final StackTrace cleanupStack;
  bool get videoDeleted => true;

  @override
  String toString() => 'Animation $animationId video was removed at '
      '$deletedVideoPath; directory cleanup failed: $cleanupError';
}

/// Removal for the numeric namespace owned by standalone animation publication.
/// Cooperating installers/removers must share the application coordinator.
/// Path checks protect stable layouts, not hostile concurrent path replacement;
/// Dart does not provide handle-relative deletion. Never recursively deletes.
class AnimationLibraryRemovalService {
  AnimationLibraryRemovalService({
    required this.coordinator,
    this.beforeDirectoryCleanup,
  });

  final AnimationInstallationCoordinator coordinator;
  // Trusted test hook: runs after real MP4 deletion, before cleanup. Does not
  // replace deletion, bypass validation, or release the shared reservation.
  final Future<void> Function()? beforeDirectoryCleanup;

  /// Recognizes only the canonical positive ID spelling used by publication.
  /// Archive-relative names (including `.backup`) do not define identity.
  static int? animationIdFor({required Directory root, required File file}) {
    if (p.split(file.path).any((part) => part == '.' || part == '..')) {
      return null;
    }
    final namespace =
        p.normalize(p.join(root.absolute.path, 'modules', 'animations'));
    final path = p.normalize(file.absolute.path);
    if (!p.isWithin(namespace, path) || !path.toLowerCase().endsWith('.mp4')) {
      return null;
    }
    final parts = p.split(p.relative(path, from: namespace));
    if (parts.length < 2 || !RegExp(r'^[1-9][0-9]*$').hasMatch(parts.first)) {
      return null;
    }
    final id = int.tryParse(parts.first);
    return id != null && id > 0 ? id : null;
  }

  /// Returns true only when the ID destination is absent and can be reinstalled.
  /// False means the MP4 was removed but other content retained its directory.
  /// Throws [AnimationLibraryPartialRemovalException] if cleanup fails after deletion.
  Future<bool> remove({required Directory root, required File file}) async {
    final id = animationIdFor(root: root, file: file);
    if (id == null) {
      throw FileSystemException('Not a published animation path', file.path);
    }
    return coordinator.run(
        animationId: id,
        operation: () async {
          final rootPath = p.normalize(root.absolute.path);
          final target = p.normalize(file.absolute.path);
          final installation = p.join(rootPath, 'modules', 'animations', '$id');

          Future<void> checkParents(String directory) async {
            if (!p.equals(directory, installation) &&
                !p.isWithin(installation, directory)) {
              throw FileSystemException(
                  'Outside animation installation', directory);
            }
            final ancestors = <String>[];
            var current = directory;
            while (!p.equals(current, rootPath)) {
              ancestors.add(current);
              current = p.dirname(current);
            }
            ancestors.add(rootPath);
            for (final path in ancestors.reversed) {
              await _requireDirectory(path);
              if (p.equals(path, rootPath)) continue;
              await for (final entry
                  in Directory(path).list(followLinks: false)) {
                if (_isModuleEntry(entry.path)) {
                  throw FileSystemException(
                      'Animation may belong to a module', path);
                }
              }
            }
          }

          final directories = <String>[];
          Future<void> inspect(String directory) async {
            await checkParents(directory);
            await for (final entry
                in Directory(directory).list(followLinks: false)) {
              final path = p.normalize(entry.absolute.path);
              if (!p.isWithin(installation, path) || _isModuleEntry(path)) {
                throw FileSystemException('Unsafe animation entry', path);
              }
              final type =
                  await FileSystemEntity.type(path, followLinks: false);
              if (type == FileSystemEntityType.directory) {
                await inspect(path);
              } else if (type != FileSystemEntityType.file) {
                throw FileSystemException('Unsafe animation entry', path);
              }
            }
            directories
                .add(directory); // Children before parents, including ID.
          }

          // Inspect the entire ID tree before deleting anything. Links and module
          // ownership markers preserve the selected MP4 as well as their targets.
          await inspect(installation);
          await checkParents(p.dirname(target));
          if (await FileSystemEntity.type(target, followLinks: false) !=
              FileSystemEntityType.file) {
            throw FileSystemException('Missing or unsafe animation', target);
          }
          await File(target).delete();
          try {
            await beforeDirectoryCleanup?.call();
            for (final directory in directories) {
              await checkParents(directory);
              if (await Directory(directory).list(followLinks: false).isEmpty) {
                // Recheck ancestors immediately before a nonrecursive deletion.
                await checkParents(directory);
                await Directory(directory).delete();
              }
            }
            return await FileSystemEntity.type(installation,
                    followLinks: false) ==
                FileSystemEntityType.notFound;
          } catch (error, stack) {
            Error.throwWithStackTrace(
              AnimationLibraryPartialRemovalException(
                animationId: id,
                deletedVideoPath: target,
                cleanupError: error,
                cleanupStack: stack,
              ),
              stack,
            );
          }
        });
  }
}

bool _isModuleEntry(String path) =>
    const ['index.html', 'story.html'].contains(p.basename(path).toLowerCase());

Future<void> _requireDirectory(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw FileSystemException('Unsafe animation directory', path);
  }
}
