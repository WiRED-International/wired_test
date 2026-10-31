import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/animation_archive_extraction_service.dart';

void main() {
  late Directory root;
  late Directory modules;
  late File sentinel;
  late File outsideSentinel;
  final service = AnimationArchiveExtractionService();
  const sentinelBytes = <int>[1, 17, 128, 255];
  const videoBytes = <int>[0, 0, 0, 24, 102, 116, 121, 112, 255, 128];

  Future<File> zipFixture(Map<String, List<int>> entries) async {
    final archive = Archive();
    for (final entry in entries.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    // Construct archives directly: unsafe entries never become fixture paths.
    return File(p.join(root.path, 'fixture.zip'))
        .writeAsBytes(ZipEncoder().encode(archive), flush: true);
  }

  Future<void> expectSentinelsUnchanged() async {
    expect(await sentinel.readAsBytes(), orderedEquals(sentinelBytes));
    expect(await outsideSentinel.readAsBytes(), orderedEquals(sentinelBytes));
  }

  setUp(() async {
    root =
        await Directory.systemTemp.createTemp('healthmap-animation-extract-');
    modules = await Directory(p.join(root.path, 'modules')).create();
    sentinel = await File(p.join(modules.path, 'unrelated.keep'))
        .writeAsBytes(sentinelBytes, flush: true);
    outsideSentinel = await File(p.join(root.path, 'outside-sentinel.bin'))
        .writeAsBytes(sentinelBytes, flush: true);
  });

  tearDown(() async {
    try {
      await expectSentinelsUnchanged();
    } finally {
      final target = p.normalize(root.absolute.path);
      expect(
          p.isWithin(p.normalize(Directory.systemTemp.absolute.path), target),
          isTrue);
      expect(p.basename(target), startsWith('healthmap-animation-extract-'));
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('extracts exact top-level MP4 bytes and reports progress', () async {
    final zip = await zipFixture({'animation.mp4': videoBytes});
    final progress = <double>[];

    await service.extractArchive(
      zipPath: zip.path,
      outputDir: modules.path,
      onProgress: progress.add,
    );

    expect(await File(p.join(modules.path, 'animation.mp4')).readAsBytes(),
        orderedEquals(videoBytes));
    expect(progress, [1.0]);
    expect(await zip.exists(), isTrue,
        reason: 'ZIP cleanup remains the download caller\'s responsibility');
    await expectSentinelsUnchanged();
  });

  test('preserves deeply nested MP4 paths and exact resource bytes', () async {
    const nestedPath = 'animations/topic/group/media/animation.mp4';
    const resourcePath = 'animations/topic/group/readme.txt';
    const resourceBytes = <int>[65, 66, 67, 10];
    final zip = await zipFixture({
      nestedPath: videoBytes,
      resourcePath: resourceBytes,
    });
    final progress = <double>[];

    await service.extractArchive(
      zipPath: zip.path,
      outputDir: modules.path,
      onProgress: progress.add,
    );

    expect(await File(p.join(modules.path, nestedPath)).readAsBytes(),
        orderedEquals(videoBytes));
    expect(await File(p.join(modules.path, resourcePath)).readAsBytes(),
        orderedEquals(resourceBytes));
    expect(await File(p.join(modules.path, 'animation.mp4')).exists(), isFalse);
    expect(progress, [0.5, 1.0]);
    await expectSentinelsUnchanged();
  });

  test('rejects unsafe archive path before writing any extracted entry',
      () async {
    final zip = await zipFixture({
      'otherwise-valid.mp4': videoBytes,
      '../outside-sentinel.bin': <int>[99, 99],
    });
    final progress = <double>[];

    await expectLater(
      service.extractArchive(
        zipPath: zip.path,
        outputDir: modules.path,
        onProgress: progress.add,
      ),
      throwsA(isA<FormatException>().having(
          (error) => error.message, 'message', 'Unsafe archive entry.')),
    );

    expect(await File(p.join(modules.path, 'otherwise-valid.mp4')).exists(),
        isFalse);
    expect(progress, isEmpty);
    await expectSentinelsUnchanged();
  });
}
