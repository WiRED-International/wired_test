import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/animation_zip_integrity_verification_service.dart';
import 'package:wired_test/services/animation_zip_metadata_reader.dart';

void main() {
  late Directory root;
  late File zip;
  late File sentinel;
  late List<int> original;
  final payload = List<int>.generate(4097, (index) => index % 251);

  Future<AnimationZipDescriptor> fixture(int method,
      {List<int>? content}) async {
    final data = content ?? payload;
    final entry = ArchiveFile('deep/clip.mp4', data.length, data)
      ..compression =
          method == 0 ? CompressionType.none : CompressionType.deflate;
    final archive = Archive()..addFile(entry);
    original = ZipEncoder().encode(archive);
    await zip.writeAsBytes(original);
    final descriptor =
        await const AnimationZipMetadataReader().inspect(zip.path);
    expect(descriptor.compressionMethod, method,
        reason: 'Fixture must use the requested ZIP compression');
    return descriptor;
  }

  AnimationZipDescriptor altered(
    AnimationZipDescriptor d, {
    int? compressed,
    int? uncompressed,
    int? crc,
    int? method,
    int? offset,
    String? path,
  }) =>
      AnimationZipDescriptor(
        mp4RelativePath: path ?? d.mp4RelativePath,
        compressedSize: compressed ?? d.compressedSize,
        uncompressedSize: uncompressed ?? d.uncompressedSize,
        crc32: crc ?? d.crc32,
        compressionMethod: method ?? d.compressionMethod,
        payloadOffset: offset ?? d.payloadOffset,
      );

  Future<void> verify(
    AnimationZipDescriptor descriptor, {
    int chunkSize = 32 * 1024,
    AnimationZipLimits limits = const AnimationZipLimits(),
  }) =>
      AnimationZipIntegrityVerificationService(
              chunkSize: chunkSize, limits: limits)
          .verify(zipPath: zip.path, descriptor: descriptor);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('healthmap-integrity-');
    zip = File(p.join(root.path, 'fixture.zip'));
    sentinel = await File(p.join(root.path, 'sentinel')).writeAsString('keep');
    original = [];
  });
  tearDown(() async {
    expect(await sentinel.readAsString(), 'keep');
    if (await zip.exists()) expect(await zip.readAsBytes(), original);
    expect(await root.list().length, await zip.exists() ? 2 : 1);
    expect(p.isWithin(Directory.systemTemp.absolute.path, root.path), isTrue);
    expect(p.basename(root.path), startsWith('healthmap-integrity-'));
    await root.delete(recursive: true);
  });

  for (final method in [0, 8]) {
    for (final chunk in [1, 7, 1024, 32768]) {
      test('valid method $method, chunk $chunk: exact size and CRC', () async {
        final d = await fixture(method);
        expect(d.crc32, getCrc32(payload));
        await verify(d, chunkSize: chunk);
      });
    }
    test('method $method rejects wrong CRC', () async {
      final d = await fixture(method);
      await expectLater(
          verify(altered(d, crc: d.crc32 ^ 1)), throwsFormatException);
    });
  }

  test('Deflate output below declared size fails final size check', () async {
    final d = await fixture(8);
    await expectLater(
        verify(altered(d, uncompressed: payload.length + 1)),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            'Animation payload size or CRC mismatch.')));
  });
  test('Deflate output above declared size aborts in output sink', () async {
    final d = await fixture(8);
    await expectLater(
        verify(altered(d, uncompressed: payload.length - 1)),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            'Animation output exceeds its size limit.')));
  });
  test('configured declared output maximum rejects before decoding', () async {
    final d = await fixture(8);
    await expectLater(
        verify(d, limits: const AnimationZipLimits(maxMp4Bytes: 16)),
        throwsFormatException);
  });
  test('configured compressed ZIP maximum is enforced', () async {
    final d = await fixture(0);
    await expectLater(
        verify(d, limits: AnimationZipLimits(maxZipBytes: original.length - 1)),
        throwsFormatException);
  });
  test('truncated compressed range fails and releases file', () async {
    final d = await fixture(8);
    original = original.sublist(0, d.payloadOffset + d.compressedSize - 1);
    await zip.writeAsBytes(original);
    await expectLater(verify(d), throwsFormatException);
    await zip.delete();
    expect(await zip.exists(), isFalse);
  });
  test('corrupted Deflate block rejected and handle released', () async {
    final d = await fixture(8);
    original[d.payloadOffset] = (original[d.payloadOffset] & ~6) | 6;
    await zip.writeAsBytes(original);
    await expectLater(verify(d), throwsFormatException);
    await zip.delete();
  });
  test('stored corruption produces CRC failure', () async {
    final d = await fixture(0);
    original[d.payloadOffset] ^= 0xff;
    await zip.writeAsBytes(original);
    await expectLater(verify(d), throwsFormatException);
  });
  test('high expansion aborts at small limit rather than completing CRC',
      () async {
    final d = await fixture(8, content: List.filled(128 * 1024, 65));
    expect(d.compressedSize, lessThan(1024));
    await expectLater(
        verify(altered(d, uncompressed: 32),
            chunkSize: 1, limits: const AnimationZipLimits(maxMp4Bytes: 32)),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            'Animation output exceeds its size limit.')));
    await zip.delete();
  });
  test('near-maximum offset rejected by bounds check before seek or read',
      () async {
    final d = await fixture(8);
    await expectLater(
        verify(altered(d, offset: 0x7ffffffffffffffe)),
        throwsA(isA<FormatException>().having((error) => error.message,
            'message', 'Invalid or truncated animation payload range.')));
    // An invalid seek would instead produce an I/O error; the bounds error
    // occurs before setPosition/read, and finally must still release the file.
    await zip.delete();
  });
  test('success closes input handle', () async {
    final d = await fixture(8);
    await verify(d);
    await zip.delete();
  });
  final invalid =
      <String, AnimationZipDescriptor Function(AnimationZipDescriptor)>{
    'zero compressed size': (d) => altered(d, compressed: 0),
    'negative compressed size': (d) => altered(d, compressed: -1),
    'zero output size': (d) => altered(d, uncompressed: 0),
    'negative output size': (d) => altered(d, uncompressed: -1),
    'negative offset': (d) => altered(d, offset: -1),
    'offset before local header': (d) => altered(d, offset: 0),
    'offset beyond file': (d) => altered(d, offset: 999999),
    'negative CRC': (d) => altered(d, crc: -1),
    'oversized CRC': (d) => altered(d, crc: 0x100000000),
    'unsupported method': (d) => altered(d, method: 12),
    'stored size mismatch': (d) => altered(d, method: 0),
    'unsafe path': (d) => altered(d, path: '../clip.mp4'),
    'wrong extension': (d) => altered(d, path: 'clip.txt'),
    'empty path': (d) => altered(d, path: ''),
  };
  for (final entry in invalid.entries) {
    test('invalid descriptor: ${entry.key}', () async {
      final d = await fixture(8);
      await expectLater(verify(entry.value(d)), throwsFormatException);
    });
  }
  test('invalid chunk sizes and limits rejected', () async {
    final d = await fixture(8);
    for (final chunk in [0, -1, 1024 * 1024 + 1]) {
      await expectLater(verify(d, chunkSize: chunk), throwsArgumentError);
    }
    await expectLater(
        verify(d, limits: const AnimationZipLimits(maxMp4Bytes: 0)),
        throwsArgumentError);
  });
}
