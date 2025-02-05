import 'package:flutter/material.dart';
import '../../utils/functions.dart';

class LandscapeProfileSection  extends StatelessWidget {
  final String firstName;
  final String dateJoined;

  LandscapeProfileSection({required this.firstName, required this.dateJoined});

  @override
  Widget build(BuildContext context) {
    double scalingFactor = getScalingFactor(context);
    final double circleDiameter = scalingFactor * (isTablet(context) ? 70 : 80);
    final double circleDiameterSmall = scalingFactor * (isTablet(context) ? 64 : 73);

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          // Allows the circle to extend outside the container
          children: [
            Container(
              // height: scalingFactor * (isTablet(context) ? 0.05 : 125),
              height: MediaQuery.of(context).size.height * (isTablet(context) ? 0.20 : 0.26),
              width: MediaQuery.of(context).size.width,
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
              //top: scalingFactor * (isTablet(context) ? 0.05 : 120) - (circleDiameter / 2),
              top: MediaQuery.of(context).size.height * (isTablet(context) ? 0.20 : 0.24) - (circleDiameter / 2),
              // Middle of the circle aligns with the bottom
              //left: scalingFactor * (isTablet(context) ? 0.05 : 60) - (circleDiameter / 2),
              left: MediaQuery.of(context).size.width * (isTablet(context) ? 0.11 : 0.12) - (circleDiameter / 2),
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
              //top: scalingFactor * (isTablet(context) ? 0.05 : 120) - circleDiameterSmall / 2,
              top: MediaQuery.of(context).size.height * (isTablet(context) ? 0.20 : 0.24) - circleDiameterSmall / 2,
              // Adjust position to place on top of first circle
              //left: scalingFactor * (isTablet(context) ? 0.05 : 60) - (circleDiameterSmall / 2),
              left: MediaQuery.of(context).size.width * (isTablet(context) ? 0.11 : 0.12) - (circleDiameterSmall / 2),
              // Smaller circle horizontally centered
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: circleDiameterSmall, // Smaller circle
                    height: circleDiameterSmall,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey, // Different color for the second circle
                    ),
                  ),
                  Icon(
                    Icons.person_2_sharp, // Flutter icon
                    size: scalingFactor * (isTablet(context) ? 57 : 65),
                    color: Colors.white,
                  ),
                ],
              ),
            ),
            // Text at the Bottom Center
            Positioned(
              bottom: scalingFactor * (isTablet(context) ? 3 : 3),
              // Position slightly above the bottom of the container
              left: 0,
              right: scalingFactor * (isTablet(context) ? 215 : 210),
              child: Text(
                "Hi, ${firstName ?? 'Guest'}",
                textAlign: TextAlign.center, // Center the text horizontally
                style: TextStyle(
                  fontSize: scalingFactor * (isTablet(context) ? 14 : 15),
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 5 : 6),
        ),
        Row(
          children: [
            SizedBox(
              width: scalingFactor * (isTablet(context) ? 105 : 113),
            ),
            Text(
              "Joined: ${formatDate(dateJoined)}",
              style: TextStyle(
                fontSize: scalingFactor * (isTablet(context) ? 11 : 11),
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
