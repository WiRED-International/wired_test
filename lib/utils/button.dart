import 'package:flutter/material.dart';

class CustomButton extends StatefulWidget {
  final VoidCallback onTap;
  final List<Color> gradientColors;
  final String text;
  final double? width;

  const CustomButton({
    Key? key,
    required this.onTap,
    required this.gradientColors,
    required this.text,
    this.width, // Optional width parameter
  }) : super(key: key);

  @override
  _CustomButtonState createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool isTapped = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        setState(() {
          isTapped = true;
        });
        widget.onTap(); // Execute the passed onTap function
        // Reset the button color after the action is complete
        setState(() {
          isTapped = false;
        });
      },
      child: Container(
        height: 60,
        width: widget.width ?? MediaQuery.of(context).size.width / 2.5, // Use provided width or fallback to a default
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isTapped
                ? widget.gradientColors.map((color) => color.withOpacity(0.7)).toList()
                : widget.gradientColors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(1, 3), // changes position of shadow
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  widget.text,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


