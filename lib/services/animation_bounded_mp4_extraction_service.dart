import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart' show getCrc32;
import 'package:path/path.dart' as p;

import 'animation_zip_metadata_reader.dart';

class AnimationBoundedMp4ExtractionResult {
  const AnimationBoundedMp4ExtractionResult({
    required this.relativePath,
    required this.extractedBytes,
  });
  final String relativePath;
  final int extractedBytes;
}

/// Extracts only the descriptor's MP4 into an exclusively owned workspace.
/// Run in a worker isolate: decoder callbacks and disk writes are synchronous.
/// Dart raw Deflate may accept truncated endings, trailing compressed bytes,
/// and concatenated streams. Size/CRC checks are not strict stream-boundary,
/// media-playability or authenticity validation. The ZIP must remain immutable.
class AnimationBoundedMp4ExtractionService {
  AnimationBoundedMp4ExtractionService({
    this.limits = const AnimationZipLimits(),
    this.chunkSize = 32 * 1024,
    Future<RandomAccessFile> Function(File)? inputOpener,
    RandomAccessFile Function(File)? outputOpener,
  })  : _inputOpener =
            inputOpener ?? ((file) => file.open(mode: FileMode.read)),
        _outputOpener = outputOpener ??
            ((file) => file.openSync(mode: FileMode.writeOnlyAppend));

  final AnimationZipLimits limits;
  final int chunkSize;
  // Trusted I/O hooks for tests. Openers must close handles themselves if they
  // throw before returning. Output writes must finish synchronously.
  final Future<RandomAccessFile> Function(File) _inputOpener;
  final RandomAccessFile Function(File) _outputOpener;

  Future<AnimationBoundedMp4ExtractionResult> extract({
    required File zipFile,
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
        descriptor.compressedSize <= 0 ||
        descriptor.compressedSize > limits.maxZipBytes ||
        descriptor.uncompressedSize <= 0 ||
        descriptor.uncompressedSize > limits.maxMp4Bytes ||
        descriptor.payloadOffset < 30 ||
        descriptor.crc32 < 0 ||
        descriptor.crc32 > 0xffffffff ||
        (descriptor.compressionMethod != 0 &&
            descriptor.compressionMethod != 8) ||
        (descriptor.compressionMethod == 0 &&
            descriptor.compressedSize != descriptor.uncompressedSize)) {
      throw const FormatException('Invalid animation extraction descriptor.');
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
    final target = File(p.joinAll([payload, ...parts]));
    if (!p.isWithin(payload, target.path)) {
      throw const FormatException('MP4 destination escapes private payload.');
    }
    Future<void> checkWorkspace() async {
      // The caller's canonical root is trusted; OS aliases above it (iOS /var)
      // are outside this boundary. Path checks cannot defeat hostile races.
      for (final path in [root, parent, attempt, payload]) {
        if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.directory) {
          throw FileSystemException('Unsafe private payload ancestor', path);
        }
      }
    }

    await checkWorkspace();
    if (await FileSystemEntity.type(zipFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException('Expected an ordinary ZIP file', zipFile.path);
    }
    final input = await _inputOpener(zipFile);
    RandomAccessFile? output;
    Object? primaryError;
    try {
      final length = await input.length();
      if (length > limits.maxZipBytes ||
          descriptor.payloadOffset > length ||
          descriptor.compressedSize > length - descriptor.payloadOffset) {
        throw const FormatException('Invalid or truncated MP4 payload range.');
      }
      await checkWorkspace();
      var directory = payload;
      for (final component in parts.take(parts.length - 1)) {
        directory = p.join(directory, component);
        final type = await FileSystemEntity.type(directory, followLinks: false);
        if (type == FileSystemEntityType.notFound) {
          await Directory(directory).create();
        }
        if (await FileSystemEntity.type(directory, followLinks: false) !=
            FileSystemEntityType.directory) {
          throw FileSystemException('Unsafe MP4 parent directory', directory);
        }
      }
      if (await FileSystemEntity.type(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException(
            'MP4 destination already exists', target.path);
      }
      await target.create(exclusive: true);
      // Append-open avoids truncation; exclusive creation above refuses all
      // pre-existing outputs. No protection against hostile path replacement.
      output = _outputOpener(target);
      final sink =
          _Mp4FileSink(output, descriptor.uncompressedSize, limits.maxMp4Bytes);
      final ByteConversionSink? decoder = descriptor.compressionMethod == 8
          ? ZLibCodec(raw: true).decoder.startChunkedConversion(sink)
          : null;
      await input.setPosition(descriptor.payloadOffset);
      var remaining = descriptor.compressedSize;
      while (remaining > 0) {
        final chunk = await input.read(math.min(chunkSize, remaining));
        if (chunk.isEmpty) {
          throw const FormatException('Truncated MP4 payload.');
        }
        remaining -= chunk.length;
        if (decoder == null) {
          sink.add(chunk);
        } else {
          decoder.add(chunk);
        }
      }
      decoder?.close();
      if (sink.count != descriptor.uncompressedSize ||
          sink.crc != descriptor.crc32) {
        throw const FormatException('Extracted MP4 size or CRC mismatch.');
      }
      output.flushSync();
      if (output.lengthSync() != sink.count) {
        throw const FormatException('Extracted MP4 file size mismatch.');
      }
      return AnimationBoundedMp4ExtractionResult(
          relativePath: relative, extractedBytes: sink.count);
    } catch (error) {
      primaryError = error;
      rethrow;
    } finally {
      Object? cleanupError;
      try {
        output?.closeSync();
      } catch (error) {
        cleanupError = error;
      }
      try {
        await input.close();
      } catch (error) {
        cleanupError ??= error;
      }
      if (primaryError == null && cleanupError != null) throw cleanupError;
      // Partial output is deliberately preserved for workspace-owned cleanup.
    }
  }
}

class _Mp4FileSink extends ByteConversionSink {
  _Mp4FileSink(this.file, this.expected, this.maximum);
  final RandomAccessFile file;
  final int expected, maximum;
  int count = 0, crc = 0;
  @override
  void add(List<int> chunk) {
    if (chunk.length > expected - count || chunk.length > maximum - count) {
      throw const FormatException('Extracted MP4 exceeds output size limit.');
    }
    file.writeFromSync(chunk);
    crc = getCrc32(chunk, crc);
    count += chunk.length;
  }

  @override
  void close() {} // The service owns flushing and closing the file handle.
}
