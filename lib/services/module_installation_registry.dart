import 'package:hive/hive.dart';

/// Stores information about modules installed by the new downloader.
class ModuleInstallationRegistry {
  static const String boxName = 'module_installations';

  /// Opens the installation registry if it is not already open.
  Future<Box> openRegistry() async {
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
