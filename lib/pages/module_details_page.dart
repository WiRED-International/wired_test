import 'dart:io';

import 'package:wired_test/pages/home_page.dart';
import '../providers/auth_guard.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/side_nav_bar.dart';
import '../utils/functions.dart';
import 'creditsTracker/credits_tracker.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
import 'module_library.dart';

import 'package:flutter/material.dart';

import '../models/downloadable_module.dart';
import '../services/module_download_service.dart';
import '../services/legacy_module_installation_service.dart';
import '../services/location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_layout.dart';
import '../utils/custom_app_bar.dart';

/// Module details and downloads for compiler and Storyline modules.
class ModuleDetailsPage extends StatefulWidget {
  final DownloadableModule module;

  const ModuleDetailsPage({super.key, required this.module});

  @override
  State<ModuleDetailsPage> createState() => _ModuleDetailsPageState();
}

class _ModuleDetailsPageState extends State<ModuleDetailsPage> {
  final ModuleDownloadService _downloads = ModuleDownloadService();
  late final LegacyModuleInstallationService _installer =
  LegacyModuleInstallationService(downloadService: _downloads);

  bool _checking = true;
  bool _busy = false;
  bool _installed = false;
  double? _progress;
  String _phase = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshInstallation();
  }

  Future<void> _refreshInstallation() async {
    if (mounted) setState(() => _checking = true);
    try {
      final name = widget.module.name.trim();
      final safeName = legacyModuleFolderName(name);
      final modules = await _downloads.getModulesDirectory();
      final base = await _downloads.getBaseDirectory();
      // Compiler modules use the module name as their directory.
      final compiler = File('${modules.path}/$safeName/index.html');
      var installed = await compiler.exists();
      // Also recognize older compiler installs that used the original title.
      if (!installed && safeName != name && !name.contains('/') && !name.contains('\\')) {
        installed = await File('${modules.path}/$name/index.html').exists();
      }

      // Legacy Storyline launchers carry the module title in their HTML.
      // Match the title, not the Storyline folder name, which can differ.
      if (!installed) {
        await for (final entity in modules.list(followLinks: false)) {
          if (entity is! File || !entity.path.toLowerCase().endsWith('.htm')) {
            continue;
          }
          final content = await entity.readAsString();
          final titleMatch = RegExp(
            r'<meta\s+name="module-title"\s+content="([^"]*)"',
            caseSensitive: false,
          ).firstMatch(content);
          if (titleMatch == null) continue;
          final title = titleMatch.group(1)!
              .replaceAll('&quot;', '"')
              .replaceAll('&lt;', '<')
              .replaceAll('&gt;', '>')
              .replaceAll('&amp;', '&');
          if (title != name) continue;
          final launcherName = entity.uri.pathSegments.last;
          final folderName = launcherName.substring(0, launcherName.length - 4);
          if (await File('${base.path}/files/$folderName/story.html').exists()) {
            installed = true;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Unable to check installation: $error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _offerOptionalLocationSharing() async {
    final prefs = await SharedPreferences.getInstance();
    bool? choice = prefs.getBool('location_permission_choice');
    if (choice == null) {
      if (!mounted) return;
      choice = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Share Location to Support Public Health'),
          content: const Text(
            'Would you like to share your location (including precise GPS-level data) '
                'to help us understand where health education modules are being used? '
                'This is optional.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not Now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Allow Location'),
            ),
          ],
        ),
      ) ?? false;
      await prefs.setBool('location_permission_choice', choice);
    }
    if (choice && mounted) {
      final locationService = LocationService();
      final location = await locationService.getLocation(context);
      await locationService.saveDownload(int.parse(widget.module.moduleId), location);
    }
  }

  void _updateProgress(String phase, double value) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _progress = value.clamp(0.0, 1.0);
    });
  }

  Future<void> _install() async {
    final module = widget.module;
    final url = module.downloadLink;
    if (_busy || _checking || _installed || url == null || url.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
      _phase = 'Preparing download';
      _progress = null;
    });

    var installedSuccessfully = false;
    try {
      await _installer.downloadAndInstall(
        moduleId: module.moduleId,
        moduleName: module.name,
        downloadUrl: url,
        onDownloadProgress: (value) =>
            _updateProgress('Downloading module', value),
        onExtractionProgress: (value) =>
            _updateProgress('Extracting module', value),
      );
      installedSuccessfully = true;
      if (!mounted) return;
      setState(() {
        _phase = 'Installation complete';
        _progress = 1;
      });
      await _refreshInstallation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Module installed successfully.')),
      );
    } catch (error) {
      debugPrint('Module installation failed: $error');
      if (!mounted) return;
      await _refreshInstallation();
      if (!mounted) return;
      setState(() {
        _error = 'Installation could not be completed. Please try again.';
        _phase = 'Installation not completed';
        _progress = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // Location sharing is entirely optional and must never turn a successful
    // installation into a download failure.
    if (installedSuccessfully && mounted) {
      try {
        await _offerOptionalLocationSharing();
      } catch (_) {
        // The installed module remains available even if location fails.
      }
    }
  }

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _openMenu() async {
    final loggedIn = await checkIfUserIsLoggedIn();
    if (!mounted) return;
    _open(loggedIn ? Menu() : GuestMenu());
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    final description = module.description?.trim() ?? '';
    final canDownload = !_checking && !_busy && !_installed &&
        module.isDownloadable &&
        RegExp(r'^[0-9]+$').hasMatch(module.moduleId) &&
        Uri.tryParse(module.downloadLink ?? '')?.scheme == 'https';

    final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return AppLayout(
      appBar: CustomAppBar(
        onBackPressed: () => Navigator.pop(context),
        requireAuth: false,
      ),
      bottomNav: landscape
          ? null
          : CustomBottomNavBar(
        onHomeTap: () => _open(const MyHomePage()),
        onLibraryTap: () => _open(ModuleLibrary()),
        onTrackerTap: () => _open(AuthGuard(child: CreditsTracker())),
        onMenuTap: _openMenu,
      ),
      child: landscape
          ? Row(children: [
        CustomSideNavBar(
          onHomeTap: () => _open(const MyHomePage()),
          onLibraryTap: () => _open(ModuleLibrary()),
          onTrackerTap: () => _open(AuthGuard(child: CreditsTracker())),
          onMenuTap: _openMenu,
        ),
        Expanded(child: _detailsContent(description, canDownload)),
      ])
          : _detailsContent(description, canDownload),
    );
  }

  Widget _detailsContent(String description, bool canDownload) {
    final module = widget.module;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Module Details',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF183E59),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFD7E4EA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      module.name,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF16466A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Health Education Module',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF358347),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                      description.isEmpty
                          ? 'No description is available for this module.'
                          : description,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.55,
                        color: Color(0xFF455D6C),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_checking)
                      const Center(child: CircularProgressIndicator())
                    else
                      Text(
                        _installed ? 'Installed' : 'Not downloaded',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF358347),
                        ),
                      ),
                    if (_busy) ...[
                      const SizedBox(height: 18),
                      Text(_phase, style: const TextStyle(fontSize: 15)),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(value: _progress),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFF9C3C2E),
                          fontSize: 14,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: canDownload ? _install : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0876D6),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF9FB5C3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        child: Text(
                          _busy
                              ? 'Installing...'
                              : _installed
                              ? 'Installed'
                              : 'Download Module',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
