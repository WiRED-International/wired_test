import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'functions.dart';

class CustomSideNavBar extends StatelessWidget {
  final VoidCallback onHomeTap;
  final VoidCallback onLibraryTap;
  final VoidCallback onTrackerTap;
  final VoidCallback onMenuTap;
  final double? scale;

  const CustomSideNavBar({
    Key? key,
    required this.onHomeTap,
    required this.onLibraryTap,
    required this.onTrackerTap,
    required this.onMenuTap,
    this.scale,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    var baseSize = MediaQuery.of(context).size.shortestSide;
    final isTabletDevice = isTablet(context);
    final effectiveScale = scale ?? (isTabletDevice ? 1.0 : 1.0);

    double iconSize = baseSize * 0.08 * effectiveScale;
    double fontSize = baseSize * 0.03 * effectiveScale;
    double verticalPadding = screenHeight * 0.04 * effectiveScale;

    return Container(
      width: screenWidth * (isTabletDevice ? 0.08 : 0.08), // Adjust the width of the side nav
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ), // You can change the background color if needed
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // =====================
            // 🔹 HOME BUTTON
            // =====================
            _buildNavItem(
              context,
              label: "Home",
              icon: Icons.home,
              onTap: onHomeTap,
              iconSize: iconSize,
              fontSize: fontSize,
              verticalPadding: verticalPadding,
            ),

            // =====================
            // 🔹 LIBRARY BUTTON
            // =====================
            _buildNavItem(
              context,
              label: "Library",
              icon: Icons.library_books,
              onTap: onLibraryTap,
              iconSize: iconSize,
              fontSize: fontSize,
              verticalPadding: verticalPadding,
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
              verticalPadding: verticalPadding,
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
              verticalPadding: verticalPadding,
            ),
          ],
        ),
      ),
    );
  }

  // =====================
  // 🔹 Helper for Icon Buttons
  // =====================
  Widget _buildNavItem(
      BuildContext context, {
        required String label,
        required IconData icon,
        required VoidCallback onTap,
        required double iconSize,
        required double fontSize,
        required double verticalPadding,
      }) {
    return Semantics(
      label: '$label button',
      button: true,
      onTapHint: "Tap to go to $label",
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          child: Column(
            children: [
              Icon(icon, size: iconSize, color: Colors.black),
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
      ),
    );
  }

  // =====================
  // 🔹 Helper for SVG Buttons
  // =====================
  Widget _buildSvgNavItem(
      BuildContext context, {
        required String label,
        required String svgPath,
        required VoidCallback onTap,
        required double iconSize,
        required double fontSize,
        required double verticalPadding,
      }) {
    final bool isCreditsIcon = svgPath.contains('credits');

    return Semantics(
      label: '$label button',
      button: true,
      onTapHint: "Tap to go to $label",
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          child: Column(
            children: [
              SvgPicture.asset(
                svgPath,
                height: iconSize,
                color: isCreditsIcon ? null : Colors.black,
              ),
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
      ),
    );
  }
}
