import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/animation_installation_workspace_service.dart';
import 'package:wired_test/services/animation_private_download_service.dart';
import 'package:wired_test/services/animation_zip_metadata_reader.dart';

class _Transport implements AnimationDownloadTransport {
  _Transport(this.response);
  final Future<AnimationDownloadResponse> Function() response;
  bool closed = false;
  int opens = 0;
  Object? closeError;
  @override
  Future<AnimationDownloadResponse> open(Uri uri) {
    opens++;
    return response();
  }

  @override
  void close() {
    closed = true;
    if (closeError != null) throw closeError!;
  }
}

class _Writer implements AnimationDownloadWriter {
  _Writer(this.file,
      {this.gate,
      this.failWrite = false,
      this.failFlush = false,
      this.closeError});
  final RandomAccessFile file;
  final Completer<void>? gate;
  final bool failWrite, failFlush;
  final started = Completer<void>();
  int pending = 0, maximumPending = 0, writes = 0;
  bool closed = false;
  final Object? closeError;
  final closeStarted = Completer<void>();
  @override
  Future<void> write(List<int> bytes) async {
    pending++;
    if (pending > maximumPending) maximumPending = pending;
    writes++;
    if (!started.isCompleted) started.complete();
    try {
      if (failWrite) throw const FileSystemException('disk full');
      if (gate != null) await gate!.future;
      await file.writeFrom(bytes);
    } finally {
      pending--;
    }
  }

  @override
  Future<void> flush() async {
    if (failFlush) throw const FileSystemException('flush failed');
    await file.flush();
  }

  @override
  Future<void> close() async {
    expect(pending, 0, reason: 'Never close a writer during an active write');
    closed = true;
    await file.close();
    closeStarted.complete();
    if (closeError != null) throw closeError!;
  }
}

void main() {
  final uri = Uri.parse('https://example.invalid/animation.zip');
  late Directory root;
  late AnimationInstallationWorkspace workspace;
  late File sentinel;
  late _Transport transport;
  AnimationPrivateDownloadService service({
    int maximum = 100,
    Duration inactivity = const Duration(seconds: 1),
    Duration request = const Duration(seconds: 1),
    Duration progress = Duration.zero,
    Duration cancellation = const Duration(seconds: 1),
    Future<AnimationDownloadWriter> Function(File)? writer,
  }) =>
      AnimationPrivateDownloadService(
        limits: AnimationZipLimits(maxZipBytes: maximum),
        transportFactory: () => transport,
        writerFactory: writer,
        inactivityTimeout: inactivity,
        requestTimeout: request,
        progressInterval: progress,
        cancellationTimeout: cancellation,
      );
  void respond({int status = 200, int length = 4, Stream<List<int>>? body}) {
    transport = _Transport(() async => AnimationDownloadResponse(
        statusCode: status,
        contentLength: length,
        body: body ??
            Stream.fromIterable([
              [1, 2],
              [3, 4]
            ])));
  }

  Future<AnimationDownloadResult> download(AnimationPrivateDownloadService s,
          {void Function(AnimationDownloadProgress)? progress}) =>
      s.download(
          uri: uri, destination: workspace.downloadFile, onProgress: progress);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('healthmap-private-download-');
    workspace = await AnimationInstallationWorkspaceService()
        .create(root: root, animationId: 42);
    sentinel = await File(p.join(root.path, 'unrelated.keep'))
        .writeAsString('preserve');
    respond();
  });
  tearDown(() async {
    expect(await sentinel.readAsString(), 'preserve');
    expect(await Directory(p.join(root.path, 'modules')).exists(), isFalse);
    expect(p.isWithin(Directory.systemTemp.absolute.path, root.path), isTrue);
    expect(p.basename(root.path), startsWith('healthmap-private-download-'));
    await root.delete(recursive: true);
  });

  test('known length download and determinate progress', () async {
    final events = <AnimationDownloadProgress>[];
    final result = await download(service(), progress: events.add);
    expect(result.downloadedBytes, 4);
    expect(await workspace.downloadFile.readAsBytes(), [1, 2, 3, 4]);
    expect(events.map((e) => e.receivedBytes), [0, 2, 4, 4]);
    expect(events.map((e) => e.fraction), [0.0, 0.5, 1.0, 1.0]);
    expect(transport.closed, isTrue);
  });
  test('unknown length streams with indeterminate progress', () async {
    respond(length: -1);
    final events = <AnimationDownloadProgress>[];
    expect(
        (await download(service(), progress: events.add)).downloadedBytes, 4);
    expect(events.every((e) => e.fraction == null && e.totalBytes == null),
        isTrue);
    expect(transport.closed, isTrue);
  });
  test('progress updates throttled with initial and final events', () async {
    respond(
        length: 20, body: Stream.fromIterable(List.generate(20, (_) => [1])));
    final events = <AnimationDownloadProgress>[];
    await download(service(progress: const Duration(days: 1)),
        progress: events.add);
    expect(events.map((e) => e.receivedBytes), [0, 20]);
  });
  test(
      'oversized header rejected before destination creation and body cancelled',
      () async {
    var cancelled = false;
    final controller = StreamController<List<int>>(onCancel: () {
      cancelled = true;
    });
    respond(length: 101, body: controller.stream);
    await expectLater(download(service()), throwsFormatException);
    expect(await workspace.downloadFile.exists(), isFalse);
    expect(cancelled, isTrue);
    expect(transport.closed, isTrue);
    await controller.close();
  });
  for (final length in [-1, 99]) {
    test('actual size cap rejects next chunk before writing, length $length',
        () async {
      respond(
          length: length,
          body: Stream.fromIterable([
            [1, 2],
            List.filled(99, 3)
          ]));
      await expectLater(download(service()), throwsFormatException);
      expect(await workspace.downloadFile.readAsBytes(), [1, 2]);
      expect(transport.closed, isTrue);
    });
  }
  for (final length in [3, 5]) {
    test('incorrect Content-Length $length rejected', () async {
      respond(length: length);
      await expectLater(download(service()), throwsFormatException);
      expect(transport.closed, isTrue);
    });
  }
  for (final status in [302, 404, 500]) {
    test('HTTP $status rejected without creating destination', () async {
      respond(status: status);
      await expectLater(download(service()), throwsA(isA<HttpException>()));
      expect(await workspace.downloadFile.exists(), isFalse);
      expect(transport.closed, isTrue);
    });
  }
  test('interrupted stream preserves only private partial bytes', () async {
    Stream<List<int>> interrupted() async* {
      yield [1, 2];
      throw const HttpException('connection lost');
    }

    respond(body: interrupted());
    await expectLater(download(service()), throwsA(isA<HttpException>()));
    expect(await workspace.downloadFile.readAsBytes(), [1, 2]);
    expect(transport.closed, isTrue);
  });
  test('stalled response times out and cancels subscription', () async {
    var cancelled = false;
    final controller = StreamController<List<int>>(onCancel: () {
      cancelled = true;
    });
    respond(length: -1, body: controller.stream);
    await expectLater(
        download(service(inactivity: const Duration(milliseconds: 10))),
        throwsA(isA<TimeoutException>()));
    expect(cancelled, isTrue);
    expect(transport.closed, isTrue);
    await controller.close();
  });
  test('request timeout closes transport without creating destination',
      () async {
    transport = _Transport(() => Completer<AnimationDownloadResponse>().future);
    await expectLater(
        download(service(request: const Duration(milliseconds: 10))),
        throwsA(isA<TimeoutException>()));
    expect(transport.closed, isTrue);
    expect(await workspace.downloadFile.exists(), isFalse);
  });
  for (final flush in [false, true]) {
    test('disk ${flush ? 'flush' : 'write'} error closes writer and transport',
        () async {
      late _Writer writer;
      final downloader = service(
          writer: (file) async => writer = _Writer(
              await file.open(mode: FileMode.writeOnlyAppend),
              failWrite: !flush,
              failFlush: flush));
      await expectLater(
          download(downloader), throwsA(isA<FileSystemException>()));
      expect(writer.closed, isTrue);
      expect(transport.closed, isTrue);
      await workspace.downloadFile.delete(); // handle released on Windows too
    });
  }
  test('writer-open failure cancels the unconsumed response body', () async {
    var cancelled = false;
    final controller = StreamController<List<int>>(onCancel: () {
      cancelled = true;
    });
    respond(body: controller.stream);
    await expectLater(
        download(service(
            writer: (_) async =>
                throw const FileSystemException('cannot open writer'))),
        throwsA(isA<FileSystemException>()));
    expect(cancelled, isTrue);
    expect(transport.closed, isTrue);
    await controller.close();
  });
  test('existing destination refused without network or mutation', () async {
    await workspace.downloadFile.writeAsString('original');
    await expectLater(download(service()), throwsA(isA<FileSystemException>()));
    expect(await workspace.downloadFile.readAsString(), 'original');
    expect(transport.opens, 0);
  });
  test('destination link refused and target preserved where supported',
      () async {
    try {
      await Link(workspace.downloadFile.path).create(sentinel.path);
    } on FileSystemException catch (e) {
      markTestSkipped('Symlinks unavailable: $e');
      return;
    }
    await expectLater(download(service()), throwsA(isA<FileSystemException>()));
    expect(await sentinel.readAsString(), 'preserve');
    expect(transport.opens, 0);
  });
  test('linked workspace ancestor refused', () async {
    final attempt = workspace.directory.path;
    final original = await workspace.directory.rename('$attempt.saved');
    try {
      await Link(attempt).create(original.path);
    } on FileSystemException catch (e) {
      markTestSkipped('Symlinks unavailable: $e');
      return;
    }
    await expectLater(download(service()), throwsA(isA<FileSystemException>()));
    expect(await File(p.join(original.path, 'download.zip')).exists(), isFalse);
  });
  test('unexpected directory destination refused', () async {
    await Directory(workspace.downloadFile.path).create();
    await expectLater(download(service()), throwsA(isA<FileSystemException>()));
    expect(transport.opens, 0);
  });
  test('invalid HTTPS URLs and nonprivate destinations rejected', () async {
    for (final value in [
      'http://example.invalid/a.zip',
      '/relative',
      'https:/missing',
      'https://user:pass@example.invalid/a.zip'
    ]) {
      await expectLater(
          service().download(
              uri: Uri.parse(value), destination: workspace.downloadFile),
          throwsArgumentError);
    }
    await expectLater(
        service().download(
            uri: uri, destination: File(p.join(root.path, 'download.zip'))),
        throwsArgumentError);
    expect(transport.opens, 0);
  });
  test('pending cancellation cannot prevent transport and writer shutdown',
      () async {
    final cancelGate = Completer<void>();
    final cancelStarted = Completer<void>();
    final controller = StreamController<List<int>>(onCancel: () {
      cancelStarted.complete();
      return cancelGate.future;
    });
    respond(body: controller.stream);
    final ready = Completer<_Writer>();
    final original = StateError('progress after data');
    final downloader = service(
        cancellation: const Duration(milliseconds: 10),
        writer: (file) async {
          final writer =
              _Writer(await file.open(mode: FileMode.writeOnlyAppend));
          ready.complete(writer);
          return writer;
        });
    final pending = download(downloader, progress: (event) {
      if (event.receivedBytes > 0) throw original;
    });
    final assertion = expectLater(pending, throwsA(same(original)));
    final writer = await ready.future;
    controller.add([1, 2]);
    await cancelStarted.future;
    await writer.closeStarted.future;
    expect(transport.closed, isTrue);
    expect(writer.closed, isTrue);
    expect(cancelGate.isCompleted, isFalse);
    await assertion; // bounded wait expires although cancellation is pending
    expect(await workspace.downloadFile.readAsBytes(), [1, 2]);
    // A late cancellation failure must be observed, not an unhandled error.
    cancelGate.completeError(StateError('late cancellation error'));
    await Future<void>.delayed(Duration.zero);
    await controller.close();
  });

  test('progress failure before consumption still closes all resources',
      () async {
    var cancelled = false;
    final controller = StreamController<List<int>>(onCancel: () {
      cancelled = true;
    });
    respond(body: controller.stream);
    late _Writer writer;
    final original = StateError('initial progress');
    await expectLater(
        download(
            service(
                writer: (file) async => writer =
                    _Writer(await file.open(mode: FileMode.writeOnlyAppend))),
            progress: (_) => throw original),
        throwsA(same(original)));
    expect(cancelled, isTrue);
    expect(writer.closed, isTrue);
    expect(transport.closed, isTrue);
    expect(await workspace.downloadFile.length(), 0);
    await controller.close();
  });

  test('cancellation exception cannot replace a progress error or skip closes',
      () async {
    final cancellationError = StateError('cancel failed');
    final original = StateError('progress failed');
    final controller = StreamController<List<int>>(
        onCancel: () => Future<void>.error(cancellationError));
    respond(body: controller.stream);
    late _Writer writer;
    await expectLater(
        download(
            service(
                writer: (file) async => writer =
                    _Writer(await file.open(mode: FileMode.writeOnlyAppend))),
            progress: (_) => throw original),
        throwsA(same(original)));
    expect(writer.closed, isTrue);
    expect(transport.closed, isTrue);
    await controller.close();
  });

  test('writer close error on success is reported after transport shutdown',
      () async {
    final error = StateError('writer close failed');
    late _Writer writer;
    await expectLater(
        download(service(
            writer: (file) async => writer = _Writer(
                await file.open(mode: FileMode.writeOnlyAppend),
                closeError: error))),
        throwsA(same(error)));
    expect(writer.closed, isTrue);
    expect(transport.closed, isTrue);
    await workspace.downloadFile.delete();
  });

  test('transport close error cannot prevent writer close', () async {
    final error = StateError('transport close failed');
    transport.closeError = error;
    late _Writer writer;
    await expectLater(
        download(service(
            writer: (file) async => writer =
                _Writer(await file.open(mode: FileMode.writeOnlyAppend)))),
        throwsA(same(error)));
    expect(writer.closed, isTrue);
    expect(transport.closed, isTrue);
    await workspace.downloadFile.delete();
  });

  test('original download failure survives writer and transport close failures',
      () async {
    final controller = StreamController<List<int>>(
        onCancel: () => Future<void>.error(StateError('cancel failed')));
    respond(body: controller.stream);
    transport.closeError = StateError('transport close failed');
    late _Writer writer;
    final ready = Completer<void>();
    final pending = download(service(writer: (file) async {
      writer = _Writer(await file.open(mode: FileMode.writeOnlyAppend),
          failWrite: true, closeError: StateError('writer close failed'));
      ready.complete();
      return writer;
    }));
    final assertion = expectLater(
        pending,
        throwsA(isA<FileSystemException>()
            .having((error) => error.message, 'message', 'disk full')));
    await ready.future;
    controller.add([1, 2]);
    await assertion;
    expect(writer.closed, isTrue);
    expect(transport.closed, isTrue);
    await controller.close();
  });

  test('writer is not closed while an awaited write remains active', () async {
    final gate = Completer<void>();
    final ready = Completer<_Writer>();
    final original = StateError('progress after awaited write');
    final pending = download(service(writer: (file) async {
      final writer =
          _Writer(await file.open(mode: FileMode.writeOnlyAppend), gate: gate);
      ready.complete(writer);
      return writer;
    }), progress: (event) {
      if (event.receivedBytes > 0) throw original;
    });
    final assertion = expectLater(pending, throwsA(same(original)));
    final writer = await ready.future;
    await writer.started.future;
    expect(writer.pending, 1);
    expect(writer.closed, isFalse);
    expect(transport.closed, isFalse);
    gate.complete();
    await assertion;
    expect(writer.pending, 0);
    expect(writer.closed, isTrue);
    expect(transport.closed, isTrue);
  });

  test('slow disk has one outstanding write and pauses response consumption',
      () async {
    var produced = 0;
    Stream<List<int>> chunks() async* {
      for (var i = 0; i < 4; i++) {
        produced++;
        yield [i];
      }
    }

    respond(body: chunks());
    final gate = Completer<void>();
    final ready = Completer<_Writer>();
    final downloader = service(writer: (file) async {
      final writer =
          _Writer(await file.open(mode: FileMode.writeOnlyAppend), gate: gate);
      ready.complete(writer);
      return writer;
    });
    final pending = download(downloader);
    final writer = await ready.future;
    await writer.started.future;
    await Future<void>.delayed(Duration.zero);
    expect(writer.writes, 1);
    expect(writer.pending, 1);
    expect(produced, 1);
    gate.complete();
    await pending;
    expect(writer.maximumPending, 1);
    expect(writer.closed, isTrue);
    expect(await workspace.downloadFile.readAsBytes(), [0, 1, 2, 3]);
  });
}
