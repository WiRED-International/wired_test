import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import 'functions.dart';

class CustomSideNavBar extends StatelessWidget {
  final VoidCallback onHomeTap;
  final VoidCallback onLibraryTap;
  final VoidCallback onTrackerTap;
  final VoidCallback onMenuTap;

  const CustomSideNavBar({
    Key? key,
    required this.onHomeTap,
    required this.onLibraryTap,
    required this.onTrackerTap,
    required this.onMenuTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    var baseSize = MediaQuery.of(context).size.shortestSide;

    return Container(
      width: screenWidth * 0.1, // Adjust the width of the side nav
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
      ), // You can change the background color if needed
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Home Button
          Semantics(
            label: 'Home button',
            button: true,
            onTapHint: "Tap to go to Home",
            child: GestureDetector(
              onTap: onHomeTap,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.04),
                child: Column(
                  children: [
                    Icon(
                      Icons.home,
                      size: baseSize * (isTablet(context) ? .07 : 0.09),
                      color: Colors.black,
                    ),
                    Text(
                      "Home",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: baseSize * (isTablet(context) ? .028 : 0.04),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Library Button
          Semantics(
            label: 'Library button',
            button: true,
            onTapHint: "Tap to go to Library",
            child: GestureDetector(
              onTap: onLibraryTap,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.04),
                child: Column(
                  children: [
                    Icon(
                      Icons.library_books,
                      size: baseSize * (isTablet(context) ? .07 : 0.09),
                      color: Colors.black,
                    ),
                    Text(
                      "Library",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: baseSize * (isTablet(context) ? .028 : 0.04),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Policy Button
          Semantics(
            label: 'CME Tracker button',
            button: true,
            onTapHint: "Tap to track your CME credits",
            child: GestureDetector(
              onTap: onTrackerTap,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.04),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/cme1.svg',
                      //width: baseSize * (isTablet(context) ? .07 : 0.1),
                      height: baseSize * (isTablet(context) ? .07 : 0.09),
                      color: Colors.black,
                    ),
                    Text(
                        "Tracker",
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: baseSize * (isTablet(context) ? .028 : 0.04),
                          fontWeight: FontWeight.w500,
                        )
                    ),
                  ],
                ),
              ),
            ),
          ),
          Semantics(
            label: 'Menu button',
            button: true,
            onTapHint: "Tap to go to Menu",
            child: GestureDetector(
              onTap: onMenuTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/icons/hamburger.svg',
                    //width: baseSize * (isTablet(context) ? .07 : 0.1),
                    height: baseSize * (isTablet(context) ? .07 : 0.09),
                    color: Colors.black,
                  ),
                  Text(
                      "Menu",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: baseSize * (isTablet(context) ? .028 : 0.04),
                        fontWeight: FontWeight.w500,
                      )
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}