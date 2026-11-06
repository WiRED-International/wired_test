import 'package:flutter/material.dart';
import '../providers/auth_guard.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'creditsTracker/credits_tracker.dart';
import 'home_page.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
import 'module_library.dart';

import '../models/downloadable_module.dart';
import '../services/module_catalog_service.dart';
import '../services/module_installation_status_service.dart';
import '../services/location_service.dart';
import '../utils/app_layout.dart';
import '../utils/custom_app_bar.dart';
import 'module_details_page.dart';
import '../services/program_download_service.dart';

class ProgramModulesPage extends StatefulWidget {
  const ProgramModulesPage({
    super.key,
    required this.title,
    required this.trainingType,
    this.specializationName,
    this.catalogService,
    this.installationStatus,
    this.programDownloader,
    this.locationService,
  });

  final String title;
  final String trainingType;
  final String? specializationName;
  final ModuleCatalogService? catalogService;
  final ModuleInstallationStatusService? installationStatus;
  final ProgramDownloadService? programDownloader;
  final LocationService? locationService;

  @override
  State<ProgramModulesPage> createState() => _ProgramModulesPageState();
}

class _ProgramModulesPageState extends State<ProgramModulesPage> {
  late Future<List<DownloadableModule>> _modules;

  late final ProgramDownloadService _programDownloader =
      widget.programDownloader ?? ProgramDownloadService();

  bool _downloadingProgram = false;
  ProgramDownloadProgress? _programProgress;
  String? _programError;
  String? _programMessage;

  late final ModuleInstallationStatusService _installationStatus =
      widget.installationStatus ?? ModuleInstallationStatusService();
  final Map<(int?, String), Future<InstructionalInstallationInspection>>
      _installationChecks = {};
  // onModuleInstalled is emitted only after the service verifies published files.
  // Discard this session-only evidence on navigation, where files may be removed.
  final Set<(int?, String)> _sessionPublications = {};
  final Set<(int?, String)> _warningModules = {};
  Future<List<InstructionalInstallationInspection>>? _summary;
  int _statusGeneration = 0;

  (int?, String) _identity(DownloadableModule module) =>
      (module.id, module.moduleId);
  bool _isInstalled(DownloadableModule module,
          InstructionalInstallationInspection inspection) =>
      inspection.state == InstructionalInstallationState.confirmed ||
      _sessionPublications.contains(_identity(module));

  void _invalidateChecks({bool discardPublications = false}) {
    _installationChecks.clear();
    _summary = null;
    _statusGeneration++;
    if (discardPublications) {
      _sessionPublications.clear();
      _warningModules.clear();
      _programMessage = null;
      _programError = null;
    }
  }

  Future<InstructionalInstallationInspection> _inspect(
      DownloadableModule module) {
    return _installationChecks.putIfAbsent(
      _identity(module),
      () async {
        try {
          return await _installationStatus.inspectInstallation(
              databaseId: module.id,
              moduleId: module.moduleId,
              moduleName: module.name);
        } catch (error) {
          return InstructionalInstallationInspection(
              InstructionalInstallationState.unavailable,
              'Installation check failed: $error', const []);
        }
      },
    );
  }

  String _statusLabel(InstructionalInstallationState state) => switch (state) {
        InstructionalInstallationState.confirmed => 'Installed',
        InstructionalInstallationState.notInstalled => 'Not downloaded',
        InstructionalInstallationState.legacyCandidate =>
          'Existing offline content; identity unverified',
        InstructionalInstallationState.ambiguous =>
          'Needs verification: multiple matches',
        InstructionalInstallationState.conflict =>
          'Installation identity conflict',
        InstructionalInstallationState.invalidRecord =>
          'Installation tracking needs attention',
        InstructionalInstallationState.unavailable =>
          'Installation status unavailable',
      };

  void _retryChecks() {
    if (_downloadingProgram) return;
    setState(() {
      _invalidateChecks();
      _programError = null;
      _programMessage = null;
    });
  }

  static const _blue = Color(0xFF0070C0);
  static const _navy = Color(0xFF183E59);

  @override
  void initState() {
    super.initState();
    _modules = (widget.catalogService ?? ModuleCatalogService()).fetchModules();
  }

  List<DownloadableModule> _filterModules(
    List<DownloadableModule> modules,
  ) {
    final filtered = modules.where((module) {
      if (!module.belongsToTrainingType(widget.trainingType)) {
        return false;
      }

      if (widget.specializationName != null) {
        return module.belongsToSpecialization(
          widget.specializationName!,
        );
      }

      return true;
    }).toList();

    filtered.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    return filtered;
  }

  Future<void> _downloadEntireProgram(
    List<DownloadableModule> modules,
  ) async {
    if (_downloadingProgram) return;

    setState(() {
      _downloadingProgram = true;
      _programProgress = null;
      _programError = null;
      _programMessage = null;
      _warningModules.clear();
      _invalidateChecks();
    });

    try {
      final missing = <DownloadableModule>[];
      final issues = <ProgramInstallationIssue>[];
      for (final module in modules) {
        final inspection = await _inspect(module);
        if (_isInstalled(module, inspection)) continue;
        if (inspection.state == InstructionalInstallationState.notInstalled) {
          missing.add(module);
        } else {
          issues.add(ProgramInstallationIssue(module, inspection));
        }
      }
      if (issues.isNotEmpty) {
        throw ProgramDownloadBlockedException(
            phase: 'preflight',
            issues: issues,
            remainingModules: modules.where(
                (module) => !_sessionPublications.contains(_identity(module))));
      }

      // Validate the entire queue before starting.
      final unavailable = missing.where((module) {
        final url = module.downloadLink;
        return !module.isDownloadable ||
            !RegExp(r'^[0-9]+$').hasMatch(module.moduleId) ||
            url == null ||
            Uri.tryParse(url)?.scheme != 'https';
      }).toList();

      if (unavailable.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _programError =
              '${unavailable.length} module(s) cannot currently be downloaded. '
              'No downloads were started.';
        });
        return;
      }

      if (missing.isEmpty) {
        if (!mounted) return;
        setState(() {
          _programMessage = 'All modules are already installed.';
          _programError = null;
        });
        return;
      }

      final locationService = widget.locationService ?? LocationService();

      await _programDownloader.downloadProgram(
        modules: modules
            .where(
                (module) => !_sessionPublications.contains(_identity(module)))
            .toList(),
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _programProgress = progress;
          });
        },
        onModuleInstalled: (module) async {
          if (mounted) {
            setState(() => _sessionPublications.add(_identity(module)));
          }
          final databaseModuleId = module.id;

          if (databaseModuleId == null) {
            debugPrint(
              'Download statistics skipped: missing database ID '
              'for module ${module.moduleId}',
            );
            return;
          }

          await locationService.saveDownload(
            databaseModuleId,
            null,
          );
        },
        onInstallationWarning: (module, result) {
          if (mounted) setState(() => _warningModules.add(_identity(module)));
          debugPrint(
              'Program module ${module.id}/${module.moduleId} installed with '
              'tracking warning ${result.trackingError}; cleanup ${result.cleanupWarnings}');
        },
      );

      if (!mounted) return;

      setState(() {
        _programMessage = _warningModules.isEmpty
            ? 'Program download completed successfully.'
            : 'Program download completed with warnings for ${_warningModules.length} module(s). '
                'Successfully installed modules are available offline.';
      });
    } on ProgramDownloadBlockedException catch (error) {
      if (!mounted) return;
      setState(() {
        _programMessage = null;
        _programError =
            'Program download needs attention. Existing offline content is preserved.\n'
            '${error.completedModules.length} module(s) completed during this download.\n'
            '${error.issues.map((issue) => '${issue.module.name}: ${_statusLabel(issue.inspection.state)}. '
                '${issue.inspection.reason}').join('\n')}';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _programError = 'The program download was interrupted. '
            'Completed modules remain installed. '
            'You can retry the remaining modules.';

        debugPrint('Program download failed: $error');
      });
    } finally {
      if (mounted) {
        setState(() {
          _downloadingProgram = false;
          _invalidateChecks();
        });
      }
    }
  }

  Widget _buildProgramDownloadPanel(
    List<DownloadableModule> modules,
  ) {
    return FutureBuilder<List<InstructionalInstallationInspection>>(
      key: ValueKey(_statusGeneration),
      future: _summary ??= Future.wait(modules.map(_inspect)),
      builder: (context, snapshot) {
        final installedCount = snapshot.hasData
            ? List.generate(modules.length, (index) => index)
                .where((index) =>
                    _isInstalled(modules[index], snapshot.data![index]))
                .length
            : 0;

        final total = modules.length;
        final missing = snapshot.hasData
            ? List.generate(modules.length, (index) => index)
                .where((index) =>
                    !_isInstalled(modules[index], snapshot.data![index]) &&
                    snapshot.data![index].state ==
                        InstructionalInstallationState.notInstalled)
                .length
            : 0;
        final legacy = snapshot.hasData
            ? List.generate(modules.length, (index) => index)
                .where((index) =>
                    !_isInstalled(modules[index], snapshot.data![index]) &&
                    snapshot.data![index].state ==
                        InstructionalInstallationState.legacyCandidate)
                .length
            : 0;
        final unresolved =
            snapshot.hasData ? total - installedCount - missing - legacy : 0;
        final allInstalled =
            snapshot.hasData && total > 0 && installedCount == total;
        final needsRetry = snapshot.hasError ||
            (snapshot.hasData &&
                snapshot.data!.any((inspection) =>
                    inspection.state ==
                    InstructionalInstallationState.unavailable));

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFD7E4EA),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Offline Training',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.hasData
                    ? '$installedCount of $total modules installed'
                    : snapshot.hasError
                        ? 'Installation status could not be checked.'
                        : 'Checking installed modules...',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF526B7C),
                ),
              ),
              if (snapshot.hasData)
                Text(
                    '$missing missing; $legacy legacy; $unresolved need attention',
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF526B7C))),
              if (needsRetry && !_downloadingProgram)
                TextButton.icon(
                    onPressed: _retryChecks,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry installation checks')),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: snapshot.hasData && total > 0
                    ? installedCount / total
                    : null,
                minHeight: 8,
                backgroundColor: const Color(0xFFE4EDF2),
                color: const Color(0xFF548235),
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 18),
              if (_downloadingProgram) ...[
                Text(
                  _programProgress?.currentModule.isNotEmpty == true
                      ? _programProgress!.currentModule
                      : 'Preparing program download...',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _programProgress?.phase ?? 'Checking modules',
                  style: const TextStyle(
                    color: Color(0xFF526B7C),
                  ),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _programProgress?.overallProgress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                  color: _blue,
                ),
                const SizedBox(height: 8),
                if (_programProgress != null && _programProgress!.total > 0)
                  Text(
                    '${_programProgress!.completed} of '
                    '${_programProgress!.total} remaining modules completed',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF526B7C),
                    ),
                  ),
              ] else
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: snapshot.hasData &&
                            missing > 0 &&
                            legacy == 0 &&
                            unresolved == 0 &&
                            !_downloadingProgram
                        ? () => _downloadEntireProgram(modules)
                        : null,
                    icon: Icon(
                      allInstalled
                          ? Icons.check_circle_outline
                          : Icons.download_rounded,
                    ),
                    label: Text(
                      allInstalled
                          ? 'All Modules Installed'
                          : snapshot.hasData
                              ? legacy + unresolved > 0
                                  ? 'Installation Needs Verification'
                                  : 'Download Remaining $missing Modules'
                              : 'Checking Modules...',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF9FB5C3),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              if (_programError != null) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Text(
                      _programError!,
                      style: const TextStyle(color: Color(0xFF9C3C2E)),
                    ),
                  ),
                ),
              ],
              if (_programMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _programMessage!,
                  style: const TextStyle(
                    color: Color(0xFF548235),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _openModule(DownloadableModule module) async {
    if (_downloadingProgram) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ModuleDetailsPage(module: module),
      ),
    );

    if (!mounted) return;

    setState(() {
      _invalidateChecks(discardPublications: true);
    });
  }

  Future<void> _openNavigationPage(Widget page) async {
    if (_downloadingProgram) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted && page is ModuleLibrary) {
      setState(() => _invalidateChecks(discardPublications: true));
    }
  }

  Future<void> _openNavigationMenu() async {
    if (_downloadingProgram) return;

    final loggedIn = await checkIfUserIsLoggedIn();

    if (!mounted || _downloadingProgram) return;

    _openNavigationPage(loggedIn ? Menu() : GuestMenu());
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return PopScope(
      canPop: !_downloadingProgram,
      child: AppLayout(
        appBar: CustomAppBar(
          onBackPressed: () {
            if (!_downloadingProgram) {
              Navigator.pop(context);
            }
          },
          requireAuth: false,
        ),
        bottomNav: landscape
            ? null
            : CustomBottomNavBar(
                onHomeTap: () => _openNavigationPage(const MyHomePage()),
                onLibraryTap: () => _openNavigationPage(ModuleLibrary()),
                onTrackerTap: () =>
                    _openNavigationPage(AuthGuard(child: CreditsTracker())),
                onMenuTap: _openNavigationMenu,
              ),
        child: landscape
            ? Row(
                children: [
                  CustomSideNavBar(
                    onHomeTap: () => _openNavigationPage(const MyHomePage()),
                    onLibraryTap: () => _openNavigationPage(ModuleLibrary()),
                    onTrackerTap: () => _openNavigationPage(
                      AuthGuard(child: CreditsTracker()),
                    ),
                    onMenuTap: _openNavigationMenu,
                  ),
                  Expanded(child: _buildPageContent(landscape: true)),
                ],
              )
            : _buildPageContent(landscape: false),
      ),
    );
  }

  Widget _buildPageContent({required bool landscape}) {
    return Stack(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.menu_book_outlined,
                        size: 48,
                        color: _blue,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Select a module to view details or download it.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF526B7C),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<DownloadableModule>>(
                    future: _modules,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(color: _blue),
                        );
                      }

                      if (snapshot.hasError) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Unable to load modules. Please check your connection.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      final modules = _filterModules(snapshot.data ?? []);

                      if (modules.isEmpty) {
                        return const Center(
                          child: Text('No modules available for this program.'),
                        );
                      }
                      return Column(
                        children: [
                          if (!landscape) _buildProgramDownloadPanel(modules),
                          Expanded(
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 120),
                              itemCount: modules.length + (landscape ? 1 : 0),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                if (landscape && index == 0) {
                                  return _buildProgramDownloadPanel(modules);
                                }
                                final module =
                                    modules[landscape ? index - 1 : index];

                                return Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    onTap: _downloadingProgram
                                        ? null
                                        : () => _openModule(module),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFFD7E4EA),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              module.name,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: _navy,
                                              ),
                                            ),
                                          ),
                                          FutureBuilder<
                                              InstructionalInstallationInspection>(
                                            key: ValueKey((
                                              _identity(module),
                                              _statusGeneration
                                            )),
                                            future: _inspect(module),
                                            builder: (context, snapshot) {
                                              if (snapshot.connectionState !=
                                                  ConnectionState.done) {
                                                return const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                );
                                              }

                                              if (snapshot.hasError) {
                                                return const Tooltip(
                                                  message:
                                                      'Unable to check installation',
                                                  child: Icon(
                                                    Icons.error_outline,
                                                    color: Colors.orange,
                                                    size: 21,
                                                  ),
                                                );
                                              }

                                              final inspection = snapshot.data;
                                              final installed =
                                                  inspection != null &&
                                                      _isInstalled(
                                                          module, inspection);
                                              final state = inspection?.state ??
                                                  InstructionalInstallationState
                                                      .unavailable;

                                              return Tooltip(
                                                message: installed
                                                    ? state ==
                                                            InstructionalInstallationState
                                                                .confirmed
                                                        ? 'Installed'
                                                        : 'Installed during this session; identity tracking unconfirmed'
                                                    : _statusLabel(state),
                                                child: Icon(
                                                  installed
                                                      ? Icons
                                                          .check_circle_rounded
                                                      : state ==
                                                              InstructionalInstallationState
                                                                  .notInstalled
                                                          ? Icons
                                                              .download_outlined
                                                          : Icons.info_outline,
                                                  color: installed
                                                      ? const Color(0xFF548235)
                                                      : state ==
                                                              InstructionalInstallationState
                                                                  .notInstalled
                                                          ? const Color(
                                                              0xFF78909C)
                                                          : Colors.orange,
                                                  size: 23,
                                                ),
                                              );
                                            },
                                          ),
                                          const SizedBox(width: 10),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: _blue,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 100,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00FFD09A), Color(0xFFFFD09A)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
