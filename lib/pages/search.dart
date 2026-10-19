import 'package:flutter/material.dart';
import 'package:wired_test/pages/home_page.dart';

import '../providers/auth_guard.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import '../utils/app_layout.dart';
import 'byAlphabet/by_alphabet.dart';
import 'byPackage/by_packages.dart';
import 'byTopic/by_topic.dart';
import 'creditsTracker/credits_tracker.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
import 'module_library.dart';
import 'animations/animation_list.dart';
import 'module_search_results.dart';

class Search extends StatefulWidget {
  const Search({super.key});

  @override
  State<Search> createState() => _SearchState();
}

class _SearchState extends State<Search> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _submitSearch(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    _open(ModuleSearchResults(initialQuery: query));
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 350;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 740),
              child: Column(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF0070C0),
                    ),
                    child: const Icon(Icons.menu_book_rounded,
                        size: 46, color: Colors.white),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Explore Learning',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF183E59),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Find health education modules, training materials, and animations.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Color(0xFF4C5660),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Material(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(14),
                    child: TextField(
                      controller: _searchController,
                      onSubmitted: _submitSearch,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'Search health education modules',
                        hintStyle: const TextStyle(
                          color: Color(0xFF536B7C),
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Color(0xFF0070C0),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded),
                          color: const Color(0xFF0070C0),
                          tooltip: 'Search modules',
                          onPressed: () =>
                              _submitSearch(_searchController.text),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                          const BorderSide(color: Color(0xFF97BDD4)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                          const BorderSide(color: Color(0xFF97BDD4)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF0070C0),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Row(
                    children: [
                      Expanded(
                          child: Divider(color: Color(0xFFC8B8A7))),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Browse Modules',
                          style: TextStyle(
                            color: Color(0xFF365C6C),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Expanded(
                          child: Divider(color: Color(0xFFC8B8A7))),
                    ],
                  ),
                  const SizedBox(height: 20),
                  GridView.count(
                    crossAxisCount: compact ? 1 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: compact ? 3.0 : 1.42,
                    children: [
                      _tile('By Alphabet', 'Browse modules A–Z',
                          const Color(0xFF0876D6),
                              () => _open(ByAlphabet())),
                      _tile('By Topic', 'Explore health topics',
                          const Color(0xFF22B85C),
                              () => _open(ByTopic())),
                      _tile('By Package', 'Existing training packages',
                          const Color(0xFF0876D6),
                              () => _open(ByPackages())),
                      _tile('Animations', 'Visual learning materials',
                          const Color(0xFF22B85C),
                              () => _open(AnimationList())),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.offline_pin_outlined,
                          color: Color(0xFF397D4C), size: 19),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Downloaded modules work offline',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF526B58),
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tile(String title, String subtitle, Color color, VoidCallback onTap) {
    return Material(
      color: color,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

