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
  });

  final String title;
  final String trainingType;
  final String? specializationName;

  @override
  State<ProgramModulesPage> createState() => _ProgramModulesPageState();
}

class _ProgramModulesPageState extends State<ProgramModulesPage> {
  late Future<List<DownloadableModule>> _modules;

  final ProgramDownloadService _programDownloader = ProgramDownloadService();

  bool _downloadingProgram = false;
  ProgramDownloadProgress? _programProgress;
  String? _programError;
  String? _programMessage;

  final ModuleInstallationStatusService _installationStatus =
  ModuleInstallationStatusService();

  final Map<String, Future<bool>> _installationChecks = {};

  Future<bool> _isInstalled(DownloadableModule module) {
    return _installationChecks.putIfAbsent(
      module.name,
          () => _installationStatus.isInstalled(
        moduleName: module.name,
      ),
    );
  }

  static const _blue = Color(0xFF0070C0);
  static const _navy = Color(0xFF183E59);

  @override
  void initState() {
    super.initState();
    _modules = ModuleCatalogService().fetchModules();
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

    // Identify modules that still need downloading.
    final missing = <DownloadableModule>[];

    try {
      for (final module in modules) {
        final installed = await _isInstalled(module);
        if (!installed) missing.add(module);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _programError = 'Unable to check installed modules: $error';
      });
      return;
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

    if (!mounted) return;

    setState(() {
      _downloadingProgram = true;
      _programProgress = null;
      _programError = null;
      _programMessage = null;
    });

    try {
      final locationService = LocationService();

      await _programDownloader.downloadProgram(
        modules: modules,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _programProgress = progress;
          });
        },
        onModuleInstalled: (module) async {
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
      );

      if (!mounted) return;

      setState(() {
        _programMessage = 'Program download completed successfully.';
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
          _installationChecks.clear();
        });
      }
    }
  }

  Widget _buildProgramDownloadPanel(
      List<DownloadableModule> modules,
      ) {
    return FutureBuilder<List<bool>>(
      future: Future.wait(
        modules.map(_isInstalled),
      ),
      builder: (context, snapshot) {
        final installedCount = snapshot.hasData
            ? snapshot.data!.where((installed) => installed).length
            : 0;

        final total = modules.length;
        final remaining = total - installedCount;

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
                    : 'Checking installed modules...',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF526B7C),
                ),
              ),
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
                        remaining > 0 &&
                        !_downloadingProgram
                        ? () => _downloadEntireProgram(modules)
                        : null,
                    icon: Icon(
                      remaining == 0 && snapshot.hasData
                          ? Icons.check_circle_outline
                          : Icons.download_rounded,
                    ),
                    label: Text(
                      snapshot.hasData && remaining == 0
                          ? 'All Modules Installed'
                          : snapshot.hasData
                          ? 'Download Remaining $remaining Modules'
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
                Text(
                  _programError!,
                  style: const TextStyle(
                    color: Color(0xFF9C3C2E),
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
      _installationChecks.clear();
    });
  }

  void _openNavigationPage(Widget page) {
    if (_downloadingProgram) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
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
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                              itemCount: modules.length + (landscape ? 1 : 0),
                              separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                if (landscape && index == 0) {
                                  return _buildProgramDownloadPanel(modules);
                                }
                                final module = modules[landscape ? index - 1 : index];

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
                                          FutureBuilder<bool>(
                                            future: _isInstalled(module),
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

                                              final installed =
                                                  snapshot.data ?? false;

                                              return Tooltip(
                                                message: installed
                                                    ? 'Installed'
                                                    : 'Not installed',
                                                child: Icon(
                                                  installed
                                                      ? Icons
                                                      .check_circle_rounded
                                                      : Icons.download_outlined,
                                                  color: installed
                                                      ? const Color(0xFF548235)
                                                      : const Color(0xFF78909C),
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


