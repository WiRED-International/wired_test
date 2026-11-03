import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/animation_installation_coordinator.dart';
import 'package:wired_test/services/animation_installation_inspection_service.dart';
import 'package:wired_test/services/animation_library_removal_service.dart';
import 'package:wired_test/services/animation_preparation_service.dart';
import 'package:wired_test/services/animation_private_download_service.dart';

class _Transport implements AnimationDownloadTransport {
  @override
  Future<AnimationDownloadResponse> open(Uri uri) async {
    final bytes = ZipEncoder().encode(Archive()
      ..addFile(ArchiveFile('topic.backup/nested/clip.MP4', 3, [1, 2, 3])));
    return AnimationDownloadResponse(
        statusCode: 200,
        contentLength: bytes.length,
        body: Stream.value(bytes));
  }

  @override
  void close() {}
}

void main() {
  late Directory root;
  late AnimationInstallationCoordinator coordinator;
  late AnimationLibraryRemovalService removal;
  File file(String relative) => File(p.join(root.path, relative));
  Future<File> write(String relative, [String content = 'keep']) async {
    final result = file(relative);
    await result.parent.create(recursive: true);
    return result.writeAsString(content);
  }

  const selected = 'modules/animations/42/topic/nested/clip.MP4';
  setUp(() async {
    root = await Directory.systemTemp.createTemp('animation-removal-');
    coordinator = AnimationInstallationCoordinator();
    removal = AnimationLibraryRemovalService(coordinator: coordinator);
    await write('sentinel.keep');
  });
  tearDown(() async {
    expect(await file('sentinel.keep').readAsString(), 'keep');
    expect(p.isWithin(Directory.systemTemp.absolute.path, root.path), isTrue);
    expect(p.basename(root.path), startsWith('animation-removal-'));
    await root.delete(recursive: true);
  });

  test(
      'identity is the immediate canonical numeric directory, never the filename',
      () {
    for (final path in [
      selected,
      'modules/animations/42/topic.backup/999.mp4',
      'modules/animations/42/clip.mp4'
    ]) {
      expect(
          AnimationLibraryRemovalService.animationIdFor(
              root: root, file: file(path)),
          42);
    }
    for (final path in [
      'modules/42/clip.mp4',
      'modules/animations/topic/42/clip.mp4',
      'modules/animations/0/clip.mp4',
      'modules/animations/-1/clip.mp4',
      'modules/animations/042/clip.mp4',
      'modules/animations/42.backup/clip.mp4',
      'modules/animations/42/story.html',
      'packages/42/clip.mp4'
    ]) {
      expect(
          AnimationLibraryRemovalService.animationIdFor(
              root: root, file: file(path)),
          isNull);
    }
  });

  test('prunes nested and sibling empty directories only within the ID',
      () async {
    final video = await write(selected);
    await Directory(p.join(root.path, 'modules/animations/42/empty/also-empty'))
        .create(recursive: true);
    for (final path in [
      'modules/animations/43/other.mp4',
      'modules/legacy.mp4',
      'modules/compiler/index.html',
      'modules/storyline/story.html',
      'modules/99.backup/recovery.mp4',
      'packages/old/story.html'
    ]) {
      await write(path);
    }
    expect(await removal.remove(root: root, file: video), isTrue);
    expect(await Directory(p.join(root.path, 'modules/animations/42')).exists(),
        isFalse);
    expect(await Directory(p.join(root.path, 'modules/animations')).exists(),
        isTrue);
    expect(
        (await AnimationInstallationInspectionService()
                .inspectInstallation(root: root, animationId: 42))
            .status,
        AnimationInstallationStatus.notInstalled);
    for (final path in [
      'modules/animations/43/other.mp4',
      'modules/legacy.mp4',
      'modules/compiler/index.html',
      'modules/storyline/story.html',
      'modules/99.backup/recovery.mp4',
      'packages/old/story.html'
    ]) {
      expect(await file(path).readAsString(), 'keep');
    }
  });

  test('published animation can be removed and actually reinstalled', () async {
    final installer = AnimationPreparationService(
        coordinator: coordinator,
        downloader:
            AnimationPrivateDownloadService(transportFactory: _Transport.new));
    Future<PublishedAnimation> install() => installer.withPrepared(
        animationId: 42,
        canonicalRoot: root,
        downloadUri: Uri.parse('https://example.invalid/animation.zip'),
        use: (prepared) async => await prepared.publish());
    await install();
    final video = file('modules/animations/42/topic.backup/nested/clip.MP4');
    expect(await video.readAsBytes(), [1, 2, 3]);
    await removal.remove(root: root, file: video);
    expect(
        (await AnimationInstallationInspectionService()
                .inspectInstallation(root: root, animationId: 42))
            .status,
        AnimationInstallationStatus.notInstalled);
    await install();
    expect(await video.readAsBytes(), [1, 2, 3]);
  });

  test(
      'failure before deletion never reports partial removal or starts cleanup',
      () async {
    final video = await write(selected);
    await write('modules/animations/42/index.html');
    var cleanupStarted = false;
    removal = AnimationLibraryRemovalService(
      coordinator: coordinator,
      beforeDirectoryCleanup: () async {
        cleanupStarted = true;
      },
    );
    await expectLater(
        removal.remove(root: root, file: video),
        throwsA(allOf(isA<FileSystemException>(),
            isNot(isA<AnimationLibraryPartialRemovalException>()))));
    expect(cleanupStarted, isFalse);
    expect(await video.readAsString(), 'keep');
    await coordinator.run(animationId: 42, operation: () async {});
  });

  test('cleanup failure retains deleted status, original error and stack',
      () async {
    final video = await write(selected);
    final original = FileSystemException('injected directory cleanup failure');
    final originalStack = StackTrace.current;
    final entered = Completer<void>(), release = Completer<void>();
    removal = AnimationLibraryRemovalService(
      coordinator: coordinator,
      beforeDirectoryCleanup: () async {
        entered.complete();
        await release.future;
        Error.throwWithStackTrace(original, originalStack);
      },
    );
    final operation = removal.remove(root: root, file: video);
    final checked = expectLater(
        operation,
        throwsA(isA<AnimationLibraryPartialRemovalException>()
            .having((e) => e.videoDeleted, 'MP4 deleted', isTrue)
            .having((e) => e.animationId, 'backend ID', 42)
            .having((e) => e.deletedVideoPath, 'deleted path',
                p.normalize(video.path))
            .having((e) => e.cleanupError, 'original error', same(original))
            .having((e) => e.cleanupStack.toString(), 'original stack',
                originalStack.toString())));
    try {
      await entered.future;
      expect(await video.exists(), isFalse);
      expect(await video.parent.exists(), isTrue);
      await expectLater(
          coordinator.run(animationId: 42, operation: () async {}),
          throwsA(isA<AnimationInstallationInProgressException>()));
    } finally {
      release.complete();
      await checked;
    }
    expect(await Directory(p.join(root.path, 'modules/animations/42')).exists(),
        isTrue);
    await coordinator.run(animationId: 42, operation: () async {});
  });

  test('nonempty directories, unrelated files and other MP4s survive',
      () async {
    final video = await write(selected);
    await write('modules/animations/42/topic/nested/unrelated.keep');
    await write('modules/animations/42/other/other.mp4');
    expect(await removal.remove(root: root, file: video), isFalse);
    expect(await video.exists(), isFalse);
    expect(
        (await AnimationInstallationInspectionService()
                .inspectInstallation(root: root, animationId: 42))
            .status,
        AnimationInstallationStatus.conflict);
    expect(await video.parent.exists(), isTrue);
    expect(
        await file('modules/animations/42/topic/nested/unrelated.keep')
            .readAsString(),
        'keep');
    expect(await file('modules/animations/42/other/other.mp4').readAsString(),
        'keep');
  });

  test('an active installer prevents deletion and reservation is reusable',
      () async {
    final video = await write(selected);
    final release = Completer<void>();
    final installation =
        coordinator.run(animationId: 42, operation: () => release.future);
    try {
      await expectLater(removal.remove(root: root, file: video),
          throwsA(isA<AnimationInstallationInProgressException>()));
      expect(await video.readAsString(), 'keep');
    } finally {
      release.complete();
      await installation;
    }
    await removal.remove(root: root, file: video);
    expect(await video.exists(), isFalse);
  });

  for (final marker in ['index.html', 'story.html', 'INDEX.HTML']) {
    test('$marker ownership marker refuses removal before any deletion',
        () async {
      final video = await write(selected);
      await write('modules/animations/42/sibling/$marker');
      await expectLater(removal.remove(root: root, file: video),
          throwsA(isA<FileSystemException>()));
      expect(await video.readAsString(), 'keep');
      expect(await file('modules/animations/42/sibling/$marker').readAsString(),
          'keep');
      await coordinator.run(animationId: 42, operation: () async {});
    });
  }

  test('traversal and paths outside the numeric namespace are rejected',
      () async {
    final video = await write(selected);
    final unsafe = File(
        '${root.path}/modules/animations/42/topic/../topic/nested/clip.MP4');
    for (final candidate in [
      unsafe,
      file('sentinel.keep'),
      file('modules/animations/42/../../legacy.mp4')
    ]) {
      await expectLater(removal.remove(root: root, file: candidate),
          throwsA(isA<FileSystemException>()));
    }
    expect(await video.readAsString(), 'keep');
  });

  for (final relative in [
    '',
    'modules',
    'modules/animations',
    'modules/animations/42',
    'modules/animations/42/topic',
    selected
  ]) {
    test('rejects linked ${relative.isEmpty ? 'root' : relative}', () async {
      await write(selected);
      final path = relative.isEmpty ? root.path : file(relative).path;
      final savedPath =
          relative.isEmpty ? '${root.path}-saved' : '${path}_saved';
      final isFile = relative == selected;
      if (isFile) {
        await File(path).rename(savedPath);
      } else {
        await Directory(path).rename(savedPath);
      }
      var linked = false;
      try {
        try {
          await Link(path).create(savedPath);
          linked = true;
        } on FileSystemException catch (error) {
          markTestSkipped('Symlinks unavailable: $error');
          return;
        }
        await expectLater(removal.remove(root: root, file: file(selected)),
            throwsA(isA<FileSystemException>()));
        final savedVideo = isFile
            ? File(savedPath)
            : File(
                p.join(savedPath, p.relative(file(selected).path, from: path)));
        expect(await savedVideo.readAsString(), 'keep');
      } finally {
        if (linked) await Link(path).delete();
        if (isFile) {
          await File(savedPath).rename(path);
        } else {
          await Directory(savedPath).rename(path);
        }
      }
    });
  }

  test('a sibling symlink preserves selected video and external target',
      () async {
    final video = await write(selected);
    final external = await write('external/keep.mp4');
    final link = Link(file('modules/animations/42/linked.mp4').path);
    try {
      await link.create(external.path);
    } on FileSystemException catch (error) {
      markTestSkipped('Symlinks unavailable: $error');
      return;
    }
    try {
      await expectLater(removal.remove(root: root, file: video),
          throwsA(isA<FileSystemException>()));
      expect(await video.readAsString(), 'keep');
      expect(await external.readAsString(), 'keep');
    } finally {
      await link.delete();
    }
  });
}
