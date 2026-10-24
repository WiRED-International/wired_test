import '../models/downloadable_module.dart';
import 'legacy_module_installation_service.dart';
import 'module_installation_status_service.dart';

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

  Future<void> downloadProgram({
    required List<DownloadableModule> modules,
    void Function(ProgramDownloadProgress)? onProgress,
    Future<void> Function(DownloadableModule module)? onModuleInstalled,
  }) async {
    if (modules.isEmpty) {
      return;
    }

    // Identify missing modules before starting downloads.
    final missing = <DownloadableModule>[];

    for (final module in modules) {
      final installed = await _installationStatus.isInstalled(
        moduleName: module.name,
      );

      if (!installed) {
        missing.add(module);
      }
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

    for (final module in missing) {
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
      final alreadyInstalled = await _installationStatus.isInstalled(
        moduleName: module.name,
      );

      if (alreadyInstalled) {
        completed++;
        report('Already installed', 0);
        continue;
      }

      await _installer.downloadAndInstall(
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

      // Confirm that installation actually succeeded.
      final installed = await _installationStatus.isInstalled(
        moduleName: module.name,
      );

      if (!installed) {
        throw StateError(
          'Installation could not be verified for "${module.name}".',
        );
      }

      completed++;
      report('Module installed', 0);

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
