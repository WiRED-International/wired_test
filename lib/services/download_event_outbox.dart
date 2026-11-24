import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

/// Enable ONLY after the configured backend supports idempotent event_id.
/// Off by default in every build, including production.
const downloadEventOutboxEnabled =
    bool.fromEnvironment('DOWNLOAD_EVENT_OUTBOX_ENABLED', defaultValue: false);

String downloadEventUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// One application-isolate owner. Delivered/permanent entries are retained as
/// installation receipts so reconciliation cannot recreate acknowledged events.
class DownloadEventOutbox with WidgetsBindingObserver {
  DownloadEventOutbox(this.box,
      {required this.endpoint,
      http.Client? client,
      DateTime Function()? now,
      this.enabled = downloadEventOutboxEnabled,
      this.timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  static DownloadEventOutbox? current;
  static const boxName = 'download_event_outbox';
  final Box<String> box;
  final Uri endpoint;
  final bool enabled;
  final Duration timeout;
  final http.Client _client;
  final DateTime Function() _now;
  Future<void> _writes = Future.value();
  bool _delivering = false;
  bool _disposed = false;
  bool _started = false;
  bool get available => enabled && !_disposed;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _writes.then((_) => work());
    _writes = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// UUID and serialized body are written atomically in the same Hive value.
  /// installationKey identifies one publication, not one module forever.
  Future<void> enqueue(int moduleId, Map<String, double?>? location,
          {required String installationKey}) =>
      _serial(() async {
        if (_disposed) throw StateError('Download outbox is disposed');
        if (!enabled) return;
        if (moduleId <= 0 || installationKey.isEmpty) {
          throw ArgumentError(
              'A database module ID and publication key are required');
        }
        final key = 'event:$installationKey';
        if (box.containsKey(key)) {
          // A previous put may have succeeded before flush failed.
          await box.flush();
          if (_started) kick();
          return;
        }
        final id = downloadEventUuid();
        final body = jsonEncode({
          'event_id': id,
          'module_id': moduleId,
          'latitude': location?['latitude'],
          'longitude': location?['longitude'],
        });
        await box.put(
            key,
            jsonEncode({
              'event_id': id,
              'payload_json': body,
              'created_at': _now().toUtc().toIso8601String(),
              'status': 'pending',
              'attempts': 0,
              'next_attempt_at': _now().toUtc().toIso8601String(),
            }));
        await box.flush();
        if (_started) kick();
      });

  /// Startup, foreground, connectivity, and timer are merely delivery hints.
  /// The single drain guard also protects against duplicate in-flight requests.
  void start() {
    if (!enabled || _disposed || _started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      _connectivity = Connectivity().onConnectivityChanged.listen((results) {
        if (results.any((r) => r != ConnectivityResult.none)) kick();
      },
          onError: (Object e) =>
              debugPrint('Download connectivity unavailable: $e'));
    } catch (e) {
      debugPrint('Download connectivity unavailable: $e');
    }
    kick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) kick();
  }

  void kick() {
    if (!enabled || _disposed) return;
    unawaited(deliver().catchError((Object e) {
      debugPrint('Download outbox delivery unavailable: $e');
    }));
  }

  Future<void> deliver() async {
    if (!enabled || _disposed || _delivering) return;
    _delivering = true;
    try {
      for (final key in box.keys.toList()) {
        if (_disposed || key is! String || !key.startsWith('event:')) continue;
        late Map<String, dynamic> entry;
        try {
          entry = Map<String, dynamic>.from(jsonDecode(box.get(key)!) as Map);
          if (entry['status'] == 'pending') {
            DateTime.parse(entry['next_attempt_at'] as String);
            if (entry['payload_json'] is! String || entry['attempts'] is! int) {
              throw const FormatException('Invalid queued event');
            }
          }
        } catch (e) {
          debugPrint('Download outbox entry requires inspection: $key ($e)');
          continue;
        }
        if (entry['status'] != 'pending' ||
            DateTime.parse(entry['next_attempt_at'] as String)
                .isAfter(_now())) {
          continue;
        }
        int? status;
        String? error;
        final abort = Completer<void>();
        try {
          final request = http.AbortableRequest('POST', endpoint,
              abortTrigger: abort.future)
            ..headers['Content-Type'] = 'application/json'
            ..body = entry['payload_json'] as String;
          final response = await (() async =>
                  http.Response.fromStream(await _client.send(request)))()
              .timeout(timeout, onTimeout: () {
            abort.complete();
            throw TimeoutException('Download event request timed out');
          });
          status = response.statusCode;
          error = status == 200 ? null : 'HTTP $status';
        } catch (e) {
          error = e.runtimeType.toString();
        }
        final attempts = (entry['attempts'] as int) + 1;
        entry['attempts'] = attempts;
        entry['last_attempt_at'] = _now().toUtc().toIso8601String();
        entry['last_status'] = status;
        entry['last_error'] = error;
        if (status == 200) {
          entry['status'] = 'delivered';
        } else if (status != null &&
            status != 408 &&
            status != 429 &&
            status < 500) {
          // Includes 400/409; retain evidence for inspection, never auto-retry.
          entry['status'] = 'permanent_failure';
        } else {
          final seconds = min(3600, 5 * pow(2, min(attempts - 1, 10)).toInt());
          entry['next_attempt_at'] =
              _now().add(Duration(seconds: seconds)).toUtc().toIso8601String();
        }
        await _serial(() async {
          await box.put(key, jsonEncode(entry));
          await box.flush();
        });
      }
    } finally {
      _delivering = false;
      _timer?.cancel();
      if (!_disposed && enabled && _started) {
        Duration? delay;
        for (final key in box.keys.whereType<String>()) {
          if (!key.startsWith('event:')) continue;
          try {
            final entry = jsonDecode(box.get(key)!) as Map;
            if (entry['status'] != 'pending') continue;
            final remaining = DateTime.parse(entry['next_attempt_at'] as String)
                .difference(_now());
            final candidate = remaining < const Duration(seconds: 5)
                ? const Duration(seconds: 5)
                : remaining;
            if (delay == null || candidate < delay) delay = candidate;
          } catch (_) {
            // Corrupt entries remain available for inspection.
          }
        }
        if (delay != null) _timer = Timer(delay, kick);
      }
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_connectivity?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _client.close();
  }
}
