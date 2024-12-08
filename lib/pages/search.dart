import 'package:flutter/material.dart';
import 'package:wired_test/pages/home_page.dart';
import 'package:wired_test/pages/policy.dart';
import '../utils/button.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'by_alphabet.dart';
import 'by_packages.dart';
import 'by_topic.dart';
import 'module_library.dart';


class Search extends StatefulWidget {
  @override
  _SearchState createState() => _SearchState();
}

class _SearchState extends State<Search> {
  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    var baseSize = MediaQuery.of(context).size.shortestSide;
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

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
                                  builder: (context) => MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => ModuleLibrary()),
                            );
                          },
                          onHelpTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const Policy()),
                            );
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(screenWidth, screenHeight, baseSize)
                              : _buildPortraitLayout(screenWidth, screenHeight, baseSize),
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
                            builder: (context) => MyHomePage()),
                      );
                    },
                    onLibraryTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => ModuleLibrary()),
                      );
                    },
                    onHelpTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const Policy()),
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

  Widget _buildPortraitLayout(double screenWidth, double screenHeight, double baseSize) {
    return Column(
      children: [
        SizedBox(
          height: screenHeight * 0.038,
        ),
        Hero(
          tag: 'modules',
          child: Text(
            'Modules',
            style: TextStyle(
              fontSize: baseSize * (isTablet(context) ? 0.09 : 0.09),
              fontWeight: FontWeight.w500,
              color: Color(0xFF0070C0),
            ),
          ),
        ),
        SizedBox(
          height: screenHeight * 0.09,
        ),
        CustomButton(
          onTap: () {
            print('Alphabet button pressed');
            Navigator.push(context, MaterialPageRoute(builder: (context) => ByAlphabet()));
          },
          gradientColors: [
            Color(0xFF0070C0),
            Color(0xFF00C1FF),
            Color(0xFF0070C0),
          ],
          text: 'By Alphabet',
          width: baseSize * (isTablet(context) ? 0.3 : 0.5),
        ),
        SizedBox(
          height: screenHeight * 0.09,
        ),
        CustomButton(
          onTap: () {
            print('Topic button pressed');
            Navigator.push(context, MaterialPageRoute(builder: (context) => ByTopic()));
          },
          gradientColors: [
            Color(0xFF519921),
            Color(0xFF93D221),
            Color(0xFF519921),
          ],
          text: 'By Topic',
          width: baseSize * (isTablet(context) ? 0.3 : 0.5),
        ),
        SizedBox(
          height: screenHeight * 0.09,
        ),
        CustomButton(
          onTap: () {
            print('package button pressed');
            Navigator.push(context, MaterialPageRoute(builder: (context) => ByPackages()));
          },
          gradientColors: [
            Color(0xFF0070C0),
            Color(0xFF00C1FF),
            Color(0xFF0070C0),
          ],
          text: 'By Package',
          width: baseSize * (isTablet(context) ? 0.3 : 0.5),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(double screenWidth, double screenHeight, double baseSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.038 : 0.0),
        ),
        Flexible(
          child: Hero(
            tag: 'search',
            child: Text(
              'Search Modules',
              style: TextStyle(
                fontSize: baseSize * (isTablet(context) ? 0.09 : 0.09),
                fontWeight: FontWeight.w500,
                color: Color(0xFF0070C0),
              ),
            ),
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.1 : 0.03),
        ),
        CustomButton(
          onTap: () {
            print('Alphabet button pressed');
            Navigator.push(context, MaterialPageRoute(builder: (context) => ByAlphabet()));
          },
          gradientColors: [
            Color(0xFF0070C0),
            Color(0xFF00C1FF),
            Color(0xFF0070C0),
          ],
          text: 'By Alphabet',
          width: baseSize * (isTablet(context) ? 0.3 : 0.5),
        ),
        SizedBox(
          height: screenHeight * 0.09,
        ),
        CustomButton(
          onTap: () {
            print('Topic button pressed');
            Navigator.push(context, MaterialPageRoute(builder: (context) => ByTopic()));
          },
          gradientColors: [
            Color(0xFF519921),
            Color(0xFF93D221),
            Color(0xFF519921),
          ],
          text: 'By Topic',
          width: baseSize * (isTablet(context) ? 0.3 : 0.5),
        ),
        SizedBox(
          height: screenHeight * 0.09,
        ),
        CustomButton(
          onTap: () {
            print('Topic button pressed');
            //Navigator.push(context, MaterialPageRoute(builder: (context) => Search()));
          },
          gradientColors: [
            Color(0xFF0070C0),
            Color(0xFF00C1FF),
            Color(0xFF0070C0),
          ],
          text: 'By Package',
          width: baseSize * (isTablet(context) ? 0.3 : 0.5),
        ),
      ],
    );
  }
}