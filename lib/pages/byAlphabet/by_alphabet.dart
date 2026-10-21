import 'package:flutter/material.dart';

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
import '../module_library.dart';
import 'module_by_alphabet.dart';

/// Letter picker for the alphabetical module catalog.
class ByAlphabet extends StatefulWidget {
  const ByAlphabet({super.key});

  @override
  State<ByAlphabet> createState() => _ByAlphabetState();
}

class _ByAlphabetState extends State<ByAlphabet> {
  static const Color _blue = Color(0xFF16466A);
  static const Color _border = Color(0xFFD7E4EA);

  static const List<String> _letters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L',
    'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X-Y-Z',
  ];

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
          Expanded(child: _buildContent()),
        ],
      )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 720 ? 6 : width >= 520 ? 5 : 4;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 25),
                child: Column(
                  children: const [
                    Text(
                      'Browse by Alphabet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        color: _blue,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Select a letter to explore modules',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF607889),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 85),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                      (context, index) => _letterTile(_letters[index]),
                  childCount: _letters.length,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 13,
                  crossAxisSpacing: 13,
                  childAspectRatio: columns >= 5 ? 1.35 : 1.12,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _letterTile(String letter) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _open(ModuleByAlphabet(letter: letter)),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF0F8FF),
                Color(0xFFD9ECFC),
                Color(0xFFBBDDF5),
              ],
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: const Color(0xFFA8CFEA),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF16466A).withValues(alpha: 0.08),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: letter.length > 1 ? 19 : 28,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3479A8),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}