import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/animation_bounded_mp4_extraction_service.dart';
import 'package:wired_test/services/animation_installation_coordinator.dart';
import 'package:wired_test/services/animation_installation_inspection_service.dart';
import 'package:wired_test/services/animation_installation_workspace_service.dart';
import 'package:wired_test/services/animation_mp4_extraction_worker_service.dart';
import 'package:wired_test/services/animation_preparation_service.dart';
import 'package:wired_test/services/animation_private_download_service.dart';
import 'package:wired_test/services/animation_staged_mp4_verification_service.dart';
import 'package:wired_test/services/animation_zip_metadata_reader.dart';

class _Transport implements AnimationDownloadTransport {
  _Transport(this.bytes, {this.status = 200, this.gate});
  final List<int> bytes;
  final int status;
  final Future<void>? gate;
  bool closed = false;
  @override
  Future<AnimationDownloadResponse> open(Uri uri) async =>
      AnimationDownloadResponse(
          statusCode: status, contentLength: bytes.length, body: _body());
  Stream<List<int>> _body() async* {
    if (gate != null) await gate;
    for (var i = 0; i < bytes.length; i += 37) {
      yield bytes.sublist(i, i + 37 > bytes.length ? bytes.length : i + 37);
    }
  }

  @override
  void close() => closed = true;
}

class _FailExtractor extends AnimationMp4ExtractionWorkerService {
  _FailExtractor(this.error, {this.gate, this.entered});
  final Object error;
  final Future<void>? gate;
  final Completer<void>? entered;
  @override
  Future<AnimationBoundedMp4ExtractionResult> extract({
    required String zipPath,
    required AnimationZipDescriptor descriptor,
    required String payloadPath,
    AnimationExtractionCancellation? cancellation,
    void Function(AnimationExtractionPhase)? onPhase,
  }) async {
    entered?.complete();
    if (gate != null) await gate;
    throw error;
  }
}

class _FailStaged extends AnimationStagedMp4VerificationService {
  const _FailStaged();
  @override
  Future<AnimationStagedMp4VerificationResult> verify({
    required AnimationZipDescriptor descriptor,
    required Directory payloadDirectory,
  }) async =>
      throw StateError('staged failure');
}

class _FailWorkspace extends AnimationInstallationWorkspaceService {
  @override
  Future<AnimationInstallationWorkspace> create(
          {required Directory root, required int animationId}) async =>
      throw StateError('workspace failure');
}

void main() {
  late Directory root;
  late AnimationInstallationCoordinator coordinator;
  late List<int> zipBytes;
  late List<_Transport> transports;
  late bool destinationFixture;
  final data = List<int>.generate(4097, (i) => i % 251);
  final uri = Uri.parse('https://example.invalid/animation.zip');

  List<int> archive(
          {int method = 8, String path = 'deep/topic/Original.MP4'}) =>
      ZipEncoder().encode(Archive()
        ..addFile(ArchiveFile(path, data.length, data)
          ..compression =
              method == 0 ? CompressionType.none : CompressionType.deflate));

  AnimationPreparationService service({
    int status = 200,
    Future<void>? downloadGate,
    AnimationMp4ExtractionWorkerService? extractor,
    AnimationStagedMp4VerificationService? staged,
    AnimationInstallationWorkspaceService? workspaces,
    AnimationBackgroundZipVerification? verifyZip,
  }) =>
      AnimationPreparationService(
          coordinator: coordinator,
          downloader: AnimationPrivateDownloadService(transportFactory: () {
            final transport =
                _Transport(zipBytes, status: status, gate: downloadGate);
            transports.add(transport);
            return transport;
          }),
          extractor: extractor,
          stagedVerifier: staged,
          workspaces: workspaces,
          verifyZip: verifyZip);

  Future<List<Directory>> attempts() async {
    final parent = Directory(p.join(root.path, 'animation_installations'));
    if (!await parent.exists()) return [];
    return parent
        .list()
        .where((e) => e is Directory)
        .cast<Directory>()
        .toList();
  }

  Future<T> prepare<T>(AnimationPreparationService s,
          Future<T> Function(PreparedAnimation) use,
          {int id = 42,
          Uri? url,
          AnimationPreparationCancellation? cancellation,
          void Function(AnimationPreparationProgress)? progress}) =>
      s.withPrepared(
          animationId: id,
          canonicalRoot: root,
          downloadUri: url ?? uri,
          use: use,
          cancellation: cancellation,
          onProgress: progress);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('healthmap-preparation-');
    coordinator = AnimationInstallationCoordinator();
    transports = [];
    destinationFixture = false;
    zipBytes = archive();
    for (final relative in [
      'sentinel.keep',
      'modules/historical/index.html',
      'packages/historical/story.html'
    ]) {
      final file = File(p.join(root.path, relative));
      await file.parent.create(recursive: true);
      await file.writeAsString('preserve');
    }
  });
  tearDown(() async {
    for (final relative in [
      'sentinel.keep',
      'modules/historical/index.html',
      'packages/historical/story.html'
    ]) {
      expect(
          await File(p.join(root.path, relative)).readAsString(), 'preserve');
    }
    if (!destinationFixture) {
      expect(
          await Directory(p.join(root.path, 'modules', 'animations')).exists(),
          isFalse);
    }
    for (final transport in transports) {
      expect(transport.closed, isTrue);
    }
    expect(p.isWithin(Directory.systemTemp.absolute.path, root.path), isTrue);
    expect(p.basename(root.path), startsWith('healthmap-preparation-'));
    await root.delete(recursive: true);
  });

  for (final method in [0, 8]) {
    for (final path in ['Original.MP4', 'deep/topic/Original.MP4']) {
      test('verified method $method preserves $path and cleans after callback',
          () async {
        zipBytes = archive(method: method, path: path);
        final phases = <AnimationPreparationPhase>[];
        final result = await prepare(service(), (prepared) async {
          expect(prepared.animationId, 42);
          expect(prepared.relativePath, path);
          expect(prepared.verifiedBytes, data.length);
          expect(prepared.descriptor.crc32, getCrc32(data));
          final attempt = (await attempts()).single;
          expect(
              await File(
                      p.joinAll([attempt.path, 'payload', ...path.split('/')]))
                  .readAsBytes(),
              data);
          expect(await File(p.join(attempt.path, 'download.zip')).readAsBytes(),
              zipBytes);
          return 'callback result';
        }, progress: (progress) => phases.add(progress.phase));
        expect(result, 'callback result');
        expect(await attempts(), isEmpty);
        expect(phases.first, AnimationPreparationPhase.inspectingDestination);
        expect(phases.last, AnimationPreparationPhase.cleaningUp);
        expect(
            phases.where((p) => p == AnimationPreparationPhase.prepared).length,
            1);
      });
    }
  }

  for (final id in [0, -1]) {
    test('invalid ID $id has no workspace or download', () async {
      await expectLater(
          prepare(service(), (_) async => fail('callback'), id: id),
          throwsArgumentError);
      expect(await attempts(), isEmpty);
      expect(transports, isEmpty);
    });
  }
  for (final url in [
    'http://example.invalid/a.zip',
    '/relative.zip',
    'https://user:pass@example.invalid/a.zip',
    'https://example.invalid/a.zip#fragment'
  ]) {
    test('rejects URL $url before workspace', () async {
      await expectLater(
          prepare(service(), (_) async => fail('callback'),
              url: Uri.parse(url)),
          throwsArgumentError);
      expect(await attempts(), isEmpty);
      expect(transports, isEmpty);
    });
  }
  for (final installed in [true, false]) {
    test('refuses ${installed ? 'installed' : 'empty conflicting'} destination',
        () async {
      destinationFixture = true;
      final destination =
          Directory(p.join(root.path, 'modules', 'animations', '42'));
      await destination.create(recursive: true);
      if (installed) {
        await File(p.join(destination.path, 'old.mp4')).writeAsString('old');
      }
      await expectLater(
          prepare(service(), (_) async => fail('callback')),
          throwsA(isA<AnimationPreparationDestinationException>().having(
              (e) => e.status,
              'status',
              installed
                  ? AnimationInstallationStatus.installed
                  : AnimationInstallationStatus.conflict)));
      expect(await destination.exists(), isTrue);
      if (installed) {
        expect(await File(p.join(destination.path, 'old.mp4')).readAsString(),
            'old');
      }
      expect(transports, isEmpty);
      expect(await attempts(), isEmpty);
    });
  }

  for (final stage in [
    'workspace',
    'download',
    'metadata',
    'integrity',
    'extraction',
    'staged'
  ]) {
    test('$stage failure never invokes callback and cleans owned attempt',
        () async {
      if (stage == 'metadata') zipBytes = [1, 2, 3];
      if (stage == 'integrity') {
        zipBytes = archive(method: 0);
        // Mutate only stored payload; valid headers still declare the original CRC.
        final fixture = File(p.join(root.path, 'fixture.zip'));
        await fixture.writeAsBytes(zipBytes);
        final descriptor =
            await const AnimationZipMetadataReader().inspect(fixture.path);
        zipBytes[descriptor.payloadOffset] ^= 1;
      }
      final s = service(
          status: stage == 'download' ? 500 : 200,
          workspaces: stage == 'workspace' ? _FailWorkspace() : null,
          extractor: stage == 'extraction'
              ? _FailExtractor(StateError('extraction'))
              : null,
          staged: stage == 'staged' ? const _FailStaged() : null);
      final expected = stage == 'download'
          ? isA<HttpException>()
          : stage == 'metadata' || stage == 'integrity'
              ? isA<FormatException>()
              : isA<StateError>();
      await expectLater(
          prepare(s, (_) async => fail('callback')), throwsA(expected));
      expect(await attempts(), isEmpty);
      await coordinator.run(animationId: 42, operation: () async {});
    });
  }

  test('callback failure preserved and owned workspace removed', () async {
    final error = StateError('callback error');
    await expectLater(
        prepare(service(), (_) async => throw error), throwsA(same(error)));
    expect(await attempts(), isEmpty);
  });
  test('throwing progress observer cannot abandon preparation', () async {
    expect(
        await prepare(service(), (_) async => 123,
            progress: (_) => throw StateError('observer')),
        123);
    expect(await attempts(), isEmpty);
  });
  test('reservation spans callback; different ID independently prepares',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    final s = service();
    final first = prepare(s, (_) async {
      entered.complete();
      await release.future;
      return 42;
    });
    try {
      await entered.future;
      await expectLater(prepare(service(), (_) async => fail('duplicate')),
          throwsA(isA<AnimationInstallationInProgressException>()));
      expect(await prepare(service(), (_) async => 43, id: 43), 43);
      expect((await attempts()).length, 1);
    } finally {
      release.complete();
      await first;
    }
    expect(await attempts(), isEmpty);
  });
  test('pre-cancelled preparation creates nothing', () async {
    final token = AnimationPreparationCancellation()..cancel();
    await expectLater(
        prepare(service(), (_) async => fail('callback'), cancellation: token),
        throwsA(isA<AnimationPreparationCancelled>()));
    expect(transports, isEmpty);
    expect(await attempts(), isEmpty);
  });
  for (final phase in AnimationPreparationPhase.values.where((phase) =>
      phase != AnimationPreparationPhase.cleaningUp &&
      phase != AnimationPreparationPhase.publishing)) {
    test('cancellation at $phase prevents callback and discards attempt',
        () async {
      final token = AnimationPreparationCancellation();
      await expectLater(
          prepare(service(), (_) async => fail('callback'), cancellation: token,
              progress: (progress) {
            if (progress.phase == phase) token.cancel();
          }),
          throwsA(isA<AnimationPreparationCancelled>()));
      expect(await attempts(), isEmpty);
      await coordinator.run(animationId: 42, operation: () async {});
    });
  }
  test('escaped preparation is inert metadata, not a live workspace', () async {
    final metadata = await prepare(service(), (prepared) async => prepared);
    expect(metadata.animationId, 42);
    expect(metadata.relativePath, 'deep/topic/Original.MP4');
    expect(metadata.verifiedBytes, data.length);
    expect(await attempts(), isEmpty);
  });
  test('cancellation during download waits for completion before cleanup',
      () async {
    final gate = Completer<void>(), downloading = Completer<void>();
    final token = AnimationPreparationCancellation();
    final operation = prepare(
        service(downloadGate: gate.future), (_) async => fail('callback'),
        cancellation: token, progress: (p) {
      if (p.download != null && !downloading.isCompleted) {
        downloading.complete();
      }
    });
    final checked =
        expectLater(operation, throwsA(isA<AnimationPreparationCancelled>()));
    await downloading.future;
    token.cancel();
    expect((await attempts()).length, 1);
    await expectLater(coordinator.run(animationId: 42, operation: () async {}),
        throwsA(isA<AnimationInstallationInProgressException>()));
    gate.complete();
    await checked;
    expect(await attempts(), isEmpty);
  });
  test('active extraction is awaited despite cancellation', () async {
    final gate = Completer<void>(), entered = Completer<void>();
    final token = AnimationPreparationCancellation();
    final operation = prepare(
        service(
            extractor: _FailExtractor(const AnimationExtractionCancelled(),
                gate: gate.future, entered: entered)),
        (_) async => fail('callback'),
        cancellation: token);
    final checked =
        expectLater(operation, throwsA(isA<AnimationPreparationCancelled>()));
    await entered.future;
    token.cancel();
    expect((await attempts()).length, 1);
    await expectLater(coordinator.run(animationId: 42, operation: () async {}),
        throwsA(isA<AnimationInstallationInProgressException>()));
    gate.complete();
    await checked;
    expect(await attempts(), isEmpty);
  });
  test('background verification stage is awaited on cancellation', () async {
    final gate = Completer<void>(), entered = Completer<void>();
    final token = AnimationPreparationCancellation();
    final operation =
        prepare(service(verifyZip: (path, descriptor, limits) async {
      entered.complete();
      await gate.future;
    }), (_) async => fail('callback'), cancellation: token);
    final checked =
        expectLater(operation, throwsA(isA<AnimationPreparationCancelled>()));
    await entered.future;
    token.cancel();
    expect((await attempts()).length, 1);
    gate.complete();
    await checked;
    expect(await attempts(), isEmpty);
  });
  test('cancellation in callback waits for callback before discard', () async {
    final token = AnimationPreparationCancellation();
    await expectLater(
        prepare(service(), (_) async {
          token.cancel();
          expect((await attempts()).length, 1);
          return 1;
        }, cancellation: token),
        throwsA(isA<AnimationPreparationCancelled>()));
    expect(await attempts(), isEmpty);
  });
  for (final failCallback in [false, true]) {
    test('cleanup failure observable; primary retained: $failCallback',
        () async {
      final primary = StateError('original callback failure');
      await expectLater(
          prepare(service(), (_) async {
            final attempt = (await attempts()).single;
            await File(p.join(attempt.path, 'unknown.keep'))
                .writeAsString('preserve');
            if (failCallback) throw primary;
            return 1;
          }),
          throwsA(isA<AnimationPreparationCleanupException>()
              .having((e) => e.primaryError, 'primary',
                  failCallback ? same(primary) : isNull)
              .having((e) => e.cleanupError, 'cleanup',
                  isA<FileSystemException>())));
      final attempt = (await attempts()).single;
      expect(await File(p.join(attempt.path, 'unknown.keep')).readAsString(),
          'preserve');
      expect(await File(p.join(attempt.path, 'download.zip')).exists(), isTrue);
      await coordinator.run(animationId: 42, operation: () async {});
    });
  }
}
