import 'dart:io';

import 'package:path/path.dart' as p;

import 'animation_zip_metadata_reader.dart';

enum AnimationInstallationStatus { notInstalled, installed, conflict }

class AnimationInstallationInspection {
  const AnimationInstallationInspection(this.status, {this.mp4RelativePath});

  final AnimationInstallationStatus status;
  final String? mp4RelativePath;
}

/// Read-only contract inspection. Nonempty MP4 means a regular file with an
/// MP4 extension and bytes, not a guarantee of media decodability.
class AnimationInstallationInspectionService {
  void validateAnimationId(int animationId) {
    if (animationId <= 0) throw ArgumentError.value(animationId, 'animationId');
  }

  AnimationInstallationInspectionService({
    this.zipLimits = const AnimationZipLimits(),
  });

  final AnimationZipLimits zipLimits;

  /// Validates structure and declared sizes only; never decompresses payloads.
  Future<AnimationZipDescriptor> inspectArchiveMetadata(String zipPath) =>
      AnimationZipMetadataReader(limits: zipLimits).inspect(zipPath);

  /// Compatibility convenience returning the original safe MP4-relative path.
  Future<String> inspectArchive(String zipPath) async =>
      (await inspectArchiveMetadata(zipPath)).mp4RelativePath;

  /// [root] is the selected storage base, excluding `modules/`.
  /// Existing ancestors are checked without following links. No paths are
  /// created, and unreadable or ambiguous state is a conflict.
  Future<AnimationInstallationInspection> inspectInstallation({
    required Directory root,
    required int animationId,
  }) async {
    validateAnimationId(animationId);
    const conflict =
        AnimationInstallationInspection(AnimationInstallationStatus.conflict);
    const absent = AnimationInstallationInspection(
        AnimationInstallationStatus.notInstalled);
    try {
      var current = p.normalize(root.absolute.path);
      // The platform-selected root is the trust boundary. Do not reject
      // platform aliases above it (for example iOS /var), or traverse them.
      final rootType = await FileSystemEntity.type(current, followLinks: false);
      if (rootType == FileSystemEntityType.notFound) return absent;
      if (rootType != FileSystemEntityType.directory) return conflict;
      await Directory(current).list(followLinks: false).drain<void>();
      for (final component in ['modules', 'animations', '$animationId']) {
        current = p.join(current, component);
        final type = await FileSystemEntity.type(current, followLinks: false);
        if (type == FileSystemEntityType.notFound) return absent;
        if (type != FileSystemEntityType.directory) return conflict;
        await Directory(current).list(followLinks: false).drain<void>();
      }
      String? video;
      await for (final entry
          in Directory(current).list(recursive: true, followLinks: false)) {
        final type =
            await FileSystemEntity.type(entry.path, followLinks: false);
        if (type == FileSystemEntityType.directory) continue;
        if (type != FileSystemEntityType.file ||
            video != null ||
            !entry.path.toLowerCase().endsWith('.mp4')) {
          return conflict;
        }
        final file = File(entry.path);
        final handle = await file.open();
        try {
          if (await handle.length() <= 0 || (await handle.read(1)).isEmpty) {
            return conflict;
          }
        } finally {
          await handle.close();
        }
        video = p.relative(entry.path, from: current);
      }
      return video == null
          ? conflict
          : AnimationInstallationInspection(
              AnimationInstallationStatus.installed,
              mp4RelativePath: video.replaceAll('\\', '/'));
    } on FileSystemException {
      return conflict;
    }
  }
}
