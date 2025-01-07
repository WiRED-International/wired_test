import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:wired_test/utils/functions.dart';
import '../pages/search.dart';
import '../utils/custom_nav_bar.dart';
import 'cme/cme_info.dart';
import 'menu.dart';
import 'module_library.dart';
import 'policy.dart';
import 'package:wired_test/utils/side_nav_bar.dart';
import 'package:http/http.dart' as http;

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, this.title});
  final String? title;

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
    const remoteServer = 'http://widm.wiredhealthresources.net/apiv2/alerts/latest';
    const localServer = 'http://10.0.2.2:3000/alerts/latest';
    try {
      final response = await http.get(Uri.parse(remoteServer));

      debugPrint("Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check what data is being decoded
        debugPrint("Fetched Data: $data");

        // Parse the single Alert object
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
  }

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    var baseSize = MediaQuery.of(context).size.shortestSide;
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: Row(
        children: [
          // Conditionally show the side navigation bar in landscape mode
          if (isLandscape)
            CustomSideNavBar(
              onHomeTap: () {
                // Navigator.push(context,
                //     MaterialPageRoute(builder: (context) => MyHomePage()));
              },
              onLibraryTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => ModuleLibrary()));
              },
              onHelpTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => const Policy()));
              },
            ),

          // Main content area (expanded to fill remaining space)
          Expanded(
            child: Stack(
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
                      child: isLandscape
                          ? _buildLandscapeLayout(screenWidth, screenHeight, baseSize)
                          : _buildPortraitLayout(screenWidth, screenHeight, baseSize),
                    ),
                  ),
                ),
                // Conditionally show the bottom navigation bar in portrait mode
                if (!isLandscape)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: CustomBottomNavBar(
                      onHomeTap: () {
                        // Navigator.push(context, MaterialPageRoute(builder: (context) => DownloadConfirm(moduleName: moduleName)));
                      },
                      onLibraryTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (
                            context) => ModuleLibrary()));
                      },
                      onTrackerTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (
                            context) => CmeInfo()));
                      },
                      onMenuTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (
                            context) => Menu()));
                      },
                    ),
                  ),
              ],
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
            'assets/images/wired-logo.png',
            height: baseSize * (isTablet(context) ? 0.3 : 0.3),
          ),
        ),
        Text(
          'CME Module Library',
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.07 : 0.08),
            fontWeight: FontWeight.w500,
            color: const Color.fromRGBO(0, 102, 179, 1),
          ),
        ),
        Text(
          'News and Updates',
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.06 : 0.07),
            fontWeight: FontWeight.w500,
            color: Color.fromRGBO(84, 130, 53, 1),
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
                    vertical: baseSize * (isTablet(context) ? 0.02 : 0.02),
                    horizontal: baseSize * (isTablet(context) ? 0.03 : 0.03),
                  ),
                  child: Text(
                    alert.isNotEmpty ? alert : 'Welcome to WiRED\'s new mobile HealthMap app. Feel free to browse the modules and find topics that interest you. All of WiRED\'s modules are free, evidence-based, peer-reviewed, and written by licensed healthcare professionals. We hope you find them useful!',
                    style: TextStyle(
                      fontSize: baseSize * (isTablet(context) ? 0.035 : 0.04),
                      fontWeight: FontWeight.w500,
                      color: isImportant ? Colors.red : Colors.black,
                    ),
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
                          color: Colors.black.withOpacity(0.5),
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
        Padding(
          padding: EdgeInsets.only(top: screenHeight * 0.02),
          child: Semantics(
            label: 'Wired Logo',
            child: Image.asset(
              'assets/images/wired-logo.png',
              height: baseSize * (isTablet(context) ? 0.2 : 0.2),
            ),
          ),
        ),
        Text(
          'CME Module Library',
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.05 : 0.05),
            fontWeight: FontWeight.w500,
            color: const Color.fromRGBO(0, 102, 179, 1),
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          'News and Updates',
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.05 : 0.05),
            fontWeight: FontWeight.w500,
            color: Color.fromRGBO(84, 130, 53, 1),
          ),
          textAlign: TextAlign.center,
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
              // height: baseSize * (isTablet(context) ? 0.35 : 0.5),
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
                  child: Text(
                    alert.isNotEmpty ? alert : 'Hello Testers! Welcome to WiRED\'s new mobile HealthMap app. Thank you for choosing to participate in this closed test. This does mean a lot to all of us here at WiRED. We ask that you please do not click on any button or link that says "Leave the test." We need all testers to remain opted in for 14 consecutive days. After the 14 days, you may leave the test if you wish. Once again, thank you so much for your participation in this test.',
                    style: TextStyle(
                      fontSize: baseSize * (isTablet(context) ? 0.032 : 0.032),
                      fontWeight: FontWeight.w500,
                      color: isImportant ? Colors.red : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ),
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
                tag: 'search',
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
                          color: Colors.black.withOpacity(0.5),
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
                          double iconSize = buttonWidth * 0.15;
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
