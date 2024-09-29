import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wired_test/utils/custom_nav_bar.dart';
import '../utils/custom_app_bar.dart';
import 'home_page.dart';
import 'module_library.dart';

class Policy extends StatelessWidget {
  const Policy({super.key});

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
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
    return Scaffold(
      body: Stack(
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
                      child: Column(
                        children: [
                          CustomAppBar(
                            onBackPressed: () {
                              Navigator.pop(context);
                            },
                          ),
                          // Module Description Container
                          Flexible(
                            child: Stack(
                              children: [
                                Positioned(
                                  //top: MediaQuery.of(context).size.width / 50, // Adjust this value based on your layout
                                  left: MediaQuery
                                      .of(context)
                                      .size
                                      .width / 15,
                                  right: MediaQuery
                                      .of(context)
                                      .size
                                      .width / 15,
                                  //bottom: 140,
                                  bottom: screenHeight * 0.14,
                                  child: Container(
                                    //height: 750,
                                    height: screenHeight * 0.80,
                                    width: 400,
                                    decoration: BoxDecoration(
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: SingleChildScrollView(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          bottom: 50,
                                          top: 50,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              privacyPolicy,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Container for gradient text fade
                                Positioned(
                                  //bottom: 140,
                                  bottom: screenHeight * 0.14,
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
                                              // Colors.transparent,
                                              // Color(0xFFFFF0DC),
                                              //Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
                                              Color(0xFFFCDBB3).withOpacity(0.0),
                                              Color(0xFFFED39F),
                                            ],
                                          ),
                                        )
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          // Bottom Nav Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CustomBottomNavBar(
              onHomeTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => MyHomePage()));
              },
              onLibraryTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleLibrary()));
              },
              onHelpTap: () {
                print("Policy");
                //Navigator.push(context, MaterialPageRoute(builder: (context) => Help()));
              },
            ),
          ),

    ],
    )
    );
  }
}