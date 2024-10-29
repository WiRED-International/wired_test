import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:wired_test/utils/functions.dart';
import '../pages/search.dart';
import '../utils/custom_nav_bar.dart';
import 'module_library.dart';
import 'policy.dart';
import 'package:wired_test/utils/side_nav_bar.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, this.title});
  final String? title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: Row(
        children: [
          // Conditionally show the side navigation bar in landscape mode
          if (isLandscape)
            CustomSideNavBar(
              onHomeTap: () {
                // Navigator.push(context,
                //     MaterialPageRoute(builder: (context) => MyHomePage()));
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
                      child: isLandscape ? _buildLandscapeLayout(
                          screenWidth, screenHeight) : _buildPortraitLayout(
                          screenWidth, screenHeight),
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
                        // Navigator.push(context, MaterialPageRoute(builder: (context) => DownloadConfirm(moduleName: moduleName)));
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
    var baseSize = MediaQuery.of(context).size.shortestSide;
    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(top: 0,
              bottom: baseSize * (isTablet(context) ? 0.03 : 0.021)),
          child: Semantics(
            label: 'Wired Logo',
            child: Image.asset(
              'assets/images/wired-logo.png',
              height: baseSize * (isTablet(context) ? 0.17 : 0.2),
            ),
          ),
        ),
        Text(
          'CME Module Library',
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.07 : 0.09),
            fontWeight: FontWeight.w500,
            color: const Color.fromRGBO(0, 102, 179, 1),
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.01 : 0.015),
        ),
        Text(
          'News and Updates',
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
            fontWeight: FontWeight.w500,
            color: Color.fromRGBO(84, 130, 53, 1),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            top: baseSize * (isTablet(context) ? 0.015 : 0.015),
            bottom: baseSize * (isTablet(context) ? 0.04 : 0.04),
            left: baseSize * (isTablet(context) ? 0.05 : 0.04),
            right: baseSize * (isTablet(context) ? 0.05 : 0.04),
          ),
          child: Container(
            //height: 470,
            height: baseSize * (isTablet(context) ? 0.6 : 0.7),
            decoration: BoxDecoration(
              color: Color(0xFFF9EBD9),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: Color(0xFF0070C0),
                width: 2,
              ),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: baseSize * (isTablet(context) ? 0.02 : 0.02),
                  horizontal: baseSize * (isTablet(context) ? 0.03 : 0.03),
                ),
                child: Text(
                  'Hello Testers! Welcome to WiRED\'s new mobile HealthMap app. Thank you for choosing to participate in this closed test. This does mean a lot to all of us here at WiRED. We ask that you please do not click on any button or link that says "Leave the test." We need all testers to remain opted in for 14 consecutive days. After the 14 days, you may leave the test if you wish. Once again, thank you so much for your participation in this test.',
                  style: TextStyle(
                    fontSize: baseSize * (isTablet(context) ? 0.035 : 0.045),
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.05 : 0.015),
        ),
        Semantics(
          label: 'Search Button',
          hint: 'Tap to search for modules',
          child: GestureDetector(
            onTap: () async {
              Navigator.push(
                  context, MaterialPageRoute(builder: (context) => Search()));
            },
            child: Hero(
              tag: 'search',
              child: FractionallySizedBox(
                widthFactor: isTablet(context) ? 0.33 : 0.4,
                child: Container(
                  height: baseSize * (isTablet(context) ? 0.09 : 0.13),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF0070C0),
                        Color(0xFF00C1FF),
                        Color(0xFF0070C0),
                      ], // Your gradient colors
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: const Offset(
                            1, 3), // changes position of shadow
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                      builder: (context, constraints) {
                        double buttonWidth = constraints.maxWidth;
                        double fontSize = buttonWidth * 0.2;
                        double padding = buttonWidth * 0.02;
                        double iconSize = buttonWidth * 0.15;
                        return Padding(
                          padding: EdgeInsets.all(padding),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.fitWidth,
                                  child: Text(
                                    "Search",
                                    style: TextStyle(
                                      fontSize: fontSize,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: baseSize * (isTablet(context) ? 0.015 : 0.025),
                              ),
                              Semantics(
                                label: 'Search Icon',
                                child: SvgPicture.asset(
                                  'assets/icons/search.svg',
                                  height: iconSize,
                                  width: iconSize,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(double screenWidth, double screenHeight) {
    var baseSize = MediaQuery.of(context).size.shortestSide;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(top: screenHeight * 0.02),
          child: Semantics(
            label: 'Wired Logo',
            child: Image.asset(
              'assets/images/wired-logo.png',
              height: baseSize * (isTablet(context) ? 0.15 : 0.12),
            ),
          ),
        ),
        SizedBox(height: screenHeight * 0.02),
        Text(
          'CME Module Library',
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.058 : 0.07),
            fontWeight: FontWeight.w500,
            color: const Color.fromRGBO(0, 102, 179, 1),
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.01 : 0.015),
        ),
        Text(
          'News and Updates',
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.065 : 0.06),
            fontWeight: FontWeight.w500,
            color: Color.fromRGBO(84, 130, 53, 1),
          ),
          textAlign: TextAlign.center,
        ),
        Padding(
          padding: EdgeInsets.only(
            top: baseSize * (isTablet(context) ? 0.015 : 0.015),
            bottom: baseSize * (isTablet(context) ? 0.04 : 0.04),
            left: baseSize * (isTablet(context) ? 0.25 : 0.04),
            right: baseSize * (isTablet(context) ? 0.25 : 0.04),
          ),
          child: Container(
            height: baseSize * (isTablet(context) ? 0.35 : 0.5),
            decoration: BoxDecoration(
              color: Color(0xFFF9EBD9),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: Color(0xFF0070C0),
                width: 2,
              ),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: baseSize * (isTablet(context) ? 0.01 : 0.02),
                  horizontal: baseSize * (isTablet(context) ? 0.02 : 0.03),
                ),
                child: Text(
                  'Hello Testers! Welcome to WiRED\'s new mobile HealthMap app. Thank you for choosing to participate in this closed test. This does mean a lot to all of us here at WiRED. We ask that you please do not click on any button or link that says "Leave the test." We need all testers to remain opted in for 14 consecutive days. After the 14 days, you may leave the test if you wish. Once again, thank you so much for your participation in this test.',
                  style: TextStyle(
                    fontSize: baseSize * (isTablet(context) ? 0.03 : 0.05),
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
        Semantics(
          label: 'Search Button',
          hint: 'Tap to search for modules',
          child: GestureDetector(
            onTap: () async {
              Navigator.push(
                  context, MaterialPageRoute(builder: (context) => Search()));
            },
            child: Hero(
              tag: 'search',
              child: FractionallySizedBox(
                widthFactor: isTablet(context) ? 0.2 : 0.4,
                child: Container(
                  height: baseSize * (isTablet(context) ? 0.08 : 0.06),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF0070C0),
                        Color(0xFF00C1FF),
                        Color(0xFF0070C0),
                      ], // Your gradient colors
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: const Offset(
                            1, 3), // changes position of shadow
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                      builder: (context, constraints) {
                        double buttonWidth = constraints.maxWidth;
                        double fontSize = buttonWidth * 0.2;
                        double padding = buttonWidth * 0.02;
                        double iconSize = buttonWidth * 0.15;
                        return Padding(
                          padding: EdgeInsets.all(padding),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.fitWidth,
                                  child: Text(
                                    "Search",
                                    style: TextStyle(
                                      fontSize: fontSize,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: baseSize * (isTablet(context) ? 0.015 : 0.025),
                              ),
                              Semantics(
                                label: 'Search Icon',
                                child: SvgPicture.asset(
                                  'assets/icons/search.svg',
                                  height: iconSize,
                                  width: iconSize,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
