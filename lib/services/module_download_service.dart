import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'dart:convert';
import 'dart:isolate';

/// Manages storage locations for HealthMAP modules.
///
/// All new compiler-generated modules will eventually be
/// downloaded, validated, and installed through this service.
class ModuleDownloadService {
  /// Uses the same storage location as the existing
  /// HealthMAP module downloader.
  Future<Directory> getBaseDirectory() async {
    Directory? baseDirectory;

    try {
      baseDirectory = await getExternalStorageDirectory();
    } catch (_) {
      // Fall back to internal application storage.
    }

    return baseDirectory ?? await getApplicationDocumentsDirectory();
  }

  /// Permanent location for installed modules.
  Future<Directory> getModulesDirectory() async {
    final baseDirectory = await getBaseDirectory();
    final directory = Directory('${baseDirectory.path}/modules');

    await directory.create(recursive: true);
    return directory;
  }

  /// Temporary location for ZIP downloads and extraction.
  Future<Directory> getDownloadsDirectory() async {
    final baseDirectory = await getBaseDirectory();
    final directory = Directory('${baseDirectory.path}/module_downloads');

    await directory.create(recursive: true);
    return directory;
  }

  /// Permanent installation directory for a specific module.
  ///
  /// Uses module_id rather than the ZIP filename.
  Future<Directory> getModuleDirectory(String moduleId) async {
    if (!RegExp(r'^[0-9]+$').hasMatch(moduleId)) {
      throw ArgumentError('Invalid module ID: $moduleId');
    }

    final modulesDirectory = await getModulesDirectory();

    return Directory('${modulesDirectory.path}/$moduleId');
  }

  /// Downloads a module ZIP to temporary storage.
  ///
  /// This method does not extract or install the module.
  Future<File> downloadModuleZip({
    required String moduleId,
    required String downloadUrl,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // Validate the module identifier.
    if (!RegExp(r'^[0-9]+$').hasMatch(moduleId)) {
      throw ArgumentError('Invalid module ID: $moduleId');
    }

    final uri = Uri.tryParse(downloadUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty) {
      throw ArgumentError('Invalid HTTPS download URL');
    }

    final downloadsDirectory = await getDownloadsDirectory();
    final zipFile = File(
      '${downloadsDirectory.path}/$moduleId.zip',
    );

    final dio = Dio();

    try {
      await dio.download(
        downloadUrl,
        zipFile.path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call(received / total);
          }
        },
      );

      if (!await zipFile.exists() ||
          await zipFile.length() == 0) {
        throw StateError('Downloaded ZIP is missing or empty');
      }

      return zipFile;
    } catch (_) {
      // Remove incomplete downloads for now.
      // We'll retain partial files when resume support is added.
      if (await zipFile.exists()) {
        await zipFile.delete();
      }
      rethrow;
    } finally {
      dio.close();
    }
  }

  /// Temporary directory used to extract a module before installation.
  ///
  /// Never extracts directly into the permanent modules directory.
  Future<Directory> getStagingDirectory(String moduleId) async {
    if (!RegExp(r'^[0-9]+$').hasMatch(moduleId)) {
      throw ArgumentError('Invalid module ID: $moduleId');
    }

    final downloadsDirectory = await getDownloadsDirectory();

    return Directory(
      '${downloadsDirectory.path}/$moduleId.staging',
    );
  }

  /// Backup location for an existing module during replacement.
  ///
  /// The backup is kept until the new installation is confirmed.
  Future<Directory> getModuleBackupDirectory(String moduleId) async {
    if (!RegExp(r'^[0-9]+$').hasMatch(moduleId)) {
      throw ArgumentError('Invalid module ID: $moduleId');
    }

    final modulesDirectory = await getModulesDirectory();

    return Directory(
      '${modulesDirectory.path}/$moduleId.backup',
    );
  }

  /// Moves an existing module into its backup directory.
  ///
  /// Does nothing if the module has not been installed.
  /// Refuses to overwrite an existing backup.
  Future<bool> backupExistingModule(String moduleId) async {
    final moduleDirectory = await getModuleDirectory(moduleId);
    final backupDirectory = await getModuleBackupDirectory(moduleId);

    if (await backupDirectory.exists()) {
      throw StateError(
        'Backup already exists for module $moduleId',
      );
    }

    if (!await moduleDirectory.exists()) {
      return false;
    }

    await moduleDirectory.rename(backupDirectory.path);

    return true;
  }

  /// Restores a previously backed-up module.
  ///
  /// Refuses to overwrite an existing installation.
  /// Returns false when no backup exists.
  Future<bool> restoreModuleBackup(String moduleId) async {
    final moduleDirectory = await getModuleDirectory(moduleId);
    final backupDirectory = await getModuleBackupDirectory(moduleId);

    if (!await backupDirectory.exists()) {
      return false;
    }

    if (await moduleDirectory.exists()) {
      throw StateError(
        'Cannot restore module $moduleId: '
            'installation directory already exists',
      );
    }

    await backupDirectory.rename(moduleDirectory.path);

    return true;
  }

  /// Installs a validated module from its staging directory.
  ///
  /// Refuses to overwrite an existing installation.
  /// Existing modules must be backed up before replacement.
  Future<Directory> installStagedModule(String moduleId) async {
    final stagingDirectory = await getStagingDirectory(moduleId);
    final moduleDirectory = await getModuleDirectory(moduleId);

    if (!await stagingDirectory.exists()) {
      throw StateError(
        'No staged module exists for module $moduleId',
      );
    }

    if (await moduleDirectory.exists()) {
      throw StateError(
        'Module $moduleId is already installed',
      );
    }

    // Validate before moving anything into permanent storage.
    await validateExtractedModule(
      moduleId: moduleId,
      stagingDirectory: stagingDirectory,
    );

    await stagingDirectory.rename(moduleDirectory.path);

    return moduleDirectory;
  }

  /// Replaces an installed module with a validated staged version.
  ///
  /// Keeps the backup until the caller confirms that the
  /// installation has been recorded successfully.
  Future<Directory> replaceModule(String moduleId) async {
    final stagingDirectory = await getStagingDirectory(moduleId);
    final moduleDirectory = await getModuleDirectory(moduleId);
    final backupDirectory = await getModuleBackupDirectory(moduleId);

    // Validate the replacement before touching the installed module.
    await validateExtractedModule(
      moduleId: moduleId,
      stagingDirectory: stagingDirectory,
    );

    // Never overwrite a backup from an interrupted installation.
    if (await backupDirectory.exists()) {
      throw StateError(
        'An unresolved backup exists for module $moduleId',
      );
    }

    final hadExistingModule = await backupExistingModule(moduleId);

    try {
      return await installStagedModule(moduleId);
    } catch (_) {
      // If installation failed, restore the previous module.
      if (hadExistingModule && !await moduleDirectory.exists()) {
        await restoreModuleBackup(moduleId);
      }

      rethrow;
    }
  }

  /// Inspects the filesystem for an interrupted or pending
  /// module replacement without modifying any files.
  Future<String> getModuleInstallationState(String moduleId) async {
    final moduleDirectory = await getModuleDirectory(moduleId);
    final backupDirectory = await getModuleBackupDirectory(moduleId);

    final moduleExists = await moduleDirectory.exists();
    final backupExists = await backupDirectory.exists();

    if (moduleExists && backupExists) {
      return 'replacement_pending';
    }

    if (!moduleExists && backupExists) {
      return 'restore_required';
    }

    if (moduleExists) {
      return 'installed';
    }

    return 'not_installed';
  }

  /// Extracts a module ZIP in a background isolate.
  ///
  /// Files are written only to the staging directory.
  Future<Directory> extractModuleZip({
    required String moduleId,
    required File zipFile,
    void Function(double progress)? onProgress,
  }) async {
    if (!RegExp(r'^[0-9]+$').hasMatch(moduleId)) {
      throw ArgumentError('Invalid module ID: $moduleId');
    }

    if (!await zipFile.exists()) {
      throw StateError('Module ZIP does not exist');
    }

    final stagingDirectory = await getStagingDirectory(moduleId);

    if (await stagingDirectory.exists()) {
      throw StateError(
        'Staging directory already exists for module $moduleId',
      );
    }

    await stagingDirectory.create(recursive: true);

    final progressPort = ReceivePort();

    final progressSubscription = progressPort.listen((message) {
      if (message is double) {
        onProgress?.call(message);
      }
    });

    final progressSendPort = progressPort.sendPort;

    try {
      await Isolate.run(() async {
        final inputStream = InputFileStream(zipFile.path);

        try {
          final archive = ZipDecoder().decodeStream(inputStream);

          if (archive.isEmpty) {
            throw const FormatException('Module ZIP is empty');
          }

          const maxArchiveEntries = 10000;

          if (archive.length > maxArchiveEntries) {
            throw const FormatException(
              'Module ZIP contains too many files or directories',
            );
          }

          final rootPath = stagingDirectory.absolute.path;
          final separator = Platform.pathSeparator;
          final rootPrefix = '$rootPath$separator';

          const maxUncompressedBytes = 1024 * 1024 * 1024;
          var totalUncompressedBytes = 0;
          var extracted = 0;

          for (final entry in archive) {
            if (entry.isSymbolicLink) {
              throw FormatException(
                'Symbolic links are not allowed in module ZIPs: ${entry.name}',
              );
            }

            final entryName = entry.name.replaceAll('\\', '/');
            final segments = entryName.split('/');

            final invalidSegments = segments.any(
                  (segment) =>
              segment == '..' ||
                  segment == '.' ||
                  (segment.isEmpty &&
                      segment != segments.last),
            );

            if (entryName.isEmpty ||
                entryName.startsWith('/') ||
                entryName.contains(':') ||
                invalidSegments) {
              throw FormatException(
                'Unsafe ZIP entry: ${entry.name}',
              );
            }

            final destination = File(
              '$rootPath$separator${segments.join(separator)}',
            ).absolute.path;

            if (!destination.startsWith(rootPrefix)) {
              throw FormatException(
                'ZIP entry escapes staging directory: ${entry.name}',
              );
            }

            if (entry.isFile) {
              totalUncompressedBytes += entry.size;

              if (totalUncompressedBytes > maxUncompressedBytes) {
                throw const FormatException(
                  'Module ZIP exceeds the maximum extracted size of 1 GB',
                );
              }

              final outputFile = File(destination);

              await outputFile.parent.create(recursive: true);

              final output = OutputFileStream(destination);

              try {
                entry.writeContent(output);
              } finally {
                await output.close();
              }
            } else {
              await Directory(destination).create(recursive: true);
            }

            extracted++;

            if (extracted % 5 == 0 ||
                extracted == archive.length) {
              progressSendPort.send(
                extracted / archive.length,
              );
            }
          }
        } finally {
          await inputStream.close();
        }
      });

      return stagingDirectory;
    } catch (_) {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }

      rethrow;
    } finally {
      await progressSubscription.cancel();
      progressPort.close();
    }
  }

  /// Validates a compiler-generated module before installation.
  ///
  /// Throws an exception if the module is incomplete or its
  /// internal module_id does not match the expected identifier.
  Future<void> validateExtractedModule({
    required String moduleId,
    required Directory stagingDirectory,
  }) async {
    if (!RegExp(r'^[0-9]+$').hasMatch(moduleId)) {
      throw ArgumentError('Invalid module ID: $moduleId');
    }

    if (!await stagingDirectory.exists()) {
      throw StateError('Module staging directory does not exist');
    }

    final indexFile = File(
      '${stagingDirectory.path}/index.html',
    );

    final manifestFile = File(
      '${stagingDirectory.path}/module.json',
    );

    if (!await indexFile.exists() ||
        await indexFile.length() == 0) {
      throw FormatException(
        'Module $moduleId is missing a valid index.html',
      );
    }

    if (!await manifestFile.exists()) {
      throw FormatException(
        'Module $moduleId is missing module.json',
      );
    }

    final dynamic manifest;

    try {
      manifest = jsonDecode(
        await manifestFile.readAsString(),
      );
    } on FormatException {
      throw FormatException(
        'Module $moduleId contains invalid module.json',
      );
    }

    if (manifest is! Map<String, dynamic>) {
      throw FormatException(
        'Module $moduleId has an invalid manifest structure',
      );
    }

    final manifestModuleId =
    manifest['module_id']?.toString().trim();

    if (manifestModuleId != moduleId) {
      throw FormatException(
        'Module ID mismatch: expected $moduleId, '
            'found $manifestModuleId',
      );
    }
  }
}
