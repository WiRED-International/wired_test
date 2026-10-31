import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Extracts animation ZIPs while preserving their existing offline layout.
/// Storage selection and isolate messaging remain the caller's responsibility.
class AnimationArchiveExtractionService {
  Future<void> extractArchive({
    required String zipPath,
    required String outputDir,
    void Function(double progress)? onProgress,
  }) async {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);

      final root = Directory(outputDir).absolute.path;
      final normalizedRoot = root.replaceAll('\\', '/');
      final destinations = <String, bool>{};
      final directories = <String, String>{};
      final files = <String>[];
      String destinationKey(String path) =>
          Platform.isWindows ? path.toLowerCase() : path;
      for (final entry in archive) {
        final name = entry.name.replaceAll('\\', '/');
        final parts = name.split('/');
        if (name.startsWith('/') ||
            name.contains(':') ||
            parts.contains('..') ||
            parts.contains('.') ||
            parts.any((part) => part.isEmpty && part != parts.last) ||
            entry.isSymbolicLink) {
          throw const FormatException('Unsafe archive entry.');
        }
        final target = File('$root/$name').absolute.path.replaceAll('\\', '/');
        if (!target.startsWith('$normalizedRoot/')) {
          throw const FormatException(
              'Archive entry escapes the storage directory.');
        }
        final destination = p.normalize(target);
        if (!p.isWithin(p.normalize(root), destination)) {
          throw const FormatException('Unsafe archive entry.');
        }
        final key = destinationKey(destination);
        if (destinations.containsKey(key)) {
          throw const FormatException('Duplicate archive destination.');
        }
        if (entry.isFile && directories.containsKey(key)) {
          throw const FormatException('Archive file/directory conflict.');
        }
        destinations[key] = entry.isFile;
        if (entry.isFile) files.add(destination);

        var directory = entry.isFile ? p.dirname(destination) : destination;
        while (true) {
          final directoryKey = destinationKey(directory);
          if (destinations[directoryKey] == true) {
            throw const FormatException('Archive file/directory conflict.');
          }
          directories[directoryKey] = directory;
          if (p.equals(directory, p.normalize(root))) break;
          directory = p.dirname(directory);
        }
      }

      // Validate every destination before creating any output. Check parent
      // directories first so existing links cannot redirect descendant checks.
      final parents = directories.values.toList()
        ..sort((a, b) => a.length.compareTo(b.length));
      for (final directory in parents) {
        final type = await FileSystemEntity.type(directory, followLinks: false);
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory) {
          throw FileSystemException('Conflicting archive directory', directory);
        }
      }
      for (final file in files) {
        if (await FileSystemEntity.type(file, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw FileSystemException('Archive destination already exists', file);
        }
      }

      var count = 0;
      for (final entry in archive) {
        final target = p.normalize('$root/${entry.name.replaceAll('\\', '/')}');
        if (entry.isFile) {
          await Directory(File(target).parent.path).create(recursive: true);
          final output = OutputFileStream(target);
          try {
            entry.writeContent(output);
          } finally {
            await output.close();
          }
        } else {
          await Directory(target).create(recursive: true);
        }
        count++;
        onProgress?.call(count / archive.length);
      }
    } finally {
      await input.close();
    }
  }
}
