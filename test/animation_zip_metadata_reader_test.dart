import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/animation_zip_metadata_reader.dart';

// Raw fixtures deliberately bypass Archive/ZipDecoder name deduplication.
Uint8List fixture(
    {List<String> names = const ['clip.mp4'],
    bool descriptor = false,
    String comment = ''}) {
  final local = BytesBuilder();
  final central = BytesBuilder();
  for (final name in names) {
    final encoded = utf8.encode(name);
    final data = name.endsWith('/') ? <int>[] : <int>[1, 2, 3, 255];
    final crc = getCrc32(data);
    final offset = local.length;
    final header = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, descriptor ? 8 : 0, Endian.little)
      ..setUint32(14, descriptor ? 0 : crc, Endian.little)
      ..setUint32(18, descriptor ? 0 : data.length, Endian.little)
      ..setUint32(22, descriptor ? 0 : data.length, Endian.little)
      ..setUint16(26, encoded.length, Endian.little);
    local.add(header.buffer.asUint8List());
    local.add(encoded);
    local.add(data);
    if (descriptor) {
      final record = ByteData(16)
        ..setUint32(0, 0x08074b50, Endian.little)
        ..setUint32(4, crc, Endian.little)
        ..setUint32(8, data.length, Endian.little)
        ..setUint32(12, data.length, Endian.little);
      local.add(record.buffer.asUint8List());
    }
    final record = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, descriptor ? 8 : 0, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, data.length, Endian.little)
      ..setUint16(28, encoded.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central.add(record.buffer.asUint8List());
    central.add(encoded);
  }
  final footer = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, names.length, Endian.little)
    ..setUint16(10, names.length, Endian.little)
    ..setUint32(12, central.length, Endian.little)
    ..setUint32(16, local.length, Endian.little)
    ..setUint16(20, utf8.encode(comment).length, Endian.little);
  return (BytesBuilder()
        ..add(local.takeBytes())
        ..add(central.takeBytes())
        ..add(footer.buffer.asUint8List())
        ..add(utf8.encode(comment)))
      .takeBytes();
}

void main() {
  late Directory root;
  late File zip;
  late File sentinel;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('healthmap-zip-metadata-');
    zip = File(p.join(root.path, 'fixture.zip'));
    sentinel = await File(p.join(root.path, 'sentinel')).writeAsString('keep');
  });
  tearDown(() async {
    expect(await sentinel.readAsString(), 'keep');
    expect(p.isWithin(Directory.systemTemp.absolute.path, root.path), isTrue);
    expect(p.basename(root.path), startsWith('healthmap-zip-metadata-'));
    await root.delete(recursive: true);
  });
  Future<AnimationZipDescriptor> inspect(Uint8List data,
      [AnimationZipLimits limits = const AnimationZipLimits()]) async {
    await zip.writeAsBytes(data);
    try {
      return await AnimationZipMetadataReader(limits: limits).inspect(zip.path);
    } finally {
      expect(await zip.readAsBytes(), data);
      expect(await root.list().length, 2);
    }
  }

  int central(Uint8List bytes) =>
      ByteData.sublistView(bytes).getUint32(bytes.length - 6, Endian.little);

  test('descriptor fields, comments and signed data descriptor', () async {
    for (final descriptor in [false, true]) {
      final result =
          await inspect(fixture(descriptor: descriptor, comment: 'ok'));
      expect(result.mp4RelativePath, 'clip.mp4');
      expect(result.compressedSize, 4);
      expect(result.uncompressedSize, 4);
      expect(result.crc32, getCrc32([1, 2, 3, 255]));
      expect(result.compressionMethod, 0);
      expect(result.payloadOffset, 30 + 'clip.mp4'.length);
    }
  });
  test('raw exact duplicates are present and rejected before merging',
      () async {
    final data = fixture(names: ['clip.mp4', 'clip.mp4']);
    expect(
        ByteData.sublistView(data).getUint16(data.length - 12, Endian.little),
        2);
    final directory = ZipDirectory()..read(InputMemoryStream(data));
    expect(directory.fileHeaders.map((entry) => entry.filename),
        ['clip.mp4', 'clip.mp4']);
    await expectLater(inspect(data), throwsFormatException);
  });

  for (final names in [
    ['a/clip.mp4', r'a\clip.mp4'],
    ['a/', 'A/', 'clip.mp4'],
    ['clip.mp4', 'clip.mp4/'],
    ['clip.mp4/', 'clip.mp4'],
    ['a//clip.mp4'],
    ['../clip.mp4'],
    ['/clip.mp4'],
    ['a./clip.mp4'],
    ['a /clip.mp4'],
    ['a\u0000/clip.mp4'],
  ]) {
    test('rejects unsafe or conflicting raw paths: $names', () async {
      await expectLater(inspect(fixture(names: names)), throwsFormatException);
    });
  }

  final patches = <String, void Function(ByteData, int, int)>{
    'declared counts differ': (b, c, e) => b.setUint16(e + 8, 2, Endian.little),
    'too few actual records': (b, c, e) {
      b.setUint16(e + 8, 2, Endian.little);
      b.setUint16(e + 10, 2, Endian.little);
    },
    'unconsumed directory bytes': (b, c, e) {
      b.setUint16(c + 28, 1, Endian.little);
    },
    'bad central signature': (b, c, e) => b.setUint32(c, 0, Endian.little),
    'bad local signature': (b, c, e) => b.setUint32(0, 0, Endian.little),
    'local name mismatch': (b, c, e) => b.setUint8(30, 88),
    'local method mismatch': (b, c, e) => b.setUint16(8, 8, Endian.little),
    'local size mismatch': (b, c, e) => b.setUint32(22, 99, Endian.little),
    'local CRC mismatch': (b, c, e) => b.setUint32(14, 0, Endian.little),
    'local extra truncation': (b, c, e) =>
        b.setUint16(28, 65535, Endian.little),
    'central extra truncation': (b, c, e) =>
        b.setUint16(c + 30, 65535, Endian.little),
    'central offset outside file': (b, c, e) =>
        b.setUint32(e + 16, 99999, Endian.little),
    'invalid comment length': (b, c, e) =>
        b.setUint16(e + 20, 1, Endian.little),
    'encryption': (b, c, e) => b.setUint16(c + 8, 1, Endian.little),
    'unsupported compression': (b, c, e) =>
        b.setUint16(c + 10, 12, Endian.little),
    'multi disk footer': (b, c, e) => b.setUint16(e + 4, 1, Endian.little),
    'multi disk entry': (b, c, e) => b.setUint16(c + 34, 1, Endian.little),
    'ZIP64 footer': (b, c, e) => b.setUint16(e + 10, 65535, Endian.little),
    'ZIP64 size': (b, c, e) => b.setUint32(c + 24, 0xffffffff, Endian.little),
    'symlink mode': (b, c, e) => b.setUint32(c + 38, 0xa1ff0000, Endian.little),
    'FIFO mode': (b, c, e) => b.setUint32(c + 38, 0x11ff0000, Endian.little),
    'payload overlaps directory': (b, c, e) {
      b.setUint32(c + 20, 999, Endian.little);
      b.setUint32(18, 999, Endian.little);
    },
  };
  for (final patch in patches.entries) {
    test('rejects ${patch.key}', () async {
      final bytes = fixture();
      patch.value(
          ByteData.sublistView(bytes), central(bytes), bytes.length - 22);
      await expectLater(inspect(bytes), throwsFormatException);
    });
  }
  for (final limits in [
    const AnimationZipLimits(maxZipBytes: 30),
    const AnimationZipLimits(maxMp4Bytes: 3),
    const AnimationZipLimits(maxMetadataBytes: 46),
    const AnimationZipLimits(maxNameBytes: 3),
  ]) {
    test('rejects configured resource bound: $limits', () async {
      await expectLater(inspect(fixture(), limits), throwsFormatException);
    });
  }
  test('entry count and depth limits with small fixtures', () async {
    await expectLater(
        inspect(fixture(names: ['a/', 'a/clip.mp4']),
            const AnimationZipLimits(maxEntries: 1)),
        throwsFormatException);
    await expectLater(
        inspect(fixture(names: ['a/b/clip.mp4']),
            const AnimationZipLimits(maxDepth: 1)),
        throwsFormatException);
    expect(
        (await inspect(fixture(names: ['a/clip.mp4']),
                const AnimationZipLimits(maxDepth: 1)))
            .mp4RelativePath,
        'a/clip.mp4');
  });
  test('metadata inspection does not decode or validate payload CRC', () async {
    final data = fixture();
    final b = ByteData.sublistView(data);
    // Both methods agree, but payload is intentionally not a valid deflate
    // stream. Metadata-only inspection must not attempt to inflate it.
    b.setUint16(8, 8, Endian.little);
    b.setUint16(central(data) + 10, 8, Endian.little);
    data[30 + 'clip.mp4'.length] ^= 0xff;
    expect((await inspect(data)).compressionMethod, 8);
  });
}
