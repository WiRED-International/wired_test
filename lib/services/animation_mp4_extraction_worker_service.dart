import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'animation_bounded_mp4_extraction_service.dart';
import 'animation_zip_metadata_reader.dart';

enum AnimationExtractionPhase { extracting }

enum AnimationExtractionWorkerFailureKind {
  spawn,
  extraction,
  unexpectedError,
  prematureExit,
  protocol,
}

class AnimationExtractionWorkerException implements Exception {
  const AnimationExtractionWorkerException(this.kind, this.message,
      [this.workerStack]);
  final AnimationExtractionWorkerFailureKind kind;
  final String message;
  final String? workerStack;
  @override
  String toString() => 'Animation extraction ${kind.name}: $message';
}

class AnimationExtractionCancelled implements Exception {
  const AnimationExtractionCancelled();
}

/// Deferred cancellation: work is never killed, and may run to completion.
class AnimationExtractionCancellation {
  bool _requested = false;
  bool get isRequested => _requested;
  void cancel() => _requested = true;
}

typedef AnimationExtractionWorkerSpawner = Future<Isolate> Function(
  void Function(Map<String, Object?>) entryPoint,
  Map<String, Object?> request, {
  required SendPort onError,
  required SendPort onExit,
});

/// Runs the unchanged bounded extractor off the application isolate.
/// The returned Future settles only after exit (or a failed spawn). Callers
/// must await it before cleaning the workspace or releasing an ID reservation.
/// Cancellation takes precedence after exit, including over extraction errors.
/// It cannot interrupt synchronous decoding or a stuck filesystem operation.
/// Phase callback exceptions are ignored so observers cannot abandon supervision.
/// ZIP immutability, exclusive workspace ownership and the extractor's documented
/// raw-Deflate/filesystem limitations still apply. No publication is performed.
class AnimationMp4ExtractionWorkerService {
  AnimationMp4ExtractionWorkerService({
    this.limits = const AnimationZipLimits(),
    this.chunkSize = 32 * 1024,
    AnimationExtractionWorkerSpawner? spawner,
    ReceivePort Function()? portFactory,
  })  : _spawner = spawner ?? _spawn,
        _portFactory = portFactory ?? ReceivePort.new;

  final AnimationZipLimits limits;
  final int chunkSize;
  // Trusted parent-side lifecycle hooks for tests; never sent to the worker.
  // A spawner must either return its supervised isolate or fail without leaving
  // a live worker. An indefinitely pending spawn cannot safely be abandoned.
  final AnimationExtractionWorkerSpawner _spawner;
  final ReceivePort Function() _portFactory;

  Future<AnimationBoundedMp4ExtractionResult> extract({
    required String zipPath,
    required AnimationZipDescriptor descriptor,
    required String payloadPath,
    AnimationExtractionCancellation? cancellation,
    void Function(AnimationExtractionPhase)? onPhase,
  }) async {
    if (cancellation?.isRequested ?? false) {
      throw const AnimationExtractionCancelled();
    }
    limits.validate();
    if (chunkSize <= 0 || chunkSize > 1024 * 1024) {
      throw ArgumentError.value(chunkSize, 'chunkSize');
    }
    final port = _portFactory();
    // Keep VM lifecycle notifications off the application-message port: an
    // invalid null message must never be mistaken for confirmed worker exit.
    final lifecyclePort = _portFactory();
    final exited = Completer<void>();
    AnimationBoundedMp4ExtractionResult? result;
    AnimationExtractionWorkerException? failure;
    var started = false;
    var terminal = false;
    void protocolFailure() {
      failure ??= const AnimationExtractionWorkerException(
          AnimationExtractionWorkerFailureKind.protocol,
          'Malformed, duplicate or out-of-order worker message.');
    }

    final lifecycleSubscription = lifecyclePort.listen((dynamic message) {
      if (message == null) {
        if (!exited.isCompleted) exited.complete();
        return;
      }
      if (message is List && message.length == 2) {
        failure = AnimationExtractionWorkerException(
            AnimationExtractionWorkerFailureKind.unexpectedError,
            '${message[0]}',
            '${message[1]}');
      }
    });
    final subscription = port.listen((dynamic message) {
      if (message is! Map || message['v'] != 1) {
        protocolFailure();
        return;
      }
      // Acknowledge even invalid terminal messages so a cooperative worker can
      // exit. Acknowledgement is receipt, never permission to publish.
      final ack = message['ack'];
      if (ack is SendPort) ack.send(null);
      switch (message['type']) {
        case 'started':
          if (started || terminal || ack != null) {
            protocolFailure();
          } else {
            started = true;
            try {
              onPhase?.call(AnimationExtractionPhase.extracting);
            } catch (_) {
              // Observers do not own worker lifecycle.
            }
          }
        case 'completed':
          if (!started ||
              terminal ||
              ack is! SendPort ||
              message['path'] != descriptor.mp4RelativePath ||
              message['bytes'] != descriptor.uncompressedSize) {
            protocolFailure();
          } else {
            result = AnimationBoundedMp4ExtractionResult(
                relativePath: descriptor.mp4RelativePath,
                extractedBytes: descriptor.uncompressedSize);
          }
          terminal = true;
        case 'failed':
          if (!started ||
              terminal ||
              ack is! SendPort ||
              message['error'] is! String ||
              message['stack'] is! String) {
            protocolFailure();
          } else {
            failure ??= AnimationExtractionWorkerException(
                AnimationExtractionWorkerFailureKind.extraction,
                message['error'] as String,
                message['stack'] as String);
          }
          terminal = true;
        default:
          protocolFailure();
      }
    });
    try {
      try {
        await _spawner(
            _extractWorker,
            {
              'port': port.sendPort,
              'zip': zipPath,
              'payload': payloadPath,
              'path': descriptor.mp4RelativePath,
              'compressed': descriptor.compressedSize,
              'size': descriptor.uncompressedSize,
              'crc': descriptor.crc32,
              'method': descriptor.compressionMethod,
              'offset': descriptor.payloadOffset,
              'chunk': chunkSize,
              'limits': [
                limits.maxZipBytes,
                limits.maxMp4Bytes,
                limits.maxEntries,
                limits.maxDepth,
                limits.maxMetadataBytes,
                limits.maxNameBytes
              ],
            },
            onError: lifecyclePort.sendPort,
            onExit: lifecyclePort.sendPort);
      } catch (error, stack) {
        throw AnimationExtractionWorkerException(
            AnimationExtractionWorkerFailureKind.spawn, '$error', '$stack');
      }
      await exited.future;
      if (cancellation?.isRequested ?? false) {
        throw const AnimationExtractionCancelled();
      }
      if (failure != null) throw failure!;
      if (result == null) {
        throw const AnimationExtractionWorkerException(
            AnimationExtractionWorkerFailureKind.prematureExit,
            'Worker exited without an extraction result.');
      }
      return result!;
    } finally {
      port.close();
      lifecyclePort.close();
      await subscription.cancel();
      await lifecycleSubscription.cancel();
    }
  }
}

Future<Isolate> _spawn(void Function(Map<String, Object?>) entryPoint,
        Map<String, Object?> request,
        {required SendPort onError, required SendPort onExit}) =>
    Isolate.spawn(entryPoint, request,
        onError: onError, onExit: onExit, errorsAreFatal: true);

void _extractWorker(Map<String, Object?> request) async {
  final port = request['port'] as SendPort;
  port.send({'v': 1, 'type': 'started'});
  final ack = ReceivePort();
  try {
    Map<String, Object?> terminal;
    try {
      final l = (request['limits'] as List).cast<int>();
      final result = await AnimationBoundedMp4ExtractionService(
        chunkSize: request['chunk'] as int,
        limits: AnimationZipLimits(
            maxZipBytes: l[0],
            maxMp4Bytes: l[1],
            maxEntries: l[2],
            maxDepth: l[3],
            maxMetadataBytes: l[4],
            maxNameBytes: l[5]),
      ).extract(
        zipFile: File(request['zip'] as String),
        payloadDirectory: Directory(request['payload'] as String),
        descriptor: AnimationZipDescriptor(
            mp4RelativePath: request['path'] as String,
            compressedSize: request['compressed'] as int,
            uncompressedSize: request['size'] as int,
            crc32: request['crc'] as int,
            compressionMethod: request['method'] as int,
            payloadOffset: request['offset'] as int),
      );
      terminal = {
        'type': 'completed',
        'path': result.relativePath,
        'bytes': result.extractedBytes
      };
    } catch (error, stack) {
      terminal = {'type': 'failed', 'error': '$error', 'stack': '$stack'};
    }
    port.send({...terminal, 'v': 1, 'ack': ack.sendPort});
    await ack.first;
  } finally {
    ack.close();
  }
}
