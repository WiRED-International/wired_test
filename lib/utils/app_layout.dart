import 'package:flutter/material.dart';

class AppLayout extends StatelessWidget {
  final Widget child;
  final Widget? appBar;
  final Widget? bottomNav;

  const AppLayout({
    Key? key,
    required this.child,
    this.appBar,
    this.bottomNav,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
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
              ),
            ),
          ),
          // CONTENT ONLY inside SafeArea
          SafeArea(
            child: Column(
              children: [
                if (appBar != null) appBar!,

                Expanded(child: child),

                if (bottomNav != null) bottomNav!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}