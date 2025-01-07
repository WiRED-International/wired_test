import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wired_test/pages/cme/register.dart';
import 'package:wired_test/pages/policy.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../download_confirm.dart';
import '../home_page.dart';
import '../menu.dart';
import '../module_library.dart';
import 'login.dart';

class CmeInfo extends StatefulWidget {
  @override
  _CmeInfoState createState() => _CmeInfoState();
}

class _CmeInfoState extends State<CmeInfo> {
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
                              MaterialPageRoute(builder: (context) => MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ModuleLibrary()),
                            );
                          },
                          onHelpTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const Policy()),
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
                        MaterialPageRoute(builder: (context) => ModuleLibrary()),
                      );
                    },
                    onTrackerTap: () {
                      // Navigator.push(context, MaterialPageRoute(builder: (
                      //     context) => Policy()));
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

  Widget _buildPortraitLayout(screenWidth, screenHeight, baseSize) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          Text(
            "Welcome to the CME Credits Tracker",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
              fontWeight: FontWeight.w500,
              color: Color(0xFF0070C0),
            ),
          ),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'This tracker is designed for WiRED\'s CHWs. This tracker will help you report the modules you have completed. It will tell you the points earned so far adn the points you need to qualify for the year. If you are not one of WiRED\'s CHWs, but you are interested in learning more, please visit us here:\n',
                  style: TextStyle(
                    fontSize: baseSize * (isTablet(context) ? 0.06 : 0.065),
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF548235),
                  ),
                ),
                WidgetSpan(
                  child: SizedBox(
                    height: baseSize * (isTablet(context) ? 0.08 : 0.08),
                  ),
                ),
                TextSpan(
                  text: 'www.wiredinternational.org',
                  style: TextStyle(
                    fontSize: baseSize * (isTablet(context) ? 0.06 : 0.065),
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF0070C0),
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () async {
                    final url = Uri.parse(
                        'https://www.wiredinternational.org');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url);
                      } else {
                        throw 'Could not launch $url';
                      }
                    },
                ),
              ],
            ),
          ),
          SizedBox(
            height: baseSize * (isTablet(context) ? 0.05 : 0.03),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (
                      context) => Login()));
                },
                child: Text(
                  "Login",
                  style: TextStyle(
                    fontSize: baseSize * (isTablet(context) ? 0.07 : 0.07),
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF0070C0),
                  ),
                ),
              ),
              SizedBox(
                width: baseSize * (isTablet(context) ? 0.05 : 0.05),
              ),
              Text(
                "or",
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.06 : 0.065),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF548235),
                ),
              ),
              SizedBox(
                width: baseSize * (isTablet(context) ? 0.05 : 0.05),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (
                      context) => Register()));
                },
                child: Text(
                  "Register",
                  style: TextStyle(
                    fontSize: baseSize * (isTablet(context) ? 0.07 : 0.07),
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF0070C0),
                  ),
                ),
              )
            ],
          ),
          SizedBox(
            height: baseSize * (isTablet(context) ? 0.05 : 0.03),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight, baseSize) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Text(
          "Welcom to the CME Credits Tracker",
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
            fontWeight: FontWeight.w500,
            color: Color(0xFF548235),
          ),
        ),
      ],
    );
  }
}

