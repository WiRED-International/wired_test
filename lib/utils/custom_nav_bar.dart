import 'package:flutter/material.dart';
import 'package:wired_test/utils/functions.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CustomBottomNavBar extends StatelessWidget {
  final VoidCallback onHomeTap;
  final VoidCallback onLibraryTap;
  final VoidCallback onTrackerTap;
  final VoidCallback onMenuTap;

  const CustomBottomNavBar({
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
      color: Colors.transparent,
      height: baseSize * (isTablet(context) ? .17 : 0.19),
      //height: screenHeight * 0.1,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Semantics(
            label: 'Home button',
            button: true,
            onTapHint: "Tap to go to Home",
            child: GestureDetector(
              onTap: onHomeTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.home,
                    size: baseSize * (isTablet(context) ? .07 : 0.1),
                    color: Colors.black,
                  ),
                  Text(
                    "Home",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: baseSize * (isTablet(context) ? .028 : 0.044),
                      fontWeight: FontWeight.w500,
                    )
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            label: 'Library button',
            button: true,
            onTapHint: "Tap to go to Library",
            child: GestureDetector(
              onTap: onLibraryTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.library_books,
                    size: baseSize * (isTablet(context) ? .07 : 0.1),
                    color: Colors.black,
                  ),
                  Text(
                    "My Library",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: baseSize * (isTablet(context) ? .028 : 0.044),
                      fontWeight: FontWeight.w500,
                    )
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            label: 'CME Tracker button',
            button: true,
            onTapHint: "Tap to track your CME credits",
            child: GestureDetector(
              onTap: onTrackerTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon(
                  //   Icons.info,
                  //   size: baseSize * (isTablet(context) ? .07 : 0.1),
                  //   color: Colors.black
                  // ),
                  SvgPicture.asset(
                    'assets/icons/cme.svg',
                    //width: baseSize * (isTablet(context) ? .07 : 0.1),
                    height: baseSize * (isTablet(context) ? .07 : 0.1),
                    color: Colors.black,
                  ),
                  Text(
                    "Tracker",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: baseSize * (isTablet(context) ? .028 : 0.044),
                      fontWeight: FontWeight.w500,
                    )
                  ),
                ],
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
                  // Icon(
                  //   Icons.menu,
                  //   size: baseSize * (isTablet(context) ? .07 : 0.1),
                  //   color: Colors.black,
                  // ),
                  SvgPicture.asset(
                    'assets/icons/hamburger.svg',
                    //width: baseSize * (isTablet(context) ? .07 : 0.1),
                    height: baseSize * (isTablet(context) ? .07 : 0.1),
                    color: Colors.black,
                  ),
                  Text(
                    "Menu",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: baseSize * (isTablet(context) ? .028 : 0.044),
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