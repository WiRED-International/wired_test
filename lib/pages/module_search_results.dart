import 'package:flutter/material.dart';
import 'package:wired_test/pages/home_page.dart';

import '../models/downloadable_module.dart';
import '../providers/auth_guard.dart';
import '../services/module_catalog_service.dart';
import '../utils/app_layout.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'creditsTracker/credits_tracker.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
import 'module_details_page.dart';
import 'module_library.dart';

class ModuleSearchResults extends StatefulWidget {
  final String initialQuery;

  const ModuleSearchResults({super.key, required this.initialQuery});

  @override
  State<ModuleSearchResults> createState() => _ModuleSearchResultsState();
}

class _ModuleSearchResultsState extends State<ModuleSearchResults> {
  late final TextEditingController _controller;
  late final Future<List<DownloadableModule>> _catalog;
  late String _query;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery.trim();
    _controller = TextEditingController(text: _query);
    _catalog = ModuleCatalogService().fetchModules();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _openMenu() async {
    final loggedIn = await checkIfUserIsLoggedIn();
    if (!mounted) return;
    _open(loggedIn ? Menu() : GuestMenu());
  }

  List<DownloadableModule> _matches(List<DownloadableModule> modules) {
    return modules.where((module) => module.matchesSearch(_query)).toList();
  }

  void _search(String input) {
    setState(() => _query = input.trim());
    FocusScope.of(context).unfocus();
  }

  void _openModule(DownloadableModule module) {
    _open(ModuleDetailsPage(module: module));
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
            onTrackerTap: () =>
                _open(AuthGuard(child: CreditsTracker())),
            onMenuTap: _openMenu,
          ),
          Expanded(child: _content()),
        ],
      )
          : _content(),
    );
  }

  Widget _content() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 740),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Search Results',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF183E59),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _search,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Search modules',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search,
                          color: Color(0xFF0070C0)),
                      suffixIcon: IconButton(
                        tooltip: 'Search',
                        icon: const Icon(Icons.arrow_forward_rounded,
                            color: Color(0xFF0070C0)),
                        onPressed: () => _search(_controller.text),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                        const BorderSide(color: Color(0xFF97BDD4)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: Color(0xFF0070C0), width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<DownloadableModule>>(
                future: _catalog,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                              color: Color(0xFF0070C0)),
                          SizedBox(height: 16),
                          Text('Finding available modules...'),
                        ],
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return _message(
                      Icons.wifi_off_rounded,
                      'Unable to load modules',
                      'Please check your internet connection and try again. '
                          'Your downloaded modules are still available in My Library.',
                    );
                  }

                  final matches = _matches(snapshot.data ?? []);
                  if (matches.isEmpty) {
                    return _message(
                      Icons.search_off_rounded,
                      'No matching modules',
                      _query.isEmpty
                          ? 'Enter a word or phrase above to search.'
                          : 'Try a different keyword or a shorter phrase.',
                    );
                  }

                  return ListView.separated(
                    keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    itemCount: matches.length + 1,
                    separatorBuilder: (_, __) =>
                    const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '${matches.length} ${matches.length == 1 ? 'module' : 'modules'} found',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF526B7D),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }
                      final module = matches[index - 1];
                      return Material(
                        color: Colors.white,
                        elevation: 1,
                        borderRadius: BorderRadius.circular(15),
                        child: InkWell(
                          onTap: () => _openModule(module),
                          borderRadius: BorderRadius.circular(15),
                          child: Container(
                            constraints:
                            const BoxConstraints(minHeight: 92),
                            padding: const EdgeInsets.all(17),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                  color: const Color(0xFFD7E4EA)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        module.name,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF16466A),
                                        ),
                                      ),
                                      if ((module.description ?? '')
                                          .trim()
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 7),
                                        Text(
                                          module.description!.trim(),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            height: 1.4,
                                            color: Color(0xFF526B7D),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFF0070C0),
                                  size: 29,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(IconData icon, String title, String description) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF0070C0)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Color(0xFF183E59),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Color(0xFF526B7D),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
