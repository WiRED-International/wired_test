import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/animation_bounded_mp4_extraction_service.dart';
import 'package:wired_test/services/animation_installation_workspace_service.dart';
import 'package:wired_test/services/animation_zip_metadata_reader.dart';

class _Handle implements RandomAccessFile {
  _Handle(this.file, {this.events, this.failWriteAt, this.closeError});
  final RandomAccessFile file;
  final List<String>? events;
  final int? failWriteAt;
  final Object? closeError;
  bool closed = false;
  int writes = 0;
  @override
  Future<int> length() => file.length();
  @override
  int lengthSync() => file.lengthSync();
  @override
  Future<RandomAccessFile> setPosition(int position) =>
      file.setPosition(position);
  @override
  Future<Uint8List> read(int count) {
    events?.add('read:$count');
    return file.read(count);
  }

  @override
  void writeFromSync(List<int> bytes, [int start = 0, int? end]) {
    writes++;
    if (writes == failWriteAt) throw const FileSystemException('disk full');
    events?.add('write:${(end ?? bytes.length) - start}');
    file.writeFromSync(bytes, start, end);
  }

  @override
  Future<RandomAccessFile> writeFrom(List<int> bytes,
          [int start = 0, int? end]) =>
      throw StateError('Asynchronous writes must not be queued');
  @override
  void flushSync() => file.flushSync();
  @override
  Future<void> close() async {
    closed = true;
    await file.close();
    if (closeError != null) throw closeError!;
  }

  @override
  void closeSync() {
    closed = true;
    file.closeSync();
    if (closeError != null) throw closeError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory root;
  late AnimationInstallationWorkspace workspace;
  late File zip;
  late List<int> zipBytes;
  late List<File> sentinels;
  final bytes = List<int>.generate(8193, (i) => i % 251);
  Future<AnimationZipDescriptor> fixture(
      {int method = 8,
      String path = 'clip.mp4',
      List<int>? content,
      bool emptyDirectories = false}) async {
    final data = content ?? bytes;
    final entry = ArchiveFile(path, data.length, data)
      ..compression =
          method == 0 ? CompressionType.none : CompressionType.deflate;
    final archive = Archive();
    if (emptyDirectories) {
      archive.addFile(ArchiveFile.directory('unrelated/empty/'));
    }
    archive.addFile(entry);
    zipBytes = ZipEncoder().encode(archive);
    await zip.writeAsBytes(zipBytes);
    final d = await const AnimationZipMetadataReader().inspect(zip.path);
    expect(d.compressionMethod, method);
    return d;
  }

  AnimationZipDescriptor alter(AnimationZipDescriptor d,
          {int? offset,
          int? compressed,
          int? size,
          int? crc,
          int? method,
          String? path}) =>
      AnimationZipDescriptor(
          mp4RelativePath: path ?? d.mp4RelativePath,
          compressedSize: compressed ?? d.compressedSize,
          uncompressedSize: size ?? d.uncompressedSize,
          crc32: crc ?? d.crc32,
          compressionMethod: method ?? d.compressionMethod,
          payloadOffset: offset ?? d.payloadOffset);
  Future<AnimationBoundedMp4ExtractionResult> extract(
    AnimationZipDescriptor d, {
    int chunk = 32768,
    AnimationZipLimits limits = const AnimationZipLimits(),
    Future<RandomAccessFile> Function(File)? input,
    RandomAccessFile Function(File)? output,
  }) =>
      AnimationBoundedMp4ExtractionService(
              limits: limits,
              chunkSize: chunk,
              inputOpener: input,
              outputOpener: output)
          .extract(
              zipFile: zip,
              descriptor: d,
              payloadDirectory: workspace.payloadDirectory);
  File destination(AnimationZipDescriptor d) => File(p.joinAll(
      [workspace.payloadDirectory.path, ...d.mp4RelativePath.split('/')]));
  setUp(() async {
    root = await Directory.systemTemp.createTemp('healthmap-bounded-extract-');
    workspace = await AnimationInstallationWorkspaceService()
        .create(root: root, animationId: 42);
    zip = workspace.downloadFile;
    zipBytes = [];
    sentinels = [];
    for (final path in [
      'outside.keep',
      'modules/old/index.html',
      'packages/old/story.html'
    ]) {
      final file = File(p.join(root.path, path));
      await file.parent.create(recursive: true);
      sentinels.add(await file.writeAsString('preserve'));
    }
  });
  tearDown(() async {
    for (final file in sentinels) {
      expect(await file.readAsString(), 'preserve');
    }
    if (await zip.exists()) expect(await zip.readAsBytes(), zipBytes);
    expect(p.isWithin(Directory.systemTemp.absolute.path, root.path), isTrue);
    expect(p.basename(root.path), startsWith('healthmap-bounded-extract-'));
    await root.delete(recursive: true);
  });
  for (final method in [0, 8]) {
    for (final path in ['Original.MP4', 'deep/topic/Original_Name.mp4']) {
      test('valid method $method preserves $path', () async {
        final d = await fixture(method: method, path: path);
        final result = await extract(d, chunk: 7);
        expect(result.relativePath, path);
        expect(result.extractedBytes, bytes.length);
        final actual = await destination(d).readAsBytes();
        expect(actual, bytes);
        expect(getCrc32(actual), d.crc32);
      });
    }
  }
  test('unrelated archive directories omitted', () async {
    final d = await fixture(path: 'deep/clip.mp4', emptyDirectories: true);
    await extract(d);
    expect(
        await Directory(p.join(workspace.payloadDirectory.path, 'unrelated'))
            .exists(),
        isFalse);
    expect(await destination(d).readAsBytes(), bytes);
  });
  test('wrong CRC leaves private output for owned cleanup', () async {
    final d = await fixture();
    await expectLater(
        extract(alter(d, crc: d.crc32 ^ 1)), throwsFormatException);
    expect(await destination(d).readAsBytes(), bytes);
  });
  test('declared underflow rejected after writing available output', () async {
    final d = await fixture();
    await expectLater(
        extract(alter(d, size: bytes.length + 1)), throwsFormatException);
    expect(await destination(d).readAsBytes(), bytes);
  });
  test('high expansion stopped before exceeding declared and configured limit',
      () async {
    final d = await fixture(content: List.filled(128 * 1024, 65));
    await expectLater(
        extract(alter(d, size: 32),
            chunk: 1, limits: const AnimationZipLimits(maxMp4Bytes: 32)),
        throwsFormatException);
    expect(await destination(d).length(), lessThanOrEqualTo(32));
  });
  test('configured limit rejects before creating output', () async {
    final d = await fixture();
    await expectLater(
        extract(d, limits: const AnimationZipLimits(maxMp4Bytes: 16)),
        throwsFormatException);
    expect(await destination(d).exists(), isFalse);
  });
  test('corrupt Deflate rejected and partial file retained', () async {
    final d = await fixture();
    zipBytes[d.payloadOffset] = (zipBytes[d.payloadOffset] & ~6) | 6;
    await zip.writeAsBytes(zipBytes);
    await expectLater(extract(d), throwsFormatException);
    expect(await destination(d).exists(), isTrue);
  });
  test('truncated compressed range rejected before output', () async {
    final d = await fixture();
    zipBytes = zipBytes.sublist(0, d.payloadOffset + d.compressedSize - 1);
    await zip.writeAsBytes(zipBytes);
    await expectLater(extract(d), throwsFormatException);
    expect(await destination(d).exists(), isFalse);
  });
  final invalid =
      <String, AnimationZipDescriptor Function(AnimationZipDescriptor)>{
    'negative offset': (d) => alter(d, offset: -1),
    'overflow offset': (d) => alter(d, offset: 0x7ffffffffffffffe),
    'zero compressed': (d) => alter(d, compressed: 0),
    'negative compressed': (d) => alter(d, compressed: -1),
    'empty output': (d) => alter(d, size: 0),
    'wrong method': (d) => alter(d, method: 12),
    'invalid CRC': (d) => alter(d, crc: -1),
    'traversal': (d) => alter(d, path: '../clip.mp4'),
    'absolute': (d) => alter(d, path: '/clip.mp4'),
    'backslash': (d) => alter(d, path: r'deep\clip.mp4'),
    'drive path': (d) => alter(d, path: 'C:/clip.mp4'),
    'stored mismatch': (d) => alter(d, method: 0),
  };
  for (final entry in invalid.entries) {
    test('invalid descriptor: ${entry.key}', () async {
      final d = await fixture();
      await expectLater(extract(entry.value(d)), throwsFormatException);
      expect(await workspace.payloadDirectory.list().toList(), isEmpty);
    });
  }
  test('existing destination preserved', () async {
    final d = await fixture();
    await destination(d).writeAsString('existing');
    await expectLater(extract(d), throwsA(isA<FileSystemException>()));
    expect(await destination(d).readAsString(), 'existing');
  });
  test('parent file conflict preserved', () async {
    final d = await fixture(path: 'deep/clip.mp4');
    final file = await File(p.join(workspace.payloadDirectory.path, 'deep'))
        .writeAsString('keep');
    await expectLater(extract(d), throwsA(isA<FileSystemException>()));
    expect(await file.readAsString(), 'keep');
  });
  for (final directoryLink in [false, true]) {
    test('linked ${directoryLink ? 'ancestor' : 'destination'} refused',
        () async {
      final d =
          await fixture(path: directoryLink ? 'deep/clip.mp4' : 'clip.mp4');
      final link = Link(directoryLink
          ? p.join(workspace.payloadDirectory.path, 'deep')
          : destination(d).path);
      try {
        await link.create(directoryLink
            ? p.join(root.path, 'modules')
            : sentinels.first.path);
      } on FileSystemException catch (e) {
        markTestSkipped('Symlinks unavailable: $e');
        return;
      }
      await expectLater(extract(d), throwsA(isA<FileSystemException>()));
    });
  }
  test(
      'disk failure preserves partial output and original error despite close errors',
      () async {
    final d = await fixture(method: 0);
    late _Handle input, output;
    await expectLater(
        extract(d,
            chunk: 32,
            input: (file) async => input = _Handle(await file.open(),
                closeError: StateError('input close')),
            output: (file) => output = _Handle(
                file.openSync(mode: FileMode.writeOnlyAppend),
                failWriteAt: 2,
                closeError: StateError('output close'))),
        throwsA(isA<FileSystemException>()
            .having((e) => e.message, 'message', 'disk full')));
    expect(input.closed, isTrue);
    expect(output.closed, isTrue);
    expect(await destination(d).readAsBytes(), bytes.take(32).toList());
  });
  test('close failure on success reported and both handles released', () async {
    final d = await fixture();
    late _Handle input, output;
    final error = StateError('output close');
    await expectLater(
        extract(d,
            input: (file) async => input = _Handle(await file.open()),
            output: (file) => output = _Handle(
                file.openSync(mode: FileMode.writeOnlyAppend),
                closeError: error)),
        throwsA(same(error)));
    expect(input.closed, isTrue);
    expect(output.closed, isTrue);
    expect(await destination(d).readAsBytes(), bytes);
  });
  test('fixed input reads and immediate synchronous writes', () async {
    final data = List<int>.generate(256 * 1024 + 13, (i) => i % 251);
    final d = await fixture(method: 0, content: data);
    final events = <String>[];
    late _Handle input, output;
    await extract(d,
        chunk: 1024,
        input: (file) async =>
            input = _Handle(await file.open(), events: events),
        output: (file) => output = _Handle(
            file.openSync(mode: FileMode.writeOnlyAppend),
            events: events));
    expect(events.length, greaterThan(512));
    for (var i = 0; i < events.length; i += 2) {
      expect(events[i].startsWith('read:'), isTrue);
      expect(events[i + 1].startsWith('write:'), isTrue);
      expect(int.parse(events[i].split(':').last), lessThanOrEqualTo(1024));
    }
    expect(await destination(d).readAsBytes(), data);
    expect(input.closed && output.closed, isTrue);
  });
  test('nonprivate payload rejected', () async {
    final d = await fixture();
    await expectLater(
        AnimationBoundedMp4ExtractionService().extract(
            zipFile: zip,
            descriptor: d,
            payloadDirectory: Directory(p.join(root.path, 'modules'))),
        throwsArgumentError);
  });
}
