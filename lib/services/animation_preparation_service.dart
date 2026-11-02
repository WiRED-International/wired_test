import 'dart:io';
import 'dart:isolate';

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
  cleaningUp,
}

class AnimationPreparationProgress {
  const AnimationPreparationProgress(this.phase, {this.download});
  final AnimationPreparationPhase phase;
  final AnimationDownloadProgress? download;
}

/// Metadata only: no workspace, file handles, or publication authority escapes.
class PreparedAnimation {
  const PreparedAnimation._(
      this.animationId, this.descriptor, this.verifiedBytes);
  final int animationId;
  final AnimationZipDescriptor descriptor;
  final int verifiedBytes;
  String get relativePath => descriptor.mp4RelativePath;
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

/// Callback-scoped preparation only. The shared coordinator's reservation spans
/// all stages, the awaited callback and cleanup. Returning from the callback
/// discards the private preparation; nothing is published or installed.
///
/// Cancellation is deferred until active stages (and any callback) complete.
/// Do not abandon/time out the owning Future and then clean its workspace.
/// An abandoned callback or stuck I/O can retain the reservation indefinitely.
/// Existing ZIP/CRC, immutable-file and exclusive-workspace limitations apply.
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
  })  : _coordinator = coordinator,
        _inspection = inspection ??
            AnimationInstallationInspectionService(zipLimits: limits),
        _workspaces = workspaces ?? AnimationInstallationWorkspaceService(),
        _downloader =
            downloader ?? AnimationPrivateDownloadService(limits: limits),
        _extractor =
            extractor ?? AnimationMp4ExtractionWorkerService(limits: limits),
        _stagedVerifier = stagedVerifier,
        _verifyZip = verifyZip ?? _verifyZipInBackground;

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
          try {
            begin(AnimationPreparationPhase.inspectingDestination);
            final destination = await _inspection.inspectInstallation(
                root: canonicalRoot, animationId: animationId);
            checkCancelled();
            if (destination.status !=
                AnimationInstallationStatus.notInstalled) {
              throw AnimationPreparationDestinationException(
                  animationId, destination.status);
            }
            begin(AnimationPreparationPhase.creatingWorkspace);
            workspace = await _workspaces.create(
                root: canonicalRoot, animationId: animationId);
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
            final result = await use(PreparedAnimation._(
                animationId, descriptor, verified.verifiedBytes));
            checkCancelled();
            return result;
          } catch (error, stack) {
            primaryError = error;
            primaryStack = stack;
            rethrow;
          } finally {
            if (workspace != null) {
              report(AnimationPreparationPhase.cleaningUp);
              try {
                await workspace.cleanup();
              } catch (error, stack) {
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
