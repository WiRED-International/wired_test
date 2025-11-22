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
import '../../utils/screen_utils.dart';

class CreditsTrackerInfo extends StatefulWidget {
  @override
  _CreditsTrackerInfoState createState() => _CreditsTrackerInfoState();
}

class _CreditsTrackerInfoState extends State<CreditsTrackerInfo>
    with SingleTickerProviderStateMixin {
  double _logoOpacity = 0.0;
  double _titleOpacity = 0.0;
  Offset _logoOffset = const Offset(0, 0.1);
  Offset _titleOffset = const Offset(0, 0.1);

  @override
  void initState() {
    super.initState();

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
    final media = MediaQuery.of(context);
    final shortest = media.size.shortestSide;
    final isLandscape = media.orientation == Orientation.landscape;
    final bool tablet = ScreenUtils.isTablet(context);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // 📌 Your original gradient background (unchanged)
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
                Expanded(
                  child: Row(
                    children: [
                      if (isLandscape)
                        CustomSideNavBar(
                          onHomeTap: () =>
                              Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const MyHomePage())),
                          onLibraryTap: () =>
                              Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => ModuleLibrary())),
                          onTrackerTap: () {},
                          onMenuTap: () async {
                            final loggedIn = await checkIfUserIsLoggedIn();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => loggedIn ? Menu() : GuestMenu(),
                              ),
                            );
                          },
                        ),

                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscape(context, shortest, tablet)
                              : _buildPortrait(context, shortest, tablet),
                        ),
                      ),
                    ],
                  ),
                ),

                if (!isLandscape)
                  CustomBottomNavBar(
                    onHomeTap: () =>
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const MyHomePage())),
                    onLibraryTap: () =>
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ModuleLibrary())),
                    onTrackerTap: () {},
                    onMenuTap: () async {
                      final loggedIn = await checkIfUserIsLoggedIn();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => loggedIn ? Menu() : GuestMenu(),
                        ),
                      );
                    },
                  ),
              ],
            ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: CustomAppBar(
                onBackPressed: () => Navigator.pop(context),
                requireAuth: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  //                           PORTRAIT
  // ================================================================
  Widget _buildPortrait(BuildContext context, double base, bool tablet) {
    final double logoSize = base * 0.36;
    final double titleSize = ScreenUtils.scaleFont(context, 30);
    final double linkSize = tablet ? base * 0.032 : base * 0.06;

    // B1 paragraph scaling: ~12-15% smaller on tablets
    final double paragraphSize = ScreenUtils.scaleFont(context, tablet ? 12.5 : 19);

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: ScreenUtils.hPad(context)),
      child: Column(
        children: [
          SizedBox(height: base * 0.02),

          AnimatedSlide(
            offset: _logoOffset,
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: _logoOpacity,
              duration: const Duration(milliseconds: 700),
              child: Image.asset(
                'assets/images/academic_credit_tracker_logo.webp',
                width: logoSize,
                height: logoSize,
              ),
            ),
          ),

          SizedBox(height: base * 0.03),

          AnimatedSlide(
            offset: _titleOffset,
            duration: const Duration(milliseconds: 600),
            child: AnimatedOpacity(
              opacity: _titleOpacity,
              duration: const Duration(milliseconds: 600),
              child: Text(
                "Credits Tracker",
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          SizedBox(height: base * 0.04),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: base * 0.02),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(
                    text:
                    'WiRED International proudly introduces our new Continuing Medical Education (CME) tracker. '
                      'Submit and track your CME credits throughout the year using WiRED’s extensive health module library. '
                        'To learn more about integrating WiRED’s CME Tracker into your curriculum, visit:\n\n',
                    style: TextStyle(
                      fontSize: paragraphSize,
                      color: const Color(0xFF548235),
                      height: 1.5,
                    ),
                  ),
                  TextSpan(
                    text: "www.wiredinternational.org",
                    style: TextStyle(
                      fontSize: linkSize,
                      color: const Color(0xFF0070C0),
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () async {
                        final url =
                        Uri.parse('https://www.wiredinternational.org');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        }
                      },
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: base * 0.08),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _navButton(context, "Login", linkSize),
              SizedBox(width: base * 0.03),
              Text("or",
                  style: TextStyle(
                      fontSize: ScreenUtils.scaleFont(context, 16),
                      color: const Color(0xFF548235))),
              SizedBox(width: base * 0.03),
              _navButton(context, "Register", linkSize, isLogin: false),
            ],
          ),

          SizedBox(height: base * 0.05),
        ],
      ),
    );
  }

  // ================================================================
  //                           LANDSCAPE
  // ================================================================
  Widget _buildLandscape(BuildContext context, double base, bool tablet) {
    final double logoSize = base * 0.35;
    final double titleSize = ScreenUtils.scaleFont(context, 26);

    final double paragraphSize =
    ScreenUtils.scaleFont(context, tablet ? 12.5 : 14);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ScreenUtils.hPad(context)),
      child: Row(
        children: [
          AnimatedSlide(
            offset: _logoOffset,
            duration: const Duration(milliseconds: 700),
            child: AnimatedOpacity(
              opacity: _logoOpacity,
              duration: const Duration(milliseconds: 700),
              child: Image.asset(
                'assets/images/academic_credit_tracker_logo.webp',
                width: logoSize,
                height: logoSize,
              ),
            ),
          ),

          SizedBox(width: base * 0.08),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSlide(
                  offset: _titleOffset,
                  duration: const Duration(milliseconds: 600),
                  child: AnimatedOpacity(
                    opacity: _titleOpacity,
                    duration: const Duration(milliseconds: 600),
                    child: Text(
                      "Credits Tracker",
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: base * 0.04),

                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text:
                        'WiRED International proudly introduces our new Continuing Medical Education (CME) tracker. '
                          'Submit and track your CME credits throughout the year using WiRED’s extensive health module library. '
                            'To learn more about integrating WiRED’s CME Tracker into your curriculum, visit:\n\n',
                        style: TextStyle(
                          fontSize: paragraphSize,
                          color: const Color(0xFF548235),
                          height: 1.4,
                        ),
                      ),
                      TextSpan(
                        text: "www.wiredinternational.org",
                        style: TextStyle(
                          fontSize: ScreenUtils.scaleFont(context, 17),
                          color: const Color(0xFF0070C0),
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w600,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () async {
                            final url = Uri.parse(
                                'https://www.wiredinternational.org');
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url);
                            }
                          },
                      ),
                    ],
                  ),
                ),

                SizedBox(height: base * 0.06),

                Row(
                  children: [
                    _navButton(context, "Login", ScreenUtils.scaleFont(context, 17)),
                    SizedBox(width: base * 0.03),
                    Text("or",
                        style: TextStyle(
                            fontSize: ScreenUtils.scaleFont(context, 15),
                            color: const Color(0xFF548235))),
                    SizedBox(width: base * 0.03),
                    _navButton(context, "Register",
                        ScreenUtils.scaleFont(context, 17),
                        isLogin: false),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // ================================================================
  //                      NAVIGATION BUTTON HELPER
  // ================================================================
  Widget _navButton(BuildContext context, String label, double size,
      {bool isLogin = true}) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => isLogin ? Login() : Register()));
      },
      child: Text(
        label,
        style: TextStyle(
          fontSize: size,
          color: const Color(0xFF0070C0),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
