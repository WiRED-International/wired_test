import 'package:flutter/material.dart';

class CustomAnimatedButton extends StatefulWidget {
  final String label;
  final List<Color> gradientColors;
  final VoidCallback onTap;
  final double scalingFactor;
  final bool isTablet;
  final bool isLandscape;

  const CustomAnimatedButton({
    Key? key,
    required this.label,
    required this.gradientColors,
    required this.onTap,
    required this.scalingFactor,
    this.isTablet = false,
    this.isLandscape = false,
  }) : super(key: key);

  @override
  State<CustomAnimatedButton> createState() => _CustomAnimatedButtonState();
}

class _CustomAnimatedButtonState extends State<CustomAnimatedButton> {
  double _scale = 1.0;
  late List<Color> _currentColors;

  @override
  void initState() {
    super.initState();
    _currentColors = widget.gradientColors;
  }

  void _onTapDown() {
    setState(() {
      _scale = 0.95;
      _currentColors = widget.gradientColors
          .map((c) => c.withOpacity(0.8))
          .toList();
    });
  }

  void _onTapUp(VoidCallback onTap) {
    setState(() {
      _scale = 1.0;
      _currentColors = widget.gradientColors;
    });
    onTap();
  }

  void _onTapCancel() {
    setState(() {
      _scale = 1.0;
      _currentColors = widget.gradientColors;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double widthFactor = widget.isLandscape
        ? (widget.isTablet ? 0.3 : 0.4)
        : (widget.isTablet ? 0.38 : 0.5);

    final double height = widget.scalingFactor *
        (widget.isLandscape
            ? (widget.isTablet ? 30 : 35)
            : (widget.isTablet ? 32 : 38));

    final double borderRadius = widget.isLandscape ? 25 : 30;

    return Semantics(
      label: '${widget.label} Button',
      hint: 'Tap to access ${widget.label}',
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(borderRadius),
          child: GestureDetector(
            onTapDown: (_) => _onTapDown(),
            onTapUp: (_) => _onTapUp(widget.onTap),
            onTapCancel: _onTapCancel,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              transform: Matrix4.diagonal3Values(_scale, _scale, 1.0),
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(borderRadius),
                splashColor: Colors.white.withOpacity(0.3),
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _currentColors,
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(borderRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: const Offset(1, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: widget.scalingFactor *
                            (widget.isTablet ? 14 : 18),
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}



// import 'package:flutter/material.dart';
//
// import 'functions.dart';
//
// class CustomButton extends StatefulWidget {
//   final VoidCallback onTap;
//   final List<Color> gradientColors;
//   final String text;
//   final double? width;
//
//   const CustomButton({
//     Key? key,
//     required this.onTap,
//     required this.gradientColors,
//     required this.text,
//     this.width, // Optional width parameter
//   }) : super(key: key);
//
//   @override
//   _CustomButtonState createState() => _CustomButtonState();
// }
//
// class _CustomButtonState extends State<CustomButton> {
//   bool isTapped = false;
//
//
//   @override
//   Widget build(BuildContext context) {
//     var screenHeight = MediaQuery.of(context).size.height;
//     var baseSize = MediaQuery.of(context).size.shortestSide;
//     return GestureDetector(
//       onTap: () async {
//         setState(() {
//           isTapped = true;
//         });
//         widget.onTap(); // Execute the passed onTap function
//         // Reset the button color after the action is complete
//         setState(() {
//           isTapped = false;
//         });
//       },
//       child: LayoutBuilder(
//         builder: (context, constraints) {
//           double buttonWidth = widget.width ?? constraints.maxWidth;
//           double fontSize = buttonWidth * 0.13;
//           double padding = buttonWidth * 0.03;
//           return Container(
//             height: baseSize * (isTablet(context) ? 0.08 : 0.13),
//             width: buttonWidth, // Use provided width or fallback to a default
//             decoration: BoxDecoration(
//               gradient: LinearGradient(
//                 colors: isTapped
//                     ? widget.gradientColors.map((color) => color.withOpacity(0.7)).toList()
//                     : widget.gradientColors,
//                 begin: Alignment.topCenter,
//                 end: Alignment.bottomCenter,
//               ),
//               borderRadius: BorderRadius.circular(30),
//               boxShadow: [
//                 BoxShadow(
//                   color: Colors.black.withOpacity(0.5),
//                   spreadRadius: 1,
//                   blurRadius: 5,
//                   offset: const Offset(1, 3), // changes position of shadow
//                 ),
//               ],
//             ),
//             child: Padding(
//               padding: EdgeInsets.all(padding),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   Text(
//                     widget.text,
//                     style: TextStyle(
//                       fontSize: fontSize,
//                       fontWeight: FontWeight.w500,
//                       color: Colors.white,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           );
//         }
//       ),
//     );
//   }
// }


