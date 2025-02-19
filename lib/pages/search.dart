import 'package:flutter/material.dart';
import 'package:wired_test/pages/home_page.dart';
import '../providers/auth_guard.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'by_alphabet.dart';
import 'by_packages.dart';
import 'by_topic.dart';
import 'cme/cme_tracker.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
import 'module_library.dart';


class Search extends StatefulWidget {
  const Search({super.key});

  @override
  _SearchState createState() => _SearchState();
}

class _SearchState extends State<Search> {
  final Map<String, double> _buttonScales = {
    'By Alphabet': 1.0,
    'By Topic': 1.0,
    'By Package': 1.0,
  };

  final Map<String, List<Color>> _buttonColors = {
    'By Alphabet': [
      Color(0xFF0070C0), // Normal
      Color(0xFF00C1FF),
      Color(0xFF0070C0),
    ],
    'By Topic': [
      Color(0xFF519921), // Normal
      Color(0xFF93D221),
      Color(0xFF519921),
    ],
    'By Package': [
      Color(0xFF0070C0), // Normal
      Color(0xFF00C1FF),
      Color(0xFF0070C0),
    ],
  };

  void _onTapDown(String label) {
    setState(() {
      _buttonScales[label] = 0.95; // Shrink effect
      _buttonColors[label] = [
        _buttonColors[label]![0].withOpacity(0.7), // Darker effect
        _buttonColors[label]![1].withOpacity(0.7),
        _buttonColors[label]![2].withOpacity(0.7),
      ];
    });
  }

  void _onTapUp(String label, VoidCallback onTap) {
    Future.delayed(Duration(milliseconds: 100), () {
      setState(() {
        _buttonScales[label] = 1.0; // Restore size
        _buttonColors[label] = [
          _buttonColors[label]![0].withOpacity(1.0), // Restore original color
          _buttonColors[label]![1].withOpacity(1.0),
          _buttonColors[label]![2].withOpacity(1.0),
        ];
      });
      onTap(); // Execute navigation
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    double scalingFactor = getScalingFactor(context);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFF0DC),
                    Color(0xFFF9EBD9),
                    Color(0xFFFFC888),
                  ],
                ),
              ),
            ),
            Column(
              children: [
                CustomAppBar(
                  onBackPressed: () {
                    Navigator.pop(context);
                  },
                  requireAuth: false,
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (isLandscape)
                        CustomSideNavBar(
                          onHomeTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => ModuleLibrary()),
                            );
                          },
                          onTrackerTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    AuthGuard(
                                      child: CMETracker(),
                                    ),
                              ),
                            );
                          },
                          onMenuTap: () async {
                            bool isLoggedIn = await checkIfUserIsLoggedIn();
                            print("Navigating to menu. Logged in: $isLoggedIn");
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                isLoggedIn
                                    ? Menu()
                                    : GuestMenu(),
                              ),
                            );
                          },
                        ),
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(scalingFactor)
                              : _buildPortraitLayout(scalingFactor),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLandscape)
                  CustomBottomNavBar(
                    onHomeTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const MyHomePage()),
                      );
                    },
                    onLibraryTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => ModuleLibrary()),
                      );
                    },
                    onTrackerTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AuthGuard(
                                child: CMETracker(),
                              ),
                        ),
                      );
                    },
                    onMenuTap: () async {
                      bool isLoggedIn = await checkIfUserIsLoggedIn();
                      print("Navigating to menu. Logged in: $isLoggedIn");
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                          isLoggedIn
                              ? Menu()
                              : GuestMenu(),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(double scalingFactor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Hero(
          tag: 'modules',
          child: Text(
            'Search Modules',
            style: TextStyle(
              fontSize: scalingFactor * (isTablet(context) ? 30 : 35),
              fontWeight: FontWeight.w500,
              color: Color(0xFF0070C0),
            ),
          ),
        ),
        _buildSearchButton(
          label: 'By Alphabet',
          gradientColors: [
            Color(0xFF0070C0),
            Color(0xFF00C1FF),
            Color(0xFF0070C0),
          ],
          onTap: () {
            Navigator.push(
                context, MaterialPageRoute(builder: (context) => ByAlphabet()));
          },
          scalingFactor: scalingFactor,
        ),
        _buildSearchButton(
          label: 'By Topic',
          gradientColors: [
            Color(0xFF519921),
            Color(0xFF93D221),
            Color(0xFF519921),
          ],
          onTap: () {
            Navigator.push(
                context, MaterialPageRoute(builder: (context) => ByTopic()));
          },
          scalingFactor: scalingFactor,
        ),
        _buildSearchButton(
          label: 'By Package',
          gradientColors: [
            Color(0xFF0070C0),
            Color(0xFF00C1FF),
            Color(0xFF0070C0),
          ],
          onTap: () {
            Navigator.push(
                context, MaterialPageRoute(builder: (context) => ByPackages()));
          },
          scalingFactor: scalingFactor,
        ),
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 20 : 20),
        ),
      ],
    );
  }

  Widget _buildSearchButton({
    required String label,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    required double scalingFactor,
  }) {
    return Semantics(
      label: '$label Search Button',
      hint: 'Tap to search for modules by $label',
      child: FractionallySizedBox(
        widthFactor: isTablet(context) ? 0.45 : 0.6,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          child: GestureDetector(
            onTapDown: (_) => _onTapDown(label),
            onTapUp: (_) => _onTapUp(label, onTap),
            onTapCancel: () {
              setState(() {
                _buttonScales[label] = 1.0;
                _buttonColors[label] = [
                  _buttonColors[label]![0].withOpacity(1.0), // Restore original
                  _buttonColors[label]![1].withOpacity(1.0),
                  _buttonColors[label]![2].withOpacity(1.0),
                ];
              });
            },
            child: AnimatedContainer(
              duration: Duration(milliseconds: 100),
              curve: Curves.easeOut,
              transform: Matrix4.diagonal3Values(
                  _buttonScales[label] ?? 1.0, _buttonScales[label] ?? 1.0,
                  1.0),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(30),
                splashColor: Colors.white.withOpacity(0.3),
                child: Container(
                  height: scalingFactor * (isTablet(context) ? 35 : 45),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _buttonColors[label] ?? [
                        Color(0xFF0070C0),
                        Color(0xFF00C1FF),
                        Color(0xFF0070C0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: Offset(1, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 17 : 20),
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(double scalingFactor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Hero(
          tag: 'modules',
          child: Text(
            'Search Modules',
            style: TextStyle(
              fontSize: scalingFactor * (isTablet(context) ? 25 : 25),
              fontWeight: FontWeight.w500,
              color: Color(0xFF0070C0),
            ),
          ),
        ),

        _buildSearchButtonLandscape(
          label: 'By Alphabet',
          gradientColors: [
            Color(0xFF0070C0),
            Color(0xFF00C1FF),
            Color(0xFF0070C0),
          ],
          onTap: () {
            print('Alphabet button pressed');
            Navigator.push(
                context, MaterialPageRoute(builder: (context) => ByAlphabet()));
          },
          width: scalingFactor * (isTablet(context) ? 40 : 40),
          scalingFactor: scalingFactor,
        ),

        _buildSearchButtonLandscape(
          label: 'By Topic',
          gradientColors: [
            Color(0xFF519921),
            Color(0xFF93D221),
            Color(0xFF519921),
          ],
          onTap: () {
            print('Topic button pressed');
            Navigator.push(
                context, MaterialPageRoute(builder: (context) => ByTopic()));
          },
          width: scalingFactor * (isTablet(context) ? 40 : 40),
          scalingFactor: scalingFactor,
        ),

        _buildSearchButtonLandscape(
          label: 'By Package',
          gradientColors: [
            Color(0xFF0070C0),
            Color(0xFF00C1FF),
            Color(0xFF0070C0),
          ],
          onTap: () {
            print('Package button pressed');
            Navigator.push(
                context, MaterialPageRoute(builder: (context) => ByPackages()));
          },
          width: scalingFactor * (isTablet(context) ? 40 : 40),
          scalingFactor: scalingFactor,
        ),
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 20 : 20),
        ),
      ],
    );
  }

  Widget _buildSearchButtonLandscape({
    required String label,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    required double width,
    required double scalingFactor,
  }) {
    return Semantics(
      label: '$label Search Button',
      hint: 'Tap to search for modules by $label',
      child: FractionallySizedBox(
        widthFactor: isTablet(context) ? 0.3 : 0.3,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          child: GestureDetector(
            onTapDown: (_) => _onTapDown(label),
            onTapUp: (_) => _onTapUp(label, onTap),
            onTapCancel: () {
              setState(() {
                _buttonScales[label] = 1.0;
                _buttonColors[label] = [
                  _buttonColors[label]![0].withOpacity(1.0), // Restore original
                  _buttonColors[label]![1].withOpacity(1.0),
                  _buttonColors[label]![2].withOpacity(1.0),
                ];
              });
            },
            child: AnimatedContainer(
              duration: Duration(milliseconds: 100),
              curve: Curves.easeOut,
              transform: Matrix4.diagonal3Values(
                _buttonScales[label] ?? 1.0,
                _buttonScales[label] ?? 1.0,
                1.0,
              ),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(30),
                splashColor: Colors.white.withOpacity(0.3),
                child: Container(
                  width: width,
                  height: scalingFactor * (isTablet(context) ? 30 : 30),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _buttonColors[label] ?? gradientColors,
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: Offset(1, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 17 : 17),
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}