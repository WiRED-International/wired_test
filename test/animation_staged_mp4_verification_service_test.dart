import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/animation_installation_workspace_service.dart';
import 'package:wired_test/services/animation_staged_mp4_verification_service.dart';
import 'package:wired_test/services/animation_zip_metadata_reader.dart';

class _ReadTrackingFile implements File {
  _ReadTrackingFile(this.delegate, this.reads);
  final File delegate;
  final List<int> reads;
  @override
  String get path => delegate.path;
  @override
  File get absolute => this; // Fixture delegate already has an absolute path.
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      _ReadTrackingHandle(await delegate.open(mode: mode), reads);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReadTrackingHandle implements RandomAccessFile {
  _ReadTrackingHandle(this.delegate, this.reads);
  final RandomAccessFile delegate;
  final List<int> reads;
  @override
  Future<Uint8List> read(int count) async {
    reads.add(count);
    return delegate.read(count);
  }

  @override
  Future<int> length() => delegate.length();
  @override
  Future<void> close() => delegate.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory root;
  late AnimationInstallationWorkspace workspace;
  late List<File> sentinels;
  late Map<String, List<int>> staged;
  final bytes = List<int>.generate(4097, (i) => i % 251);
  AnimationZipDescriptor descriptor(
          {String path = 'clip.mp4', int? size, int? crc}) =>
      AnimationZipDescriptor(
          mp4RelativePath: path,
          compressedSize: 10,
          uncompressedSize: size ?? bytes.length,
          crc32: crc ?? getCrc32(bytes),
          compressionMethod: 8,
          payloadOffset: 50);
  Future<File> write(String relative, List<int> content) async {
    final file = File(p.join(workspace.payloadDirectory.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(content);
    staged[file.path] = List.of(content);
    return file;
  }

  Future<AnimationStagedMp4VerificationResult> verify(AnimationZipDescriptor d,
          {AnimationZipLimits limits = const AnimationZipLimits(),
          int chunk = 32768}) =>
      AnimationStagedMp4VerificationService(limits: limits, chunkSize: chunk)
          .verify(descriptor: d, payloadDirectory: workspace.payloadDirectory);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('healthmap-staged-verify-');
    workspace = await AnimationInstallationWorkspaceService()
        .create(root: root, animationId: 42);
    staged = {};
    sentinels = [];
    for (final relative in [
      'unrelated.keep',
      'modules/old/clip.mp4',
      'packages/old/story.html'
    ]) {
      final file = File(p.join(root.path, relative));
      await file.parent.create(recursive: true);
      sentinels.add(await file.writeAsString('preserve'));
    }
  });
  tearDown(() async {
    for (final entry in staged.entries) {
      expect(await File(entry.key).readAsBytes(), entry.value);
    }
    for (final sentinel in sentinels) {
      expect(await sentinel.readAsString(), 'preserve');
    }
    expect(p.isWithin(Directory.systemTemp.absolute.path, root.path), isTrue);
    expect(p.basename(root.path), startsWith('healthmap-staged-verify-'));
    await root.delete(recursive: true);
  });
  for (final path in ['clip.mp4', 'deep/topic/Original_Name.MP4']) {
    test('valid exact size and CRC at $path', () async {
      await write(path, bytes);
      final result = await verify(descriptor(path: path), chunk: 7);
      expect(result.relativePath, path);
      expect(result.verifiedBytes, bytes.length);
    });
  }
  test('missing MP4 rejected despite unrelated installed MP4', () async {
    await expectLater(
        verify(descriptor()), throwsA(isA<FileSystemException>()));
  });
  for (final entry in <String, List<int>>{
    'empty': [],
    'truncated': [1, 2],
    'extra bytes': [...bytes, 1],
    'same-size corruption': [bytes.first ^ 1, ...bytes.skip(1)],
  }.entries) {
    test('rejects ${entry.key} without changing staged bytes', () async {
      await write('clip.mp4', entry.value);
      await expectLater(verify(descriptor()), throwsFormatException);
    });
  }
  test('configured MP4 maximum rejects oversized actual file', () async {
    await write('clip.mp4', bytes);
    await expectLater(
        verify(descriptor(), limits: const AnimationZipLimits(maxMp4Bytes: 16)),
        throwsFormatException);
  });
  test('actual oversized file rejected when declared size fits maximum',
      () async {
    await write('clip.mp4', bytes);
    await expectLater(
        verify(descriptor(size: 16),
            limits: const AnimationZipLimits(maxMp4Bytes: 16)),
        throwsFormatException);
  });
  test('extra regular file rejected', () async {
    await write('clip.mp4', bytes);
    await write('extra.txt', [1]);
    await expectLater(
        verify(descriptor()), throwsA(isA<FileSystemException>()));
  });
  test('root MP4 permits unrelated empty directory', () async {
    await write('clip.mp4', bytes);
    final extra =
        await Directory(p.join(workspace.payloadDirectory.path, 'unexpected'))
            .create();
    expect((await verify(descriptor())).verifiedBytes, bytes.length);
    expect(await extra.exists(), isTrue);
  });
  for (final path in [
    '../clip.mp4',
    '/clip.mp4',
    r'..\clip.mp4',
    'a//clip.mp4',
    'a/./clip.mp4',
    'C:/clip.mp4',
    'a./clip.mp4'
  ]) {
    test('rejects unsafe descriptor path $path', () async {
      await expectLater(verify(descriptor(path: path)), throwsFormatException);
    });
  }
  test('file in place of expected directory rejected', () async {
    await write('deep', [1]);
    await expectLater(verify(descriptor(path: 'deep/clip.mp4')),
        throwsA(isA<FileSystemException>()));
  });
  test('directory in place of MP4 rejected', () async {
    final file =
        await Directory(p.join(workspace.payloadDirectory.path, 'clip.mp4'))
            .create();
    await expectLater(
        verify(descriptor()), throwsA(isA<FileSystemException>()));
    expect(await file.exists(), isTrue);
  });
  Future<bool> link(String path, String target) async {
    try {
      await Link(path).create(target);
      return true;
    } on FileSystemException catch (e) {
      markTestSkipped('Symlinks unavailable: $e');
      return false;
    }
  }

  test('external file link rejected without reading target', () async {
    if (!await link(p.join(workspace.payloadDirectory.path, 'clip.mp4'),
        sentinels.first.path)) {
      return;
    }
    await expectLater(
        verify(descriptor()), throwsA(isA<FileSystemException>()));
  });
  test('external directory link rejected without traversing target', () async {
    if (!await link(p.join(workspace.payloadDirectory.path, 'deep'),
        p.join(root.path, 'modules'))) {
      return;
    }
    await expectLater(verify(descriptor(path: 'deep/clip.mp4')),
        throwsA(isA<FileSystemException>()));
  });
  test('nested MP4 permits unrelated empty branches', () async {
    await write('deep/clip.mp4', bytes);
    await Directory(p.join(workspace.payloadDirectory.path, 'deep', 'extra'))
        .create();
    await Directory(p.join(workspace.payloadDirectory.path, 'other', 'empty'))
        .create(recursive: true);
    expect((await verify(descriptor(path: 'deep/clip.mp4'))).relativePath,
        'deep/clip.mp4');
  });
  test('root MP4 permits multiple unrelated empty directories', () async {
    await write('clip.mp4', bytes);
    for (final name in ['first', 'second', 'third']) {
      await Directory(p.join(workspace.payloadDirectory.path, name)).create();
    }
    expect((await verify(descriptor())).verifiedBytes, bytes.length);
  });
  test('empty directory tree at maximum depth accepted', () async {
    await write('clip.mp4', bytes);
    final deepest = Directory(p.joinAll(
        [workspace.payloadDirectory.path, ...List.generate(10, (i) => 'd$i')]));
    await deepest.create(recursive: true);
    await verify(descriptor());
    expect(await deepest.exists(), isTrue);
  });
  test('excessive empty directory depth rejected', () async {
    await write('clip.mp4', bytes);
    await Directory(p.joinAll([
      workspace.payloadDirectory.path,
      ...List.generate(11, (i) => 'd$i')
    ])).create(recursive: true);
    await expectLater(verify(descriptor()), throwsFormatException);
  });
  test('actual entry count includes directories and expected MP4', () async {
    await write('clip.mp4', bytes);
    await Directory(p.join(workspace.payloadDirectory.path, 'first')).create();
    await verify(descriptor(), limits: const AnimationZipLimits(maxEntries: 2));
    await Directory(p.join(workspace.payloadDirectory.path, 'second')).create();
    await expectLater(
        verify(descriptor(), limits: const AnimationZipLimits(maxEntries: 2)),
        throwsFormatException);
  });
  test('regular file inside otherwise permitted branch rejected', () async {
    await write('clip.mp4', bytes);
    await write('empty/branch/extra.txt', [1, 2, 3]);
    await expectLater(
        verify(descriptor()), throwsA(isA<FileSystemException>()));
  });
  test('link inside permitted branch rejected and target preserved', () async {
    await write('clip.mp4', bytes);
    final branch =
        await Directory(p.join(workspace.payloadDirectory.path, 'empty'))
            .create();
    if (!await link(p.join(branch.path, 'external'), sentinels.first.path)) {
      return;
    }
    await expectLater(
        verify(descriptor()), throwsA(isA<FileSystemException>()));
    expect(await sentinels.first.readAsString(), 'preserve');
  });
  test('nonprivate payload rejected without inspecting installed content',
      () async {
    await expectLater(
        const AnimationStagedMp4VerificationService().verify(
            descriptor: descriptor(),
            payloadDirectory: Directory(p.join(root.path, 'modules'))),
        throwsArgumentError);
  });
  test('fixed chunk reads on larger file, handle released', () async {
    final content = List<int>.generate(256 * 1024 + 13, (i) => i % 251);
    final file = await write('clip.mp4', content);
    final reads = <int>[];
    final outer = Zone.current;
    final result = await IOOverrides.runZoned(
        () => verify(descriptor(size: content.length, crc: getCrc32(content)),
            chunk: 1024),
        fseGetType: (path, followLinks) => outer
            .run(() => FileSystemEntity.type(path, followLinks: followLinks)),
        createDirectory: (path) => outer.run(() => Directory(path)),
        createFile: (path) {
          expect(path, file.path, reason: 'Only the staged MP4 may be opened');
          return _ReadTrackingFile(file, reads);
        });
    expect(result.verifiedBytes, content.length);
    expect(reads.length, greaterThan(256));
    expect(reads.every((count) => count == 1024), isTrue);
    // Rename requires closing the read handle on Windows as well.
    final renamed = await file.rename('${file.path}.checked');
    staged.remove(file.path);
    staged[renamed.path] = content;
  });
  test('invalid sizes CRC and chunk limits rejected', () async {
    for (final d in [
      descriptor(size: 0),
      descriptor(size: -1),
      descriptor(crc: -1),
      descriptor(crc: 0x100000000)
    ]) {
      await expectLater(verify(d), throwsFormatException);
    }
    for (final chunk in [0, -1, 1024 * 1024 + 1]) {
      await expectLater(
          verify(descriptor(), chunk: chunk), throwsArgumentError);
    }
  });
}
