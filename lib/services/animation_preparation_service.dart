import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'animation_installation_coordinator.dart';
import 'animation_installation_inspection_service.dart';
import 'animation_installation_workspace_service.dart';
import 'animation_mp4_extraction_worker_service.dart';
import 'animation_private_download_service.dart';
import 'animation_staged_mp4_verification_service.dart';
import 'animation_zip_integrity_verification_service.dart';
import 'animation_zip_metadata_reader.dart';

enum AnimationPreparationPhase {
  inspectingDestination,
  creatingWorkspace,
  downloading,
  inspectingZip,
  verifyingZip,
  extracting,
  verifyingStaged,
  prepared,
  publishing,
  cleaningUp,
}

class AnimationPreparationProgress {
  const AnimationPreparationProgress(this.phase, {this.download});
  final AnimationPreparationPhase phase;
  final AnimationDownloadProgress? download;
}

class PublishedAnimation {
  const PublishedAnimation._(
      this.animationId, this.relativePath, this.verifiedBytes);
  final int animationId;
  final String relativePath;
  final int verifiedBytes;
}

/// Verified metadata with publication authority valid only during the callback.
/// No workspace, file handles or arbitrary destination arguments are exposed.
class PreparedAnimation {
  PreparedAnimation._(this.animationId, this.descriptor, this.verifiedBytes);
  final int animationId;
  final AnimationZipDescriptor descriptor;
  final int verifiedBytes;
  String get relativePath => descriptor.mp4RelativePath;
  Future<PublishedAnimation> Function()? _publish;
  Future<PublishedAnimation> publish() {
    final publish = _publish;
    if (publish == null) {
      return Future.error(StateError('Preparation scope is closed'));
    }
    return publish();
  }
}

/// The move committed. Neither callback nor private cleanup errors undo it.
class AnimationPublicationCommittedException implements Exception {
  const AnimationPublicationCommittedException(
      {required this.publication,
      required this.primaryError,
      required this.primaryStack,
      this.cleanupError,
      this.cleanupStack});
  final PublishedAnimation publication;
  final Object primaryError;
  final StackTrace primaryStack;
  final Object? cleanupError;
  final StackTrace? cleanupStack;
  @override
  String toString() => 'Animation ${publication.animationId} was published; '
      'subsequent error: $primaryError; cleanup: $cleanupError';
}

class _Publication {
  Future<PublishedAnimation>? pending;
  PublishedAnimation? committed;

  Future<PublishedAnimation> start(Future<PublishedAnimation> Function() move) {
    if (pending != null) return pending!;
    final completion = Completer<PublishedAnimation>();
    final future = pending = completion.future;
    // Observe failures immediately even when the callback neglects to await.
    // The scope still awaits the original future and propagates its failure.
    future.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    // Reserve before invoking user-observable phase callbacks, which can
    // reenter publish() synchronously. Such calls must receive the same Future.
    Future.sync(move).then(completion.complete,
        onError: (Object error, StackTrace stack) =>
            completion.completeError(error, stack));
    return future;
  }
}

class AnimationPreparationCancellation {
  final _extraction = AnimationExtractionCancellation();
  bool get isRequested => _extraction.isRequested;
  void cancel() => _extraction.cancel();
}

class AnimationPreparationCancelled implements Exception {
  const AnimationPreparationCancelled();
}

class AnimationPreparationDestinationException implements Exception {
  const AnimationPreparationDestinationException(this.animationId, this.status);
  final int animationId;
  final AnimationInstallationStatus status;
  @override
  String toString() => 'Animation $animationId destination: ${status.name}';
}

/// Cleanup failure is never hidden. If preparation/callback already failed,
/// retain that original object and stack as the primary cause, alongside cleanup.
class AnimationPreparationCleanupException implements Exception {
  const AnimationPreparationCleanupException({
    required this.workspacePath,
    required this.cleanupError,
    required this.cleanupStack,
    this.primaryError,
    this.primaryStack,
  });
  final String workspacePath;
  final Object cleanupError;
  final StackTrace cleanupStack;
  final Object? primaryError;
  final StackTrace? primaryStack;
  @override
  String toString() =>
      'Animation preparation cleanup failed at $workspacePath; '
      'primary: $primaryError; cleanup: $cleanupError';
}

typedef AnimationBackgroundZipVerification = Future<void> Function(
    String zipPath,
    AnimationZipDescriptor descriptor,
    AnimationZipLimits limits);

/// Callback-scoped preparation/publication. The shared reservation spans all
/// stages, callback, pending publication and private cleanup. Returning without
/// publishing discards preparation. A successful move is never rolled back.
///
/// Cancellation is deferred until active stages (and any callback) complete.
/// Do not abandon/time out the owning Future and then clean its workspace.
/// An abandoned callback or stuck I/O can retain the reservation indefinitely.
/// Existing ZIP/CRC, immutable-file and exclusive-workspace limitations apply.
/// Directory.rename is not atomic no-replace: POSIX can replace an empty
/// destination created after the final check. Cooperating writers must share
/// the coordinator. Uncoordinated writers/ancestor replacement remain a race.
class AnimationPreparationService {
  AnimationPreparationService({
    required AnimationInstallationCoordinator coordinator,
    this.limits = const AnimationZipLimits(),
    AnimationInstallationInspectionService? inspection,
    AnimationInstallationWorkspaceService? workspaces,
    AnimationPrivateDownloadService? downloader,
    AnimationMp4ExtractionWorkerService? extractor,
    AnimationStagedMp4VerificationService? stagedVerifier,
    AnimationBackgroundZipVerification? verifyZip,
    Future<void> Function(Directory source, String destination)? renamePayload,
  })  : _coordinator = coordinator,
        _inspection = inspection ??
            AnimationInstallationInspectionService(zipLimits: limits),
        _workspaces = workspaces ?? AnimationInstallationWorkspaceService(),
        _downloader =
            downloader ?? AnimationPrivateDownloadService(limits: limits),
        _extractor =
            extractor ?? AnimationMp4ExtractionWorkerService(limits: limits),
        _stagedVerifier = stagedVerifier,
        _verifyZip = verifyZip ?? _verifyZipInBackground,
        _renamePayload = renamePayload ?? _renameDirectory;

  final AnimationZipLimits limits;
  final AnimationInstallationCoordinator _coordinator;
  // Injected stages are trusted: they must await all work and preserve the same
  // ownership/limit contracts as the defaults. No dependencies cross isolates.
  final AnimationInstallationInspectionService _inspection;
  final AnimationInstallationWorkspaceService _workspaces;
  final AnimationPrivateDownloadService _downloader;
  final AnimationMp4ExtractionWorkerService _extractor;
  final AnimationStagedMp4VerificationService? _stagedVerifier;
  final AnimationBackgroundZipVerification _verifyZip;
  // Trusted test hook: complete only after the actual move finishes, and throw
  // only when no move committed. No fallback copy or destination deletion.
  final Future<void> Function(Directory, String) _renamePayload;

  Future<T> withPrepared<T>({
    required int animationId,
    required Directory canonicalRoot,
    required Uri downloadUri,
    required Future<T> Function(PreparedAnimation prepared) use,
    AnimationPreparationCancellation? cancellation,
    void Function(AnimationPreparationProgress)? onProgress,
  }) async {
    if (animationId <= 0) throw ArgumentError.value(animationId, 'animationId');
    if (downloadUri.scheme != 'https' ||
        downloadUri.host.isEmpty ||
        downloadUri.userInfo.isNotEmpty ||
        downloadUri.hasFragment) {
      throw ArgumentError.value(
          downloadUri, 'downloadUri', 'Expected HTTPS URL');
    }
    limits.validate();
    final storageRoot = Directory(p.normalize(canonicalRoot.absolute.path));
    void checkCancelled() {
      if (cancellation?.isRequested ?? false) {
        throw const AnimationPreparationCancelled();
      }
    }

    void report(AnimationPreparationPhase phase,
        [AnimationDownloadProgress? download]) {
      try {
        onProgress
            ?.call(AnimationPreparationProgress(phase, download: download));
      } catch (_) {
        // Observers cannot abandon ownership or worker supervision.
      }
    }

    void begin(AnimationPreparationPhase phase) {
      checkCancelled();
      report(phase);
      checkCancelled();
    }

    checkCancelled();
    return _coordinator.run(
        animationId: animationId,
        operation: () async {
          AnimationInstallationWorkspace? workspace;
          Object? primaryError;
          StackTrace? primaryStack;
          PreparedAnimation? prepared;
          final publication = _Publication();
          try {
            begin(AnimationPreparationPhase.inspectingDestination);
            final destination = await _inspection.inspectInstallation(
                root: storageRoot, animationId: animationId);
            checkCancelled();
            if (destination.status !=
                AnimationInstallationStatus.notInstalled) {
              throw AnimationPreparationDestinationException(
                  animationId, destination.status);
            }
            begin(AnimationPreparationPhase.creatingWorkspace);
            workspace = await _workspaces.create(
                root: storageRoot, animationId: animationId);
            begin(AnimationPreparationPhase.downloading);
            await _downloader.download(
                uri: downloadUri,
                destination: workspace.downloadFile,
                onProgress: (progress) =>
                    report(AnimationPreparationPhase.downloading, progress));
            begin(AnimationPreparationPhase.inspectingZip);
            final descriptor = await _inspection
                .inspectArchiveMetadata(workspace.downloadFile.path);
            begin(AnimationPreparationPhase.verifyingZip);
            await _verifyZip(workspace.downloadFile.path, descriptor, limits);
            begin(AnimationPreparationPhase.extracting);
            try {
              await _extractor.extract(
                  zipPath: workspace.downloadFile.path,
                  descriptor: descriptor,
                  payloadPath: workspace.payloadDirectory.path,
                  cancellation: cancellation?._extraction);
            } on AnimationExtractionCancelled {
              throw const AnimationPreparationCancelled();
            }
            begin(AnimationPreparationPhase.verifyingStaged);
            final verified = _stagedVerifier == null
                ? await _verifyStagedInBackground(
                    workspace.payloadDirectory.path, descriptor, limits)
                : await _stagedVerifier.verify(
                    descriptor: descriptor,
                    payloadDirectory: workspace.payloadDirectory);
            if (verified.relativePath != descriptor.mp4RelativePath ||
                verified.verifiedBytes != descriptor.uncompressedSize) {
              throw const FormatException(
                  'Inconsistent staged verification result.');
            }
            begin(AnimationPreparationPhase.prepared);
            final ownedWorkspace = workspace;
            prepared = PreparedAnimation._(
                animationId, descriptor, verified.verifiedBytes);
            prepared._publish = () => publication.start(() async {
                  begin(AnimationPreparationPhase.publishing);
                  await ownedWorkspace.validateOwnership();
                  // Always use the real background verifier at the publication
                  // boundary, even when initial stage hooks were injected.
                  final checked = await _verifyStagedInBackground(
                      ownedWorkspace.payloadDirectory.path, descriptor, limits);
                  if (checked.relativePath != descriptor.mp4RelativePath ||
                      checked.verifiedBytes != descriptor.uncompressedSize) {
                    throw const FormatException('Invalid publication payload');
                  }
                  await ownedWorkspace.validateOwnership();
                  final root = storageRoot.path;
                  final ancestors = [
                    root,
                    p.join(root, 'modules'),
                    p.join(root, 'modules', 'animations')
                  ];
                  for (var i = 0; i < ancestors.length; i++) {
                    final type = await FileSystemEntity.type(ancestors[i],
                        followLinks: false);
                    if (i > 0 && type == FileSystemEntityType.notFound) {
                      await Directory(ancestors[i]).create();
                    }
                    await _requirePublicationDirectory(ancestors[i]);
                  }
                  final target = p.join(ancestors.last, '$animationId');
                  // Recheck all relevant ancestors, then destination, immediately
                  // before submitting rename. These path checks do not close the
                  // accepted race with noncooperating filesystem writers.
                  await ownedWorkspace.validateOwnership();
                  await _requirePublicationDirectory(
                      ownedWorkspace.payloadDirectory.path);
                  for (final ancestor in ancestors) {
                    await _requirePublicationDirectory(ancestor);
                  }
                  if (await FileSystemEntity.type(target, followLinks: false) !=
                      FileSystemEntityType.notFound) {
                    throw FileSystemException(
                        'Publication destination already exists', target);
                  }
                  checkCancelled();
                  await _renamePayload(ownedWorkspace.payloadDirectory, target);
                  final committed = PublishedAnimation._(animationId,
                      descriptor.mp4RelativePath, checked.verifiedBytes);
                  publication.committed =
                      committed; // Before any further await.
                  return committed;
                });
            late T result;
            try {
              result = await use(prepared);
            } catch (error, stack) {
              primaryError = error;
              primaryStack = stack;
            } finally {
              prepared._publish =
                  null; // Cannot start publication after callback.
            }
            try {
              await publication.pending;
            } catch (error, stack) {
              primaryError ??= error;
              primaryStack ??= stack;
            }
            if (primaryError != null) {
              Error.throwWithStackTrace(primaryError, primaryStack!);
            }
            if (publication.committed == null) checkCancelled();
            return result;
          } catch (error, stack) {
            primaryError ??= error;
            primaryStack ??= stack;
            if (publication.committed != null) {
              throw AnimationPublicationCommittedException(
                  publication: publication.committed!,
                  primaryError: primaryError,
                  primaryStack: primaryStack);
            }
            rethrow;
          } finally {
            prepared?._publish = null;
            if (workspace != null) {
              report(AnimationPreparationPhase.cleaningUp);
              try {
                await workspace.cleanup();
              } catch (error, stack) {
                if (publication.committed != null) {
                  throw AnimationPublicationCommittedException(
                      publication: publication.committed!,
                      primaryError: primaryError ?? error,
                      primaryStack: primaryStack ?? stack,
                      cleanupError: error,
                      cleanupStack: stack);
                }
                throw AnimationPreparationCleanupException(
                    workspacePath: workspace.directory.path,
                    cleanupError: error,
                    cleanupStack: stack,
                    primaryError: primaryError,
                    primaryStack: primaryStack);
              }
            }
          }
        });
  }
}

Future<void> _requirePublicationDirectory(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw FileSystemException('Unsafe publication directory', path);
  }
}

Future<void> _renameDirectory(Directory source, String destination) async {
  await source.rename(destination);
}

// Only these small immutable values are captured; never the orchestrator,
// callback, workspace ownership object, or injected services. Isolate.run waits
// for worker completion; no forced cancellation/termination is used.
Future<void> _verifyZipInBackground(String path,
        AnimationZipDescriptor descriptor, AnimationZipLimits limits) =>
    Isolate.run(() => AnimationZipIntegrityVerificationService(limits: limits)
        .verify(zipPath: path, descriptor: descriptor));

Future<AnimationStagedMp4VerificationResult> _verifyStagedInBackground(
        String path,
        AnimationZipDescriptor descriptor,
        AnimationZipLimits limits) =>
    Isolate.run(() => AnimationStagedMp4VerificationService(limits: limits)
        .verify(descriptor: descriptor, payloadDirectory: Directory(path)));
