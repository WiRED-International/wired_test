import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/pages/policy.dart';
import '../providers/auth_guard.dart';
import '../providers/auth_provider.dart';
import '../providers/user_provider.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'cme/cme_info.dart';
import 'cme/cme_tracker.dart';
import 'cme/login.dart';
import 'home_page.dart';
import 'module_library.dart';


class Menu extends StatefulWidget {
  @override
  _MenuState createState() => _MenuState();
}

class _MenuState extends State<Menu> {
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
                // Custom AppBar
                // CustomAppBar(
                //   onBackPressed: () {
                //     Navigator.pop(context);
                //   },
                // ),
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
                            // Retrieve user data from UserProvider
                            final userProvider = Provider.of<UserProvider>(context, listen: false);

                            // Check if the user data is available
                            if (userProvider.firstName != null && userProvider.email != null) {
                              // Navigate to CMETracker with user data
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CMETracker(),
                                ),
                              );
                            } else {
                              // Handle the case where user data is not available (e.g., redirect to login)
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => Login(), // Redirect to Login if no user data
                                ),
                              );
                            }
                          },
                          onMenuTap: () {
                            //Purposefully left blank
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(context, screenWidth, screenHeight, baseSize)
                              : _buildPortraitLayout(context, screenWidth, screenHeight, baseSize),
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
                      // Retrieve user data from UserProvider
                      final userProvider = Provider.of<UserProvider>(context, listen: false);

                      // Check if the user data is available
                      if (userProvider.firstName != null && userProvider.email != null) {
                        // Navigate to CMETracker with user data
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CMETracker(),
                          ),
                        );
                      } else {
                        // Handle the case where user data is not available (e.g., redirect to login)
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => Login(), // Redirect to Login if no user data
                          ),
                        );
                      }
                    },
                    onMenuTap: () {
                      //Purposefully left blank
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(
      BuildContext context, double screenWidth, double screenHeight, double baseSize) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Expanded(
          child: ListView(
            children: <Widget>[
              ListTile(
                title: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: baseSize * (isTablet(context) ? 0.6 : 0.7),
                    child: Container(
                      padding: EdgeInsets.all(16.0), // Adds padding for a square-like shape
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: const Color(0xFFFFFFFF),
                        border: Border.all(color: Colors.black, width: 2), // Black border
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.5), // Shadow color with opacity
                            spreadRadius: 2, // Spread radius
                            blurRadius: 5, // Blur radius
                            offset: Offset(3, 3), // Horizontal and vertical shadow offset
                          ),
                        ],
                      ),
                      child: Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: baseSize * (isTablet(context) ? 0.07 : 0.08),
                          fontWeight: FontWeight.w500,
                          color: const Color.fromRGBO(0, 102, 179, 1),
                        ),
                      ),
                    ),
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => Policy()),
                  );
                },
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () {
            Provider.of<AuthProvider>(context, listen: false).logOut();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => Login()),
            );
          },
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: baseSize * (isTablet(context) ? 0.05 : 0.03)),
              child: Text(
                'Log out',
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.07 : 0.08),
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.05 : 0.06),
          width: baseSize * (isTablet(context) ? 0.05 : 0.06),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(
      BuildContext context, double screenWidth, double screenHeight, double baseSize) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Expanded(
          child: ListView(
            children: <Widget>[
              ListTile(
                title: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: baseSize * (isTablet(context) ? 0.6 : 0.7),
                    child: Container(
                      padding: EdgeInsets.all(16.0), // Adds padding for a square-like shape
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: const Color(0xFFFFFFFF),
                        border: Border.all(color: Colors.black, width: 2), // Black border
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.5), // Shadow color with opacity
                            spreadRadius: 2, // Spread radius
                            blurRadius: 5, // Blur radius
                            offset: Offset(3, 3), // Horizontal and vertical shadow offset
                          ),
                        ],
                      ),
                      child: Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: baseSize * (isTablet(context) ? 0.07 : 0.08),
                          fontWeight: FontWeight.w500,
                          color: const Color.fromRGBO(0, 102, 179, 1),
                        ),
                      ),
                    ),
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => Policy()),
                  );
                },
              ),
              GestureDetector(
                onTap: () {
                  Provider.of<AuthProvider>(context, listen: false).logOut();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => Login()),
                  );
                },
                child: Text(
                  'Log out',
                  style: TextStyle(
                    fontSize: baseSize * (isTablet(context) ? 0.07 : 0.08),
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
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
