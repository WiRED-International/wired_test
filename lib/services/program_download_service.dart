import 'dart:io';
import 'package:path/path.dart' as p;

import '../models/downloadable_module.dart';
import 'legacy_module_installation_service.dart';
import 'module_installation_status_service.dart';

class ProgramInstallationIssue {
  const ProgramInstallationIssue(this.module, this.inspection);
  final DownloadableModule module;
  final InstructionalInstallationInspection inspection;
}

/// No replacement is attempted for unresolved identity evidence. Completed
/// modules remain installed; remaining modules have not been downloaded here.
class ProgramDownloadBlockedException implements Exception {
  ProgramDownloadBlockedException({
    required this.phase,
    required Iterable<ProgramInstallationIssue> issues,
    Iterable<DownloadableModule> completedModules = const [],
    Iterable<DownloadableModule> confirmedModules = const [],
    required Iterable<DownloadableModule> remainingModules,
  })  : issues = List.unmodifiable(issues),
        completedModules = List.unmodifiable(completedModules),
        confirmedModules = List.unmodifiable(confirmedModules),
        remainingModules = List.unmodifiable(remainingModules);

  final String phase;
  final List<ProgramInstallationIssue> issues;

  /// Newly published and verified during this operation.
  final List<DownloadableModule> completedModules;

  /// Confirmed by inspection, including previously installed modules.
  final List<DownloadableModule> confirmedModules;
  final List<DownloadableModule> remainingModules;

  @override
  String toString() =>
      'Program download blocked during $phase: ${issues.map((issue) => '${issue.module.name} (database ${issue.module.id}, content ${issue.module.moduleId}): '
          '${issue.inspection.state.name}: ${issue.inspection.reason}').join('; ')}';
}

/// Progress information for a sequential program download.
class ProgramDownloadProgress {
  const ProgramDownloadProgress({
    required this.completed,
    required this.total,
    required this.currentModule,
    required this.phase,
    required this.moduleProgress,
  });

  final int completed;
  final int total;
  final String currentModule;
  final String phase;
  final double moduleProgress;

  double get overallProgress {
    if (total == 0) return 1.0;

    return ((completed + moduleProgress) / total).clamp(0.0, 1.0);
  }
}

/// Downloads missing modules individually using HealthMAP's
/// existing legacy-compatible installation workflow.
class ProgramDownloadService {
  ProgramDownloadService({
    LegacyModuleInstallationService? installer,
    ModuleInstallationStatusService? installationStatus,
  })  : _installer = installer ?? LegacyModuleInstallationService(),
        _installationStatus =
            installationStatus ?? ModuleInstallationStatusService();

  final LegacyModuleInstallationService _installer;
  final ModuleInstallationStatusService _installationStatus;

  Future<InstructionalInstallationInspection> _inspect(
      DownloadableModule module) async {
    try {
      return await _installationStatus.inspectInstallation(
          databaseId: module.id,
          moduleId: module.moduleId,
          moduleName: module.name);
    } catch (error) {
      return InstructionalInstallationInspection(
          InstructionalInstallationState.unavailable,
          'Installation inspection failed: $error', const []);
    }
  }

  Future<bool> _verifyPublication(
      InstructionalInstallationResult result) async {
    try {
      if (!p.equals(
              p.dirname(result.entryPointPath), result.contentDirectory) ||
          !await Directory(result.contentDirectory).exists() ||
          !await File(result.entryPointPath).exists() ||
          await File(result.entryPointPath).length() == 0) {
        return false;
      }
      if (result.format == 'compiler') {
        return p.basename(result.entryPointPath) == 'index.html';
      }
      final launcher = result.launcherPath;
      return result.format == 'storyline' &&
          p.basename(result.entryPointPath) == 'story.html' &&
          launcher != null &&
          await File(launcher).exists() &&
          await File(launcher).length() > 0;
    } on FileSystemException {
      return false;
    }
  }

  /// Throws [ProgramDownloadBlockedException] for unresolved preflight or fresh
  /// identity checks. Its snapshots distinguish published, confirmed and pending
  /// modules; no registry writes or content repairs are performed by this service.
  Future<void> downloadProgram({
    required List<DownloadableModule> modules,
    void Function(ProgramDownloadProgress)? onProgress,
    Future<void> Function(DownloadableModule module)? onModuleInstalled,
    void Function(
            DownloadableModule module, InstructionalInstallationResult result)?
        onInstallationWarning,
  }) async {
    if (modules.isEmpty) {
      return;
    }

    // Inspect every supplied identity before starting any downloads. Never turn
    // uncertainty into absence or a successful empty queue.
    final missing = <DownloadableModule>[];
    final confirmed = <DownloadableModule>[];
    final completedModules = <DownloadableModule>[];
    final issues = <ProgramInstallationIssue>[];

    for (final module in modules) {
      final inspection = await _inspect(module);
      if (inspection.state == InstructionalInstallationState.notInstalled) {
        missing.add(module);
      } else if (inspection.state == InstructionalInstallationState.confirmed) {
        confirmed.add(module);
      } else {
        issues.add(ProgramInstallationIssue(module, inspection));
      }
    }
    if (issues.isNotEmpty) {
      throw ProgramDownloadBlockedException(
          phase: 'preflight',
          issues: issues,
          confirmedModules: confirmed,
          remainingModules:
              modules.where((module) => !confirmed.contains(module)));
    }

    if (missing.isEmpty) {
      onProgress?.call(
        const ProgramDownloadProgress(
          completed: 0,
          total: 0,
          currentModule: '',
          phase: 'All modules already installed',
          moduleProgress: 1.0,
        ),
      );
      return;
    }

    var completed = 0;

    for (var index = 0; index < missing.length; index++) {
      final module = missing[index];
      final url = module.downloadLink;

      if (url == null || url.isEmpty) {
        throw StateError(
          'No download URL available for "${module.name}".',
        );
      }

      void report(String phase, double value) {
        onProgress?.call(
          ProgramDownloadProgress(
            completed: completed,
            total: missing.length,
            currentModule: module.name,
            phase: phase,
            moduleProgress: value,
          ),
        );
      }

      report('Preparing download', 0);

      // Recheck immediately before installing to avoid overwriting
      // a module that was installed after the initial scan.
      final inspection = await _inspect(module);
      if (inspection.state == InstructionalInstallationState.confirmed) {
        confirmed.add(module);
        completed++;
        report('Already installed', 0);
        continue;
      }
      if (inspection.state != InstructionalInstallationState.notInstalled) {
        throw ProgramDownloadBlockedException(
            phase: 'before installation',
            issues: [ProgramInstallationIssue(module, inspection)],
            completedModules: completedModules,
            confirmedModules: confirmed,
            remainingModules: missing.sublist(index));
      }

      final result = await _installer.downloadAndInstallWithResult(
        databaseId: module.id,
        version: module.version,
        moduleId: module.moduleId,
        moduleName: module.name,
        downloadUrl: url,
        onDownloadProgress: (value) {
          report('Downloading module', value * 0.9);
        },
        onExtractionProgress: (value) {
          report('Installing module', 0.9 + value * 0.1);
        },
      );

      // Publication evidence is independent of registry persistence. A tracking
      // warning must not invalidate files successfully installed in this run.
      if (!await _verifyPublication(result)) {
        throw StateError(
          'Installation could not be verified for "${module.name}".',
        );
      }

      completed++;
      completedModules.add(module);
      report(
          result.hasWarnings
              ? 'Module installed with warnings'
              : 'Module installed',
          0);
      if (result.hasWarnings && onInstallationWarning != null) {
        try {
          onInstallationWarning(module, result);
        } catch (_) {
          // Warning observers cannot invalidate published content.
        }
      }

      if (onModuleInstalled != null) {
        try {
          await onModuleInstalled(module);
        } catch (error) {
          // Statistics failures must never invalidate a successful installation.
          // The module remains installed and the program download continues.
        }
      }
    }

    onProgress?.call(
      ProgramDownloadProgress(
        completed: completed,
        total: missing.length,
        currentModule: '',
        phase: 'Program download complete',
        moduleProgress: 0,
      ),
    );
  }
}
