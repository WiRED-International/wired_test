import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/utils/functions.dart';
import '../providers/auth_provider.dart';

class CustomAppBar extends StatelessWidget {
  final VoidCallback onBackPressed;
  final bool requireAuth; // Defaults to true to check authentication for all pages
  final double? scale;

  const CustomAppBar({
    Key? key,
    required this.onBackPressed,
    this.requireAuth = true, // Enable authentication check by default
    this.scale,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    var baseSize = MediaQuery.of(context).size.shortestSide;
    final isTabletDevice = isTablet(context);
    final effectiveScale = scale ?? (isTabletDevice ? 1.0 : 1.0);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.005 * effectiveScale,
        vertical: screenHeight * 0.002 * effectiveScale,
      ),
      color: Colors.transparent,
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              // Handle navigation logic based on authentication requirement
              if (requireAuth) {
                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                if (authProvider.isLoggedIn) {
                  // User is authenticated, navigate back
                  onBackPressed();
                } else {
                  // Redirect to login page for unauthenticated users
                  Navigator.pushNamed(context, '/login'); // Adjust to your login route
                }
              } else {
                // No authentication required, proceed with navigation
                onBackPressed();
              }
            },
            child: Row(
              children: [
                Semantics(
                  label: 'Back button',
                  button: true,
                  onTapHint: "Tap to go back to the previous page",
                  child: SvgPicture.asset(
                    'assets/icons/chevron_left.svg',
                    height: baseSize * 0.05 * effectiveScale,
                    width: baseSize * 0.05 * effectiveScale,
                  ),
                ),
                SizedBox(width: baseSize * 0.00 * effectiveScale),
                Text(
                  "Back",
                  style: TextStyle(
                    fontSize: baseSize * 0.05 * effectiveScale,
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