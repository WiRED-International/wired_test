import 'package:flutter/material.dart';
import '../../utils/functions.dart';

class ProfileSection  extends StatelessWidget {
  final String firstName;
  final String dateJoined;

  ProfileSection({required this.firstName, required this.dateJoined});

  @override
  Widget build(BuildContext context) {
    var baseSize = MediaQuery
        .of(context)
        .size
        .shortestSide;
    final double circleDiameter = 130.0;
    final double circleDiameterSmall = 115.0;

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          // Allows the circle to extend outside the container
          children: [
            Container(
              height: baseSize * (isTablet(context) ? 0.05 : 0.35),
              width: MediaQuery
                  .of(context)
                  .size
                  .width,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF2853FF),
                    Color(0xFFC3C6FB),
                  ],
                ),
              ),
            ),
            Positioned(
              top: baseSize * (isTablet(context) ? 0.05 : 0.35) -
                  (circleDiameter / 2),
              // Middle of the circle aligns with the bottom
              left: baseSize * (isTablet(context) ? 0.05 : 0.18) -
                  (circleDiameter / 2),
              // Horizontally centered
              child: Container(
                width: circleDiameter, // Diameter of the circle
                height: circleDiameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFCEEDB),
                ),
              ),
            ),
            // Second Circle
            Positioned(
              top: baseSize * (isTablet(context) ? 0.05 : 0.35) -
                  circleDiameterSmall / 2,
              // Adjust position to place on top of first circle
              left: baseSize * (isTablet(context) ? 0.05 : 0.18) -
                  (circleDiameterSmall / 2),
              // Smaller circle horizontally centered
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: circleDiameterSmall, // Smaller circle
                    height: circleDiameterSmall,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors
                          .grey, // Different color for the second circle
                    ),
                  ),
                  Icon(
                    Icons.person_2_sharp, // Flutter icon
                    size: baseSize * (isTablet(context) ? .07 : 0.25),
                    // Scale the icon size
                    color: Colors.white,
                  ),
                ],
              ),
            ),
            // Text at the Bottom Center
            Positioned(
              bottom: 10.0,
              // Position slightly above the bottom of the container
              left: 0,
              right: baseSize * (isTablet(context) ? 0.07 : 0.06),
              child: Text(
                "Hi, ${firstName ?? 'Guest'}",
                textAlign: TextAlign.center, // Center the text horizontally
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.07 : 0.06),
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.02 : 0.02),
        ),
        Row(
          children: [
            SizedBox(
              width: baseSize * (isTablet(context) ? 0.05 : 0.35),
            ),
            Text(
              "Joined: ${dateJoined != null
                  ? formatDate(dateJoined!)
                  : 'Unknown'}",
              style: TextStyle(
                fontSize: baseSize * (isTablet(context) ? 0.07 : 0.045),
                fontWeight: FontWeight.w400,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ],
    );
  }
}


