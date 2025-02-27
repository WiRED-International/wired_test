import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'functions.dart';

class CreditText extends StatefulWidget {
  final int creditsEarned;
  final int creditsRemaining;
  final double scalingFactor;
  final BuildContext context;

  CreditText({
    required this.creditsEarned,
    required this.creditsRemaining,
    required this.scalingFactor,
    required this.context,
  });

  @override
  _CreditTextState createState() => _CreditTextState();
}

class _CreditTextState extends State<CreditText> with WidgetsBindingObserver {
  String? lastRankShown;
  Orientation? lastOrientation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLastShownRank();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadLastShownRank() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    lastRankShown = prefs.getString('lastRankShown');
    print("Last rank loaded from storage: $lastRankShown");
    _checkForRankUp();
  }

  Future<void> _saveLastShownRank(String rank) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastRankShown', rank);
    print("Saved rank: $rank");
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    Orientation currentOrientation = MediaQuery.of(context).orientation;
    if (lastOrientation != currentOrientation) {
      lastOrientation = currentOrientation;
      _checkForRankUp(); // Recheck rank only if orientation changes
    }
  }

  void _checkForRankUp() {
    String? currentRank = _getCurrentRank(widget.creditsEarned);
    print("Current rank: $currentRank");

    if (currentRank != null && currentRank != lastRankShown) {
      lastRankShown = currentRank;
      _saveLastShownRank(currentRank); // Persist the new rank immediately
      _showRankUpAlert(currentRank);
    }
  }

  String? _getCurrentRank(int creditsEarned) {
    if (creditsEarned >= 200) {
      return "Supreme";
    } else if (creditsEarned >= 150) {
      return "Diamond";
    } else if (creditsEarned >= 110) {
      return "Platinum";
    } else if (creditsEarned >= 80) {
      return "Gold";
    } else if (creditsEarned >= 60) {
      return "Silver";
    } else if (creditsEarned >= 50) {
      return "Bronze";
    }
    return null;
  }

  void _showRankUpAlert(String rank) {
    String badgeImage = _getBadgeImage(rank);
    double scalingFactor = widget.scalingFactor;

    print("Showing alert for rank: $rank");

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          contentPadding: EdgeInsets.all(20),
          backgroundColor: Color(0xFF000000),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Badge Image
                Image.asset(
                  badgeImage,
                  height: scalingFactor * (isTablet(context) ? 50 : 100),
                  width: scalingFactor * (isTablet(context) ? 50 : 100),
                  fit: BoxFit.contain,
                ),
                SizedBox(height: 16),
                // Title
                Text(
                  "🎉 Congratulations!",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                // Rank Message
                Text(
                  "You've reached $rank rank! Keep up the great work!",
                  style:TextStyle(
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text("Exit"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

// Helper method to return the badge image path based on rank
  String _getBadgeImage(String rank) {
    switch (rank) {
      case "Supreme":
        return 'assets/images/circular_supreme_badge.webp';
      case "Diamond":
        return 'assets/images/circular_diamond_badge.webp';
      case "Platinum":
        return 'assets/images/circular_platinum_badge.webp';
      case "Gold":
        return 'assets/images/circular_gold_badge.webp';
      case "Silver":
        return 'assets/images/circular_silver_badge.webp';
      case "Bronze":
        return 'assets/images/circular_bronze_badge.webp';
      default:
        return 'assets/images/iron_badge_circular.webp';
    }
  }

  String getNextBadgeMessage(int creditsEarned, int creditsRemaining) {
    if (creditsEarned >= 200) {
      return "Congratulations! You've reached the highest rank: Supreme! You've earned \$creditsEarned credits! Keep going to get first place on the leaderboard.";
    } else if (creditsEarned >= 150) {
      return "Congratulations! You've earned \$creditsEarned credits. Complete \$creditsRemaining more credits to reach Supreme!";
    } else if (creditsEarned >= 110) {
      return "Great job! You've earned \$creditsEarned credits. Complete \$creditsRemaining more credits to reach Diamond!";
    } else if (creditsEarned >= 80) {
      return "Awesome! You've earned \$creditsEarned credits. Complete \$creditsRemaining more credits to reach Platinum!";
    } else if (creditsEarned >= 60) {
      return "Good progress! You've earned \$creditsEarned credits. Complete \$creditsRemaining more credits to reach Gold!";
    } else if (creditsEarned >= 50) {
      return "Congratulations! You've completed all of your CME credits for the year! You've earned \$creditsEarned credits. Complete \$creditsRemaining more credits to reach Silver!";
    } else {
      return "You have earned \$creditsEarned credits this year. You need \$creditsRemaining more credits before Dec. 31.";
    }
  }

  List<TextSpan> _buildHighlightedMessage(String message) {
    List<TextSpan> spans = [];
    int currentIndex = 0;

    while (currentIndex < message.length) {
      if (message.startsWith("\$creditsEarned", currentIndex)) {
        spans.add(TextSpan(
          text: "${widget.creditsEarned}",
          style: TextStyle(
            color: Color(0xFFBD34FD),
            fontSize: widget.scalingFactor * (isTablet(context) ? 15 : 20),
          ),
        ));
        currentIndex += "\$creditsEarned".length;
      } else if (message.startsWith("\$creditsRemaining", currentIndex)) {
        spans.add(TextSpan(
          text: "${widget.creditsRemaining}",
          style: TextStyle(
            color: Color(0xFFBD34FD),
            fontSize: widget.scalingFactor * (isTablet(context) ? 15 : 20),
          ),
        ));
        currentIndex += "\$creditsRemaining".length;
      } else {
        spans.add(TextSpan(
          text: message[currentIndex],
          style: TextStyle(
            fontSize: widget.scalingFactor * (isTablet(context) ? 15 : 20),
            color: Colors.black,
            fontWeight: FontWeight.w400,
          ),
        ));
        currentIndex++;
      }
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    String message = getNextBadgeMessage(widget.creditsEarned, widget.creditsRemaining);
    return RichText(
      textAlign: TextAlign.left,
      text: TextSpan(
        children: _buildHighlightedMessage(message),
      ),
    );
  }
}
