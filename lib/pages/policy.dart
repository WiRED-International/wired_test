
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wired_test/utils/custom_nav_bar.dart';
import '../utils/custom_app_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'cme/cme_info.dart';
import 'home_page.dart';
import 'menu.dart';
import 'module_library.dart';

class Policy extends StatelessWidget {
  const Policy({super.key});

    final privacyPolicy = ''' 
Privacy Policy

Effective Date: 9/26/24

1. Introduction

WiRED International respects your privacy. This Privacy Policy explains how we handle user information in connection with the  mobile application. By using the App, you agree to the terms of this Privacy Policy.

2. Information We Do Not Collect

We do not collect, use, or share any personally identifiable information (PII) or non-personally identifiable information (Non-PII) from users of the App. Your privacy is important to us, and we are committed to protecting it.

3. Permissions Requested

The App requests permission to access your device's external storage. This permission is solely used for the purpose of transferring health education modules to your external storage so that you can view these modules offline within the App. No other data is collected, stored, or shared during this process.

4. How We Use the Permissions

External Storage Access: The App requires access to your device’s external storage to save the health education modules you choose to download. These files are stored locally on your device and are not shared with any third party.

5. Data Security

We do not collect or store any personal data, thus eliminating the risk of unauthorized access or data breaches. The health education modules stored on your device remain under your control, and their security depends on your device's security settings.

6. Third-Party Services

The App does not integrate or use any third-party services that collect data from users.

7. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Any changes will be reflected with a new "Effective Date" at the top of this document. We encourage you to review this Privacy Policy periodically to stay informed about how we are protecting your privacy.

8. Contact Us

If you have any questions or concerns about this Privacy Policy, please contact us at seanbristol81@gmail.com.

    ''';
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
                            onTrackerTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => CmeInfo()),
                              );
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
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => CmeInfo()),
                        );
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

  Widget _buildPortraitLayout(BuildContext context, screenWidth, screenHeight, baseSize) {
    return Column(
      children: [
        // Module Description Container
        Flexible(
          child: Stack(
            children: [
              Container(
                // height: baseSize * (isTablet(context) ? 1.16 : 1.3),
                width: baseSize * (isTablet(context) ? 0.9 : 0.9),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: baseSize * (isTablet(context) ? 0.17 : 0.17),
                      top: 15,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          privacyPolicy,
                          style: TextStyle(
                            fontSize: baseSize * (isTablet(context) ? 0.03 : 0.03),
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: baseSize * (isTablet(context) ? 0.3 : 0.3),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 1.0],
                        colors: [
                          Color(0xFFFDD09A).withOpacity(0.0),
                          Color(0xFFFDD09A),
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

  Widget _buildLandscapeLayout(BuildContext context, screenWidth, screenHeight, baseSize) {
    return Column(
      children: [
        Flexible(
          child: Stack(
            children: [
              Container(
                //height: screenHeight * 0.80,
                width: baseSize * (isTablet(context) ? 1.5 : 1.5),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: baseSize * (isTablet(context) ? 0.17 : 0.17),
                      top: 15,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          privacyPolicy,
                          style: TextStyle(
                            fontSize: baseSize * (isTablet(context) ? 0.03 : 0.03),
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 5.0],
                        colors: [
                          Color(0xFFFCDBB3).withOpacity(0.0),
                          Color(0xFFFED39F),
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
