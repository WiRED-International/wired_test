import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:wired_test/pages/byTopic/module_by_topic.dart';
import '../../providers/auth_guard.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../cme/cme_tracker.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
// import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class Language extends StatelessWidget {
  final Locale currentLocale;
  final void Function(Locale) onLocaleChange;

  const Language({
    super.key,
    required this.currentLocale,
    required this.onLocaleChange,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final baseSize = screenSize.shortestSide;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final scalingFactor = getScalingFactor(context);
    final isTabletDevice = isTablet(context);

    final supportedLanguages = {
      Locale('en'): 'English',
      Locale('es'): 'Español',
      Locale('zh'): '中文',
    };

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
                // Custom AppBar
                CustomAppBar(
                  onBackPressed: () {
                    Navigator.pop(context);
                  },
                  requireAuth: false,
                ),
                // Expanded layout for the main content
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

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(
                              context, baseSize)
                              : _buildPortraitLayout(
                              context, baseSize),
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

  Widget _buildPortraitLayout(BuildContext context, double baseSize) {
    final supportedLanguages = {
      const Locale('en'): 'English',
      const Locale('es'): 'Español',
      const Locale('zh'): '中文',
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Text(
            'Select Language',
            style: TextStyle(
              fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
              fontWeight: FontWeight.w500,
              color: const Color(0xFF548235),
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              ListView.builder(
                itemCount: supportedLanguages.length,
                itemBuilder: (context, index) {
                  final locale = supportedLanguages.keys.elementAt(index);
                  final label = supportedLanguages.values.elementAt(index);
                  final isSelected = locale.languageCode ==
                      currentLocale.languageCode;

                  return Column(
                    children: [
                      ListTile(
                        title: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: baseSize *
                                  (isTablet(context) ? 0.054 : 0.054),
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF0070C0),
                            ),
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                        onTap: () {
                          if (locale != currentLocale) {
                            onLocaleChange(locale);
                            Navigator.pop(
                                context); // Go back to Menu after change
                          }
                        },
                      ),
                      Container(
                        color: Colors.grey,
                        height: 1,
                        width: baseSize * (isTablet(context) ? 0.75 : 0.85),
                      ),
                    ],
                  );
                },
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 1.0],
                        colors: [
                          Color(0xFFFED09A).withOpacity(0.0),
                          Color(0xFFFED09A),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(BuildContext context, double baseSize) {
    final supportedLanguages = {
      const Locale('en'): 'English',
      const Locale('es'): 'Español',
      const Locale('zh'): '中文',
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Text(
            'Select Language',
            style: TextStyle(
              fontSize: baseSize * (isTablet(context) ? 0.07 : 0.07),
              fontWeight: FontWeight.w500,
              color: const Color(0xFF548235),
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Flexible(
          child: Stack(
            children: [
              ListView.builder(
                itemCount: supportedLanguages.length,
                itemBuilder: (context, index) {
                  final locale = supportedLanguages.keys.elementAt(index);
                  final label = supportedLanguages.values.elementAt(index);
                  final isSelected = locale.languageCode ==
                      currentLocale.languageCode;

                  return Column(
                    children: [
                      ListTile(
                        title: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: baseSize *
                                  (isTablet(context) ? 0.05 : 0.05),
                              fontFamilyFallback: [
                                'NotoSans',
                                'NotoSerif',
                                'Roboto',
                                'sans-serif'
                              ],
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF0070C0),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                        onTap: () {
                          if (locale != currentLocale) {
                            onLocaleChange(locale);
                            Navigator.pop(context);
                          }
                        },
                      ),
                      Container(
                        height: 1,
                        width: baseSize * (isTablet(context) ? 0.75 : 0.85),
                        color: Colors.grey,
                      ),
                    ],
                  );
                },
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 1.0],
                        colors: [
                          const Color(0xFFFED09A).withOpacity(0.0),
                          const Color(0xFFFED09A),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
