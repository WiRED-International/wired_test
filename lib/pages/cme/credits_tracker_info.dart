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

class CreditsTrackerInfo extends StatefulWidget {
  @override
  _CreditsTrackerInfoState createState() => _CreditsTrackerInfoState();
}

class _CreditsTrackerInfoState extends State<CreditsTrackerInfo> with SingleTickerProviderStateMixin {
  double _logoOpacity = 0.0;
  double _titleOpacity = 0.0;
  Offset _logoOffset = const Offset(0, 0.1);
  Offset _titleOffset = const Offset(0, 0.1);

  @override
  void initState() {
    super.initState();

    // 🕒 Smooth fade-in sequence
    Future.delayed(const Duration(milliseconds: 300), () {
      setState(() {
        _logoOpacity = 1.0;
        _logoOffset = Offset.zero;
      });
    });

    Future.delayed(const Duration(milliseconds: 700), () {
      setState(() {
        _titleOpacity = 1.0;
        _titleOffset = Offset.zero;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final baseSize = mediaQuery.size.shortestSide;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final isTabletDevice = isTablet(context);

    // 🔹 Adjust scaling for tablet vs phone
    final scale = isTabletDevice ? 1.0 : 1.0;

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
                            //Purposefully left blank
                          },
                          onMenuTap: () async {
                            bool isLoggedIn = await checkIfUserIsLoggedIn();
                            print("Navigating to menu. Logged in: $isLoggedIn");
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                isLoggedIn
                                    ? Menu()
                                    : GuestMenu(),
                              ),
                            );
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(context, baseSize, scale)
                              : _buildPortraitLayout(context, baseSize, scale),
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
                      //Purposefully left blank
                    },
                    onMenuTap: () async {
                      bool isLoggedIn = await checkIfUserIsLoggedIn();
                      print("Navigating to menu. Logged in: $isLoggedIn");
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                          isLoggedIn
                              ? Menu()
                              : GuestMenu(),
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


  Widget _buildPortraitLayout(BuildContext context, double baseSize,
      double scale) {
    final bool tablet = isTablet(context);

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: baseSize * 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: baseSize * 0.0),

          // 🟢 Animated Logo
          AnimatedSlide(
            offset: _logoOffset,
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: _logoOpacity,
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              child: Image.asset(
                'assets/images/academic_credit_tracker_logo.webp',
                width: baseSize * 0.36 * scale,
                height: baseSize * 0.36 * scale,
                fit: BoxFit.contain,
              ),
            ),
          ),

          SizedBox(height: baseSize * 0.03),

          // 🏷️ Animated Title
          AnimatedSlide(
            offset: _titleOffset,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: _titleOpacity,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              child: Text(
                "Credits Tracker",
                style: TextStyle(
                  fontSize: baseSize * 0.06 * scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          SizedBox(height: baseSize * 0.04),

          // 🩺 Info Text + Link
          Padding(
            padding: EdgeInsets.symmetric(horizontal: baseSize * 0.02),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(
                    text:
                    'WiRED International is proud to introduce our new Continuing Medical Education (CME) tracker. '
                        'Submit and track all of your CME credits for the year using WiRED’s extensive health module library. '
                        'For more information on how to manage and incorporate WiRED’s CME Tracker into your curriculum, please visit:\n\n',
                    style: TextStyle(
                      fontSize: baseSize * (tablet ? 0.028 : 0.036) * scale,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF548235),
                      height: 1.5,
                    ),
                  ),
                  TextSpan(
                    text: 'www.wiredinternational.org',
                    style: TextStyle(
                      fontSize: baseSize * (tablet ? 0.032 : 0.045) * scale,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0070C0),
                      decoration: TextDecoration.underline,
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

          SizedBox(height: baseSize * 0.08),

          // 🔹 Login / Register Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                    fontSize: baseSize * (tablet ? 0.04 : 0.055) * scale,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0070C0),
                  ),
                ),
              ),
              SizedBox(width: baseSize * 0.03),
              Text(
                "or",
                style: TextStyle(
                  fontSize: baseSize * (tablet ? 0.034 : 0.045) * scale,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF548235),
                ),
              ),
              SizedBox(width: baseSize * 0.03),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => Register()),
                  );
                },
                child: Text(
                  "Register",
                  style: TextStyle(
                    fontSize: baseSize * (tablet ? 0.04 : 0.055) * scale,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0070C0),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: baseSize * 0.05),
        ],
      ),
    );
  }


  Widget _buildLandscapeLayout(BuildContext context, double baseSize,
      double scale) {
    final bool tablet = isTablet(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: baseSize * 0.05),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 🟢 Animated Logo (Left side)
          AnimatedSlide(
            offset: _logoOffset,
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: _logoOpacity,
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              child: Image.asset(
                'assets/images/academic_credit_tracker_logo.webp',
                width: baseSize * 0.35 * scale,
                height: baseSize * 0.35 * scale,
                fit: BoxFit.contain,
              ),
            ),
          ),

          SizedBox(width: baseSize * 0.07),

          // 📘 Animated Title + Text + Buttons (Right side)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🏷️ Title
                AnimatedSlide(
                  offset: _titleOffset,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  child: AnimatedOpacity(
                    opacity: _titleOpacity,
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    child: Text(
                      "Credits Tracker",
                      style: TextStyle(
                        fontSize: baseSize * 0.06 * scale,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: baseSize * 0.05),

                // 🩺 Info Text + Link
                RichText(
                  textAlign: TextAlign.start,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text:
                        'WiRED International proudly introduces our new Continuing Medical Education (CME) tracker. '
                            'Submit and track your CME credits throughout the year using WiRED’s extensive health module library. '
                            'To learn more about integrating WiRED’s CME Tracker into your curriculum, visit:\n\n',
                        style: TextStyle(
                          fontSize: baseSize * (tablet ? 0.026 : 0.036) * scale,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF548235),
                          height: 1.4,
                        ),
                      ),
                      TextSpan(
                        text: 'www.wiredinternational.org',
                        style: TextStyle(
                          fontSize: baseSize * (tablet ? 0.03 : 0.045) * scale,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0070C0),
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () async {
                            final url =
                            Uri.parse('https://www.wiredinternational.org');
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

                SizedBox(height: baseSize * 0.06),

                // 🔹 Login / Register Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
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
                          fontSize: baseSize * (tablet ? 0.035 : 0.055) * scale,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0070C0),
                        ),
                      ),
                    ),
                    SizedBox(width: baseSize * 0.025),
                    Text(
                      "or",
                      style: TextStyle(
                        fontSize: baseSize * (tablet ? 0.03 : 0.045) * scale,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF548235),
                      ),
                    ),
                    SizedBox(width: baseSize * 0.025),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => Register()),
                        );
                      },
                      child: Text(
                        "Register",
                        style: TextStyle(
                          fontSize: baseSize * (tablet ? 0.035 : 0.055) * scale,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0070C0),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
