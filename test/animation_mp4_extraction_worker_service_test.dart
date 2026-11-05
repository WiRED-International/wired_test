import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/animation_bounded_mp4_extraction_service.dart';
import 'package:wired_test/services/animation_installation_coordinator.dart';
import 'package:wired_test/services/animation_installation_workspace_service.dart';
import 'package:wired_test/services/animation_mp4_extraction_worker_service.dart';
import 'package:wired_test/services/animation_zip_metadata_reader.dart';

// Gate both terminal delivery and exit independently, without timer sleeps.
void _controlledWorker(Map<String, Object?> args) async {
  final request = args['request'] as Map;
  final parent = request['port'] as SendPort;
  final mode = args['mode'];
  if (mode == 'exit') return;
  if (mode == 'crash') throw StateError('unexpected worker crash');
  final observer = args['observer'] as SendPort;
  final control = ReceivePort();
  final commands = StreamIterator(control);
  final ack = ReceivePort();
  try {
    parent.send({'v': 1, 'type': 'started'});
    observer.send(control.sendPort);
    await commands.moveNext();
    if (mode == 'malformed') {
      parent.send(null);
      parent.send({'v': 2, 'type': 'unknown'});
    }
    final terminal = mode == 'failed'
        ? {
            'v': 1,
            'type': 'failed',
            'error': 'controlled extraction failure',
            'stack': 'controlled stack',
            'ack': ack.sendPort
          }
        : {
            'v': 1,
            'type': 'completed',
            'path': request['path'],
            'bytes': request['size'],
            'ack': ack.sendPort
          };
    parent.send(terminal);
    if (mode == 'duplicate') parent.send(terminal);
    await ack.first;
    observer.send('terminal acknowledged');
    await commands.moveNext();
  } finally {
    ack.close();
    await commands.cancel();
    control.close();
  }
}

class _TrackedPort implements ReceivePort {
  final ReceivePort inner = ReceivePort();
  bool _closed = false;
  bool _allocated = false;
  bool cancelled = false;
  final List<_TrackedPort> children = [];
  bool get closed => _closed && cancelled && children.every((p) => p.closed);
  ReceivePort create() {
    if (!_allocated) {
      _allocated = true;
      return this;
    }
    final child = _TrackedPort();
    children.add(child);
    return child;
  }

  @override
  SendPort get sendPort => inner.sendPort;
  @override
  void close() {
    _closed = true;
    inner.close();
  }

  @override
  StreamSubscription<dynamic> listen(void Function(dynamic)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _TrackedSubscription(
          inner.listen(onData,
              onError: onError, onDone: onDone, cancelOnError: cancelOnError),
          () => cancelled = true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TrackedSubscription implements StreamSubscription<dynamic> {
  _TrackedSubscription(this.inner, this.onCancel);
  final StreamSubscription<dynamic> inner;
  final void Function() onCancel;
  @override
  Future<void> cancel() async {
    await inner.cancel();
    onCancel();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory root;
  late AnimationInstallationWorkspace workspace;
  late AnimationZipDescriptor descriptor;
  late File sentinel;
  late List<int> originalZip;
  final bytes = List<int>.generate(4097, (i) => i % 251);
  Future<void> fixture(
      {int method = 8, String path = 'nested/Original.MP4'}) async {
    final entry = ArchiveFile(path, bytes.length, bytes)
      ..compression =
          method == 0 ? CompressionType.none : CompressionType.deflate;
    originalZip = ZipEncoder().encode(Archive()..addFile(entry));
    await workspace.downloadFile.writeAsBytes(originalZip);
    descriptor = await const AnimationZipMetadataReader()
        .inspect(workspace.downloadFile.path);
  }

  Future<dynamic> extract(
    AnimationMp4ExtractionWorkerService service, {
    AnimationExtractionCancellation? cancellation,
    void Function(AnimationExtractionPhase)? onPhase,
  }) =>
      service.extract(
          zipPath: workspace.downloadFile.path,
          descriptor: descriptor,
          payloadPath: workspace.payloadDirectory.path,
          cancellation: cancellation,
          onPhase: onPhase);

  Matcher failure(AnimationExtractionWorkerFailureKind kind) =>
      isA<AnimationExtractionWorkerException>()
          .having((e) => e.kind, 'kind', kind);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('healthmap-worker-');
    workspace = await AnimationInstallationWorkspaceService()
        .create(root: root, animationId: 42);
    sentinel = File(p.join(root.path, 'modules', 'existing', 'keep'));
    await sentinel.parent.create(recursive: true);
    await sentinel.writeAsString('preserve');
    await fixture();
  });
  tearDown(() async {
    expect(await sentinel.readAsString(), 'preserve');
    if (await workspace.downloadFile.exists()) {
      expect(await workspace.downloadFile.readAsBytes(), originalZip);
    }
    expect(p.isWithin(Directory.systemTemp.absolute.path, root.path), isTrue);
    expect(p.basename(root.path), startsWith('healthmap-worker-'));
    await root.delete(recursive: true);
  });

  for (final method in [0, 8]) {
    for (final path in ['Original.MP4', 'deep/topic/Original.MP4']) {
      test('real worker method $method preserves $path', () async {
        await fixture(method: method, path: path);
        final phases = <AnimationExtractionPhase>[];
        final port = _TrackedPort();
        final result = await extract(
            AnimationMp4ExtractionWorkerService(
                chunkSize: 7, portFactory: port.create),
            onPhase: phases.add);
        expect(result.relativePath, path);
        expect(result.extractedBytes, bytes.length);
        expect(
            await File(p.joinAll(
                    [workspace.payloadDirectory.path, ...path.split('/')]))
                .readAsBytes(),
            bytes);
        expect(phases, [AnimationExtractionPhase.extracting]);
        expect(port.closed, isTrue);
      });
    }
  }
  test('real extraction failure preserves existing destination and closes port',
      () async {
    await fixture(path: 'clip.mp4');
    final target =
        await File(p.join(workspace.payloadDirectory.path, 'clip.mp4'))
            .writeAsString('existing');
    final port = _TrackedPort();
    await expectLater(
        extract(AnimationMp4ExtractionWorkerService(portFactory: port.create)),
        throwsA(failure(AnimationExtractionWorkerFailureKind.extraction)));
    expect(await target.readAsString(), 'existing');
    expect(port.closed, isTrue);
  });
  test('real worker survives throwing phase observer', () async {
    final result = await extract(AnimationMp4ExtractionWorkerService(),
        onPhase: (_) => throw StateError('observer'));
    expect(result.extractedBytes, bytes.length);
  });
  test('pre-spawn cancellation never creates ports or spawns', () async {
    final cancellation = AnimationExtractionCancellation()
      ..cancel()
      ..cancel();
    final service = AnimationMp4ExtractionWorkerService(
        portFactory: () => throw StateError('must not allocate'));
    await expectLater(extract(service, cancellation: cancellation),
        throwsA(isA<AnimationExtractionCancelled>()));
    expect(await workspace.payloadDirectory.list().toList(), isEmpty);
  });
  test('spawn failure closes port', () async {
    final port = _TrackedPort();
    final service = AnimationMp4ExtractionWorkerService(
        portFactory: port.create,
        spawner: (entry, request, {required onError, required onExit}) async {
          throw StateError('spawn unavailable');
        });
    await expectLater(extract(service),
        throwsA(failure(AnimationExtractionWorkerFailureKind.spawn)));
    expect(port.closed, isTrue);
  });

  for (final mode in ['exit', 'crash']) {
    test('handles unexpected $mode and closes port', () async {
      final port = _TrackedPort();
      final service = AnimationMp4ExtractionWorkerService(
          portFactory: port.create,
          spawner: (entry, request, {required onError, required onExit}) =>
              Isolate.spawn(
                  _controlledWorker, {'request': request, 'mode': mode},
                  onError: onError, onExit: onExit, errorsAreFatal: true));
      await expectLater(
          extract(service),
          throwsA(failure(mode == 'exit'
              ? AnimationExtractionWorkerFailureKind.prematureExit
              : AnimationExtractionWorkerFailureKind.unexpectedError)));
      expect(port.closed, isTrue);
    });
  }

  for (final mode in [
    'completed',
    'failed',
    'duplicate',
    'malformed',
    'cancel during',
    'cancel near completion',
    'cancel and failure',
    'observer'
  ]) {
    test('gated lifecycle: $mode', () async {
      final observer = ReceivePort();
      final events = StreamIterator(observer);
      final port = _TrackedPort();
      final cancellation = AnimationExtractionCancellation();
      final coordinator = AnimationInstallationCoordinator();
      final service = AnimationMp4ExtractionWorkerService(
          portFactory: port.create,
          spawner: (entry, request, {required onError, required onExit}) =>
              Isolate.spawn(
                  _controlledWorker,
                  {
                    'request': request,
                    'observer': observer.sendPort,
                    'mode': mode == 'cancel and failure' ? 'failed' : mode
                  },
                  onError: onError,
                  onExit: onExit,
                  errorsAreFatal: true));
      var settled = false;
      final operation = coordinator.run(
          animationId: 42,
          operation: () =>
              extract(service, cancellation: cancellation, onPhase: (_) {
                if (mode == 'observer') throw StateError('observer');
              }));
      // Observe failures immediately; do not leave an unhandled error while gated.
      final outcome = operation.then<Object>((value) {
        settled = true;
        return value;
      }, onError: (Object error) {
        settled = true;
        return error;
      });
      try {
        expect(await events.moveNext(), isTrue);
        final control = events.current as SendPort;
        if (mode == 'cancel during' || mode == 'cancel and failure') {
          cancellation
            ..cancel()
            ..cancel();
        }
        control.send('send terminal');
        expect(await events.moveNext(), isTrue);
        expect(events.current, 'terminal acknowledged');
        if (mode == 'cancel near completion') {
          cancellation
            ..cancel()
            ..cancel();
        }
        expect(settled, isFalse);
        expect(port.closed, isFalse);
        await expectLater(
            coordinator.run(animationId: 42, operation: () async {}),
            throwsA(isA<AnimationInstallationInProgressException>()));
        control.send('exit');
        final result = await outcome;
        if (mode.startsWith('cancel')) {
          expect(result, isA<AnimationExtractionCancelled>());
        } else if (mode == 'failed') {
          expect(
              result, failure(AnimationExtractionWorkerFailureKind.extraction));
        } else if (mode == 'duplicate' || mode == 'malformed') {
          expect(
              result, failure(AnimationExtractionWorkerFailureKind.protocol));
        } else {
          expect((result as AnimationBoundedMp4ExtractionResult).extractedBytes,
              bytes.length);
        }
        expect(port.closed, isTrue);
        // Send after settlement: a closed parent port must not process observers.
        port.sendPort.send({'v': 1, 'type': 'started'});
        await coordinator.run(
            animationId: 42,
            operation: () async {
              await workspace.cleanup();
            });
        expect(await workspace.directory.exists(), isFalse);
      } finally {
        await events.cancel();
        observer.close();
      }
    });
  }
}
