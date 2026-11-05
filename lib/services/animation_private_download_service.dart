import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'animation_zip_metadata_reader.dart';

class AnimationDownloadResult {
  const AnimationDownloadResult(this.downloadedBytes);
  final int downloadedBytes;
}

class AnimationDownloadProgress {
  const AnimationDownloadProgress(this.receivedBytes, this.totalBytes);
  final int receivedBytes;
  final int? totalBytes;
  double? get fraction => totalBytes == null || totalBytes == 0
      ? null
      : (receivedBytes / totalBytes!).clamp(0.0, 1.0);
}

/// One transport instance per download, owned and closed by the service.
/// close() must synchronously initiate shutdown, including pending open()
/// operations and responses arriving after a request timeout. A timeout does
/// not cancel an arbitrary injected Future; its transport owns late resources.
abstract class AnimationDownloadTransport {
  Future<AnimationDownloadResponse> open(Uri uri);
  void close();
}

class AnimationDownloadResponse {
  const AnimationDownloadResponse(
      {required this.statusCode,
      required this.contentLength,
      required this.body});
  final int statusCode;

  /// -1 indicates unknown length, matching HttpClientResponse.
  final int contentLength;
  final Stream<List<int>> body;
}

/// A writer must finish each write before completing its Future and retain no
/// queued chunks afterward. Injection is for tests; the service owns the file.
abstract class AnimationDownloadWriter {
  Future<void> write(List<int> bytes);
  Future<void> flush();
  Future<void> close();
}

class AnimationPrivateDownloadService {
  AnimationPrivateDownloadService({
    this.limits = const AnimationZipLimits(),
    this.requestTimeout = const Duration(seconds: 30),
    this.inactivityTimeout = const Duration(seconds: 45),
    this.progressInterval = const Duration(milliseconds: 100),
    this.cancellationTimeout = const Duration(seconds: 5),
    AnimationDownloadTransport Function()? transportFactory,
    Future<AnimationDownloadWriter> Function(File)? writerFactory,
  })  : _transportFactory =
            transportFactory ?? (() => _HttpTransport(requestTimeout)),
        _writerFactory = writerFactory ?? _FileWriter.open;

  final AnimationZipLimits limits;
  final Duration requestTimeout, inactivityTimeout, progressInterval;
  final Duration cancellationTimeout;
  final AnimationDownloadTransport Function() _transportFactory;
  final Future<AnimationDownloadWriter> Function(File) _writerFactory;

  /// Downloads only to an existing `animation_installations/<attempt>/` folder.
  /// The caller must exclusively own that workspace. Partial files are retained
  /// on failure for its ownership-checked cleanup; this service deletes nothing.
  Future<AnimationDownloadResult> download({
    required Uri uri,
    required File destination,
    void Function(AnimationDownloadProgress)? onProgress,
  }) async {
    limits.validate();
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw ArgumentError.value(uri, 'uri', 'Expected HTTPS URL');
    }
    if (requestTimeout <= Duration.zero ||
        inactivityTimeout <= Duration.zero ||
        progressInterval < Duration.zero ||
        cancellationTimeout <= Duration.zero) {
      throw ArgumentError('Invalid download timing');
    }
    final target = File(p.normalize(destination.absolute.path));
    final attempt = target.parent;
    final parent = attempt.parent;
    final root = parent.parent;
    if (p.basename(target.path) != 'download.zip' ||
        p.basename(parent.path) != 'animation_installations' ||
        !RegExp(r'^[1-9][0-9]*-.+$').hasMatch(p.basename(attempt.path))) {
      throw ArgumentError(
          'Destination must be a private animation workspace ZIP');
    }
    Future<void> checkPaths() async {
      // Platform-selected root is trusted; do not reject OS aliases above it.
      for (final directory in [root, parent, attempt]) {
        if (await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          throw FileSystemException(
              'Unsafe download workspace', directory.path);
        }
      }
      if (await FileSystemEntity.type(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException(
            'Download destination already exists', target.path);
      }
    }

    await checkPaths();
    final transport = _transportFactory();
    AnimationDownloadWriter? writer;
    StreamIterator<List<int>>? body;
    Stream<List<int>>? responseBody;
    var iteratorStarted = false;
    Object? primaryError;
    try {
      final response = await transport.open(uri).timeout(requestTimeout);
      responseBody = response.body;
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      if (response.contentLength < -1 ||
          response.contentLength > limits.maxZipBytes) {
        throw const FormatException('Invalid or oversized Content-Length');
      }
      body = StreamIterator(response.body.timeout(inactivityTimeout));
      await checkPaths();
      // Exclusive creation refuses regular files, links and other destinations.
      // Append-open afterward avoids truncation. As with the workspace service,
      // hostile replacement between path checks is outside this API's guarantee.
      await target.create(exclusive: true);
      writer = await _writerFactory(target);
      var received = 0;
      final total = response.contentLength < 0 ? null : response.contentLength;
      final clock = Stopwatch()..start();
      var lastProgress = Duration.zero;
      void report() =>
          onProgress?.call(AnimationDownloadProgress(received, total));
      report();
      iteratorStarted = true;
      while (await body.moveNext()) {
        final chunk = body.current;
        if (chunk.length > limits.maxZipBytes - received) {
          throw const FormatException(
              'Animation download exceeds ZIP size limit');
        }
        if (total != null && chunk.length > total - received) {
          throw const FormatException(
              'Animation download exceeds Content-Length');
        }
        // StreamIterator pauses between moveNext calls. Awaited writes provide
        // backpressure instead of unbounded IOSink.add buffering.
        await writer.write(chunk);
        received += chunk.length;
        if (clock.elapsed - lastProgress >= progressInterval) {
          report();
          lastProgress = clock.elapsed;
        }
      }
      if (total != null && received != total) {
        throw const FormatException('Animation download was incomplete');
      }
      await writer.flush();
      report();
      return AnimationDownloadResult(received);
    } catch (error) {
      primaryError = error;
      rethrow;
    } finally {
      // Observe cancellation errors immediately, including errors arriving
      // after the bounded wait expires. Never block other closes on cancel().
      Object? cleanupError;
      final cancellation = Future<void>.sync(() async {
        await body?.cancel();
        // StreamIterator subscribes lazily on its first moveNext.
        if (!iteratorStarted) await responseBody?.listen(null).cancel();
      }).then<Object?>((_) => null,
          onError: (Object error, StackTrace stack) => error);
      try {
        transport.close();
      } catch (error) {
        cleanupError = error;
      }
      try {
        await writer?.close();
      } catch (error) {
        cleanupError ??= error;
      }
      // All write/flush Futures are awaited in the operation above, so no
      // active write races writer.close(). A stuck writer is not force-closed.
      final cancellationError = await cancellation.timeout(cancellationTimeout,
          onTimeout: () => TimeoutException('Response cancellation timed out'));
      cleanupError ??= cancellationError;
      if (primaryError == null && cleanupError != null) throw cleanupError;
    }
  }
}

class _HttpTransport implements AnimationDownloadTransport {
  _HttpTransport(this.timeout) {
    _client.connectionTimeout = timeout;
    _client.autoUncompress = false;
  }
  final Duration timeout;
  final HttpClient _client = HttpClient();

  @override
  Future<AnimationDownloadResponse> open(Uri uri) async {
    final request = await _client.getUrl(uri).timeout(timeout);
    // Reject redirects rather than permitting an HTTPS-to-HTTP downgrade.
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final response = await request.close().timeout(timeout);
    return AnimationDownloadResponse(
        statusCode: response.statusCode,
        contentLength: response.contentLength,
        body: response);
  }

  @override
  void close() => _client.close(force: true);
}

class _FileWriter implements AnimationDownloadWriter {
  _FileWriter(this.file);
  final RandomAccessFile file;
  static Future<AnimationDownloadWriter> open(File path) async =>
      _FileWriter(await path.open(mode: FileMode.writeOnlyAppend));
  @override
  Future<void> write(List<int> bytes) async {
    await file.writeFrom(bytes);
  }

  @override
  Future<void> flush() async {
    await file.flush();
  }

  @override
  Future<void> close() => file.close();
}
