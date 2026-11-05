import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Limits apply before payload decoding. MB/GB here mean binary MiB/GiB.
class AnimationZipLimits {
  const AnimationZipLimits({
    this.maxZipBytes = 500 * 1024 * 1024,
    this.maxMp4Bytes = 1024 * 1024 * 1024,
    this.maxEntries = 100,
    this.maxDepth = 10,
    this.maxMetadataBytes = 1024 * 1024,
    this.maxNameBytes = 4096,
  });

  final int maxZipBytes;
  final int maxMp4Bytes;
  final int maxEntries;
  final int maxDepth;
  final int maxMetadataBytes;
  final int maxNameBytes;

  void validate() {
    if ([
      maxZipBytes,
      maxMp4Bytes,
      maxEntries,
      maxDepth,
      maxMetadataBytes,
      maxNameBytes
    ].any((value) => value <= 0)) {
      throw ArgumentError('ZIP limits must be positive.');
    }
  }
}

/// Validated metadata only: this does not establish payload CRC or MP4 integrity.
class AnimationZipDescriptor {
  const AnimationZipDescriptor({
    required this.mp4RelativePath,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.crc32,
    required this.compressionMethod,
    required this.payloadOffset,
  });

  final String mp4RelativePath;
  final int compressedSize;
  final int uncompressedSize;
  final int crc32;
  final int compressionMethod;
  final int payloadOffset;
}

/// Narrow, single-disk ZIP32 reader. Never reads compressed payload bytes.
class AnimationZipMetadataReader {
  const AnimationZipMetadataReader({this.limits = const AnimationZipLimits()});

  final AnimationZipLimits limits;

  Never _invalid(String reason) => throw FormatException(reason);

  Future<AnimationZipDescriptor> inspect(String path) async {
    limits.validate();
    final file = await File(path).open();
    try {
      final length = await file.length();
      if (length < 22 || length > limits.maxZipBytes) {
        _invalid('Invalid or oversized ZIP length.');
      }
      Future<ByteData> read(int offset, int count, int end) async {
        if (offset < 0 || count < 0 || offset + count > end) {
          _invalid('ZIP metadata exceeds its bounds.');
        }
        await file.setPosition(offset);
        final bytes = await file.read(count);
        if (bytes.length != count) _invalid('Truncated ZIP metadata.');
        return ByteData.sublistView(bytes);
      }

      // The ZIP32 EOCD has at most 65535 bytes of comment.
      final tailStart = math.max(0, length - 22 - 65535);
      final tail = await read(tailStart, length - tailStart, length);
      int? eocd;
      for (var i = tail.lengthInBytes - 22; i >= 0; i--) {
        if (_u32(tail, i) == 0x06054b50 &&
            i + 22 + _u16(tail, i + 20) == tail.lengthInBytes) {
          if (eocd != null) _invalid('Ambiguous ZIP footer.');
          eocd = i;
        }
      }
      if (eocd == null) {
        _invalid('Missing ZIP footer or invalid comment length.');
      }
      final footer = eocd;
      final footerOffset = tailStart + footer;
      if (_u16(tail, footer + 4) != 0 || _u16(tail, footer + 6) != 0) {
        _invalid('Multi-disk ZIP is unsupported.');
      }
      final count = _u16(tail, footer + 10);
      final size = _u32(tail, footer + 12);
      final start = _u32(tail, footer + 16);
      if (count == 0xffff || size == 0xffffffff || start == 0xffffffff) {
        _invalid('ZIP64 is unsupported.');
      }
      if (footerOffset >= 20 &&
          _u32(await read(footerOffset - 20, 4, length), 0) == 0x07064b50) {
        _invalid('ZIP64 is unsupported.');
      }
      if (count == 0 ||
          count > limits.maxEntries ||
          _u16(tail, footer + 8) != count ||
          size > limits.maxMetadataBytes ||
          size < count * 46 ||
          start + size != footerOffset) {
        _invalid('Invalid central-directory count or bounds.');
      }
      final entries = <_Entry>[];
      final destinations = <String, bool>{};
      final directories = <String>{};
      var cursor = start;
      _Entry? video;
      for (var index = 0; index < count; index++) {
        final header = await read(cursor, 46, footerOffset);
        if (_u32(header, 0) != 0x02014b50) _invalid('Invalid central header.');
        final nameLength = _u16(header, 28);
        final extraLength = _u16(header, 30);
        final commentLength = _u16(header, 32);
        if (nameLength == 0 || nameLength > limits.maxNameBytes) {
          _invalid('Invalid or oversized ZIP name.');
        }
        final end = cursor + 46 + nameLength + extraLength + commentLength;
        if (end > footerOffset) _invalid('Central entry exceeds directory.');
        final flags = _u16(header, 8);
        final method = _u16(header, 10);
        _profile(flags, method, _u16(header, 6));
        final compressed = _u32(header, 20);
        final uncompressed = _u32(header, 24);
        if (method == 0 && compressed != uncompressed) {
          _invalid('Stored entry sizes differ.');
        }
        final localOffset = _u32(header, 42);
        if ([compressed, uncompressed, localOffset].contains(0xffffffff) ||
            _u16(header, 34) == 0xffff) {
          _invalid('ZIP64 is unsupported.');
        }
        if (_u16(header, 34) != 0) _invalid('Multi-disk ZIP is unsupported.');
        final rawName = (await read(cursor + 46, nameLength, footerOffset))
            .buffer
            .asUint8List();
        final name = _name(rawName, flags);
        final isDirectory = name.endsWith('/') || name.endsWith('\\');
        final mode = _u32(header, 38) >> 16;
        final type = mode & 0xf000;
        if (type != 0 && type != (isDirectory ? 0x4000 : 0x8000)) {
          _invalid('Links and nonregular ZIP entries are unsupported.');
        }
        if ((_u32(header, 38) & 0x10) != 0 && !isDirectory) {
          _invalid('Inconsistent directory attributes.');
        }
        final relative = _safePath(name, isDirectory);
        // Conservative alias rejection across case-insensitive mobile storage.
        final key = relative.toLowerCase();
        if (destinations.containsKey(key)) {
          _invalid('Duplicate ZIP destination.');
        }
        if (!isDirectory && directories.contains(key)) {
          _invalid('ZIP file/directory conflict.');
        }
        destinations[key] = !isDirectory;
        final components = key.split('/');
        for (var n = 1; n <= components.length; n++) {
          if (n == components.length && !isDirectory) break;
          final parent = components.take(n).join('/');
          if (destinations[parent] == true) {
            _invalid('ZIP file/directory conflict.');
          }
          directories.add(parent);
        }
        await _extras(
            read, cursor + 46 + nameLength, extraLength, footerOffset);
        final entry = _Entry(relative, rawName, flags, method, _u32(header, 16),
            compressed, uncompressed, localOffset);
        entries.add(entry);
        if (isDirectory) {
          if (uncompressed != 0) _invalid('Directory declares file content.');
        } else {
          if (video != null ||
              !relative.toLowerCase().endsWith('.mp4') ||
              uncompressed == 0 ||
              uncompressed > limits.maxMp4Bytes ||
              compressed == 0) {
            _invalid('Expected exactly one bounded nonempty MP4.');
          }
          video = entry;
        }
        cursor = end;
      }
      if (cursor != footerOffset || video == null) {
        _invalid('Central-directory count mismatch or missing MP4.');
      }
      // Check every local record, including directories. Contiguous records
      // disallow overlapping payloads, hidden local entries and SFX prefixes.
      entries.sort((a, b) => a.localOffset.compareTo(b.localOffset));
      var localEnd = 0;
      for (final entry in entries) {
        if (entry.localOffset != localEnd) {
          _invalid('Invalid local record bounds.');
        }
        final header = await read(entry.localOffset, 30, start);
        if (_u32(header, 0) != 0x04034b50 ||
            _u16(header, 6) != entry.flags ||
            _u16(header, 8) != entry.method) {
          _invalid('Inconsistent local header.');
        }
        _profile(entry.flags, entry.method, _u16(header, 4));
        final nameLength = _u16(header, 26);
        final extraLength = _u16(header, 28);
        if (nameLength != entry.rawName.length) {
          _invalid('Local name mismatch.');
        }
        final localName = await read(entry.localOffset + 30, nameLength, start);
        for (var i = 0; i < nameLength; i++) {
          if (localName.getUint8(i) != entry.rawName[i]) {
            _invalid('Local name mismatch.');
          }
        }
        final localSizes = [
          _u32(header, 14),
          _u32(header, 18),
          _u32(header, 22)
        ];
        if (localSizes.skip(1).contains(0xffffffff)) {
          _invalid('ZIP64 is unsupported.');
        }
        final expected = [entry.crc, entry.compressed, entry.uncompressed];
        for (var i = 0; i < 3; i++) {
          if (localSizes[i] != expected[i] &&
              !(entry.flags & 8 != 0 && localSizes[i] == 0)) {
            _invalid('Local CRC or size mismatch.');
          }
        }
        await _extras(
            read, entry.localOffset + 30 + nameLength, extraLength, start);
        entry.payloadOffset = entry.localOffset + 30 + nameLength + extraLength;
        localEnd = entry.payloadOffset + entry.compressed;
        if (localEnd > start) _invalid('Compressed payload exceeds bounds.');
        if (entry.flags & 8 != 0) {
          final first = await read(localEnd, 4, start);
          final signed = _u32(first, 0) == 0x08074b50;
          final descriptor = await read(localEnd, signed ? 16 : 12, start);
          final offset = signed ? 4 : 0;
          for (var i = 0; i < 3; i++) {
            if (_u32(descriptor, offset + i * 4) != expected[i]) {
              _invalid('Invalid data descriptor.');
            }
          }
          localEnd += signed ? 16 : 12;
        }
      }
      if (localEnd != start) {
        _invalid('Unexpected data before central directory.');
      }
      return AnimationZipDescriptor(
          mp4RelativePath: video.path,
          compressedSize: video.compressed,
          uncompressedSize: video.uncompressed,
          crc32: video.crc,
          compressionMethod: video.method,
          payloadOffset: video.payloadOffset);
    } finally {
      await file.close();
    }
  }

  void _profile(int flags, int method, int version) {
    if (flags & 0x2041 != 0) _invalid('Encrypted ZIP is unsupported.');
    if (flags & ~0x080e != 0 ||
        (method != 0 && method != 8) ||
        version > 20 ||
        (method == 0 && flags & 6 != 0)) {
      _invalid('Unsupported ZIP feature or compression.');
    }
  }

  String _name(Uint8List bytes, int flags) {
    if (flags & 0x800 == 0 && bytes.any((byte) => byte >= 128)) {
      _invalid('Non-UTF8 legacy filename encoding is unsupported.');
    }
    return utf8.decode(bytes);
  }

  String _safePath(String name, bool directory) {
    final normalized = name.replaceAll('\\', '/');
    final path =
        directory ? normalized.substring(0, normalized.length - 1) : normalized;
    final parts = path.split('/');
    if (parts.any((part) =>
            part.isEmpty ||
            part == '.' ||
            part == '..' ||
            part.endsWith('.') ||
            part.endsWith(' ') ||
            part.codeUnits.any((c) => c < 32 || c == 127) ||
            RegExp(r'[:<>"|?*]').hasMatch(part)) ||
        (directory ? parts.length : parts.length - 1) > limits.maxDepth) {
      _invalid('Unsafe ZIP path or excessive depth.');
    }
    return path;
  }

  Future<void> _extras(Future<ByteData> Function(int, int, int) read,
      int offset, int length, int end) async {
    final stop = offset + length;
    if (stop > end) _invalid('Extra fields exceed bounds.');
    while (offset < stop) {
      final header = await read(offset, 4, stop);
      final id = _u16(header, 0);
      if (id == 1) _invalid('ZIP64 is unsupported.');
      // Alternate name/path and encryption extensions are not interpreted.
      if (id == 0x7075 || id == 0x9901) {
        _invalid('Unsupported ZIP extra field.');
      }
      offset += 4 + _u16(header, 2);
      if (offset > stop) _invalid('Truncated extra field.');
    }
  }

  static int _u16(ByteData data, int offset) =>
      data.getUint16(offset, Endian.little);
  static int _u32(ByteData data, int offset) =>
      data.getUint32(offset, Endian.little);
}

class _Entry {
  _Entry(this.path, this.rawName, this.flags, this.method, this.crc,
      this.compressed, this.uncompressed, this.localOffset);
  final String path;
  final Uint8List rawName;
  final int flags, method, crc, compressed, uncompressed, localOffset;
  int payloadOffset = 0;
}
