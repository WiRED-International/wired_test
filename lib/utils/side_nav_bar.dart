import 'package:flutter/material.dart';
import 'package:wired_test/utils/functions.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CustomSideNavBar extends StatelessWidget {
  final VoidCallback onHomeTap;
  final VoidCallback onLibraryTap;
  final VoidCallback onHelpTap;

  const CustomSideNavBar({
    Key? key,
    required this.onHomeTap,
    required this.onLibraryTap,
    required this.onHelpTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;

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
        mainAxisAlignment: MainAxisAlignment.center, // Align items at the start of the column
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
                      size: screenHeight * 0.06, // Adjust icon size based on height
                      color: Colors.black,
                    ),
                    Text(
                      "Home",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: screenHeight * 0.025, // Adjust text size based on height
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
                      size: screenHeight * 0.06,
                      color: Colors.black,
                    ),
                    Text(
                      "My Library",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: screenHeight * 0.025,
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
            label: 'Policy button',
            button: true,
            onTapHint: "Tap to view policy",
            child: GestureDetector(
              onTap: onHelpTap,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.04),
                child: Column(
                  children: [
                    Icon(
                      Icons.info,
                      size: screenHeight * 0.06,
                      color: Colors.black,
                    ),
                    Text(
                      "Policy",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: screenHeight * 0.025,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}