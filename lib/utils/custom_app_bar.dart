import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    double appBarHeight = screenHeight * 0.055;

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
                    height: screenHeight * 0.027,
                    width: screenHeight * 0.027,
                  ),
                ),
                SizedBox(width: screenWidth * 0.0),
                Text(
                  "Back",
                  style: TextStyle(
                    fontSize: screenWidth * 0.054,
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