import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wired_test/utils/functions.dart';

class CustomAppBar extends StatelessWidget {
  final VoidCallback onBackPressed;

  const CustomAppBar({
    Key? key,

    required this.onBackPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    var baseSize = MediaQuery.of(context).size.shortestSide;

    return Container(
      //height: appBarHeight,
      padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.005,
          vertical: screenHeight * 0.002,
      ),
      color: Colors.transparent,
      child: Row(
        children: [
          GestureDetector(
            onTap: onBackPressed,
            child: Row(
              children: [
                Semantics(
                  label: 'Back button',
                  button: true,
                  onTapHint: "Tap to go back to the previous page",
                  child: SvgPicture.asset(
                    'assets/icons/chevron_left.svg',
                    height: baseSize * (isTablet(context) ? 0.045 : 0.05),  // Use baseSize for consistency
                    width: baseSize * (isTablet(context) ? 0.045 : 0.05),
                  ),
                ),
                SizedBox(width: screenWidth * 0.0),
                Text(
                  "Back",
                  style: TextStyle(
                    fontSize: baseSize * (isTablet(context) ? 0.045 : 0.06),
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}