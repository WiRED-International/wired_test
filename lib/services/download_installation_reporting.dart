import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'download_event_outbox.dart';
import 'module_installation_registry.dart';
import 'module_installation_status_service.dart';

String instructionalPublicationKey(Map record) =>
    'instructional:${record['database_id']}:${record['installed_at']}';

/// Only scans records created after this outbox's first activation. Historical
/// records are never backfilled. Existing installer transaction boundaries stay
/// untouched: a crash before registry persistence is intentionally unrecoverable.
Future<void> reconcileDownloadInstallations(DownloadEventOutbox outbox,
    {Future<bool> Function(Map<String, dynamic>)? verify}) async {
  if (!outbox.enabled) return;
  final box = outbox.box;
  if (!box.containsKey('activated_at') || box.get('paused') == 'true') {
    final historical = <String>[];
    if (Hive.isBoxOpen(ModuleInstallationRegistry.boxName)) {
      final records = Hive.box(ModuleInstallationRegistry.boxName);
      for (final key in records.keys) {
        final record = records.get(key);
        if (key is String &&
            key.startsWith('instructional-db:') &&
            record is Map) {
          historical.add(instructionalPublicationKey(record));
        }
      }
    }
    // Snapshot existing publications even if their device timestamps are in
    // the future. A gate-off run may have reported them through legacy POST.
    await box.put('baseline_publications', jsonEncode(historical));
    await box.put('activated_at', DateTime.now().toUtc().toIso8601String());
    await box.delete('paused');
    await box.flush();
  }
  if (!Hive.isBoxOpen(ModuleInstallationRegistry.boxName)) return;
  final since = DateTime.parse(box.get('activated_at')!);
  final baseline =
      (jsonDecode(box.get('baseline_publications') ?? '[]') as List)
          .whereType<String>()
          .toSet();
  final registry = ModuleInstallationRegistry();
  final records = Hive.box(ModuleInstallationRegistry.boxName);
  for (final key in records.keys.toList()) {
    if (key is! String || !key.startsWith('instructional-db:')) continue;
    try {
      final id = int.parse(key.substring('instructional-db:'.length));
      final record = await registry.getInstructionalInstallation(id);
      if (record == null ||
          record['provenance'] != 'new-install' ||
          DateTime.parse(record['installed_at'] as String).isBefore(since)) {
        continue;
      }
      final publicationKey = instructionalPublicationKey(record);
      if (baseline.contains(publicationKey)) continue;
      if (box.containsKey('event:$publicationKey')) continue;
      final verified = verify != null
          ? await verify(record)
          : (await ModuleInstallationStatusService().inspectInstallation(
                databaseId: id,
                moduleId: record['module_id'] as String,
                moduleName: '',
              ))
                  .state ==
              InstructionalInstallationState.confirmed;
      if (verified) {
        // No historical/current location lookup. Recovery always uses null.
        await outbox.enqueue(id, null, installationKey: publicationKey);
      }
    } catch (e) {
      debugPrint('Download installation reconciliation skipped $key: $e');
    }
  }
}

/// Configured at startup; a failed attempt is cleared so reporting can retry.
Future<DownloadEventOutbox> Function()? initializeDownloadOutbox;
Future<DownloadEventOutbox>? _initializingOutbox;

Future<DownloadEventOutbox> ensureDownloadOutbox() async {
  final current = DownloadEventOutbox.current;
  if (current != null && current.available) return current;
  final pending = _initializingOutbox;
  if (pending != null) return pending;
  final initialize = initializeDownloadOutbox;
  if (initialize == null) {
    throw StateError('Download outbox initialization is not configured');
  }
  final completer = Completer<DownloadEventOutbox>();
  _initializingOutbox = completer.future;
  // Publish the shared future before calling the initializer.
  unawaited(() async {
    try {
      final outbox = await initialize();
      if (!outbox.available) throw StateError('Download outbox is unavailable');
      DownloadEventOutbox.current = outbox;
      completer.complete(outbox);
    } catch (error, stack) {
      debugPrint('Download outbox initialization failed; retry is possible, '
          'but events are not durable while storage is unavailable: $error');
      completer.completeError(error, stack);
    } finally {
      _initializingOutbox = null;
    }
  }());
  return completer.future;
}

/// Completes only after persistence, or throws. Callers isolate reporting errors
/// from installation results. Never substitutes a key from a registry read.
Future<void> queueInstalledDownload(int id, Map<String, double?>? location,
    {required String publicationKey}) async {
  try {
    if (publicationKey.isEmpty) {
      throw StateError('Confirmed publication identity unavailable; '
          'reporting requires retry with the installation identity');
    }
    final outbox = await ensureDownloadOutbox();
    await outbox.enqueue(id, location, installationKey: publicationKey);
  } catch (error) {
    debugPrint('Download event NOT acknowledged as queued: $error');
    rethrow;
  }
}

/// The opt-in is separate from anonymous counting. Never invokes a permission
/// or position API for an explicit decline. Bound location waiting, not access.
Future<Map<String, double?>?> optionalDownloadCoordinates({
  required bool consent,
  required Future<Map<String, double?>?> Function() locate,
}) async {
  if (!consent) return null;
  try {
    return await locate().timeout(const Duration(seconds: 15));
  } catch (_) {
    return null;
  }
}

// Body serialization lives only in the outbox; retries never call this layer.
// Keep this library independent of exam and CME queues.
