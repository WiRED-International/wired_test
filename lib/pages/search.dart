import 'package:flutter/material.dart';
import 'package:wired_test/pages/home_page.dart';
import 'package:wired_test/pages/policy.dart';
import '../utils/button.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'by_alphabet.dart';
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
      body: Row(
        children: [
          // Conditionally show the side navigation bar in landscape mode
          if (isLandscape)
            CustomSideNavBar(
              onHomeTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => MyHomePage()));
              },
              onLibraryTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => ModuleLibrary()));
              },
              onHelpTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => const Policy()));
              },
            ),

          // Main content area (expanded to fill remaining space)
          Expanded(
            child: Stack(
              children: <Widget>[
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
                  child: SafeArea(
                    child: Center(
                      child: isLandscape ? _buildLandscapeLayout(screenWidth, screenHeight) : _buildPortraitLayout(screenWidth, screenHeight),
                    ),
                  ),
                ),
                // Conditionally show the bottom navigation bar in portrait mode
                if (!isLandscape)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: CustomBottomNavBar(
                      onHomeTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => MyHomePage()),
                        );
                      },
                      onLibraryTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (
                            context) => ModuleLibrary()));
                      },
                      onHelpTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (
                            context) => const Policy()));
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout(double screenWidth, double screenHeight) {
    return Column(
      children: [
        CustomAppBar(
          onBackPressed: () {
            Navigator.pop(context);
          },
        ),
        SizedBox(
          height: screenHeight * 0.038,
        ),
        Hero(
          tag: 'search',
          child: Text(
            'Search Modules',
            style: TextStyle(
              fontSize: screenWidth * 0.1,
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
          width: 240,
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
          width: 240,
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
          width: 240,
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(double screenWidth, double screenHeight) {
    var baseSize = MediaQuery.of(context).size.shortestSide;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CustomAppBar(
          onBackPressed: () {
            Navigator.pop(context);
          },
        ),
        SizedBox(
          height: screenHeight * 0.038,
        ),
        Hero(
          tag: 'search',
          child: Text(
            'Search Modules',
            style: TextStyle(
              fontSize: baseSize * (isTablet(context) ? 0.1 : 0.1),
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
          width: 240,
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
          width: 240,
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
          width: 240,
        ),
      ],
    );
  }

  //   return Scaffold(
  //     body: Stack(
  //       children: [
  //         Container(
  //           decoration: const BoxDecoration(
  //             gradient: LinearGradient(
  //               begin: Alignment.topCenter,
  //               end: Alignment.bottomCenter,
  //               colors: [
  //                 Color(0xFFFFF0DC),
  //                 Color(0xFFF9EBD9),
  //                 Color(0xFFFFC888),
  //               ],
  //             ),
  //           ),
  //       child: SafeArea(
  //         child: Center(
  //           child: Column(
  //             children: [
  //               CustomAppBar(
  //                 onBackPressed: () {
  //                   Navigator.pop(context);
  //                 },
  //               ),
  //               SizedBox(
  //                   height: screenHeight * 0.038,
  //               ),
  //               Hero(
  //                 tag: 'search',
  //                 child: Text(
  //                     'Search Modules',
  //                     style: TextStyle(
  //                       fontSize: screenWidth * 0.1,
  //                       fontWeight: FontWeight.w500,
  //                       color: Color(0xFF0070C0),
  //                     ),
  //                 ),
  //               ),
  //               SizedBox(
  //                   height: screenHeight * 0.09,
  //               ),
  //               CustomButton(
  //                 onTap: () {
  //                   print('Alphabet button pressed');
  //                   Navigator.push(context, MaterialPageRoute(builder: (context) => ByAlphabet()));
  //                 },
  //                 gradientColors: [
  //                   Color(0xFF0070C0),
  //                   Color(0xFF00C1FF),
  //                   Color(0xFF0070C0),
  //                 ],
  //                 text: 'By Alphabet',
  //                 width: 240,
  //               ),
  //               SizedBox(
  //                   height: screenHeight * 0.09,
  //               ),
  //               CustomButton(
  //                 onTap: () {
  //                   print('Topic button pressed');
  //                   Navigator.push(context, MaterialPageRoute(builder: (context) => ByTopic()));
  //                 },
  //                 gradientColors: [
  //                   Color(0xFF519921),
  //                   Color(0xFF93D221),
  //                   Color(0xFF519921),
  //                 ],
  //                 text: 'By Topic',
  //                 width: 240,
  //               ),
  //               SizedBox(
  //                   height: screenHeight * 0.09,
  //               ),
  //               CustomButton(
  //                 onTap: () {
  //                   print('Topic button pressed');
  //                   //Navigator.push(context, MaterialPageRoute(builder: (context) => Search()));
  //                 },
  //                 gradientColors: [
  //                   Color(0xFF0070C0),
  //                   Color(0xFF00C1FF),
  //                   Color(0xFF0070C0),
  //                 ],
  //                 text: 'By Package',
  //                 width: 240,
  //               ),
  //             ],
  //           ),
  //         ),
  //       ),
  //     ),
  //         // Bottom Nav Bar
  //         Positioned(
  //           bottom: 0,
  //           left: 0,
  //           right: 0,
  //           child: CustomBottomNavBar(
  //             onHomeTap: () {
  //               Navigator.push(context, MaterialPageRoute(builder: (context) => const MyHomePage()));
  //             },
  //             onLibraryTap: () {
  //               Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleLibrary()));
  //             },
  //             onHelpTap: () {
  //               Navigator.push(context, MaterialPageRoute(builder: (context) => const Policy()));
  //             },
  //           ),
  //         ),
  //     ],
  //     ),
  //   );
  // }
}