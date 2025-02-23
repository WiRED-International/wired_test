import 'package:flutter/material.dart';
import '../../utils/functions.dart';

class ProfileSection  extends StatelessWidget {
  final String firstName;
  final String dateJoined;
  final int creditsEarned;

  ProfileSection({
    required this.firstName,
    required this.dateJoined,
    required this.creditsEarned,
  });

  @override
  Widget build(BuildContext context) {
    double scalingFactor = getScalingFactor(context);
    final double circleDiameter = scalingFactor * (isTablet(context) ? 70 : 110);
    final double circleDiameterSmall = scalingFactor * (isTablet(context) ? 64 : 100);

    String badgeImage = getBadgeImage(creditsEarned);

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          // Allows the circle to extend outside the container
          children: [
            Container(
              // height: scalingFactor * (isTablet(context) ? 0.05 : 125),
              height: MediaQuery.of(context).size.height * (isTablet(context) ? 0.13 : 0.15),
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
              top: MediaQuery.of(context).size.height * (isTablet(context) ? 0.13 : .15) - (circleDiameter / 2),
              // Middle of the circle aligns with the bottom
              //left: scalingFactor * (isTablet(context) ? 0.05 : 60) - (circleDiameter / 2),
              left: MediaQuery.of(context).size.width * (isTablet(context) ? 0.15 : .18) - (circleDiameter / 2),
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
              top: MediaQuery.of(context).size.height * (isTablet(context) ? 0.13 : 0.15) - circleDiameterSmall / 2,
              // Adjust position to place on top of first circle
              //left: scalingFactor * (isTablet(context) ? 0.05 : 60) - (circleDiameterSmall / 2),
              left: MediaQuery.of(context).size.width * (isTablet(context) ? 0.15 : 0.18) - (circleDiameterSmall / 2),
              // Smaller circle horizontally centered
              child: Container(
                width: circleDiameterSmall, // Smaller circle
                height: circleDiameterSmall,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey,
                  image: DecorationImage(
                    image: AssetImage(badgeImage),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            // Text at the Bottom Center
            Positioned(
              bottom: scalingFactor * (isTablet(context) ? 4 : 6),
              // Position slightly above the bottom of the container
              left: scalingFactor * (isTablet(context) ? 98 : 127),
              child: SizedBox(
                width: scalingFactor * (isTablet(context) ? 220 : 200),
                child: Text(
                  "Hi, $firstName",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: scalingFactor * (isTablet(context) ? 14 : 20),
                    color: Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 6 : 8),
        ),
        Row(
          children: [
            SizedBox(
              width: scalingFactor * (isTablet(context) ? 100 : 125),
            ),
            Text(
              "Joined: ${formatDate(dateJoined)}",
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: scalingFactor * (isTablet(context) ? 12 : 17),
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


