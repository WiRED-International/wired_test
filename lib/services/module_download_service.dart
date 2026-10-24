import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

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

  /// Downloads a ZIP into temporary storage, resuming a partial download when
  /// the server supports HTTP byte ranges. Installation is not changed.
  Future<File> downloadModuleZip({
    required String moduleId,
    required String downloadUrl,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!RegExp(r'^[0-9]+$').hasMatch(moduleId)) {
      throw ArgumentError('Invalid module ID: $moduleId');
    }

    final uri = Uri.tryParse(downloadUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError('Invalid HTTPS download URL');
    }

    final downloadsDirectory = await getDownloadsDirectory();
    final zipFile = File('${downloadsDirectory.path}/$moduleId.zip');
    final partialFile = File('${downloadsDirectory.path}/$moduleId.zip.part');
    final sourceFile = File('${downloadsDirectory.path}/$moduleId.zip.source');
    final etagFile = File('${downloadsDirectory.path}/$moduleId.zip.etag');

    // Never append bytes from a different download URL to an old partial ZIP.
    if (await partialFile.exists()) {
      if (!await sourceFile.exists() ||
          await sourceFile.readAsString() != downloadUrl) {
        await partialFile.delete();
        if (await etagFile.exists()) await etagFile.delete();
      }
    }
    if (!await partialFile.exists() && await etagFile.exists()) {
      await etagFile.delete();
    }
    await sourceFile.writeAsString(downloadUrl, flush: true);

    final dio = Dio(
      BaseOptions(
        followRedirects: true,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (status) =>
            status == 200 || status == 206 || status == 416,
      ),
    );

    try {
      var existingBytes =
          await partialFile.exists() ? await partialFile.length() : 0;
      final savedEtag = existingBytes > 0 && await etagFile.exists()
          ? (await etagFile.readAsString()).trim()
          : '';
      final requestHeaders = <String, String>{};
      if (existingBytes > 0) {
        requestHeaders['Range'] = 'bytes=$existingBytes-';
        // S3 returns 200 with the complete new object if its ETag changed.
        if (savedEtag.isNotEmpty) requestHeaders['If-Range'] = savedEtag;
      }
      debugPrint('DEBUG: Module $moduleId download starting');
      debugPrint('DEBUG: Existing partial bytes: $existingBytes');
      debugPrint(
          'DEBUG: Requested Range: ${requestHeaders['Range'] ?? 'none'}');
      final response = await dio.get<ResponseBody>(
        downloadUrl,
        options: Options(
          responseType: ResponseType.stream,
          headers: requestHeaders.isEmpty ? null : requestHeaders,
        ),
        cancelToken: cancelToken,
      );

      final status = response.statusCode;
      debugPrint('DEBUG: Module $moduleId HTTP status: $status');
      debugPrint(
        'DEBUG: Content-Range: '
        '${response.headers.value('content-range') ?? 'none'}',
      );
      if (status == 416) {
        // The partial file may be complete, but do not assume so without
        // verifying the advertised total length. Retry from zero instead.
        if (await partialFile.exists()) await partialFile.delete();
        if (await etagFile.exists()) await etagFile.delete();
        throw StateError('Server rejected resume range; retry the download');
      }

      if (status != 200 && status != 206) {
        throw HttpException('Unexpected download status: $status');
      }

      final responseEtag = response.headers.value('etag')?.trim() ?? '';
      if (status == 206 && savedEtag.isNotEmpty && responseEtag != savedEtag) {
        throw const FormatException('Module ZIP changed during download');
      }

      if (status == 206) {
        final contentRange = response.headers.value('content-range');
        final match = contentRange == null
            ? null
            : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(contentRange);
        if (match == null || int.parse(match.group(1)!) != existingBytes) {
          throw const FormatException('Invalid HTTP resume response');
        }
        final lastByte = int.parse(match.group(2)!);
        final totalBytes = int.parse(match.group(3)!);
        if (lastByte != totalBytes - 1 || totalBytes <= existingBytes) {
          throw const FormatException('Invalid HTTP resume total');
        }
      } else {
        // A 200 response means the server ignored Range (or this is a fresh
        // download). Start from zero instead of appending duplicate content.
        existingBytes = 0;
      }

      // Persist the validator before streaming so interrupted downloads retain
      // the ETag needed to safely resume. No ETag means legacy range behavior.
      if (responseEtag.isNotEmpty) {
        await etagFile.writeAsString(responseEtag, flush: true);
      } else if (await etagFile.exists()) {
        await etagFile.delete();
      }

      final advertisedLength =
          int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
      final expectedTotal =
          advertisedLength >= 0 ? existingBytes + advertisedLength : null;
      var received = existingBytes;
      final sink = partialFile.openWrite(
        mode: existingBytes > 0 ? FileMode.append : FileMode.write,
      );
      try {
        await for (final chunk in response.data!.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (expectedTotal != null && expectedTotal > 0) {
            onProgress?.call((received / expectedTotal).clamp(0.0, 1.0));
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (received == 0 ||
          (expectedTotal != null && received != expectedTotal)) {
        throw StateError('Module download is incomplete');
      }

      // Promote the complete download only after the stream finishes.
      if (await zipFile.exists()) await zipFile.delete();
      await partialFile.rename(zipFile.path);
      if (await sourceFile.exists()) await sourceFile.delete();
      if (await etagFile.exists()) await etagFile.delete();
      onProgress?.call(1.0);
      return zipFile;
    } finally {
      // Keep .part and .source after interruption so a later attempt resumes.
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
                  (segment.isEmpty && segment != segments.last),
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

            if (extracted % 5 == 0 || extracted == archive.length) {
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

    if (!await indexFile.exists() || await indexFile.length() == 0) {
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

    final manifestModuleId = manifest['module_id']?.toString().trim();

    if (manifestModuleId != moduleId) {
      throw FormatException(
        'Module ID mismatch: expected $moduleId, '
        'found $manifestModuleId',
      );
    }
  }
}
