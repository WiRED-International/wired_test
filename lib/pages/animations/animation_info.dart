import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../providers/auth_guard.dart';
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

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _openMenu() async {
    final loggedIn = await checkIfUserIsLoggedIn();
    if (!mounted) return;
    _open(loggedIn ? Menu() : GuestMenu());
  }

  void _setProgress(String phase, double? progress) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _progress = progress?.clamp(0.0, 1.0);
    });
  }

  Future<String> _storagePath() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      // Use the internal application documents directory instead.
    }
    base ??= await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}/modules');
    await directory.create(recursive: true);
    return directory.path;
  }

  Future<void> _download() async {
    if (_busy || _completed) return;
    final uri = Uri.tryParse(widget.downloadLink);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      setState(() => _error = 'A valid HTTPS download link is not available.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _phase = 'Preparing download';
      _progress = null;
    });

    File? zipFile;
    HttpClient? client;
    try {
      final path = await _storagePath();
      // Temporary archive name is independent of the animation's display name.
      zipFile = File('$path/.animation_${widget.animationId}_${DateTime.now().microsecondsSinceEpoch}.zip');
      client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 30));
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }

      var received = 0;
      final total = response.contentLength;
      final sink = zipFile.openWrite();
      try {
        await for (final chunk in response.timeout(const Duration(seconds: 45))) {
          sink.add(chunk);
          received += chunk.length;
          _setProgress('Downloading animation', total > 0 ? received / total : null);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (total >= 0 && received != total) {
        throw const FormatException('The download was incomplete.');
      }

      _setProgress('Extracting animation', 0);
      final port = ReceivePort();
      try {
        await Isolate.spawn(_extractAnimationArchive, {
          'zipPath': zipFile.path,
          'outputDir': path,
          'sendPort': port.sendPort,
        });
        await for (final message in port) {
          if (message is double) {
            _setProgress('Extracting animation', message);
          } else if (message == 'done') {
            break;
          } else if (message is String && message.startsWith('error:')) {
            throw FormatException(message.substring(6));
          }
        }
      } finally {
        port.close();
      }

      // A completed extraction is not sufficient: My Library needs an MP4.
      final installedVideos = await Directory(path)
          .list(recursive: true, followLinks: false)
          .where((entity) => entity is File && entity.path.toLowerCase().endsWith('.mp4'))
          .cast<File>()
          .toList();
      var hasPlayableFile = false;
      for (final video in installedVideos) {
        if (await video.length() > 0) {
          hasPlayableFile = true;
          break;
        }
      }
      if (!hasPlayableFile) {
        throw const FormatException('The ZIP did not install a playable MP4 animation.');
      }
      if (!mounted) return;
      setState(() {
        _completed = true;
        _phase = 'Download complete';
        _progress = 1;
      });

      // Statistics are best-effort and must not turn a successful download
      // into a failure. This retains the previous animation tracking behavior.
      try {
        final locationService = LocationService();
        final location = await locationService.getLocation(context);
        await locationService.saveDownload(widget.animationId, location);
      } catch (error) {
        debugPrint('Animation download tracking unavailable: $error');
      }
    } catch (error) {
      debugPrint('Animation download failed: $error');
      if (mounted) {
        setState(() {
          _error = 'Download could not be completed. Please try again.';
          _phase = '';
          _progress = null;
        });
      }
    } finally {
      client?.close(force: true);
      if (zipFile != null) {
        try {
          if (await zipFile.exists()) await zipFile.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
        Expanded(child: _content()),
      ])
          : _content(),
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
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700, color: _heading)),
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
                        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: _blue)),
                    const SizedBox(height: 12),
                    const Text('Health Education Animation',
                        style: TextStyle(fontSize: 14, color: _green, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 18),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(description.isEmpty
                        ? 'No description is available for this animation.'
                        : description,
                        style: const TextStyle(fontSize: 16, height: 1.55, color: Color(0xFF455D6C))),
                    const SizedBox(height: 24),
                    Text(_completed ? 'Downloaded' : 'Not downloaded',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _green)),
                    if (_busy) ...[
                      const SizedBox(height: 18),
                      Text(_phase, style: const TextStyle(fontSize: 15)),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(value: _progress),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(fontSize: 14, color: Color(0xFF9C3C2E))),
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
                                    child: Text('Animation downloaded successfully!',
                                        style: TextStyle(fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF205D38)))),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Text('Your animation is ready to use offline.',
                                style: TextStyle(fontSize: 14, color: Color(0xFF345A43))),
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
                          child: Text(_busy ? 'Downloading...' : 'Download Animation',
                              style: const TextStyle(fontSize: 17,
                                  fontWeight: FontWeight.w700)),
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

// Keep the animation ZIP layout compatible with existing offline playback.
// Reject unsafe entries before writing any extracted files.
Future<void> _extractAnimationArchive(Map<String, dynamic> args) async {
  final port = args['sendPort'] as SendPort;
  try {
    final zipPath = args['zipPath'] as String;
    final outputDir = args['outputDir'] as String;
    final input = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeStream(input);

    final root = Directory(outputDir).absolute.path;
    final normalizedRoot = root.replaceAll('\\', '/');
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      final parts = name.split('/');
      if (name.startsWith('/') || name.contains(':') ||
          parts.contains('..') || parts.contains('.') ||
          parts.any((part) => part.isEmpty && part != parts.last) ||
          entry.isSymbolicLink) {
        throw const FormatException('Unsafe archive entry.');
      }
      final target = File('$root/$name').absolute.path.replaceAll('\\', '/');
      if (!target.startsWith('$normalizedRoot/')) {
        throw const FormatException('Archive entry escapes the storage directory.');
      }
    }

    var count = 0;
    for (final entry in archive) {
      final target = '$root/${entry.name.replaceAll('\\', '/')}';
      if (entry.isFile) {
        await Directory(File(target).parent.path).create(recursive: true);
        final output = OutputFileStream(target);
        try {
          entry.writeContent(output);
        } finally {
          await output.close();
        }
      } else {
        await Directory(target).create(recursive: true);
      }
      count++;
      port.send(count / archive.length);
    }
    await input.close();
    port.send('done');
  } catch (error) {
    port.send('error:$error');
  }
}



