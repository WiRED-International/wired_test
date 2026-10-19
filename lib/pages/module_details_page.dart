import 'dart:io';

import 'package:flutter/material.dart';

import '../models/downloadable_module.dart';
import '../services/module_download_service.dart';
import '../services/module_installation_coordinator.dart';
import '../utils/app_layout.dart';
import '../utils/custom_app_bar.dart';

/// New, compiler-format module details and installation screen.
///
/// Keep legacy Storyline modules on their existing download path until
/// their installation and offline-launch behavior has been migrated.
class ModuleDetailsPage extends StatefulWidget {
  final DownloadableModule module;

  const ModuleDetailsPage({super.key, required this.module});

  @override
  State<ModuleDetailsPage> createState() => _ModuleDetailsPageState();
}

class _ModuleDetailsPageState extends State<ModuleDetailsPage> {
  final ModuleDownloadService _downloads = ModuleDownloadService();
  late final ModuleInstallationCoordinator _coordinator =
  ModuleInstallationCoordinator(downloadService: _downloads);

  bool _checking = true;
  bool _busy = false;
  bool _installed = false;
  bool _needsRecovery = false;
  double? _progress;
  String _phase = '';
  String? _error;
  String? _installedVersion;

  @override
  void initState() {
    super.initState();
    _refreshInstallation();
  }

  Future<void> _refreshInstallation() async {
    if (mounted) setState(() => _checking = true);
    try {
      final state = await _coordinator.inspectInstallation(widget.module.moduleId);
      final filesystem = state['filesystem_state'] as String;
      final record = state['registry_record'] as Map<String, dynamic>?;
      final installed = filesystem == 'installed' && record != null;
      final recovery = filesystem == 'replacement_pending' ||
          filesystem == 'restore_required' ||
          (filesystem == 'installed' && record == null) ||
          (filesystem == 'not_installed' && record != null);
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _needsRecovery = recovery;
        _installedVersion = record?['version']?.toString();
        _error = recovery
            ? 'This module has an incomplete installation that needs recovery.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Unable to check installation: $error');
    } finally {
      if (mounted) setState(() => _checking = false);
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
    if (_busy || _checking || _needsRecovery || url == null || url.isEmpty) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _phase = 'Preparing download';
      _progress = null;
    });

    File? zip;
    try {
      // Do not alter an existing installation until validation succeeds.
      await _coordinator.ensureReadyForInstallation(module.moduleId);

      final staging = await _downloads.getStagingDirectory(module.moduleId);
      if (await staging.exists()) {
        throw StateError(
          'An earlier installation is still staged. It must be reviewed '
              'before another download can begin.',
        );
      }

      if (mounted) setState(() => _phase = 'Downloading module');
      zip = await _downloads.downloadModuleZip(
        moduleId: module.moduleId,
        downloadUrl: url,
        onProgress: (value) => _updateProgress('Downloading module', value),
      );

      if (mounted) {
        setState(() {
          _phase = 'Extracting module';
          _progress = 0;
        });
      }
      await _downloads.extractModuleZip(
        moduleId: module.moduleId,
        zipFile: zip,
        onProgress: (value) => _updateProgress('Extracting module', value),
      );

      if (mounted) {
        setState(() {
          _phase = 'Validating and installing';
          _progress = null;
        });
      }
      await _coordinator.installModule(
        moduleId: module.moduleId,
        version: module.version?.trim().isNotEmpty == true
            ? module.version!.trim()
            : 'unspecified',
      );

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
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _phase = 'Installation not completed';
        _progress = null;
      });
      await _refreshInstallation();
      if (!mounted) return;
      // Refresh may clear an ordinary error; preserve the operation failure.
      setState(() => _error = error.toString());
    } finally {
      // A downloaded ZIP is temporary. Do not delete staging/backup folders:
      // their presence may indicate a recoverable interrupted installation.
      if (zip != null) {
        try {
          if (await zip.exists()) await zip.delete();
        } on FileSystemException {
          // A cleanup failure must not change installation status.
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    final description = module.description?.trim() ?? '';
    final canDownload = !_checking && !_busy && !_needsRecovery &&
        module.isDownloadable &&
        RegExp(r'^[0-9]+$').hasMatch(module.moduleId) &&
        Uri.tryParse(module.downloadLink ?? '')?.scheme == 'https';

    return AppLayout(
      appBar: CustomAppBar(
        onBackPressed: () => Navigator.pop(context),
        requireAuth: false,
      ),
      bottomNav: null,
      child: SingleChildScrollView(
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
                          _needsRecovery
                              ? 'Installation needs attention'
                              : _installed
                              ? 'Installed${_installedVersion == null ? '' : ' · Version $_installedVersion'}'
                              : 'Not downloaded',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _needsRecovery
                                ? const Color(0xFFAA5A17)
                                : const Color(0xFF358347),
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
                                ? 'Update Module'
                                : 'Download Module',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (_needsRecovery) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Downloading is disabled until the previous installation is recovered.',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}