import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CustomBottomNavBar extends StatelessWidget {
  final VoidCallback onHomeTap;
  final VoidCallback onLibraryTap;
  final VoidCallback onHelpTap;

  const CustomBottomNavBar({
    Key? key,
    required this.onHomeTap,
    required this.onLibraryTap,
    required this.onHelpTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      height: 70,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          GestureDetector(
            onTap: onHomeTap,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.home, size: 36, color: Colors.black),
                Text("Home", style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onLibraryTap,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.library_books, size: 36, color: Colors.black),
                Text("My Library", style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onHelpTap,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info, size: 36, color: Colors.black),
                Text("Help", style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}