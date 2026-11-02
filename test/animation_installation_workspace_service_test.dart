import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/animation_installation_workspace_service.dart';

void main() {
  final service = AnimationInstallationWorkspaceService();
  late Directory root;
  late List<File> sentinels;
  Future<File> write(String path, String bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    return file.writeAsString(bytes);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('healthmap-workspace-');
    sentinels = [];
    for (final relative in [
      'unrelated.keep',
      'modules/animations/42/old.mp4',
      'modules/course/index.html',
      'packages/old/story.html',
    ]) {
      sentinels.add(await write(p.join(root.path, relative), 'preserve'));
    }
  });
  tearDown(() async {
    for (final sentinel in sentinels) {
      expect(await sentinel.readAsString(), 'preserve');
    }
    final path = p.normalize(root.absolute.path);
    expect(p.isWithin(Directory.systemTemp.absolute.path, path), isTrue);
    expect(p.basename(path), startsWith('healthmap-workspace-'));
    await root.delete(recursive: true);
  });

  test('creates contained private paths without touching installations',
      () async {
    final workspace = await service.create(root: root, animationId: 42);
    expect(workspace.animationId, 42);
    expect(p.dirname(workspace.directory.path),
        p.join(root.path, 'animation_installations'));
    expect(p.basename(workspace.directory.path), startsWith('42-'));
    expect(workspace.downloadFile.path,
        p.join(workspace.directory.path, 'download.zip'));
    expect(await workspace.downloadFile.exists(), isFalse);
    expect(await workspace.payloadDirectory.exists(), isTrue);
    expect(p.isWithin(workspace.directory.path, workspace.downloadFile.path),
        isTrue);
    for (final excluded in ['modules', 'packages']) {
      expect(p.isWithin(p.join(root.path, excluded), workspace.directory.path),
          isFalse);
    }
    await workspace.cleanup();
    expect(await workspace.directory.exists(), isFalse);
  });

  test('each same-ID attempt is unique and cleanup is isolated', () async {
    final first = await service.create(root: root, animationId: 42);
    final firstVideo =
        await write(p.join(first.payloadDirectory.path, 'clip.mp4'), 'first');
    final second = await service.create(root: root, animationId: 42);
    expect(second.directory.path, isNot(first.directory.path));
    await second.cleanup();
    expect(await firstVideo.readAsString(), 'first');
    await first.cleanup();
  });

  test('existing candidate prefix and attempt content are never reused',
      () async {
    final existing = await write(
        p.join(root.path, 'animation_installations', '42-', 'sentinel'),
        'existing');
    final workspace = await service.create(root: root, animationId: 42);
    expect(workspace.directory.path, isNot(existing.parent.path));
    await workspace.cleanup();
    expect(await existing.readAsString(), 'existing');
  });

  test('rejects invalid database IDs without creating workspace parent',
      () async {
    for (final id in [0, -1, -42]) {
      await expectLater(
          service.create(root: root, animationId: id), throwsArgumentError);
    }
    expect(
        await Directory(p.join(root.path, 'animation_installations')).exists(),
        isFalse);
  });

  test('accepts positive IDs', () async {
    for (final id in [1, 2147483647]) {
      final workspace = await service.create(root: root, animationId: id);
      await workspace.cleanup();
    }
  });

  for (final outcome in ['completed', 'failed']) {
    test('cleanup removes only own files after $outcome attempt', () async {
      final workspace = await service.create(root: root, animationId: 7);
      await workspace.downloadFile.writeAsString('zip or partial download');
      await write(
          p.join(workspace.payloadDirectory.path, 'deep', 'clip.mp4'), outcome);
      await workspace.cleanup();
      expect(await workspace.directory.exists(), isFalse);
      expect(
          await Directory(p.join(root.path, 'modules', 'animations', '7'))
              .exists(),
          isFalse);
    });
  }

  test('repeated cleanup does not touch a replacement at the old path',
      () async {
    final workspace = await service.create(root: root, animationId: 42);
    await workspace.cleanup();
    await workspace.cleanup();
    final replacement =
        await write(p.join(workspace.directory.path, 'new.keep'), 'new');
    await workspace.cleanup();
    expect(await replacement.readAsString(), 'new');
  });

  test('unexpected workspace parent file is preserved', () async {
    final file = await File(p.join(root.path, 'animation_installations'))
        .writeAsString('existing');
    await expectLater(service.create(root: root, animationId: 1),
        throwsA(isA<FileSystemException>()));
    expect(await file.readAsString(), 'existing');
  });

  test('missing canonical root is not created', () async {
    final absent = Directory(p.join(root.path, 'absent'));
    await expectLater(service.create(root: absent, animationId: 1),
        throwsA(isA<FileSystemException>()));
    expect(await absent.exists(), isFalse);
  });

  test('lost ownership refuses cleanup and preserves payload', () async {
    final workspace = await service.create(root: root, animationId: 42);
    final video = await write(
        p.join(workspace.payloadDirectory.path, 'clip.mp4'), 'keep');
    await File(p.join(workspace.directory.path, '.workspace-owner'))
        .writeAsString('different owner');
    await expectLater(workspace.cleanup(), throwsA(isA<FileSystemException>()));
    expect(await video.readAsString(), 'keep');
  });

  test('unknown top-level content refuses all cleanup', () async {
    final workspace = await service.create(root: root, animationId: 42);
    await workspace.downloadFile.writeAsString('keep zip');
    final unknown =
        await write(p.join(workspace.directory.path, 'unrelated.keep'), 'keep');
    await expectLater(workspace.cleanup(), throwsA(isA<FileSystemException>()));
    expect(await workspace.downloadFile.readAsString(), 'keep zip');
    expect(await unknown.readAsString(), 'keep');
  });

  Future<bool> link(String path, String target) async {
    try {
      await Link(path).create(target);
      return true;
    } on FileSystemException catch (error) {
      markTestSkipped('Symlinks unavailable: $error');
      return false;
    }
  }

  test('missing marker refuses cleanup and preserves attempt files', () async {
    final workspace = await service.create(root: root, animationId: 42);
    await workspace.downloadFile.writeAsString('keep zip');
    final video = await write(
        p.join(workspace.payloadDirectory.path, 'clip.mp4'), 'keep video');
    await File(p.join(workspace.directory.path, '.workspace-owner')).delete();
    await expectLater(workspace.cleanup(), throwsA(isA<FileSystemException>()));
    expect(await workspace.downloadFile.readAsString(), 'keep zip');
    expect(await video.readAsString(), 'keep video');
  });

  test('linked marker refuses cleanup and preserves external target', () async {
    final workspace = await service.create(root: root, animationId: 42);
    final marker = File(p.join(workspace.directory.path, '.workspace-owner'));
    final token = await marker.readAsString();
    // Even a link to an exact token copy must not establish ownership.
    final outside = await write(p.join(root.path, 'external-token'), token);
    await workspace.downloadFile.writeAsString('keep zip');
    await marker.delete();
    if (!await link(marker.path, outside.path)) return;
    await expectLater(workspace.cleanup(), throwsA(isA<FileSystemException>()));
    expect(await outside.readAsString(), token);
    expect(await workspace.downloadFile.readAsString(), 'keep zip');
  });

  test('linked attempt refuses cleanup without following its target', () async {
    final workspace = await service.create(root: root, animationId: 42);
    await workspace.downloadFile.writeAsString('original zip');
    final attemptPath = workspace.directory.path;
    final original = await workspace.directory.rename('$attemptPath.saved');
    if (!await link(attemptPath, original.path)) return;
    await expectLater(workspace.cleanup(), throwsA(isA<FileSystemException>()));
    expect(await File(p.join(original.path, 'download.zip')).readAsString(),
        'original zip');
    expect(await Directory(p.join(original.path, 'payload')).exists(), isTrue);
    expect(
        await File(p.join(original.path, '.workspace-owner')).exists(), isTrue);
  });

  test('missing download ZIP does not prevent owned payload cleanup', () async {
    final workspace = await service.create(root: root, animationId: 42);
    await workspace.downloadFile.writeAsString('partial zip');
    await workspace.downloadFile.delete();
    await write(p.join(workspace.payloadDirectory.path, 'clip.mp4'), 'partial');
    await workspace.cleanup();
    expect(await workspace.directory.exists(), isFalse);
  });

  test('missing payload does not prevent owned ZIP cleanup', () async {
    final workspace = await service.create(root: root, animationId: 42);
    await workspace.downloadFile.writeAsString('partial zip');
    await workspace.payloadDirectory.delete();
    await workspace.cleanup();
    expect(await workspace.directory.exists(), isFalse);
  });

  test('repeated successful cleanup is an idempotent no-op', () async {
    final workspace = await service.create(root: root, animationId: 42);
    await workspace.cleanup();
    await workspace.cleanup();
    await workspace.cleanup();
    expect(await workspace.directory.exists(), isFalse);
  });

  test('concurrent cleanup rejects the second call deterministically',
      () async {
    final workspace = await service.create(root: root, animationId: 42);
    await workspace.downloadFile.writeAsString('zip');
    await write(
        p.join(workspace.payloadDirectory.path, 'deep', 'clip.mp4'), 'video');
    // cleanup sets its in-progress flag synchronously, before its first await.
    final first = workspace.cleanup();
    final second = workspace.cleanup();
    await expectLater(
        second,
        throwsA(isA<StateError>().having((error) => error.message, 'message',
            'Workspace cleanup already in progress')));
    await first;
    expect(await workspace.directory.exists(), isFalse);
    await workspace.cleanup();
    for (final sentinel in sentinels) {
      expect(await sentinel.readAsString(), 'preserve');
    }
  });

  test('all nested payload files are attempt-owned by caller contract',
      () async {
    final workspace = await service.create(root: root, animationId: 42);
    final extra = await write(
        p.join(workspace.payloadDirectory.path, 'unexpected', 'notes.txt'),
        'disposable attempt fixture');
    await write(p.join(workspace.payloadDirectory.path, 'clip.mp4'), 'video');
    // Cleanup is not ZIP contract validation. Ordinary nested files are owned
    // by this attempt regardless of name; callers must never place unrelated
    // content inside payload/. External sentinels remain outside that contract.
    await workspace.cleanup();
    expect(await extra.exists(), isFalse);
    expect(await workspace.directory.exists(), isFalse);
  });

  test('copied marker permits replacement: documented ownership limitation',
      () async {
    final workspace = await service.create(root: root, animationId: 42);
    final markerPath = p.join(workspace.directory.path, '.workspace-owner');
    final token = await File(markerPath).readAsString();
    await workspace.downloadFile.writeAsString('original attempt zip');
    final original =
        await workspace.directory.rename('${workspace.directory.path}.saved');
    // Replacement content is deliberately disposable, NOT an unrelated
    // sentinel. Demonstrate that token equality cannot prove directory identity.
    await write(markerPath, token);
    await write(p.join(workspace.payloadDirectory.path, 'replacement.mp4'),
        'disposable replacement');
    await workspace.cleanup();
    expect(await workspace.directory.exists(), isFalse);
    expect(await File(p.join(original.path, 'download.zip')).readAsString(),
        'original attempt zip');
    expect(await File(p.join(original.path, '.workspace-owner')).readAsString(),
        token);
    for (final sentinel in sentinels) {
      expect(await sentinel.readAsString(), 'preserve');
    }
  });

  test('symlinked workspace parent rejected without touching target', () async {
    final target = await Directory(p.join(root.path, 'outside')).create();
    if (!await link(
        p.join(root.path, 'animation_installations'), target.path)) {
      return;
    }
    await expectLater(service.create(root: root, animationId: 1),
        throwsA(isA<FileSystemException>()));
    expect(await target.list().toList(), isEmpty);
  });

  test('symlinked canonical root rejected', () async {
    final alias = p.join(root.path, 'alias');
    if (!await link(alias, root.path)) return;
    await expectLater(service.create(root: Directory(alias), animationId: 1),
        throwsA(isA<FileSystemException>()));
  });

  test('payload symlink refuses cleanup before deleting ordinary files',
      () async {
    final workspace = await service.create(root: root, animationId: 42);
    await workspace.downloadFile.writeAsString('keep zip');
    final outside =
        await write(p.join(root.path, 'outside', 'keep'), 'outside');
    if (!await link(p.join(workspace.payloadDirectory.path, 'escape'),
        outside.parent.path)) {
      return;
    }
    await expectLater(workspace.cleanup(), throwsA(isA<FileSystemException>()));
    expect(await outside.readAsString(), 'outside');
    expect(await workspace.downloadFile.readAsString(), 'keep zip');
  });

  test('symlink substituted for payload directory refuses cleanup', () async {
    final workspace = await service.create(root: root, animationId: 42);
    await workspace.payloadDirectory.delete();
    final target = await Directory(p.join(root.path, 'outside')).create();
    if (!await link(workspace.payloadDirectory.path, target.path)) return;
    await expectLater(workspace.cleanup(), throwsA(isA<FileSystemException>()));
    expect(await target.list().toList(), isEmpty);
  });
}
