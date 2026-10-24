import 'dart:io';
import 'module_download_service.dart';
import 'module_installation_registry.dart';

/// Coordinates module installation and persistent registry updates.
class ModuleInstallationCoordinator {
  final ModuleDownloadService downloadService;
  final ModuleInstallationRegistry registry;

  ModuleInstallationCoordinator({
    ModuleDownloadService? downloadService,
    ModuleInstallationRegistry? registry,
  })  : downloadService = downloadService ?? ModuleDownloadService(),
        registry = registry ?? ModuleInstallationRegistry();

  /// Returns the current filesystem and registry information
  /// for a module without changing its installation.
  Future<Map<String, dynamic>> inspectInstallation(
      String moduleId,
      ) async {
    final filesystemState =
    await downloadService.getModuleInstallationState(moduleId);

    final registryRecord =
    await registry.getInstallation(moduleId);

    return {
      'module_id': moduleId,
      'filesystem_state': filesystemState,
      'registry_record': registryRecord,
    };
  }

  /// Checks whether a module is ready for installation.
  ///
  /// Prevents a new installation from starting when an
  /// earlier replacement still requires recovery.
  Future<void> ensureReadyForInstallation(String moduleId) async {
    final installation = await inspectInstallation(moduleId);

    final filesystemState =
    installation['filesystem_state'] as String;

    if (filesystemState == 'replacement_pending' ||
        filesystemState == 'restore_required') {
      throw StateError(
        'Module $moduleId has an unresolved installation '
            'state: $filesystemState. Recovery is required '
            'before another installation can begin.',
      );
    }

    final registryRecord = installation['registry_record'];

    if (filesystemState == 'not_installed' &&
        registryRecord != null) {
      throw StateError(
        'Module $moduleId has a registry record but '
            'its installation directory is missing.',
      );
    }

    if (filesystemState == 'installed' &&
        registryRecord == null) {
      throw StateError(
        'Module $moduleId has installed files but '
            'no installation registry record. '
            'Recovery is required before another '
            'installation can begin.',
      );
    }
  }

  /// Validates a staged module and checks whether installation
  /// can proceed without disturbing an existing installation.
  Future<void> prepareInstallation(String moduleId) async {
    // Check for unresolved backups or missing installed files.
    await ensureReadyForInstallation(moduleId);

    // Locate the staged module.
    final stagingDirectory =
    await downloadService.getStagingDirectory(moduleId);

    if (!await stagingDirectory.exists()) {
      throw StateError(
        'No staged module exists for module $moduleId',
      );
    }

    // Verify the module contents before making any changes.
    await downloadService.validateExtractedModule(
      moduleId: moduleId,
      stagingDirectory: stagingDirectory,
    );
  }

  /// Installs a staged module and records it in Hive.
  ///
  /// Preserves the previous installation until the registry
  /// has been updated successfully.
  Future<Directory> installModule({
    required String moduleId,
    required String version,
  }) async {
    await prepareInstallation(moduleId);

    final moduleDirectory =
    await downloadService.getModuleDirectory(moduleId);

    final backupDirectory =
    await downloadService.getModuleBackupDirectory(moduleId);

    final previousRecord =
    await registry.getInstallation(moduleId);

    // Back up the existing installation, if any, and
    // install the validated replacement.
    final installedDirectory =
    await downloadService.replaceModule(moduleId);

    try {
      // Record the new installation before removing its backup.
      await registry.saveInstallation(
        moduleId: moduleId,
        version: version,
        installationPath: installedDirectory.path,
      );

    } catch (_) {
      // Attempt to restore the previous Hive record.
      // A registry failure must not prevent filesystem recovery.
      try {
        await registry.restoreInstallationRecord(
          moduleId: moduleId,
          previousRecord: previousRecord,
        );
      } catch (registryError) {
        // Preserve the original installation error.
        // Filesystem recovery must still be attempted.
      }

      // Restore the previous module if a backup exists.
      if (await backupDirectory.exists()) {
        if (await moduleDirectory.exists()) {
          await moduleDirectory.delete(recursive: true);
        }

        await downloadService.restoreModuleBackup(moduleId);
      } else if (previousRecord == null &&
          await moduleDirectory.exists()) {
        // Failed first-time installation with no previous module.
        await moduleDirectory.delete(recursive: true);
      }

      rethrow;
    }

    // Installation and Hive registration succeeded.
    // The previous version is no longer needed.
    if (await backupDirectory.exists()) {
      try {
        await backupDirectory.delete(recursive: true);
      } on FileSystemException {
        // Keep the successfully installed module.
        // A later cleanup can remove the leftover backup.
      }
    }

    return installedDirectory;
  }

}
