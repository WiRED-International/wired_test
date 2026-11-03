import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_guard.dart';
import '../../services/animation_preparation_service.dart';
import '../../services/animation_installation_coordinator.dart';
import '../../services/animation_installation_inspection_service.dart';
import '../../services/animation_storage_service.dart';
import '../../services/location_service.dart';
import '../../utils/app_layout.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../creditsTracker/credits_tracker.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';

class AnimationInfo extends StatefulWidget {
  final int animationId;
  final String animationName;
  final String animationDescription;
  final String downloadLink;

  const AnimationInfo({
    super.key,
    required this.animationId,
    required this.animationName,
    required this.animationDescription,
    required this.downloadLink,
  });

  @override
  State<AnimationInfo> createState() => _AnimationInfoState();
}

class _AnimationInfoState extends State<AnimationInfo> {
  static const _heading = Color(0xFF183E59);
  static const _blue = Color(0xFF16466A);
  static const _brandBlue = Color(0xFF0070C0);
  static const _green = Color(0xFF358347);
  static const _border = Color(0xFFD7E4EA);

  bool _busy = false;
  bool _completed = false;
  double? _progress;
  String _phase = '';
  String? _error;

  AnimationPreparationCancellation? _cancellation;
  Future<void>? _operation;
  bool _navigating = false;

  Future<void> _open(Widget page) async {
    if (_navigating) return;
    _navigating = true;
    try {
      _cancel();
      await _operation;
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    } finally {
      _navigating = false;
    }
  }

  Future<void> _back() async {
    if (_navigating) return;
    _navigating = true;
    _cancel();
    await _operation;
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    _navigating = false;
  }

  Future<void> _openMenu() async {
    final loggedIn = await checkIfUserIsLoggedIn();
    if (!mounted) return;
    await _open(loggedIn ? Menu() : GuestMenu());
  }

  void _cancel() {
    if (!_busy || _cancellation == null) return;
    _cancellation!.cancel();
    if (mounted) {
      setState(() {
        _phase = 'Cancelling...';
        _progress = null;
      });
    }
  }

  @override
  void dispose() {
    // The async owner continues to await publication and cleanup after disposal.
    _cancellation?.cancel();
    super.dispose();
  }

  void _onProgress(AnimationPreparationProgress progress) {
    if (!mounted || (_cancellation?.isRequested ?? false)) return;
    setState(() {
      _phase = switch (progress.phase) {
        AnimationPreparationPhase.inspectingDestination =>
          'Checking installation',
        AnimationPreparationPhase.creatingWorkspace => 'Preparing download',
        AnimationPreparationPhase.downloading => 'Downloading animation',
        AnimationPreparationPhase.inspectingZip => 'Inspecting archive',
        AnimationPreparationPhase.verifyingZip => 'Verifying archive',
        AnimationPreparationPhase.extracting => 'Extracting animation',
        AnimationPreparationPhase.verifyingStaged => 'Verifying animation',
        AnimationPreparationPhase.prepared => 'Ready to install',
        AnimationPreparationPhase.publishing => 'Installing animation',
        AnimationPreparationPhase.cleaningUp => 'Cleaning up',
      };
      _progress = progress.phase == AnimationPreparationPhase.downloading
          ? progress.download?.fraction
          : null;
    });
  }

  void _download() {
    if (_busy || _completed) return;
    if (widget.animationId <= 0) {
      setState(() => _error = 'A valid animation ID is not available.');
      return;
    }
    final uri = Uri.tryParse(widget.downloadLink);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      setState(() => _error = 'A valid HTTPS download link is not available.');
      return;
    }
    final installer = context.read<AnimationPreparationService>();
    final storage = context.read<AnimationStorageService>();
    final statistics = context.read<LocationService>();
    final cancellation = _cancellation = AnimationPreparationCancellation();
    setState(() {
      _busy = true;
      _error = null;
      _phase = 'Preparing download';
      _progress = null;
    });
    _operation = _install(installer, storage, statistics, uri, cancellation);
  }

  Future<void> _install(
    AnimationPreparationService installer,
    AnimationStorageService storage,
    LocationService statistics,
    Uri uri,
    AnimationPreparationCancellation cancellation,
  ) async {
    var published = false;
    try {
      final root = await storage.getCanonicalRoot();
      await installer.withPrepared<PublishedAnimation>(
        animationId: widget.animationId,
        canonicalRoot: root,
        downloadUri: uri,
        cancellation: cancellation,
        onProgress: _onProgress,
        use: (prepared) async => await prepared.publish(),
      );
      published = true;
      if (mounted) {
        setState(() {
          _completed = true;
          _error = null;
        });
      }
    } on AnimationPublicationCommittedException catch (error) {
      published = true;
      debugPrint('Animation installed with subsequent error: $error');
      if (mounted) {
        setState(() {
          _completed = true;
          _error =
              'Animation installed, but a follow-up operation could not finish.';
        });
      }
    } on AnimationPreparationDestinationException catch (error) {
      if (mounted) {
        setState(() {
          _completed = error.status == AnimationInstallationStatus.installed;
          _error = _completed
              ? 'This animation is already installed.'
              : 'Existing content prevents installation. Open My Library to review it.';
        });
      }
    } on AnimationInstallationInProgressException {
      if (mounted) {
        setState(() => _error = 'This animation is already being installed.');
      }
    } on AnimationPreparationCancelled {
      if (mounted) setState(() => _error = 'Download cancelled.');
    } on AnimationPreparationCleanupException catch (error) {
      debugPrint('Animation private cleanup failed: $error');
      if (mounted) {
        setState(() => _error =
            'Installation did not finish and temporary files could not be cleaned up.');
      }
    } catch (error) {
      debugPrint('Animation download failed: $error');
      if (mounted) {
        setState(() =>
            _error = 'Download could not be completed. Please try again.');
      }
    } finally {
      _cancellation = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
    if (published) unawaited(_recordDownload(statistics));
  }

  Future<void> _recordDownload(LocationService statistics) async {
    // Tracking cannot hold navigation or change the installed result. Avoid
    // permission dialogs whose page context could be disposed while awaiting.
    try {
      await statistics.saveDownload(widget.animationId, null);
    } catch (error) {
      debugPrint('Animation download tracking unavailable: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: AppLayout(
        appBar: CustomAppBar(
          onBackPressed: _back,
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
                Expanded(child: _content()),
              ])
            : _content(),
      ),
    );
  }

  Widget _content() {
    final description = widget.animationDescription.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Animation Details',
                  style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                      color: _heading)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.animationName,
                        style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: _blue)),
                    const SizedBox(height: 12),
                    const Text('Health Education Animation',
                        style: TextStyle(
                            fontSize: 14,
                            color: _green,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 18),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                        description.isEmpty
                            ? 'No description is available for this animation.'
                            : description,
                        style: const TextStyle(
                            fontSize: 16,
                            height: 1.55,
                            color: Color(0xFF455D6C))),
                    const SizedBox(height: 24),
                    Text(_completed ? 'Downloaded' : 'Not downloaded',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _green)),
                    if (_busy) ...[
                      const SizedBox(height: 18),
                      Text(_phase, style: const TextStyle(fontSize: 15)),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(value: _progress),
                      TextButton(
                        onPressed: (_cancellation?.isRequested ?? false)
                            ? null
                            : _cancel,
                        child: const Text('Cancel'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xFF9C3C2E))),
                    ],
                    if (!_completed && _error != null && !_busy) ...[
                      TextButton(
                          onPressed: () => _open(ModuleLibrary()),
                          child: const Text('Open My Library')),
                    ],
                    if (_completed) ...[
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F8F2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFB9DFC5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    color: Color(0xFF25834A), size: 28),
                                SizedBox(width: 10),
                                Expanded(
                                    child: Text(
                                        'Animation downloaded successfully!',
                                        style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF205D38)))),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Text(
                                'Your animation is ready to use offline.',
                                style: TextStyle(
                                    fontSize: 14, color: Color(0xFF345A43))),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: () => _open(ModuleLibrary()),
                                icon: const Icon(Icons.library_books_outlined),
                                label: const Text('Open My Library'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0876D6),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 48,
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.arrow_back_rounded),
                                label: const Text('Browse More Animations'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _busy ? null : _download,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brandBlue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF9FB5C3),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13)),
                          ),
                          child: Text(
                              _busy ? 'Downloading...' : 'Download Animation',
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
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
