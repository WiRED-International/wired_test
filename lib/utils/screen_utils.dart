import 'package:flutter/material.dart';

class ScreenUtils {
  static bool isTablet(BuildContext context) {
    final shortest = MediaQuery.of(context).size.shortestSide;
    return shortest >= 600;
  }

  static double scaleFont(BuildContext context, double base) {
    final size = MediaQuery.of(context).size;
    final shortest = size.shortestSide;
    final isTablet = shortest >= 600;
    final isLandscape = size.width > size.height;

    if (shortest < 360) return base * 0.80;

    if (!isTablet) {
      return isLandscape ? base * 1.05 : base * 0.97;
    }

    return isLandscape ? base * 1.35 : base * 1.20;
  }

  static double hPad(BuildContext context) {
    return MediaQuery.of(context).size.width * 0.04;
  }

  static double answerVerticalPadding(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final shortest = size.shortestSide;
    final isTablet = shortest >= 600;
    final isLandscape = size.width > size.height;

    if (isTablet) return isLandscape ? 22 : 18;
    return isLandscape ? 14 : 10;
  }

  static double answerHorizontalPadding(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final shortest = size.shortestSide;
    final isTablet = shortest >= 600;
    final isLandscape = size.width > size.height;

    if (isTablet) return isLandscape ? 28 : 20;
    return isLandscape ? 18 : 14;
  }
}