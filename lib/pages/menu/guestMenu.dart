import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_guard.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import 'package:http/http.dart' as http;
import '../cme/cme_tracker.dart';
import '../cme/login.dart';
import '../cme/register.dart';
import '../creditsTracker/credits_tracker.dart';
import '../home_page.dart';
import '../module_library.dart';
import 'about_wired.dart';
import 'language.dart';
import 'meet_team.dart';


class GuestMenu extends StatefulWidget {
  final void Function(Locale)? onLocaleChange;

  const GuestMenu({Key? key, this.onLocaleChange}) : super(key: key);

  @override
  _GuestMenuState createState() => _GuestMenuState();
}


class _GuestMenuState extends State<GuestMenu> {

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
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
                                builder: (context) =>
                                    AuthGuard(
                                      child: CreditsTracker(),
                                    ),
                              ),
                            );
                          },
                          onMenuTap: () {
                            // This is purposefully left blank
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
                        MaterialPageRoute(
                            builder: (context) => ModuleLibrary()),
                      );
                    },
                    onTrackerTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AuthGuard(
                                child: CreditsTracker(),
                              ),
                        ),
                      );
                    },
                    onMenuTap: () {
                      // This is purposefully left blank
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildPortraitLayout(scalingFactor) {
    final double imageHeight = scalingFactor * (isTablet(context) ? 170 : 170);
    // Calculate extra space for the overlapping buttons.
    final double overlapOffset = scalingFactor * (isTablet(context) ? 35 : 35);

    return SingleChildScrollView(
      child: Column(
        children: <Widget>[
          Container(
            // Increase the container height to include the overlapping area.
            height: imageHeight + overlapOffset,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: <Widget>[
                // Image with fade effect
                ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Color(0xFFFCEDDA).withOpacity(0.0),
                        Color(0xFFFCEDDA).withOpacity(1.0),
                      ],
                      stops: [0.0, 0.2],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: Container(
                    width: double.infinity,
                    height: imageHeight,
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage('assets/images/menu-pic-optimized.webp'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                // Top two buttons overlapping the image
                Positioned(
                  bottom: -overlapOffset,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildInkWellButton('Meet The Team', scalingFactor, () async {
                        final Uri url = Uri.parse('https://sites.google.com/view/wired-international-team/home');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not launch Meet The Team')),
                          );
                        }
                      }),
                      _buildInkWellButton('About WiRED', scalingFactor, () async {
                        final Uri url = Uri.parse('https://sites.google.com/view/healthmap-about/home');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not launch About WiRED')),
                          );
                        }
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Spacer and the bottom section remain unchanged...
          SizedBox(height: scalingFactor * (isTablet(context) ? 45 : 45)),
          // Bottom section: Privacy Policy, Registration, and Login buttons.
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildInkWellButton('Privacy Policy', scalingFactor, () async {
                    final Uri url = Uri.parse('https://sites.google.com/view/healthmapprivacypolicy/home');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not launch Privacy Policy')),
                      );
                    }
                  }),
                  _buildInkWellButton('Language', scalingFactor, () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => Language(
                        currentLocale: Localizations.localeOf(context),
                        onLocaleChange: (Locale newLocale) {
                          // Handle the locale change (e.g., by calling a provider or setState on parent)
                          print('Locale changed to: $newLocale');
                        },
                      )),
                    );
                  }),
                ],
              ),
              SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 30)),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => Register()),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 12 : 15)),
                    child: Text(
                      'CME Tracker Registration',
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 18 : 18),
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF0070C0),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 30)),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => Login()),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 12 : 15)),
                    child: Text(
                      'CME Tracker Login',
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 18 : 18),
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF0070C0),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 30)),
              GestureDetector(
                onTap: () async {
                  final Uri deleteAccountUri = Uri.parse("https://sites.google.com/view/wired-international-healthmap/home");

                  if (await canLaunchUrl(deleteAccountUri)) {
                    await launchUrl(deleteAccountUri, mode: LaunchMode.externalApplication);
                  } else {
                    print("Could not open the delete account request page");
                    _showCopyDeleteAccountDialog(context);
                  }
                },
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 12 : 15)),
                    child: Text(
                      'Request Data Deletion',
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 18 : 18),
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF0070C0),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 20 : 0)),
        ],
      ),
    );
  }




// 🔹 Helper function for buttons with InkWell
  Widget _buildInkWellButton(String text, double scalingFactor, VoidCallback onTap) {
    return Material(
      color: Colors.transparent, // Ensures ripple effect works
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10), // Rounded edges for ripple effect
        splashColor: Colors.grey.withOpacity(0.3), // Light splash effect
        child: Container(
          height: scalingFactor * (isTablet(context) ? 90 : 90),
          width: scalingFactor * (isTablet(context) ? 165 : 165),
          padding: EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Color(0xFFFCEDDA),
            border: Border.all(color: Colors.black, width: 0.7),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.5),
                spreadRadius: 2,
                blurRadius: 5,
                offset: Offset(3, 3),
              ),
            ],
          ),
          child: Center( // Ensures text is centered
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: scalingFactor * (isTablet(context) ? 15 : 15),
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }

// 🔹 Helper function for an empty placeholder button
  Widget _buildEmptyButton(double scalingFactor) {
    return Container(
      height: scalingFactor * (isTablet(context) ? 90 : 90),
      width: scalingFactor * (isTablet(context) ? 165 : 165),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.transparent, // Invisible placeholder
      ),
    );
  }

  Widget _buildLandscapeLayout(scalingFactor) {
    final double imageHeight = scalingFactor * (isTablet(context) ? 170 : 140);
    // Calculate extra space for the overlapping buttons.
    final double overlapOffset = scalingFactor * (isTablet(context) ? 35 : 35);

    return SingleChildScrollView(
      child: Column(
        children: <Widget>[
          Container(
            // Increase the container height to include the overlapping area.
            height: imageHeight + overlapOffset,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: <Widget>[
                // Image with fade effect
                ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Color(0xFFFCEDDA).withOpacity(0.0),
                        Color(0xFFFCEDDA).withOpacity(1.0),
                      ],
                      stops: [0.0, 0.2],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: Container(
                    width: double.infinity,
                    height: imageHeight,
                    decoration: const BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage('assets/images/menu-pic-optimized.webp'),
                        fit: BoxFit.fitWidth,
                      ),
                    ),
                  ),
                ),
                // Top two buttons overlapping the image
                Positioned(
                  bottom: -overlapOffset,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildInkWellButton('Meet The Team', scalingFactor, () async {
                        final Uri url = Uri.parse('https://sites.google.com/view/wired-international-team/home');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not launch Meet The Team')),
                          );
                        }
                      }),
                      _buildInkWellButton('About WiRED', scalingFactor, () async {
                        final Uri url = Uri.parse('https://sites.google.com/view/healthmap-about/home');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not launch About WiRED')),
                          );
                        }
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Spacer and the bottom section remain unchanged...
          SizedBox(height: scalingFactor * (isTablet(context) ? 45 : 45)),
          // Bottom section: Privacy Policy, Registration, and Login buttons.
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildInkWellButton('Privacy Policy', scalingFactor, () async {
                    final Uri url = Uri.parse('https://sites.google.com/view/healthmapprivacypolicy/home');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not launch Privacy Policy')),
                      );
                    }
                  }),
                  _buildEmptyButton(scalingFactor),
                ],
              ),
              SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 30)),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => Register()),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 60 : 55)),
                    child: Text(
                      'CME Tracker Registration',
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 18 : 18),
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF0070C0),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: scalingFactor * (isTablet(context) ? 20 : 20)),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => Login()),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 60 : 55)),
                    child: Text(
                      'CME Tracker Login',
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 18 : 18),
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF0070C0),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: scalingFactor * (isTablet(context) ? 20 : 20),
              ),
              GestureDetector(
                onTap: () async {
                  final Uri deleteAccountUri = Uri.parse("https://sites.google.com/view/wired-international-healthmap/home");

                  if (await canLaunchUrl(deleteAccountUri)) {
                    await launchUrl(deleteAccountUri, mode: LaunchMode.externalApplication);
                  } else {
                    print("Could not open the delete account request page");
                    _showCopyDeleteAccountDialog(context);
                  }
                },
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 60 : 55)),
                    child: Text(
                      'Request Data Deletion',
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 18 : 18),
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF0070C0),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 30)),
        ],
      ),
    );
  }
  void _showCopyDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Unable to Open Link"),
        content: SelectableText(
          "Please manually open this link in your browser:\n\nhttps://docs.google.com/document/d/YOUR_DOCUMENT_ID/view",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: "https://sites.google.com/view/wired-international-healthmap/home"));
              Navigator.of(context, rootNavigator: true).pop(); // Close dialog
            },
            child: Text("Copy Link"),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pop(); // Close dialog
            },
            child: Text("Close"),
          ),
        ],
      ),
    );
  }
}