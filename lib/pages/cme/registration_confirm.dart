import 'package:flutter/material.dart';
import 'package:wired_test/pages/home_page.dart';
import 'package:wired_test/utils/functions.dart';
import 'package:wired_test/utils/side_nav_bar.dart';
import 'package:wired_test/utils/custom_nav_bar.dart';
import '../../providers/auth_guard.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import 'cme_tracker.dart';
import 'login.dart';

class RegistrationConfirm extends StatefulWidget {

  const RegistrationConfirm({super.key});

  @override
  _RegistrationConfirmState createState() => _RegistrationConfirmState();
}

class _RegistrationConfirmState extends State<RegistrationConfirm> {
  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final scalingFactor = getScalingFactor(context);

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
                                builder: (context) => AuthGuard(
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
                                builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                              ),
                            );
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(
                              screenWidth, screenHeight, scalingFactor)
                              : _buildPortraitLayout(
                              screenWidth, screenHeight, scalingFactor),
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
                          builder: (context) => AuthGuard(
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
                          builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
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

  Widget _buildPortraitLayout(screenWidth, screenHeight, scalingFactor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 10 : 10),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 10 : 10)),
          child: Text(
            "You have successfully registered for the CME Credits Tracker. Please login with your email and password to continue.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: scalingFactor * (isTablet(context) ? 20 : 24),
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ),
        // SizedBox(
        //   height: scalingFactor * (isTablet(context) ? 10 : 0.07),
        // ),
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
              fontSize: scalingFactor * (isTablet(context) ? 20 : 24),
              fontWeight: FontWeight.w500,
              color: Color(0xFF0070C0),
            ),
          ),
        ),
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 20 : 20),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight, scalingFactor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 50 : 40)),
          child: Text(
            "You have successfully registered for the CME Credits Tracker. Please login with your email and password to continue.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: scalingFactor * (isTablet(context) ? 18 : 22),
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
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
              fontSize: scalingFactor * (isTablet(context) ? 18 : 22),
              fontWeight: FontWeight.w500,
              color: Color(0xFF0070C0),
            ),
          ),
        ),
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 20 : 20),
        ),
      ],
    );
  }
}
