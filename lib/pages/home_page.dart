import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/providers/auth_guard.dart';
import 'package:wired_test/utils/functions.dart';
import '../l10n/app_localizations.dart';
import '../pages/search.dart';
import '../providers/auth_provider.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/updateChecker.dart';
import 'cme/cme_tracker.dart';
import 'creditsTracker/credits_tracker.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
import 'module_info.dart';
import 'module_library.dart';
import 'package:wired_test/utils/side_nav_bar.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:flutter_gen/gen_l10n/app_localizations.dart';


class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, this.title, this.onLocaleChange});
  final String? title;
  final void Function(Locale)? onLocaleChange;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class Alert {
  String? alert;
  bool? important;

  Alert({
    this.alert,
    this.important,
  });

  Alert.fromJson(Map<String, dynamic> json)
      : alert = json['alert'] as String,
        important = json['important'] as bool;

  Map<String, dynamic> toJson() => {
    'alert': alert,
    'important': important,
  };
}

class _MyHomePageState extends State<MyHomePage> {
  late Future<Alert> futureAlert;
  String alert = "";

  Future<Alert?> getAlert() async {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final apiEndpoint = '/alerts/latest';
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl$apiEndpoint'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        return Alert.fromJson(data);
      } else {
        debugPrint("Failed to load alert, status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error fetching alert: $e");
    }
    return null;
  }

  bool isImportant = false;
  @override
  void initState() {
    super.initState();
    getAlert().then((alertObj) {
      if (alertObj != null) {
        setState(() {
          alert = alertObj.alert ?? "No alert available";
          isImportant = alertObj.important ?? false;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateChecker.checkForUpdate(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    var baseSize = MediaQuery.of(context).size.shortestSide;
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.transparent, // Ensures no default white background
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
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
          ),
          Row(
            children: [
              // Side Nav Bar with transparent background
              if (isLandscape)
                SafeArea(
                  child: Container(
                    color: Colors.transparent, // Ensures no white background
                    child: CustomSideNavBar(
                      onHomeTap: () {},
                      onLibraryTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleLibrary()));
                      },
                      onTrackerTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AuthGuard(child: CreditsTracker()),
                          ),
                        );
                      },
                      onMenuTap: () async {
                        bool isLoggedIn = await checkIfUserIsLoggedIn();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Main Content
              Expanded(
                child: SafeArea(
                  child: Center(
                    child: isLandscape
                        ? _buildLandscapeLayout(screenWidth, screenHeight, baseSize)
                        : _buildPortraitLayout(screenWidth, screenHeight, baseSize),
                  ),
                ),
              ),
            ],
          ),

          // Bottom Nav Bar only in portrait mode
          if (!isLandscape)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: CustomBottomNavBar(
                onHomeTap: () {},
                onLibraryTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleLibrary()));
                },
                onTrackerTap: () {
                  final authProvider = Provider.of<AuthProvider>(context, listen: false);

                  if (authProvider.isLoading) {
                    debugPrint("AuthProvider is still loading, delaying navigation...");
                    return;
                  }
                  // Navigator.push(
                  //   context,
                  //   MaterialPageRoute(
                  //     builder: (context) => AuthGuard(child: CMETracker()),
                  //   ),
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AuthGuard(child: CreditsTracker()),
                    ),
                  );
                },
                onMenuTap: () async {
                  bool isLoggedIn = await checkIfUserIsLoggedIn();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => isLoggedIn ? Menu(onLocaleChange: widget.onLocaleChange) : GuestMenu(onLocaleChange: widget.onLocaleChange),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildPortraitLayout(double screenWidth, double screenHeight, double baseSize) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Semantics(
          label: 'Wired Logo',
          child: Image.asset(
            'assets/images/wired-logo-optimized.webp',
            height: baseSize * (isTablet(context) ? 0.3 : 0.3),
          ),
        ),
        Text(
          AppLocalizations.of(context)!.homeTitle,
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.07 : 0.08),
            fontWeight: FontWeight.w500,
            color: const Color.fromRGBO(0, 102, 179, 1),
          ),
        ),

        Flexible(
          flex: 3,
          child: Padding(
            padding: EdgeInsets.only(
              top: baseSize * (isTablet(context) ? 0.015 : 0.015),
              bottom: baseSize * (isTablet(context) ? 0.0 : 0.04),
              left: baseSize * (isTablet(context) ? 0.04 : 0.04),
              right: baseSize * (isTablet(context) ? 0.04 : 0.04),

            ),
            child: Container(
              height: baseSize * (isTablet(context) ? 0.6 : 0.9),
              decoration: BoxDecoration(
                color: Color(0xFFF9EBD9),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: Color(0xFF0070C0),
                  width: 2,
                ),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: baseSize * (isTablet(context) ? 0.02 : 0.01),
                    horizontal: baseSize * (isTablet(context) ? 0.03 : 0.03),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'News and Updates',
                        style: TextStyle(
                          fontSize: baseSize * (isTablet(context) ? 0.06 : 0.07),
                          fontWeight: FontWeight.w500,
                          color: Color.fromRGBO(84, 130, 53, 1),
                        ),
                      ),
                      SizedBox(
                        height: baseSize * (isTablet(context) ? 0.01 : 0.01),
                      ),
                      Container(
                        padding: EdgeInsets.all(baseSize * 0.02),
                        child: MarkdownBody(
                          data: alert.isNotEmpty ? alert : "No alerts available",
                          onTapLink: (text, url, title) async {
                            if (url != null) {
                              final Uri uri = Uri.parse(url);
                              if (uri.scheme == 'app' && uri.host == 'download') {
                                final moduleIdString = uri.queryParameters['id'];
                                final moduleId = int.tryParse(moduleIdString ?? '');
                                final moduleName = uri.queryParameters['name'];
                                final downloadLink = uri.queryParameters['link'];
                                final moduleDescription = uri.queryParameters['description'] ?? 'No Description available';

                                if (moduleName != null && downloadLink != null && moduleId != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ModuleInfo(
                                        moduleId: moduleId,
                                        moduleName: moduleName,
                                        downloadLink: downloadLink,
                                        moduleDescription: moduleDescription,
                                      ),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Invalid module data provided.')),
                                  );
                                }
                              } else if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else {
                                debugPrint('Could not launch $url');
                              }
                            }
                          },
                          styleSheet: MarkdownStyleSheet(
                            a: TextStyle(
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.blue, // Blue underline
                              fontWeight: FontWeight.bold,
                            ),
                            p: TextStyle(fontSize: baseSize * (isTablet(context) ? 0.035 : 0.04)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.02 : 0.015),
        ),
        Flexible(
          flex: 1,
          child: Semantics(
            label: 'Modules Search Button',
            hint: 'Tap to search for modules',
            child: GestureDetector(
              onTap: () async {
                Navigator.push(
                    context, MaterialPageRoute(builder: (context) => Search()));
              },
              child: Hero(
                tag: 'modules',
                child: FractionallySizedBox(
                  widthFactor: isTablet(context) ? 0.33 : 0.4,
                  child: Container(
                    height: baseSize * (isTablet(context) ? 0.09 : 0.13),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0070C0),
                          Color(0xFF00C1FF),
                          Color(0xFF0070C0),
                        ], // Your gradient colors
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(
                              1, 3), // changes position of shadow
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                        builder: (context, constraints) {
                          double buttonWidth = constraints.maxWidth;
                          double fontSize = buttonWidth * 0.2;
                          double padding = buttonWidth * 0.02;
                          return Padding(
                            padding: EdgeInsets.all(padding),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.fitWidth,
                                    child: Text(
                                      "Modules",
                                      style: TextStyle(
                                        fontSize: fontSize,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: baseSize * (isTablet(context) ? .2 : 0.25)),
      ],
    );
  }

  Widget _buildLandscapeLayout(double screenWidth, double screenHeight, double baseSize) {
    return Column(
      //crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Semantics(
          label: 'Wired Logo',
          child: Image.asset(
            'assets/images/wired-logo-optimized.webp',
            height: baseSize * (isTablet(context) ? 0.2 : 0.2),
          ),
        ),
        Text(
          'CME Module Library',
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.05 : 0.05),
            fontWeight: FontWeight.w500,
            color: const Color.fromRGBO(0, 102, 179, 1),
          ),
          //textAlign: TextAlign.center,
        ),

        Flexible(
          flex: 3,
          child: Padding(
            padding: EdgeInsets.only(
              top: baseSize * (isTablet(context) ? 0.015 : 0.015),
              bottom: baseSize * (isTablet(context) ? 0.03 : 0.04),
              left: baseSize * (isTablet(context) ? 0.25 : 0.04),
              right: baseSize * (isTablet(context) ? 0.25 : 0.04),
            ),
            child: Container(
              height: baseSize * (isTablet(context) ? 0.35 : 0.5),
              decoration: BoxDecoration(
                color: Color(0xFFF9EBD9),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: Color(0xFF0070C0),
                  width: 2,
                ),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: baseSize * (isTablet(context) ? 0.01 : 0.02),
                    horizontal: baseSize * (isTablet(context) ? 0.02 : 0.03),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'News and Updates',
                        style: TextStyle(
                          fontSize: baseSize * (isTablet(context) ? 0.06 : 0.07),
                          fontWeight: FontWeight.w500,
                          color: Color.fromRGBO(84, 130, 53, 1),
                        ),
                      ),
                      SizedBox(
                        height: baseSize * (isTablet(context) ? 0.01 : 0.01),
                      ),
                      Container(
                        padding: EdgeInsets.all(baseSize * 0.02),
                        child: MarkdownBody(
                          data: alert.isNotEmpty ? alert : "No alerts available",
                          onTapLink: (text, url, title) async {
                            if (url != null) {
                              final Uri uri = Uri.parse(url);
                              if (uri.scheme == 'app' && uri.host == 'download') {
                                final moduleIdString = uri.queryParameters['id'];
                                final moduleId = int.tryParse(moduleIdString ?? '');
                                final moduleName = uri.queryParameters['name'];
                                final downloadLink = uri.queryParameters['link'];
                                final moduleDescription = uri.queryParameters['description'] ?? 'No Description available';

                                if (moduleName != null && downloadLink != null && moduleId != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ModuleInfo(
                                        moduleId: moduleId,
                                        moduleName: moduleName,
                                        downloadLink: downloadLink,
                                        moduleDescription: moduleDescription,
                                      ),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Invalid module data provided.')),
                                  );
                                }
                              } else if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else {
                                debugPrint('Could not launch $url');
                              }
                            }
                          },
                          styleSheet: MarkdownStyleSheet(
                            a: TextStyle(
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.blue, // Blue underline
                              fontWeight: FontWeight.bold,
                            ),
                            p: TextStyle(fontSize: baseSize * (isTablet(context) ? 0.035 : 0.04)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.02 : 0.015),
        ),
        Flexible(
          flex: 1,
          child: Semantics(
            label: 'Search Button',
            hint: 'Tap to search for modules',
            child: GestureDetector(
              onTap: () async {
                Navigator.push(
                    context, MaterialPageRoute(builder: (context) => Search()));
              },
              child: Hero(
                tag: 'modules',
                child: FractionallySizedBox(
                  widthFactor: isTablet(context) ? 0.2 : 0.2,
                  child: Container(
                    height: baseSize * (isTablet(context) ? 0.08 : 0.08),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0070C0),
                          Color(0xFF00C1FF),
                          Color(0xFF0070C0),
                        ], // Your gradient colors
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(
                              1, 3), // changes position of shadow
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                        builder: (context, constraints) {
                          double buttonWidth = constraints.maxWidth;
                          double fontSize = buttonWidth * 0.2;
                          double padding = buttonWidth * 0.02;
                          return Padding(
                            padding: EdgeInsets.all(padding),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.fitWidth,
                                    child: Text(
                                      "Modules",
                                      style: TextStyle(
                                        fontSize: fontSize,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: baseSize * (isTablet(context) ? .03 : 0.0)),
      ],
    );
  }
}
