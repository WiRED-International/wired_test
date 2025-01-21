import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:wired_test/pages/home_page.dart';
import 'package:http/http.dart' as http;
import 'package:wired_test/utils/functions.dart';
import 'package:wired_test/utils/side_nav_bar.dart';
import 'package:wired_test/utils/custom_nav_bar.dart';
import 'package:wired_test/pages/policy.dart';

import '../menu.dart';
import '../module_library.dart';
import 'login.dart';

class RegistrationConfirm extends StatefulWidget {

  RegistrationConfirm();

  @override
  _RegistrationConfirmState createState() => _RegistrationConfirmState();
}

class _RegistrationConfirmState extends State<RegistrationConfirm> {
  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery
        .of(context)
        .size
        .width;
    var screenHeight = MediaQuery
        .of(context)
        .size
        .height;
    var baseSize = MediaQuery
        .of(context)
        .size
        .shortestSide;
    bool isLandscape = MediaQuery
        .of(context)
        .orientation == Orientation.landscape;

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
                          onTrackerTap: () {
                            //Purposefully left blank
                          },
                          onMenuTap: () {
                            Navigator.push(context, MaterialPageRoute(
                                builder: (context) => Menu()));
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(
                              screenWidth, screenHeight, baseSize)
                              : _buildPortraitLayout(
                              screenWidth, screenHeight, baseSize),
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
                    onTrackerTap: () {
                      //Purposefully left blank
                    },
                    onMenuTap: () {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (context) => Menu()));
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(screenWidth, screenHeight, baseSize) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          "You have successfully registered for the CME Credits Tracker. Please login with your email and password to continue.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.05 : 0.07),
        ),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => Login()),
            );
          },
          child: Text(
            "Login",
            style: TextStyle(
              fontSize: baseSize * (isTablet(context) ? 0.03 : 0.09),
              fontWeight: FontWeight.w500,
              color: Color(0xFF0070C0),
            ),
          ),
        )
      ],
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight, baseSize) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Text(
          "You have successfully registered for the CME Credits Tracker. Please Log In with your email and password to continue.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
            fontWeight: FontWeight.w500,
            color: Color(0xFF0070C0),
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.05 : 0.03),
        ),
      ],
    );
  }
}
