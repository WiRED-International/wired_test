import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
// import 'package:flutter/rendering.dart';

import '../pages/search.dart';
import '../utils/button.dart';
import '../utils/custom_nav_bar.dart';
import 'module_library.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, this.title});
  final String? title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;

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
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 0, bottom: 15),
                      child: Image.asset(
                          'assets/images/wired-logo.png',
                          //height: 88,
                          height: screenHeight * 0.095,
                      ),
                    ),
                    Text(
                      'CME Module Library',
                      style: TextStyle(
                        fontSize: screenWidth * 0.09,
                        fontWeight: FontWeight.w500,
                        color: Color.fromRGBO(0, 102, 179, 1),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'News and Updates',
                      style: TextStyle(
                        fontSize: screenWidth * 0.08,
                        fontWeight: FontWeight.w500,
                        color: Color.fromRGBO(84, 130, 53, 1),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Container(
                        //height: 470,
                        height: screenHeight * 0.45,
                        decoration: BoxDecoration(
                          color: Color(0xFFF9EBD9),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: Color(0xFF0070C0),
                            width: 2,
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(15.0),
                          child: Text(
                            'Alerts, Notifications, and Messages',
                            style: TextStyle(
                              fontSize: screenWidth * 0.06,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // SizedBox(
                    //   //height: 20,
                    //   height: screenHeight * 0.02,
                    // ),
                    Spacer(),
                    GestureDetector(
                      onTap: () async {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => Search()));
                      },
                      child: Hero(
                        tag: 'search',
                        child: FractionallySizedBox(
                          widthFactor: 0.4,
                          child: Container(
                            // height: 60,
                            // width: 195,
                            height: screenHeight * 0.06,
                            //alignment: Alignment.center,
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
                                  color: Colors.black.withOpacity(
                                      0.5),
                                  spreadRadius: 1,
                                  blurRadius: 5,
                                  offset: const Offset(1,
                                      3), // changes position of shadow
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(5.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.fitWidth,
                                      child: const Text(
                                        "Search",
                                        style: TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10,),
                                  SvgPicture.asset(
                                    'assets/icons/search.svg',
                                    // height: 42,
                                    // width: 42,
                                    height: screenHeight * 0.04,
                                    width: screenHeight * 0.04,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.115)
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
                print("Home");
                //Navigator.push(context, MaterialPageRoute(builder: (context) => DownloadConfirm(moduleName: moduleName)));
              },
              onLibraryTap: () {
                print("My Library");
                Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleLibrary()));
              },
              onHelpTap: () {
                print("Help");
                //Navigator.push(context, MaterialPageRoute(builder: (context) => Help()));
              },
            ),
          ),
        ],
      ),
    );
  }
}