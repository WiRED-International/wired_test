import 'dart:io';
import 'dart:async';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

/// Stores information about modules installed by the new downloader.
class ModuleInstallationRegistry {
  static const String boxName = 'module_installations';
  static Future<Box>? _initializing;
  static bool _requiresExplicitRetry = false;

  /// Explicit session initialization after global Hive setup. On native
  /// platforms [storageDirectory] must be the directory of an already-open Hive
  /// box, not a new path. Null is reserved for backends without filesystem paths.
  /// This does not change Hive's configured directory or close the resulting box.
  Future<Box> initialize({required String? storageDirectory}) {
    final pending = _initializing;
    if (pending != null) return pending;
    if (Hive.isBoxOpen(boxName)) {
      _requiresExplicitRetry = false;
      return Future.value(Hive.box(boxName));
    }
    // Defer work until the shared Future has been assigned, including failures.
    final opening = Future<Box>(() async {
      if (storageDirectory != null) {
        final artifact = p.join(storageDirectory, '$boxName.hivec');
        if (await FileSystemEntity.type(artifact, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw HiveError('Registry recovery artifact requires review: $artifact');
        }
      }
      return _openForSession();
    });
    final result = opening.then((box) {
      _initializing = null;
      _requiresExplicitRetry = false;
      return box;
    }, onError: (Object error, StackTrace stack) {
      _initializing = null;
      _requiresExplicitRetry = true;
      Error.throwWithStackTrace(error, stack);
    });
    _initializing = result;
    return result;
  }

  static Future<Box> _openForSession() {
    final completion = Completer<Box>();
    // Hive 2.2.3 also completes an internal opening-box Future with an error.
    // With no Hive-level waiter that error escapes the returned openBox Future.
    // Contain it in the initialization operation, not in the application zone.
    runZonedGuarded(() async {
      try {
        final box = await Hive.openBox(boxName,
            crashRecovery: false,
            compactionStrategy: (entries, deletedEntries) => false);
        if (!completion.isCompleted) completion.complete(box);
      } catch (error, stack) {
        if (!completion.isCompleted) completion.completeError(error, stack);
      }
    }, (error, stack) {
      if (!completion.isCompleted) completion.completeError(error, stack);
    });
    return completion.future;
  }

  /// Read-only snapshot of the requested identity and overlapping path claims.
  /// Never opens a box: opening Hive can create/repair files. An existing closed
  /// box must be initialized by its owner before inspection can proceed.
  /// Malformed instructional records fail conservatively; numeric keys are ignored.
  Future<List<Map<String, dynamic>>> inspectInstructionalClaims({
    int? databaseId,
    Iterable<String> paths = const [],
  }) async {
    if (databaseId != null) _instructionalKey(databaseId);
    if (!Hive.isBoxOpen(boxName)) {
      if (!await Hive.boxExists(boxName)) return [];
      throw HiveError('Installation registry is closed; inspection cannot open it');
    }
    final box = Hive.box(boxName);
    final matches = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('instructional-db:')) continue;
      final id = int.tryParse(key.substring('instructional-db:'.length));
      final record = box.get(key);
      if (id == null || id <= 0 || key != _instructionalKey(id) ||
          record is! Map || !_validInstructionalRecord(record, id)) {
        throw FormatException('Malformed instructional registry claim: $key');
      }
      final claimed = ['content_directory', 'entry_point_path', 'launcher_path']
          .map((field) => record[field]).whereType<String>();
      final overlaps = paths.any((path) => claimed.any((claim) {
        if (!p.isAbsolute(path) || !p.isAbsolute(claim)) return false;
        final a = p.normalize(path);
        final b = p.normalize(claim);
        return p.equals(a, b) || p.isWithin(a, b) || p.isWithin(b, a);
      }));
      if (id == databaseId || overlaps) {
        matches.add(Map<String, dynamic>.from(record));
      }
    }
    return matches;
  }

  static String _instructionalKey(int databaseId) {
    if (databaseId <= 0) {
      throw ArgumentError.value(
          databaseId, 'databaseId', 'Expected positive ID');
    }
    return 'instructional-db:$databaseId';
  }

  /// Records identity and locators only; this does not verify files or establish
  /// installed status. Callers must verify recorded filesystem paths before use.
  /// Existing numeric content-ID records are deliberately left untouched.
  /// [format] must be `storyline` or `compiler`. A launcher is optional for
  /// Storyline only. Omit [version] when the installed version is unknown.
  Future<void> saveInstructionalInstallation({
    required int databaseId,
    required String moduleId,
    required String format,
    required String contentDirectory,
    required String entryPointPath,
    String? launcherPath,
    String? version,
    required String provenance,
  }) async {
    final key = _instructionalKey(databaseId);
    final record = <String, dynamic>{
      'schema_version': 1,
      'database_id': databaseId,
      'module_id': moduleId,
      'format': format,
      'content_directory': contentDirectory,
      'entry_point_path': entryPointPath,
      if (launcherPath != null) 'launcher_path': launcherPath,
      if (version != null) 'version': version,
      'installed_at': DateTime.now().toUtc().toIso8601String(),
      'provenance': provenance,
    };
    if (!_validInstructionalRecord(record, databaseId)) {
      throw ArgumentError('Invalid instructional installation fields');
    }
    final box = await openRegistry();
    await box.put(key, record);
  }

  /// Returns metadata, not an installed-status assertion. Malformed or unknown
  /// schema versions fail explicitly rather than being treated as absent.
  Future<Map<String, dynamic>?> getInstructionalInstallation(
      int databaseId) async {
    final key = _instructionalKey(databaseId);
    final box = await openRegistry();
    if (!box.containsKey(key)) return null;
    final record = box.get(key);
    if (record is! Map || !_validInstructionalRecord(record, databaseId)) {
      throw StateError(
          'Invalid instructional installation record for $databaseId');
    }
    return Map<String, dynamic>.from(record);
  }

  /// Removes only this association. Installed files are never touched.
  Future<void> removeInstructionalInstallation(int databaseId) async {
    final key = _instructionalKey(databaseId);
    final box = await openRegistry();
    await box.delete(key);
  }

  static bool _validInstructionalRecord(Map record, int databaseId) {
    bool nonblank(dynamic value) => value is String && value.trim().isNotEmpty;
    if (record.keys.any((key) => key is! String) ||
        record['schema_version'] is! int ||
        record['schema_version'] != 1 ||
        record['database_id'] is! int ||
        record['database_id'] != databaseId ||
        !['storyline', 'compiler'].contains(record['format'])) {
      return false;
    }
    for (final field in [
      'module_id',
      'content_directory',
      'entry_point_path',
      'provenance',
      'installed_at',
    ]) {
      if (!nonblank(record[field])) return false;
    }
    for (final field in ['launcher_path', 'version']) {
      if (record.containsKey(field) && !nonblank(record[field])) return false;
    }
    if (record['format'] == 'compiler' && record.containsKey('launcher_path')) {
      return false;
    }
    return DateTime.tryParse(record['installed_at'] as String) != null;
  }

  /// Opens the installation registry if it is not already open.
  Future<Box> openRegistry() async {
    final pending = _initializing;
    if (pending != null) return pending;
    if (_requiresExplicitRetry) {
      throw HiveError('Registry initialization failed; explicit initialization '
          'retry is required before registry access');
    }
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }

    return Hive.openBox(boxName);
  }

  /// Returns the saved installation record for a module.
  Future<Map<String, dynamic>?> getInstallation(
      String moduleId,
      ) async {
    final box = await openRegistry();
    final record = box.get(moduleId);

    if (record == null) {
      return null;
    }

    if (record is! Map) {
      throw StateError(
        'Invalid installation record for module $moduleId',
      );
    }

    return Map<String, dynamic>.from(record);
  }

  /// Saves a successfully installed module in the registry.
  ///
  /// Module IDs are used as unique keys, so updating an
  /// existing installation replaces its previous record.
  Future<void> saveInstallation({
    required String moduleId,
    required String version,
    required String installationPath,
  }) async {
    if (!RegExp(r'^[0-9]+$').hasMatch(moduleId)) {
      throw ArgumentError('Invalid module ID: $moduleId');
    }

    if (installationPath.trim().isEmpty) {
      throw ArgumentError('Installation path cannot be empty');
    }

    final box = await openRegistry();

    await box.put(moduleId, {
      'module_id': moduleId,
      'version': version,
      'installation_path': installationPath,
      'installed_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Restores a previously saved installation record.
  ///
  /// A null previous record means the module was not
  /// registered before the attempted installation.
  Future<void> restoreInstallationRecord({
    required String moduleId,
    required Map<String, dynamic>? previousRecord,
  }) async {
    if (!RegExp(r'^[0-9]+$').hasMatch(moduleId)) {
      throw ArgumentError('Invalid module ID: $moduleId');
    }

    final box = await openRegistry();

    if (previousRecord == null) {
      await box.delete(moduleId);
      return;
    }

    if (previousRecord['module_id']?.toString() != moduleId) {
      throw ArgumentError(
        'Previous record does not match module $moduleId',
      );
    }

    await box.put(moduleId, Map<String, dynamic>.from(previousRecord));
  }

}
