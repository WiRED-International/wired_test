import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/auth_guard.dart';
import '../utils/app_layout.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import '../utils/webview_screen.dart';
import 'creditsTracker/credits_tracker.dart';
import 'home_page.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';

const _blue = Color(0xFF16466A);
const _deepBlue = Color(0xFF16466A);
const _green = Color(0xFF358347);
const _pastelBlue = Color(0xFFD9EAF7);

class ModuleFile {
  final FileSystemEntity file;
  final String path;
  final String moduleName;
  final String moduleId;
  final bool isCompiler;
  final bool isAnimation;
  final String? contentDirectory;

  const ModuleFile({
    required this.file,
    required this.path,
    required this.moduleName,
    required this.moduleId,
    this.isCompiler = false,
    this.isAnimation = false,
    this.contentDirectory,
  });
}

class ModuleLibrary extends StatefulWidget {
  const ModuleLibrary({super.key});

  @override
  State<ModuleLibrary> createState() => _ModuleLibraryState();
}

class _ModuleLibraryState extends State<ModuleLibrary> {
  final _storage = const FlutterSecureStorage();
  final _searchController = TextEditingController();
  List<ModuleFile> _modules = [];
  bool _loading = true;
  String? _error;
  String _sort = 'Name A–Z';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refreshSearch);
    _loadModules();
  }

  @override
  void dispose() {
    _searchController.removeListener(_refreshSearch);
    _searchController.dispose();
    super.dispose();
  }

  void _refreshSearch() => setState(() {});

  Future<Directory> _storageRoot() async {
    if (Platform.isAndroid) {
      return await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return getApplicationSupportDirectory();
    }
    return getApplicationDocumentsDirectory();
  }

  String _filename(String path) =>
      path.replaceAll('\\', '/').split('/').last;

  String _withoutExtension(String filename) =>
      filename.replaceFirst(RegExp(r'\.html?$', caseSensitive: false), '');

  String _decodeHtml(String input) => input
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  String? _titleFromLauncher(String content) {
    final match = RegExp(
      r'''<meta\s+name=["']module-title["']\s+content=["']([^"']*)''',
      caseSensitive: false,
    ).firstMatch(content);
    return match == null ? null : _decodeHtml(match.group(1)!).trim();
  }

  // Preserve the historical Storyline ID extraction rules. In particular,
  // package launchers use the second capture group, as in the old Library.
  String? _legacyId(String content, {required bool package}) {
    if (package) {
      final match = RegExp(
        r'content="0; url=files/(\d{4})/([^/]+)/story.html"',
      ).firstMatch(content);
      return match?.group(2);
    }
    return RegExp(r'files/(\d+)/story.html').firstMatch(content)?.group(1);
  }

  Future<void> _loadModules() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final root = await _storageRoot();
      final result = <ModuleFile>[];
      final packages = Directory('${root.path}/packages');
      final modules = Directory('${root.path}/modules');

      if (await packages.exists()) {
        await for (final entity in packages.list(recursive: true, followLinks: false)) {
          if (entity is! File) {
            continue;
          }
          final name = _filename(entity.path);
          final lower = name.toLowerCase();
          if (!(lower.endsWith('.htm') || lower.endsWith('.html')) ||
              lower.contains('story') ||
              lower.contains('meta') ||
              lower.contains('analytics-frame')) {
            continue;
          }
          try {
            final html = await entity.readAsString();
            final display = _titleFromLauncher(html);
            final title = display != null && display.isNotEmpty
                ? display : _withoutExtension(name);
            result.add(ModuleFile(
              file: entity,
              path: entity.path,
              moduleName: title,
              moduleId: _legacyId(html, package: true) ?? _withoutExtension(name),
            ));
          } catch (_) {
            // An unreadable launcher should not prevent other modules loading.
          }
        }
      }

      if (await modules.exists()) {
        await for (final entity in modules.list(followLinks: false)) {
          if (entity is File) {
            final name = _filename(entity.path);
            if (!RegExp(r'\.html?$', caseSensitive: false).hasMatch(name)) continue;
            try {
              final html = await entity.readAsString();
              final display = _titleFromLauncher(html);
              final title = display != null && display.isNotEmpty
                  ? display : _withoutExtension(name);
              result.add(ModuleFile(
                file: entity,
                path: entity.path,
                moduleName: title,
                moduleId: _legacyId(html, package: false) ?? _withoutExtension(name),
              ));
            } catch (_) {}
          } else if (entity is Directory) {
            final index = File('${entity.path}/index.html');
            final story = File('${entity.path}/story.html');
            final hasIndex = await index.exists();
            final hasStory = await story.exists();
            if (!hasIndex && !hasStory) continue;

            final folder = _filename(entity.path);
            var id = folder;
            var title = folder;
            final metadata = File('${entity.path}/module.json');
            if (await metadata.exists()) {
              try {
                final data = jsonDecode(await metadata.readAsString());
                if (data is Map) {
                  id = data['module_id']?.toString() ?? id;
                  title = data['module_title']?.toString() ?? title;
                }
              } catch (_) {}
            }
            result.add(ModuleFile(
              file: entity,
              path: hasIndex ? index.path : story.path,
              moduleName: title,
              moduleId: id,
              isCompiler: hasIndex,
              contentDirectory: entity.path,
            ));
          }
        }
      }
      // Animations are MP4 files, not HTML modules. Include videos in the
      // existing modules folder (including previously downloaded animations).
      if (await modules.exists()) {
        await for (final entity in modules.list(recursive: true, followLinks: false)) {
          if (entity is! File || !entity.path.toLowerCase().endsWith('.mp4')) continue;
          if (await entity.length() == 0) continue;
          final name = _filename(entity.path);
          final stem = name.replaceFirst(RegExp(r'\.mp4$', caseSensitive: false), '');
          final title = stem.replaceAll(RegExp(r'[_-]+'), ' ').trim();
          result.add(ModuleFile(
            file: entity,
            path: entity.path,
            moduleName: title.isEmpty ? name : title,
            moduleId: stem,
            isAnimation: true,
          ));
        }
      }
      if (!mounted) return;
      setState(() { _modules = result; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Unable to load downloaded modules: $e'; });
    }
  }

  List<ModuleFile> get _visibleModules {
    final query = _searchController.text.trim().toLowerCase();
    final list = _modules.where((m) =>
    m.moduleName.toLowerCase().contains(query) ||
        m.moduleId.toLowerCase().contains(query)).toList();
    list.sort((a, b) => _sort == 'Name Z–A'
        ? b.moduleName.toLowerCase().compareTo(a.moduleName.toLowerCase())
        : a.moduleName.toLowerCase().compareTo(b.moduleName.toLowerCase()));
    return list;
  }

  Future<void> _play(ModuleFile module) async {
    final entry = File(module.path);
    if (!await entry.exists()) {
      if (mounted) _notify('Module files are missing. Refresh your library.');
      return;
    }
    try {
      if (module.isAnimation) {
        final result = await OpenFile.open(module.path, type: 'video/mp4');
        if (result.type != ResultType.done && mounted) {
          _notify('Unable to open this animation: ${result.message}');
        }
        return;
      }
      // Wait for both writes: the WebView reads these values on load.
      await _storage.write(key: 'module_id', value: module.moduleId);
      await _storage.write(key: 'module_name', value: module.moduleName);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebViewScreen(
            urlRequest: URLRequest(
              url: WebUri(Uri.file(module.path).toString()),
            ),
            moduleId: module.moduleId,
          ),
        ),
      );
      if (mounted) _loadModules();
    } catch (e) {
      if (mounted) _notify('Unable to open this module.');
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete(ModuleFile module) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(module.isAnimation ? 'Remove downloaded animation?' : 'Remove downloaded module?'),
        content: Text(
          'Remove "${module.moduleName}" from this device?\n\n'
              'Saved quiz scores will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _delete(module);
  }

  Future<void> _delete(ModuleFile module) async {
    try {
      if (module.isAnimation) {
        await (module.file as File).delete();
      } else if (module.file is Directory) {
        // Compiler content is isolated in its own directory.
        await (module.file as Directory).delete(recursive: true);
      } else {
        final launcher = module.file as File;
        final html = await launcher.readAsString();
        final root = await _storageRoot();

        // New standalone Storyline launchers point to ../files/<folder>/story.html.
        // Only remove the associated folder when the launcher lives directly in
        // modules/ and no other launcher references that same folder.
        final match = RegExp(
          r'\.\./files/([^/"?<>]+)/story\.html',
          caseSensitive: false,
        ).firstMatch(html);
        Directory? content;
        if (match != null &&
            launcher.parent.path == '${root.path}/modules') {
          final folder = Uri.decodeComponent(match.group(1)!);
          if (folder != '.' && folder != '..' &&
              !folder.contains('/') && !folder.contains('\\')) {
            final candidate = Directory('${root.path}/files/$folder');
            if (await candidate.exists()) {
              var referencedElsewhere = false;
              final moduleDir = Directory('${root.path}/modules');
              await for (final sibling in moduleDir.list(followLinks: false)) {
                if (sibling is! File || sibling.path == launcher.path) {
                  continue;
                }
                if (!RegExp(r'\.html?$', caseSensitive: false)
                    .hasMatch(sibling.path)) {
                  continue;
                }
                try {
                  if ((await sibling.readAsString())
                      .contains('../files/$folder/story.html')) {
                    referencedElsewhere = true;
                    break;
                  }
                } catch (_) {}
              }
              if (!referencedElsewhere) content = candidate;
            }
          }
        }

        // Legacy package content can be shared. Do not recursively delete it.
        await launcher.delete();
        if (content != null) await content.delete(recursive: true);
      }
      if (!mounted) return;
      _notify('Removed "${module.moduleName}" from this device.');
      await _loadModules();
    } catch (_) {
      if (mounted) _notify('Unable to remove this module.');
    }
  }

  void _goHome() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const MyHomePage()));

  void _goTracker() => Navigator.push(
      context, MaterialPageRoute(builder: (_) =>
      AuthGuard(child: CreditsTracker())));

  Future<void> _goMenu() async {
    final loggedIn = await checkIfUserIsLoggedIn();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => loggedIn ? Menu() : GuestMenu()));
  }

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return AppLayout(
      appBar: CustomAppBar(
        onBackPressed: () => Navigator.pop(context),
        requireAuth: false,
      ),
      bottomNav: landscape ? null : CustomBottomNavBar(
        onHomeTap: _goHome,
        onLibraryTap: () {},
        onTrackerTap: _goTracker,
        onMenuTap: _goMenu,
      ),
      child: landscape
          ? Row(children: [
        CustomSideNavBar(
          onHomeTap: _goHome,
          onLibraryTap: () {},
          onTrackerTap: _goTracker,
          onMenuTap: _goMenu,
        ),
        Expanded(child: _libraryContent()),
      ])
          : _libraryContent(),
    );
  }

  Widget _libraryContent() {
    final visible = _visibleModules;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.0, 0.91, 1.0],
        colors: [Colors.white, Colors.white, Colors.transparent],
      ).createShader(bounds),
      child: RefreshIndicator(
        onRefresh: _loadModules,
        color: _green,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(child: _tools()),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: _blue)),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                )),
              )
            else if (visible.isEmpty)
                SliverFillRemaining(
                  child: _emptyState(_modules.isEmpty),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 86),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.crossAxisExtent;
                      final columns = width >= 980 ? 3 : width >= 620 ? 2 : 1;
                      if (columns == 1) {
                        return SliverList.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _moduleCard(visible[index]),
                          ),
                        );
                      }
                      return SliverGrid.builder(
                        itemCount: visible.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: 165,
                        ),
                        itemBuilder: (context, index) => _moduleCard(visible[index]),
                      );
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.auto_stories_outlined, color: _blue, size: 25),
        const SizedBox(width: 9),
        const Expanded(
          child: Text('My Library',
              style: TextStyle(color: _blue, fontSize: 25,
                  fontWeight: FontWeight.w700)),
        ),
        Text(
          '${_modules.length} downloaded',
          style: const TextStyle(color: _green, fontSize: 12,
              fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Widget _tools() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 7),
    child: Column(children: [
      TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search downloaded modules',
          prefixIcon: const Icon(Icons.search, color: _blue),
          suffixIcon: _searchController.text.isEmpty ? null : IconButton(
            tooltip: 'Clear search',
            onPressed: _searchController.clear,
            icon: const Icon(Icons.close),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.blueGrey.shade100),
          ),
        ),
      ),
      const SizedBox(height: 3),
      Row(children: [
        Expanded(child: Text(
          _loading ? 'Loading modules…' : '${_visibleModules.length} shown',
          style: const TextStyle(color: _deepBlue,
              fontWeight: FontWeight.w600),
        )),
        DropdownButton<String>(
          value: _sort,
          underline: const SizedBox.shrink(),
          items: ['Name A–Z', 'Name Z–A'].map((value) =>
              DropdownMenuItem(value: value, child: Text(value))).toList(),
          onChanged: (value) {
            if (value != null) setState(() => _sort = value);
          },
        ),
        IconButton(
          tooltip: 'Refresh library',
          onPressed: _loading ? null : _loadModules,
          icon: const Icon(Icons.refresh, color: _blue),
        ),
      ]),
    ]),
  );

  Widget _moduleCard(ModuleFile module) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE1EAF1)),
      boxShadow: const [
        BoxShadow(color: Color(0x0D173F5C), blurRadius: 14, offset: Offset(0, 4)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F4EB),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(module.isAnimation ? Icons.ondemand_video_rounded : Icons.menu_book_rounded, color: _green),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(module.moduleName,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16, height: 1.25,
                    fontWeight: FontWeight.w700, color: _deepBlue,
                  )),
            ],
          )),
        ]),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(child: FilledButton.icon(
            onPressed: () => _play(module),
            style: FilledButton.styleFrom(
              backgroundColor: _pastelBlue,
              foregroundColor: _blue,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(module.isAnimation ? 'Open animation' : 'Open module'),
          )),
          const SizedBox(width: 10),
          IconButton.outlined(
            tooltip: 'Remove download',
            onPressed: () => _confirmDelete(module),
            icon: const Icon(Icons.delete_outline, color: Color(0xFF8C4C4C)),
          ),
        ]),
      ],
    ),
  );

  Widget _emptyState(bool noDownloads) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(noDownloads ? Icons.library_books_outlined : Icons.search_off,
            size: 58, color: _blue),
        const SizedBox(height: 14),
        Text(noDownloads ? 'Your library is empty' : 'No matching modules',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700,
                color: _deepBlue)),
        const SizedBox(height: 8),
        Text(
          noDownloads
              ? 'Download a module to make it available here, even without internet.'
              : 'Try a different search term.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
        if (!noDownloads) ...[
          const SizedBox(height: 14),
          TextButton(
            onPressed: _searchController.clear,
            child: const Text('Clear search'),
          ),
        ],
      ]),
    ),
  );
}

