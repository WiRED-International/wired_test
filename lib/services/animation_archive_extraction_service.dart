import 'dart:io';

import 'package:archive/archive.dart';

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
      }

      var count = 0;
      for (final entry in archive) {
        final target = '$root/${entry.name.replaceAll('\\', '/')}';
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
