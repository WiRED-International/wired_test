import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/animation_installation_coordinator.dart';
import 'package:wired_test/services/animation_preparation_service.dart';
import 'package:wired_test/services/animation_private_download_service.dart';

class _Transport implements AnimationDownloadTransport {
  _Transport(this.bytes);
  final List<int> bytes;
  bool closed = false;
  @override
  Future<AnimationDownloadResponse> open(Uri uri) async =>
      AnimationDownloadResponse(
          statusCode: 200,
          contentLength: bytes.length,
          body: Stream.value(bytes));
  @override
  void close() => closed = true;
}

void main() {
  late Directory root;
  late AnimationInstallationCoordinator coordinator;
  late List<int> zip;
  late List<_Transport> transports;
  final bytes = List<int>.generate(4097, (i) => i % 251);
  final uri = Uri.parse('https://example.invalid/animation.zip');
  String getTarget() => p.join(root.path, 'modules', 'animations', '42');
  File targetFile([String path = 'nested/Original.MP4']) =>
      File(p.joinAll([getTarget(), ...path.split('/')]));
  Future<Directory> attempt() async =>
      (await Directory(p.join(root.path, 'animation_installations'))
              .list()
              .toList())
          .single as Directory;
  Future<List<FileSystemEntity>> attempts() =>
      Directory(p.join(root.path, 'animation_installations')).list().toList();
  AnimationPreparationService service({
    Future<void> Function(Directory, String)? rename,
  }) =>
      AnimationPreparationService(
          coordinator: coordinator,
          renamePayload: rename,
          downloader: AnimationPrivateDownloadService(transportFactory: () {
            final transport = _Transport(zip);
            transports.add(transport);
            return transport;
          }));
  Future<T> prepare<T>(
    AnimationPreparationService s,
    Future<T> Function(PreparedAnimation) use, {
    AnimationPreparationCancellation? cancellation,
    void Function(AnimationPreparationProgress)? progress,
  }) =>
      s.withPrepared(
          animationId: 42,
          canonicalRoot: root,
          downloadUri: uri,
          use: use,
          cancellation: cancellation,
          onProgress: progress);
  void fixture(String path, {bool stored = false}) {
    zip = ZipEncoder().encode(Archive()
      ..addFile(ArchiveFile(path, bytes.length, bytes)
        ..compression =
            stored ? CompressionType.none : CompressionType.deflate));
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('healthmap-publication-');
    coordinator = AnimationInstallationCoordinator();
    transports = [];
    fixture('nested/Original.MP4');
    for (final path in [
      'modules/storyline/story.html',
      'modules/compiler/index.html',
      'packages/old/story.html',
      'external/sentinel.keep'
    ]) {
      final file = File(p.join(root.path, path));
      await file.parent.create(recursive: true);
      await file.writeAsString('preserve');
    }
  });
  tearDown(() async {
    for (final path in [
      'modules/storyline/story.html',
      'modules/compiler/index.html',
      'packages/old/story.html',
      'external/sentinel.keep'
    ]) {
      expect(await File(p.join(root.path, path)).readAsString(), 'preserve');
    }
    for (final transport in transports) {
      expect(transport.closed, isTrue);
    }
    expect(p.isWithin(Directory.systemTemp.absolute.path, root.path), isTrue);
    expect(p.basename(root.path), startsWith('healthmap-publication-'));
    await root.delete(recursive: true);
  });

  for (final path in ['Original.MP4', 'deep/topic/Original.MP4']) {
    test('publishes complete payload preserving $path', () async {
      fixture(path, stored: path == 'Original.MP4');
      final result = await prepare(service(), (prepared) => prepared.publish());
      expect(result.animationId, 42);
      expect(result.relativePath, path);
      expect(result.verifiedBytes, bytes.length);
      expect(await targetFile(path).readAsBytes(), bytes);
      expect(await attempts(), isEmpty);
    });
  }
  for (final kind in ['empty', 'partial', 'installed', 'file']) {
    test('rejects $kind destination introduced after preparation', () async {
      await expectLater(
          prepare(service(), (prepared) async {
            final target = getTarget();
            await Directory(p.dirname(target)).create(recursive: true);
            if (kind == 'file') {
              await File(target).writeAsString('existing');
            } else {
              await Directory(target).create();
              if (kind != 'empty') {
                await File(p.join(
                        target, kind == 'partial' ? 'part.tmp' : 'old.mp4'))
                    .writeAsString('existing');
              }
            }
            return prepared.publish();
          }),
          throwsA(isA<FileSystemException>()));
      if (kind == 'file') {
        expect(await File(getTarget()).readAsString(), 'existing');
      } else {
        final entries = await Directory(getTarget()).list().toList();
        expect(entries.length, kind == 'empty' ? 0 : 1);
        if (entries.isNotEmpty) {
          expect(await File(entries.single.path).readAsString(), 'existing');
        }
      }
      expect(await attempts(), isEmpty);
    });
  }
  test('creates missing modules and animations ancestors under the same root',
      () async {
    final isolatedRoot =
        await Directory(p.join(root.path, 'new-root')).create();
    await service().withPrepared(
        animationId: 42,
        canonicalRoot: isolatedRoot,
        downloadUri: uri,
        use: (prepared) => prepared.publish());
    expect(
        await File(p.join(isolatedRoot.path, 'modules', 'animations', '42',
                'nested', 'Original.MP4'))
            .readAsBytes(),
        bytes);
    expect(
        await Directory(p.join(isolatedRoot.path, 'animation_installations'))
            .list()
            .toList(),
        isEmpty);
  });
  test('refuses a file at the animations ancestor', () async {
    await expectLater(
        prepare(service(), (prepared) async {
          await File(p.dirname(getTarget())).writeAsString('existing ancestor');
          return prepared.publish();
        }),
        throwsA(isA<FileSystemException>()));
    expect(
        await File(p.dirname(getTarget())).readAsString(), 'existing ancestor');
    expect(await attempts(), isEmpty);
  });
  test('refuses linked modules ancestor without changing its target', () async {
    final modules = Directory(p.join(root.path, 'modules'));
    final saved = Directory(p.join(root.path, 'saved-modules'));
    var linked = false;
    try {
      await expectLater(
          prepare(service(), (prepared) async {
            await modules.rename(saved.path);
            try {
              await Link(modules.path).create(saved.path);
              linked = true;
            } on FileSystemException catch (error) {
              markTestSkipped('Symlinks unavailable: $error');
              throw StateError('symlinks unavailable');
            }
            return prepared.publish();
          }),
          throwsA(anyOf(isA<FileSystemException>(), isA<StateError>())));
      expect(
          await Directory(p.join(saved.path, 'animations')).exists(), isFalse);
    } finally {
      if (linked) await Link(modules.path).delete();
      if (await saved.exists()) await saved.rename(modules.path);
    }
  });
  for (final ancestor in [false, true]) {
    test('refuses linked ${ancestor ? 'ancestor' : 'destination'}', () async {
      var skipped = false;
      await expectLater(
          prepare(service(), (prepared) async {
            final path = ancestor ? p.dirname(getTarget()) : getTarget();
            await Directory(p.dirname(path)).create(recursive: true);
            try {
              await Link(path).create(p.join(root.path, 'external'));
            } on FileSystemException catch (error) {
              markTestSkipped('Symlinks unavailable: $error');
              skipped = true;
              throw StateError('symlinks unavailable');
            }
            return prepared.publish();
          }),
          throwsA(anyOf(isA<FileSystemException>(),
              predicate((error) => skipped && error is StateError))));
      expect(await File(p.join(root.path, 'external', 'Original.MP4')).exists(),
          isFalse);
      expect(await attempts(), isEmpty);
    });
  }
  test('publication rechecks ownership marker', () async {
    await expectLater(
        prepare(service(), (prepared) async {
          await File(p.join((await attempt()).path, '.workspace-owner'))
              .writeAsString('wrong');
          return prepared.publish();
        }),
        throwsA(isA<AnimationPreparationCleanupException>().having(
            (e) => e.primaryError, 'primary', isA<FileSystemException>())));
    expect(await Directory(getTarget()).exists(), isFalse);
    expect(await File(p.join((await attempt()).path, 'download.zip')).exists(),
        isTrue);
  });
  test('publication reverifies staged content', () async {
    await expectLater(
        prepare(service(), (prepared) async {
          final video = File(p.join(
              (await attempt()).path, 'payload', 'nested', 'Original.MP4'));
          final corrupted = List<int>.from(bytes)..[0] = 99;
          await video.writeAsBytes(corrupted);
          return prepared.publish();
        }),
        throwsFormatException);
    expect(await Directory(getTarget()).exists(), isFalse);
    expect(await attempts(), isEmpty);
  });
  test('cancellation before publication prevents rename', () async {
    final token = AnimationPreparationCancellation();
    var moves = 0;
    await expectLater(
        prepare(service(rename: (source, target) async {
          moves++;
        }), (prepared) async {
          token.cancel();
          return prepared.publish();
        }, cancellation: token),
        throwsA(isA<AnimationPreparationCancelled>()));
    expect(moves, 0);
    expect(await Directory(getTarget()).exists(), isFalse);
    expect(await attempts(), isEmpty);
  });
  test('cancellation at publishing observer prevents rename', () async {
    final token = AnimationPreparationCancellation();
    await expectLater(
        prepare(service(), (p) => p.publish(), cancellation: token,
            progress: (event) {
          if (event.phase == AnimationPreparationPhase.publishing) {
            token.cancel();
          }
        }),
        throwsA(isA<AnimationPreparationCancelled>()));
    expect(await Directory(getTarget()).exists(), isFalse);
  });
  for (final failCallback in [false, true]) {
    test('unawaited pending rename is joined; callback error: $failCallback',
        () async {
      final entered = Completer<void>(), release = Completer<void>();
      final token = AnimationPreparationCancellation();
      final callbackError = StateError('callback failure');
      late PreparedAnimation escaped;
      var moves = 0, settled = false;
      final operation = prepare(service(rename: (source, target) async {
        moves++;
        entered.complete();
        await release.future;
        await source.rename(target);
      }), (prepared) async {
        escaped = prepared;
        prepared
            .publish(); // Deliberately not awaited; service owns supervision.
        if (failCallback) throw callbackError;
        return 123;
      }, cancellation: token);
      final outcome = operation.then<Object>((value) {
        settled = true;
        return value;
      }, onError: (Object error) {
        settled = true;
        return error;
      });
      try {
        await entered.future;
        await expectLater(escaped.publish(), throwsStateError);
        token.cancel(); // Models cancellation after rename was submitted.
        expect(settled, isFalse);
        expect((await attempts()).length, 1);
        await expectLater(
            coordinator.run(animationId: 42, operation: () async {}),
            throwsA(isA<AnimationInstallationInProgressException>()));
      } finally {
        release.complete();
      }
      final result = await outcome;
      if (failCallback) {
        expect(
            result,
            isA<AnimationPublicationCommittedException>()
                .having((e) => e.primaryError, 'primary', same(callbackError))
                .having((e) => e.publication.animationId, 'committed ID', 42));
      } else {
        expect(result, 123);
      }
      expect(moves, 1);
      expect(await targetFile().readAsBytes(), bytes);
      expect(await attempts(), isEmpty);
    });
  }
  test('successful move wins over later cancellation', () async {
    final token = AnimationPreparationCancellation();
    final result = await prepare(service(), (prepared) async {
      final published = await prepared.publish();
      token.cancel();
      return published;
    }, cancellation: token);
    expect(result.animationId, 42);
    expect(await targetFile().readAsBytes(), bytes);
  });
  test('concurrent and repeated publication issues one move', () async {
    var moves = 0;
    await prepare(service(rename: (source, target) async {
      moves++;
      await source.rename(target);
    }), (prepared) async {
      final first = prepared.publish(), second = prepared.publish();
      expect(identical(first, second), isTrue);
      final result = await first;
      expect(identical(await second, result), isTrue);
      expect(identical(await prepared.publish(), result), isTrue);
    });
    expect(moves, 1);
  });
  test('escaped capability is closed after discard', () async {
    final escaped = await prepare(service(), (prepared) async => prepared);
    await expectLater(escaped.publish(), throwsStateError);
    expect(await Directory(getTarget()).exists(), isFalse);
  });
  test('reentrant publication observer shares the reserved move', () async {
    PreparedAnimation? capability;
    Future<PublishedAnimation>? reentrant;
    var moves = 0;
    await prepare(service(rename: (source, target) async {
      moves++;
      await source.rename(target);
    }), (prepared) async {
      capability = prepared;
      final first = prepared.publish();
      expect(identical(first, reentrant), isTrue);
      await first;
    }, progress: (event) {
      if (event.phase == AnimationPreparationPhase.publishing) {
        reentrant = capability!.publish();
      }
    });
    expect(moves, 1);
    expect(await targetFile().readAsBytes(), bytes);
  });
  test('escaped capability is closed after successful publication', () async {
    final escaped = await prepare(service(), (prepared) async {
      await prepared.publish();
      return prepared;
    });
    await expectLater(escaped.publish(), throwsStateError);
    expect(await targetFile().readAsBytes(), bytes);
  });
  test('unawaited rename failure propagates without copying', () async {
    final failure =
        FileSystemException('simulated cross-device rename failure');
    await expectLater(
        prepare(service(rename: (source, target) async {
          expect(
              await File(p.join(source.path, 'nested', 'Original.MP4'))
                  .readAsBytes(),
              bytes);
          throw failure;
        }), (prepared) async {
          prepared.publish();
          return 1;
        }),
        throwsA(same(failure)));
    expect(await Directory(getTarget()).exists(), isFalse);
    expect(await attempts(), isEmpty);
  });
  for (final callbackFails in [false, true]) {
    test(
        'cleanup failure after commit preserves installed video: $callbackFails',
        () async {
      final original = StateError('callback after commit');
      await expectLater(
          prepare(service(), (prepared) async {
            await prepared.publish();
            await File(p.join((await attempt()).path, 'unexpected.keep'))
                .writeAsString('private');
            if (callbackFails) throw original;
            return 1;
          }),
          throwsA(isA<AnimationPublicationCommittedException>()
              .having((e) => e.publication.animationId, 'committed', 42)
              .having(
                  (e) => e.cleanupError, 'cleanup', isA<FileSystemException>())
              .having(
                  (e) => e.primaryError,
                  'primary',
                  callbackFails
                      ? same(original)
                      : isA<FileSystemException>())));
      expect(await targetFile().readAsBytes(), bytes);
      expect(
          await File(p.join((await attempt()).path, 'unexpected.keep'))
              .readAsString(),
          'private');
      await coordinator.run(animationId: 42, operation: () async {});
    });
  }
  test('callback error after commit reports publication and original stack',
      () async {
    final error = StateError('post-commit callback');
    await expectLater(
        prepare(service(), (prepared) async {
          await prepared.publish();
          throw error;
        }),
        throwsA(isA<AnimationPublicationCommittedException>()
            .having((e) => e.primaryError, 'primary', same(error))
            .having((e) => e.primaryStack.toString(), 'stack',
                contains('animation_publication_test.dart'))));
    expect(await targetFile().readAsBytes(), bytes);
    expect(await attempts(), isEmpty);
  });
  test('reservation is held when private cleanup starts after publication',
      () async {
    Future<void>? duplicate;
    await prepare(service(), (p) => p.publish(), progress: (event) {
      if (event.phase == AnimationPreparationPhase.cleaningUp) {
        duplicate = expectLater(
            coordinator.run(animationId: 42, operation: () async {}),
            throwsA(isA<AnimationInstallationInProgressException>()));
      }
    });
    await duplicate;
    expect(duplicate, isNotNull);
    expect(await targetFile().readAsBytes(), bytes);
  });
}
