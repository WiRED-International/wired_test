import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' show getCrc32;
import 'package:path/path.dart' as p;

import 'animation_zip_metadata_reader.dart';

class AnimationStagedMp4VerificationResult {
  const AnimationStagedMp4VerificationResult({
    required this.relativePath,
    required this.verifiedBytes,
  });
  final String relativePath;
  final int verifiedBytes;
}

/// Read-only size/CRC verification, not media decoding or authenticity checks.
/// The caller must exclusively own the workspace and keep its tree stable.
/// Path checks do not prevent hostile concurrent ancestor replacement.
class AnimationStagedMp4VerificationService {
  const AnimationStagedMp4VerificationService({
    this.limits = const AnimationZipLimits(),
    this.chunkSize = 32 * 1024,
  });
  final AnimationZipLimits limits;
  final int chunkSize;

  Future<AnimationStagedMp4VerificationResult> verify({
    required AnimationZipDescriptor descriptor,
    required Directory payloadDirectory,
  }) async {
    limits.validate();
    if (chunkSize <= 0 || chunkSize > 1024 * 1024) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'Must be 1..1048576');
    }
    final relative = descriptor.mp4RelativePath;
    final parts = relative.split('/');
    if (relative.isEmpty ||
        relative.contains('\\') ||
        !relative.toLowerCase().endsWith('.mp4') ||
        parts.any((part) =>
            part.isEmpty ||
            part == '.' ||
            part == '..' ||
            part.endsWith('.') ||
            part.endsWith(' ') ||
            RegExp(r'[:<>"|?*\x00-\x1f\x7f]').hasMatch(part)) ||
        parts.length - 1 > limits.maxDepth ||
        utf8.encode(relative).length > limits.maxNameBytes ||
        descriptor.uncompressedSize <= 0 ||
        descriptor.uncompressedSize > limits.maxMp4Bytes ||
        descriptor.crc32 < 0 ||
        descriptor.crc32 > 0xffffffff) {
      throw const FormatException('Invalid staged MP4 descriptor.');
    }
    final payload = p.normalize(payloadDirectory.absolute.path);
    final attempt = p.dirname(payload);
    final parent = p.dirname(attempt);
    final root = p.dirname(parent);
    if (p.basename(payload) != 'payload' ||
        p.basename(parent) != 'animation_installations' ||
        !RegExp(r'^[1-9][0-9]*-.+$').hasMatch(p.basename(attempt))) {
      throw ArgumentError('Expected a private installation payload directory.');
    }
    Future<void> checkAncestors() async {
      // The canonical root supplied by the caller is the trust boundary; OS
      // aliases above it (such as iOS /var) are not rejected.
      for (final directory in [root, parent, attempt, payload]) {
        if (await FileSystemEntity.type(directory, followLinks: false) !=
            FileSystemEntityType.directory) {
          throw FileSystemException(
              'Unsafe staged payload ancestor', directory);
        }
      }
    }

    await checkAncestors();
    final expectedFile = p.joinAll([payload, ...parts]);
    if (!p.isWithin(payload, expectedFile)) {
      throw const FormatException('Staged MP4 escapes payload directory.');
    }
    final allowedDirectories = <String>{};
    for (var i = 1; i < parts.length; i++) {
      allowedDirectories.add(p.joinAll([payload, ...parts.take(i)]));
    }
    var entries = 0;
    Future<void> checkTree(String directory, int depth) async {
      // Recheck immediately before listing; links are never traversed in a
      // stable, exclusively owned workspace. Concurrent replacement remains
      // outside the path-based API's guarantee.
      if (await FileSystemEntity.type(directory, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw FileSystemException('Unsafe staged directory', directory);
      }
      await for (final entry in Directory(directory).list(followLinks: false)) {
        entries++;
        if (entries > limits.maxEntries) {
          throw const FormatException('Too many staged payload entries.');
        }
        final name = p.basename(entry.path);
        if (!p.isWithin(payload, p.normalize(entry.absolute.path)) ||
            name.isEmpty ||
            name == '.' ||
            name == '..' ||
            name.endsWith('.') ||
            name.endsWith(' ') ||
            utf8.encode(p.relative(entry.path, from: payload)).length >
                limits.maxNameBytes ||
            RegExp(r'[:<>"|?*\\\x00-\x1f\x7f]').hasMatch(name)) {
          throw FileSystemException('Unsafe staged payload path', entry.path);
        }
        final type =
            await FileSystemEntity.type(entry.path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          if (depth + 1 > limits.maxDepth) {
            throw const FormatException(
                'Staged directory depth exceeds limit.');
          }
          await checkTree(entry.path, depth + 1);
        } else if (type != FileSystemEntityType.file ||
            entry.path != expectedFile) {
          throw FileSystemException(
              'Unexpected staged payload entry', entry.path);
        }
      }
    }

    Future<void> checkExpectedPath() async {
      await checkAncestors();
      for (final directory in allowedDirectories) {
        if (await FileSystemEntity.type(directory, followLinks: false) !=
            FileSystemEntityType.directory) {
          throw FileSystemException(
              'Missing or unsafe MP4 directory', directory);
        }
      }
      if (await FileSystemEntity.type(expectedFile, followLinks: false) !=
          FileSystemEntityType.file) {
        throw FileSystemException('Missing or unsafe staged MP4', expectedFile);
      }
    }

    await checkTree(payload, 0);
    await checkExpectedPath();
    final file = await File(expectedFile).open(mode: FileMode.read);
    var count = 0;
    var crc = 0;
    try {
      if (await file.length() != descriptor.uncompressedSize) {
        throw const FormatException('Staged MP4 size mismatch.');
      }
      while (true) {
        final chunk = await file.read(chunkSize);
        if (chunk.isEmpty) break;
        if (chunk.length > descriptor.uncompressedSize - count ||
            chunk.length > limits.maxMp4Bytes - count) {
          throw const FormatException('Staged MP4 exceeds size limit.');
        }
        crc = getCrc32(chunk, crc);
        count += chunk.length;
      }
      if (count != descriptor.uncompressedSize ||
          crc != descriptor.crc32 ||
          await file.length() != count) {
        throw const FormatException('Staged MP4 size or CRC mismatch.');
      }
    } finally {
      await file.close();
    }
    await checkExpectedPath();
    entries = 0;
    await checkTree(payload, 0);
    return AnimationStagedMp4VerificationResult(
        relativePath: relative, verifiedBytes: count);
  }
}
