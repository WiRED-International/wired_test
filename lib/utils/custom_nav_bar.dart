import 'package:flutter/material.dart';
import 'package:wired_test/utils/functions.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CustomBottomNavBar extends StatelessWidget {
  final VoidCallback onHomeTap;
  final VoidCallback onLibraryTap;
  final VoidCallback onTrackerTap;
  final VoidCallback onMenuTap;
  final double? scale;

  const CustomBottomNavBar({
    Key? key,
    required this.onHomeTap,
    required this.onLibraryTap,
    required this.onTrackerTap,
    required this.onMenuTap,
    this.scale,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final baseSize = MediaQuery
        .of(context)
        .size
        .shortestSide;
    final isTabletDevice = isTablet(context);
    final effectiveScale = scale ?? (isTabletDevice ? 1.0 : 1.0);

    final double barHeight = baseSize * 0.2 * effectiveScale;
    final double iconSize = baseSize * 0.08 * effectiveScale;
    final double fontSize = baseSize * 0.04 * effectiveScale;

    return Container(
      color: Colors.transparent,
      height: barHeight,
      padding: EdgeInsets.symmetric(vertical: baseSize * 0.01 * effectiveScale),
      //height: screenHeight * 0.1,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // =====================
          // 🔹 HOME BUTTON
          // =====================
          _buildIconNavItem(
            context,
            label: "Home",
            icon: Icons.home,
            onTap: onHomeTap,
            iconSize: iconSize,
            fontSize: fontSize,
          ),

          // =====================
          // 🔹 LIBRARY BUTTON
          // =====================
          _buildIconNavItem(
            context,
            label: "My Library",
            icon: Icons.library_books,
            onTap: onLibraryTap,
            iconSize: iconSize,
            fontSize: fontSize,
          ),

          // =====================
          // 🔹 TRACKER BUTTON (SVG)
          // =====================
          _buildSvgNavItem(
            context,
            label: "Tracker",
            svgPath: 'assets/icons/credits.svg',
            onTap: onTrackerTap,
            iconSize: iconSize,
            fontSize: fontSize,
          ),

          // =====================
          // 🔹 MENU BUTTON (SVG)
          // =====================
          _buildSvgNavItem(
            context,
            label: "Menu",
            svgPath: 'assets/icons/hamburger.svg',
            onTap: onMenuTap,
            iconSize: iconSize,
            fontSize: fontSize,
          ),
        ],
      ),
    );
  }

  // =====================
  // 🔹 Helper for Icon Buttons
  // =====================
  Widget _buildIconNavItem(BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required double iconSize,
    required double fontSize,
  }) {
    return Semantics(
      label: '$label button',
      button: true,
      onTapHint: "Tap to go to $label",
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: Colors.black),
            SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                color: Colors.black,
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================
  // 🔹 Helper for SVG Buttons
  // =====================
  Widget _buildSvgNavItem(BuildContext context, {
    required String label,
    required String svgPath,
    required VoidCallback onTap,
    required double iconSize,
    required double fontSize,
  }) {
    // Detect if this is the colored Credits icon
    final bool isCreditsIcon = svgPath.contains('credits');

    return Semantics(
      label: '$label button',
      button: true,
      onTapHint: "Tap to go to $label",
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              svgPath,
              height: iconSize,
              // 🟢 Only apply color override if NOT the Credits icon
              color: isCreditsIcon ? null : Colors.black,
            ),
            SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                color: Colors.black,
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}