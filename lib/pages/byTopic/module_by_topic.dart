import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../../models/downloadable_module.dart';
import '../../providers/auth_guard.dart';
import '../../utils/app_layout.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../creditsTracker/credits_tracker.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_details_page.dart';
import '../module_library.dart';

/// Modules for a selected subtopic. Installation is handled by ModuleDetailsPage.
class ModuleByTopic extends StatefulWidget {
  final String subcategoryName;
  final int subcategoryId;

  const ModuleByTopic({super.key, required this.subcategoryName, required this.subcategoryId});

  @override
  State<ModuleByTopic> createState() => _ModuleByTopicState();
}

class _TopicEntry {
  final DownloadableModule module;
  final String? redirectFrom;

  const _TopicEntry(this.module, {this.redirectFrom});
}

class _ModuleByTopicState extends State<ModuleByTopic> {
  static const _blue = Color(0xFF16466A);
  static const _green = Color(0xFF358347);
  static const _background = Color(0xFFFFF0DC);

  late Future<List<_TopicEntry>> _modules;

  @override
  void initState() {
    super.initState();
    _modules = _loadModules();
  }

  @override
  void didUpdateWidget(covariant ModuleByTopic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subcategoryId != widget.subcategoryId) {
      _modules = _loadModules();
    }
  }

  Future<List<_TopicEntry>> _loadModules() async {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r"/+$"), "")}/modules')
        .replace(queryParameters: {'subcategoryId': widget.subcategoryId.toString()});
    final response = await http.get(uri, headers: {
      'Content-Type': 'application/json; charset=utf-8',
    }).timeout(const Duration(seconds: 25));

    if (response.statusCode != 200) {
      throw Exception('Unable to load modules (HTTP ${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Unexpected module catalog response.');
    }

    final entries = <_TopicEntry>[];

    for (final item in decoded) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);

      final redirect = json['redirectedModule'];
      final target = redirect is Map
          ? Map<String, dynamic>.from(redirect)
          : json;

      // Some older /modules responses identify the download with "id"
      // rather than "module_id". Preserve that compatibility.
      final normalized = Map<String, dynamic>.from(target);
      final moduleId = normalized['module_id']?.toString().trim() ?? '';
      if (moduleId.isEmpty) {
        normalized['module_id'] = normalized['id']?.toString() ?? '';
      }

      final module = DownloadableModule.fromJson(normalized);
      if (module.name.trim().isEmpty) continue;
      entries.add(_TopicEntry(
        module,
        redirectFrom: redirect is Map ? json['name']?.toString() : null,
      ));
    }

    entries.sort((a, b) {
      final first = (a.redirectFrom ?? a.module.name).toLowerCase();
      final second = (b.redirectFrom ?? b.module.name).toLowerCase();
      return first.compareTo(second);
    });
    return entries;
  }

  void _reload() {
    setState(() => _modules = _loadModules());
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
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

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
          ? Row(
        children: [
          CustomSideNavBar(
            onHomeTap: () => _open(const MyHomePage()),
            onLibraryTap: () => _open(ModuleLibrary()),
            onTrackerTap: () => _open(AuthGuard(child: CreditsTracker())),
            onMenuTap: _openMenu,
          ),
          Expanded(child: _content()),
        ],
      )
          : _content(),
    );
  }

  Widget _content() {
    return Stack(
      children: [
        Container(
          color: _background,
          child: RefreshIndicator(
            onRefresh: () async {
              _reload();
              try {
                await _modules;
              } catch (_) {
                // Error state includes a retry button.
              }
            },
            child: FutureBuilder<List<_TopicEntry>>(
              future: _modules,
              builder: (context, snapshot) {
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 26, 20, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Modules by Topic',
                                  style: TextStyle(
                                    fontSize: 27,
                                    fontWeight: FontWeight.w700,
                                    color: _blue,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  snapshot.hasData
                                      ? '${widget.subcategoryName}  ·  ${snapshot.data!.length} ${snapshot.data!.length == 1 ? "module" : "modules"}'
                                      : widget.subcategoryName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF607889),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (snapshot.connectionState != ConnectionState.done)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snapshot.hasError)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _message(
                          Icons.wifi_off_rounded,
                          'Unable to load modules',
                          'Check your connection and try again.',
                          retry: true,
                        ),
                      )
                    else if ((snapshot.data ?? []).isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _message(
                            Icons.search_off_rounded,
                            'No modules found',
                            'There are no modules listed under this subtopic.',
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                final entry = snapshot.data![index];
                                return Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 760),
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _moduleCard(entry),
                                    ),
                                  ),
                                );
                              },
                              childCount: snapshot.data!.length,
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
          ),
        ),
        // Fade above the fixed navigation bar; does not intercept scrolling.
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

  Widget _moduleCard(_TopicEntry entry) {
    final module = entry.module;
    final redirected = entry.redirectFrom != null;

    return Material(
      color: Colors.white,
      elevation: 1.5,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _open(ModuleDetailsPage(module: module)),
        child: Container(
          constraints: const BoxConstraints(minHeight: 90),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFD7E4EA)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5EC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.menu_book_outlined, color: _green),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (redirected) ...[
                      Text(
                        '${entry.redirectFrom} · See also',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _green,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      module.name,
                      style: const TextStyle(
                        color: _blue,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF0876D6)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(IconData icon, String title, String detail,
      {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _green, size: 48),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: _blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF607889)),
            ),
            if (retry) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}