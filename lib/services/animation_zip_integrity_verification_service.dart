import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart' show getCrc32;

import 'animation_zip_metadata_reader.dart';

/// Verifies output length and ZIP CRC without retaining decompressed content.
/// Dart's raw Deflate decoder does NOT guarantee complete stream termination
/// or rejection of trailing compressed bytes. This is not strict Deflate
/// boundary validation, media validation, or authenticity verification.
class AnimationZipIntegrityVerificationService {
  const AnimationZipIntegrityVerificationService({
    this.limits = const AnimationZipLimits(),
    this.chunkSize = 32 * 1024,
  });

  final AnimationZipLimits limits;
  final int chunkSize;

  /// Call in a background isolate when integrated into the application: CRC
  /// and inflater callbacks execute synchronously. The caller must keep the
  /// inspected ZIP immutable; a descriptor is not proof of file identity.
  Future<void> verify({
    required String zipPath,
    required AnimationZipDescriptor descriptor,
  }) async {
    limits.validate();
    if (chunkSize <= 0 || chunkSize > 1024 * 1024) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'Must be 1..1048576');
    }
    final path = descriptor.mp4RelativePath;
    final parts = path.split('/');
    if (path.isEmpty ||
        path.contains('\\') ||
        !path.toLowerCase().endsWith('.mp4') ||
        parts.any((part) =>
            part.isEmpty ||
            part == '.' ||
            part == '..' ||
            part.endsWith('.') ||
            part.endsWith(' ') ||
            RegExp(r'[:<>"|?*\x00-\x1f\x7f]').hasMatch(part)) ||
        parts.length - 1 > limits.maxDepth ||
        utf8.encode(path).length > limits.maxNameBytes ||
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
      throw const FormatException('Invalid animation payload descriptor.');
    }
    final file = await File(zipPath).open(mode: FileMode.read);
    try {
      final length = await file.length();
      if (length > limits.maxZipBytes ||
          descriptor.payloadOffset < 0 ||
          descriptor.compressedSize < 0 ||
          descriptor.payloadOffset > length ||
          descriptor.compressedSize > length - descriptor.payloadOffset) {
        throw const FormatException(
            'Invalid or truncated animation payload range.');
      }
      await file.setPosition(descriptor.payloadOffset);
      final output =
          _VerificationSink(descriptor.uncompressedSize, limits.maxMp4Bytes);
      final ByteConversionSink? decoder = descriptor.compressionMethod == 8
          ? ZLibCodec(raw: true).decoder.startChunkedConversion(output)
          : null;
      var remaining = descriptor.compressedSize;
      while (remaining > 0) {
        final bytes = await file.read(math.min(chunkSize, remaining));
        if (bytes.isEmpty) {
          throw const FormatException('Truncated animation payload.');
        }
        remaining -= bytes.length;
        if (decoder == null) {
          output.add(bytes);
        } else {
          decoder.add(bytes);
        }
      }
      // Finalize only after successfully feeding the declared range. On an
      // error, stop immediately; do not flush additional output over a limit.
      decoder?.close();
      if (output.count != descriptor.uncompressedSize ||
          output.crc != descriptor.crc32) {
        throw const FormatException('Animation payload size or CRC mismatch.');
      }
    } finally {
      await file.close();
    }
  }
}

class _VerificationSink extends ByteConversionSink {
  _VerificationSink(this.expectedSize, this.maximumSize);

  final int expectedSize;
  final int maximumSize;
  int count = 0;
  int crc = 0;

  @override
  void add(List<int> chunk) {
    if (chunk.length > expectedSize - count ||
        chunk.length > maximumSize - count) {
      throw const FormatException('Animation output exceeds its size limit.');
    }
    crc = getCrc32(chunk, crc);
    count += chunk.length;
  }

  @override
  void close() {}
}
