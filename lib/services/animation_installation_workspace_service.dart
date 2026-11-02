import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Allocates private, per-attempt storage. No installation paths are touched.
class AnimationInstallationWorkspaceService {
  Future<AnimationInstallationWorkspace> create({
    required Directory root,
    required int animationId,
  }) async {
    if (animationId <= 0) throw ArgumentError.value(animationId, 'animationId');
    final canonical = Directory(p.normalize(root.absolute.path));
    // The platform-selected root is trusted; aliases above it (iOS /var, for
    // example) are outside this service's boundary.
    await _requireDirectory(canonical.path);
    final parent = Directory(p.join(canonical.path, 'animation_installations'));
    final type = await FileSystemEntity.type(parent.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) await parent.create();
    await _requireDirectory(parent.path);

    // createTemp atomically allocates a fresh directory rather than accepting
    // an existing candidate as Directory.create() would.
    final attempt = await parent.createTemp('$animationId-');
    final token = base64Url
        .encode(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
    final workspace = AnimationInstallationWorkspace._(
        canonical.path, parent.path, attempt.path, animationId, token);
    await _requireDirectory(attempt.path);
    final marker = File(workspace._markerPath);
    await marker.create(exclusive: true);
    await marker.writeAsString(token, flush: true);
    // Do not create download.zip: the future downloader owns its lifecycle.
    // If initialization fails, preserve the attempt rather than deleting
    // content whose ownership or filesystem state is uncertain.
    await workspace.payloadDirectory.create();
    await _requireDirectory(workspace.payloadDirectory.path);
    return workspace;
  }
}

/// The caller exclusively owns this attempt and must place only its own files
/// in payload/. Do not share its paths with another attempt or external writer.
class AnimationInstallationWorkspace {
  AnimationInstallationWorkspace._(
      this._root, this._parent, this._attempt, this.animationId, this._token);

  final String _root;
  final String _parent;
  final String _attempt;
  final String _token;
  final int animationId;
  bool _cleaned = false;
  bool _cleaning = false;

  Directory get directory => Directory(_attempt);
  File get downloadFile => File(p.join(_attempt, 'download.zip'));
  Directory get payloadDirectory => Directory(p.join(_attempt, 'payload'));
  String get _markerPath => p.join(_attempt, '.workspace-owner');

  Future<void> _checkBoundary() async {
    if (p.dirname(_attempt) != _parent ||
        p.dirname(_parent) != _root ||
        p.basename(_parent) != 'animation_installations' ||
        !p.basename(_attempt).startsWith('$animationId-')) {
      throw FileSystemException('Invalid workspace boundary', _attempt);
    }
    await _requireDirectory(_root);
    await _requireDirectory(_parent);
    await _requireDirectory(_attempt);
    if (await FileSystemEntity.type(_markerPath, followLinks: false) !=
            FileSystemEntityType.file ||
        await File(_markerPath).length() != _token.length ||
        await File(_markerPath).readAsString() != _token) {
      throw FileSystemException(
          'Workspace ownership cannot be established', _attempt);
    }
  }

  /// Refuses links, unknown top-level entries, or lost ownership. Deletions
  /// never use recursive:true. This guards stable filesystem layouts, not
  /// hostile concurrent ancestor replacement (Dart lacks handle-relative I/O).
  Future<void> cleanup() async {
    if (_cleaned) return;
    if (_cleaning) throw StateError('Workspace cleanup already in progress');
    _cleaning = true;
    try {
      await _checkBoundary();
      final files = <String>[];
      final directories = <String>[];
      Future<void> scan(String path) async {
        await _requireDirectory(path);
        await for (final entry in Directory(path).list(followLinks: false)) {
          final name = p.basename(entry.path);
          final type =
              await FileSystemEntity.type(entry.path, followLinks: false);
          if (path == _attempt) {
            if (name == '.workspace-owner' &&
                type == FileSystemEntityType.file) {
              continue;
            }
            if (!(name == 'download.zip' &&
                    type == FileSystemEntityType.file) &&
                !(name == 'payload' &&
                    type == FileSystemEntityType.directory)) {
              throw FileSystemException(
                  'Unexpected workspace entry', entry.path);
            }
          }
          if (!p.isWithin(_attempt, p.normalize(entry.absolute.path))) {
            throw FileSystemException('Entry outside workspace', entry.path);
          }
          if (type == FileSystemEntityType.directory) {
            await scan(entry.path);
            directories.add(entry.path);
          } else if (type == FileSystemEntityType.file) {
            files.add(entry.path);
          } else {
            throw FileSystemException('Unsafe workspace entry', entry.path);
          }
        }
      }

      // Complete inspection before deleting anything. Unknown entries and
      // symlinks preserve the entire attempt, including ordinary files.
      await scan(_attempt);
      Future<void> recheck(String path, FileSystemEntityType expected) async {
        await _checkBoundary();
        var parent = p.dirname(path);
        while (parent != _attempt) {
          await _requireDirectory(parent);
          parent = p.dirname(parent);
        }
        if (await FileSystemEntity.type(path, followLinks: false) != expected) {
          throw FileSystemException('Workspace entry changed', path);
        }
      }

      for (final path in files) {
        await recheck(path, FileSystemEntityType.file);
        await File(path).delete();
      }
      for (final path in directories) {
        await recheck(path, FileSystemEntityType.directory);
        await Directory(path).delete();
      }
      await _checkBoundary();
      // Refuse concurrent additions before removing the ownership marker.
      final remaining = await directory.list(followLinks: false).toList();
      if (remaining.length != 1 || remaining.single.path != _markerPath) {
        throw FileSystemException('Workspace contents changed', _attempt);
      }
      await File(_markerPath).delete();
      await directory.delete();
      _cleaned = true;
    } finally {
      _cleaning = false;
    }
  }
}

Future<void> _requireDirectory(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw FileSystemException('Expected an ordinary workspace directory', path);
  }
  // Surface unreadable directories instead of assuming they are absent/empty.
  await Directory(path).list(followLinks: false).drain<void>();
}
