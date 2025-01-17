import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wired_test/pages/home_page.dart';
import 'package:wired_test/pages/policy.dart';

import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'cme/cme_info.dart';
import 'menu.dart';
import 'module_library.dart';

class DownloadConfirm extends StatefulWidget {
  //const DownloadConfirm({Key? key}) : super(key: key);
  const DownloadConfirm({
    super.key,
    this.moduleName,
    this.packageName
  });

  final String? moduleName;
  final String? packageName;

  @override
  State<DownloadConfirm> createState() => _DownloadConfirmState();
}

class _DownloadConfirmState extends State<DownloadConfirm> {
  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    String? displayName = widget.moduleName ?? widget.packageName;

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
                              MaterialPageRoute(builder: (context) => MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ModuleLibrary()),
                            );
                          },
                          onTrackerTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (
                                context) => CmeInfo()));
                          },
                          onMenuTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (
                                context) => Menu()));
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(screenWidth, screenHeight, displayName)
                              : _buildPortraitLayout(screenWidth, screenHeight, displayName),
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
                        MaterialPageRoute(builder: (context) => ModuleLibrary()),
                      );
                    },
                    onTrackerTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (
                          context) => CmeInfo()));
                    },
                    onMenuTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (
                          context) => Menu()));
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(screenWidth, screenHeight, String? displayName) {
    var baseSize = MediaQuery.of(context).size.shortestSide;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.03 : 0.03),
        ),
        Flexible(
          child: Text(
            "You have downloaded the following module:",
            style: TextStyle(
              // fontSize: 32,
              fontSize: baseSize * (isTablet(context) ? 0.055 : 0.075),
              fontWeight: FontWeight.w500,
              color: Color(0xFF548235),
            ),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.015 : 0.05),
        ),
        Container(
          //height: 150,
          //height: baseSize * (isTablet(context) ? 0.18 : 0.25),
          padding: EdgeInsets.symmetric(horizontal: baseSize * (isTablet(context) ? 0.01 : 0.02)),
          width: double.infinity,
          alignment: Alignment.center,
          child: Center(
            child: Text(
              displayName ?? "No Name Provided",
              style: TextStyle(
                fontSize: baseSize * (isTablet(context) ? 0.055 : 0.07),
                fontWeight: FontWeight.w500,
                color: Color(0xFF0070C0),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.04 : 0.05),
        ),
        Container(
          height: baseSize * (isTablet(context) ? 0.53 : 0.63),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "View module in",
                  style: TextStyle(
                    fontSize: baseSize * (isTablet(context) ? 0.05 : 0.072),
                    fontWeight: FontWeight.w400,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleLibrary()));
                  },
                  child: Container(
                    height: baseSize * (isTablet(context) ? 0.08 : 0.095),
                    width: baseSize * (isTablet(context) ? 0.33 : 0.4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF519921), Color(0xFF93D221), Color(0xFF519921),], // Your gradient colors
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(1, 3), // changes position of shadow
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        "My Library",
                        style: TextStyle(
                          //fontSize: 32,
                          fontSize: baseSize * (isTablet(context) ? 0.051 : 0.06),
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  "or return",
                  style: TextStyle(
                    // fontSize: 32,
                    fontSize: baseSize * (isTablet(context) ? 0.05 : 0.072),
                    fontWeight: FontWeight.w400,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const MyHomePage()));
                  },
                  child: Container(
                    height: baseSize * (isTablet(context) ? 0.08 : 0.095),
                    width: baseSize * (isTablet(context) ? 0.33 : 0.4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0070C0), Color(0xFF00C1FF), Color(0xFF0070C0),], // Your gradient colors
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(1, 3), // changes position of shadow
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        "Home",
                        style: TextStyle(
                          // fontSize: 32,
                          fontSize: baseSize * (isTablet(context) ? 0.051 : 0.06),
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight, String? displayName) {
    var baseSize = MediaQuery.of(context).size.shortestSide;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.03 : 0.03),
        ),
        Text(
          "You have downloaded the following module:",
          style: TextStyle(
            //fontSize: 36,
            fontSize: baseSize * (isTablet(context) ? 0.06 : 0.07),
            fontWeight: FontWeight.w500,
            color: Color(0xFF548235),
          ),
          textAlign: TextAlign.center,
        ),
        // SizedBox(
        //   height: baseSize * (isTablet(context) ? 0.015 : 0.015),
        // ),
        Container(
          //height: 150,
          height: baseSize * (isTablet(context) ? 0.18 : 0.18),
          width: double.infinity,
          alignment: Alignment.center,
          child: Center(
            child: Text(
              displayName ?? "No Name Provided",
              style: TextStyle(
                //fontSize: 36,
                fontSize: baseSize * (isTablet(context) ? 0.06 : 0.065),
                fontWeight: FontWeight.w500,
                color: Color(0xFF0070C0),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        // SizedBox(
        //   height: baseSize * (isTablet(context) ? 0.04 : 0.04),
        // ),
        Flexible(
          child: Container(
            height: baseSize * (isTablet(context) ? 0.5 : 0.43),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "View module in",
                    style: TextStyle(
                      fontSize: baseSize * (isTablet(context) ? 0.06 : 0.062),
                      fontWeight: FontWeight.w400,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleLibrary()));
                    },
                    child: Container(
                      height: baseSize * (isTablet(context) ? 0.075 : 0.075),
                      width: baseSize * (isTablet(context) ? 0.33 : 0.33),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF519921), Color(0xFF93D221), Color(0xFF519921),], // Your gradient colors
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            spreadRadius: 1,
                            blurRadius: 5,
                            offset: const Offset(1, 3), // changes position of shadow
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          "My Library",
                          style: TextStyle(
                            //fontSize: 32,
                            fontSize: baseSize * (isTablet(context) ? 0.0515 : 0.0515),
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    "or return",
                    style: TextStyle(
                      // fontSize: 32,
                      fontSize: baseSize * (isTablet(context) ? 0.06 : 0.062),
                      fontWeight: FontWeight.w400,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const MyHomePage()));
                    },
                    child: Container(
                      height: baseSize * (isTablet(context) ? 0.075 : 0.075),
                      width: baseSize * (isTablet(context) ? 0.33 : 0.33),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0070C0), Color(0xFF00C1FF), Color(0xFF0070C0),], // Your gradient colors
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            spreadRadius: 1,
                            blurRadius: 5,
                            offset: const Offset(1, 3), // changes position of shadow
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          "Home",
                          style: TextStyle(
                            // fontSize: 32,
                            fontSize: baseSize * (isTablet(context) ? 0.0515 : 0.0515),
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}



