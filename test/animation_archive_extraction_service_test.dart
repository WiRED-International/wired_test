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

  Future<File> existingFile(String relativePath, List<int> bytes) async {
    final target = p.normalize(p.join(modules.path, relativePath));
    expect(p.isWithin(modules.path, target), isTrue);
    final file = File(target);
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<Map<String, Object>> moduleSnapshot() async {
    final snapshot = <String, Object>{};
    await for (final entry in modules.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entry.path, from: modules.path);
      if (entry is File) {
        snapshot[relative] = await entry.readAsBytes();
      } else if (entry is Directory) {
        snapshot[relative] = 'directory';
      } else {
        fail('Unexpected fixture entity: ${entry.path}');
      }
    }
    return snapshot;
  }

  Future<void> expectRejectedWithoutChanges(File zip) async {
    final before = await moduleSnapshot();
    Object? error;
    try {
      await service.extractArchive(zipPath: zip.path, outputDir: modules.path);
    } catch (caught) {
      error = caught;
    }
    // Check rejection and the entire tree together, even if extraction succeeds
    // unexpectedly. This detects overwritten bytes AND newly created entries.
    expect({
      'rejected': error != null,
      'modules': await moduleSnapshot(),
    }, {
      'rejected': true,
      'modules': before,
    }, reason: 'Reject the whole archive before changing final storage');
    await expectSentinelsUnchanged();
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

  group('Collision regressions (expected to fail before overwrite protection)', () {
    test('rejects an existing standalone MP4 without replacing its bytes',
        () async {
      await existingFile('animation.mp4', <int>[10, 20, 30, 40]);
      final zip = await zipFixture({'animation.mp4': videoBytes});

      await expectRejectedWithoutChanges(zip);
    });

    test('rejects a compiler-resource collision and preserves the entire module',
        () async {
      await existingFile('course/index.html', '<html>Course</html>'.codeUnits);
      await existingFile('course/module.json', '{"module_id":"1565"}'.codeUnits);
      await existingFile('course/assets/lesson.mp4', <int>[10, 20, 30, 40]);
      await existingFile('course/assets/other.bin', <int>[50, 60, 70]);
      final zip = await zipFixture({'course/assets/lesson.mp4': videoBytes});

      await expectRejectedWithoutChanges(zip);
    });

    test('rejects a late collision before creating any earlier archive entries',
        () async {
      await existingFile('existing.mp4', <int>[10, 20, 30, 40]);
      final zip = await zipFixture({
        'new/deep/animation.mp4': videoBytes,
        'new/readme.txt': <int>[65, 66, 67],
        'existing.mp4': videoBytes,
      });
      final decoded = ZipDecoder().decodeBytes(await zip.readAsBytes());
      expect(decoded.map((entry) => entry.name).toList(), [
        'new/deep/animation.mp4',
        'new/readme.txt',
        'existing.mp4',
      ], reason: 'The collision must genuinely occur after the new entries');

      await expectRejectedWithoutChanges(zip);
    });

    test('rejects distinct ZIP entries with the same normalized destination',
        () async {
      const slashName = 'media/animation.mp4';
      const backslashName = r'media\animation.mp4';
      final zip = await zipFixture({
        slashName: videoBytes,
        backslashName: <int>[90, 91, 92],
      });
      final decoded = ZipDecoder().decodeBytes(await zip.readAsBytes());
      final names = decoded.map((entry) => entry.name).toList();
      expect(names, [slashName, backslashName],
          reason: 'Fixture must retain two distinct entries after ZIP decoding');
      expect(names.toSet(), hasLength(2));
      expect(decoded.first.content, orderedEquals(videoBytes));
      expect(decoded.last.content, orderedEquals(<int>[90, 91, 92]));
      expect(
          names.map((name) => p.normalize(name.replaceAll('\\', '/'))).toSet(),
          hasLength(1),
          reason: 'Both decoded entries must address the same output file');

      await expectRejectedWithoutChanges(zip);
    });

    test('reinstallation refuses replacement of an already extracted animation',
        () async {
      const animationPath = 'animations/topic/group/animation.mp4';
      final firstZip = await zipFixture({animationPath: videoBytes});
      await service.extractArchive(
          zipPath: firstZip.path, outputDir: modules.path);
      expect(await File(p.join(modules.path, animationPath)).readAsBytes(),
          orderedEquals(videoBytes));

      final retryZip = await zipFixture({animationPath: <int>[90, 91, 92]});
      await expectRejectedWithoutChanges(retryZip);
    });
  });
}
