import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wired_test/pages/cme/register.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import 'login.dart';

class CmeInfo extends StatefulWidget {
  @override
  _CmeInfoState createState() => _CmeInfoState();
}

class _CmeInfoState extends State<CmeInfo> {
  @override
  Widget build(BuildContext context) {
    double scalingFactor = getScalingFactor(context);

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
                // Expanded layout for the main content
                Expanded(
                  child: Row(
                    children: [
                      if (isLandscape)
                        CustomSideNavBar(
                          onHomeTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ModuleLibrary()),
                            );
                          },
                          onTrackerTap: () {
                            //Purposefully left blank
                          },
                          onMenuTap: () async {
                            bool isLoggedIn = await checkIfUserIsLoggedIn();
                            print("Navigating to menu. Logged in: $isLoggedIn");
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                              ),
                            );
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
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
                        MaterialPageRoute(builder: (context) => ModuleLibrary()),
                      );
                    },
                    onTrackerTap: () {
                      //Purposefully left blank
                    },
                    onMenuTap: () async {
                      bool isLoggedIn = await checkIfUserIsLoggedIn();
                      print("Navigating to menu. Logged in: $isLoggedIn");
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                        ),
                      );
                    },
                  ),
              ],
            ),
            Positioned(
              top: 0, // Ensures it stays at the top of the screen
              left: 0,
              right: 0,
              child: CustomAppBar(
                onBackPressed: () {
                  Navigator.pop(context);
                },
                requireAuth: false,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildPortraitLayout(scalingFactor) {
    final double imageHeight = scalingFactor * (isTablet(context) ? 150 : 170);
    return Center(
      child: Column(
        children: <Widget>[
          Stack(
            children: [
              Container(
                width: double.infinity,
                height: imageHeight,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/cme-pic.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: scalingFactor * (isTablet(context) ? 10 : 10)),
                  child: Text(
                    "CME Credits Tracker",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 24 : 28),
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF0070C0),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 10 : 10)),
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'WiRED International is proud to introduce our new continuing medical education tracker. Submit and track all of your CME credits for the year using WiRED\'s extensive health module library. For more information on how to manage and incorporate WiRED\'s CME Tracker into your curriculum please visit here:\n',
                          style: TextStyle(
                            fontSize: scalingFactor * (isTablet(context) ? 15 : 18),
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF548235),
                          ),
                        ),
                        WidgetSpan(
                          child: SizedBox(
                            height: scalingFactor * (isTablet(context) ? 30 : 40),
                          ),
                        ),
                        TextSpan(
                          text: 'www.wiredinternational.org',
                          style: TextStyle(
                            fontSize: scalingFactor * (isTablet(context) ? 18 : 22),
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
                ),
                SizedBox(
                  height: scalingFactor * (isTablet(context) ? 10 : 10),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        print("Login Tapped");
                        Navigator.push(context, MaterialPageRoute(builder: (
                            context) => Login()));
                      },
                      child: Text(
                        "Login",
                        style: TextStyle(
                          fontSize: scalingFactor * (isTablet(context) ? 22 : 26),
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0070C0),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: scalingFactor * (isTablet(context) ? 15 : 10),
                    ),
                    Text(
                      "or",
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 18 : 26),
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF548235),
                      ),
                    ),
                    SizedBox(
                      width: scalingFactor * (isTablet(context) ? 15 : 10),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (
                            context) => Register()));
                      },
                      child: Text(
                        "Register",
                        style: TextStyle(
                          fontSize: scalingFactor * (isTablet(context) ? 22 : 26),
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0070C0),
                        ),
                      ),
                    )
                  ],
                ),
              ],
            ),
          ),

          SizedBox(
            height: scalingFactor * (isTablet(context) ? 20 : 20),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout(scalingFactor) {
    final double imageHeight = scalingFactor * (isTablet(context) ? 120 : 130);

    return Center(
      child: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            // Stack for Image and Back Button
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: imageHeight,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/images/cme-pic.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),

            // Main Content with Spacing
            Padding(
              padding: EdgeInsets.only(top: scalingFactor * (isTablet(context) ? 10 : 10)),
              child: Text(
                "CME Credits Tracker",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: scalingFactor * (isTablet(context) ? 24 : 28),
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF0070C0),
                ),
              ),
            ),
            SizedBox(height: scalingFactor * (isTablet(context) ? 15 : 0)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 40 : 10)),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'WiRED International is proud to introduce our new continuing medical education tracker. Submit and track all of your CME credits for the year using WiRED\'s extensive health module library. For more information on how to manage and incorporate WiRED\'s CME Tracker into your curriculum please visit here:\n',
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 15 : 18),
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF548235),
                      ),
                    ),
                    WidgetSpan(
                      child: SizedBox(
                        height: scalingFactor * (isTablet(context) ? 30 : 40),
                      ),
                    ),
                    TextSpan(
                      text: 'www.wiredinternational.org',
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 18 : 22),
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF0070C0),
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () async {
                          final url = Uri.parse('https://www.wiredinternational.org');
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
            ),

            SizedBox(height: scalingFactor * (isTablet(context) ? 20 : 20)),

            // Login / Register Section
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    print("Login Tapped");
                    Navigator.push(context, MaterialPageRoute(builder: (context) => Login()));
                  },
                  child: Text(
                    "Login",
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 22 : 26),
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0070C0),
                    ),
                  ),
                ),
                SizedBox(width: scalingFactor * (isTablet(context) ? 15 : 10)),
                Text(
                  "or",
                  style: TextStyle(
                    fontSize: scalingFactor * (isTablet(context) ? 18 : 26),
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF548235),
                  ),
                ),
                SizedBox(width: scalingFactor * (isTablet(context) ? 15 : 10)),
                GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => Register()));
                  },
                  child: Text(
                    "Register",
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 22 : 26),
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0070C0),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: scalingFactor * (isTablet(context) ? 20 : 20)),
          ],
        ),
      ),
    );
  }
}
