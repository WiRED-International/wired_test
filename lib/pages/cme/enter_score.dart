import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:wired_test/pages/cme/cme_tracker.dart';
import '../../providers/auth_guard.dart';
import '../../providers/auth_provider.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';

class EnterScore extends StatefulWidget {

  const EnterScore({
    super.key,
    this.moduleId,
    this.moduleName
  });

  final String? moduleId;
  final String? moduleName;

  @override
  _EnterScoreState createState() => _EnterScoreState();
}

class _EnterScoreState extends State<EnterScore> {
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  List<TextEditingController> _controllers = List.generate(5, (index) => TextEditingController());
  double? _storedScore;

  @override
  void initState() {
    super.initState();
    _loadStoredScore();
  }

  /// Load stored score from Secure Storage and auto-fill if it matches the module_id
  Future<void> _loadStoredScore() async {
    String? storedScoresJson = await secureStorage.read(key: "quiz_scores");

    if (storedScoresJson != null) {
      try {
        print("📌 Raw Stored Scores Data: $storedScoresJson");

        // Convert stored string back into a Map
        Map<String, dynamic> scoreMap = jsonDecode(storedScoresJson);
        print("📌 Parsed Score Data: $scoreMap");

        // Ensure the map contains an entry for the current module ID
        if (widget.moduleId != null) {
          String normalizedModuleId = widget.moduleId!.trim();
          print("🔍 Normalized Module ID: $normalizedModuleId");

          if (scoreMap.containsKey(normalizedModuleId)) {
            double storedScore = scoreMap[normalizedModuleId];
            print("🆔 Stored Module ID: $normalizedModuleId, Score: $storedScore");
            setState(() {
              _storedScore = storedScore;
            });
            _autoFillScore(storedScore);
          } else {
            print("⚠️ No score found for normalized module_id: $normalizedModuleId");
          }
        }
      } catch (e) {
        print("❌ Error parsing stored scores data: $e");
      }
    } else {
      print("ℹ️ No stored scores found.");
    }
  }


  /// Auto-fill score into the text fields
  void _autoFillScore(double score) {
    String scoreString = score.toStringAsFixed(2); // Ensure two decimal places
    List<String> scoreParts = scoreString.split(".");
    List<String> integerPart = scoreParts[0].padLeft(3, "0").split("");
    List<String> decimalPart = scoreParts[1].padRight(2, "0").split("");
    List<String> fullScore = [...integerPart, ...decimalPart];

    for (int i = 0; i < _controllers.length; i++) {
      _controllers[i].text = fullScore[i];
    }
  }

  Future<void> _updateStoredScore(String moduleId, double score) async {
    try {
      // Retrieve existing stored scores
      String? storedScoresJson = await secureStorage.read(key: "quiz_scores");
      Map<String, dynamic> storedScores = storedScoresJson != null ? jsonDecode(storedScoresJson) : {};

      // Update the score for the module
      storedScores[moduleId] = score;

      // Save updated scores back to Secure Storage
      await secureStorage.write(key: "quiz_scores", value: jsonEncode(storedScores));

      print("✅ Successfully updated score: Module ID: $moduleId, Score: $score");
    } catch (e) {
      print("❌ Error updating quiz score: $e");
    }
  }

  Future<void> _handleSubmit(BuildContext context) async {
    if (_storedScore == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No score available to submit.')),
      );
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.authToken;
    final userId = authProvider.getUserIdFromToken();

    if (token == null || userId == null) {
      print('Token or user_id is missing');
      return;
    }

    try {
      final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

      final apiEndpoint = '/quiz-scores';

      final response = await http.post(
        Uri.parse("$apiBaseUrl$apiEndpoint"),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'module_id': widget.moduleId.toString().substring(widget.moduleId.toString().length - 4),
          'user_id': userId,
          'score': _storedScore,
          'date_taken': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        await _updateStoredScore(widget.moduleId.toString(), _storedScore!);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Success'),
              content: Text('Your score has been submitted successfully!'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => CMETracker()),
                    );
                  },
                  child: Text('OK'),
                ),
              ],
            );
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit score. Please try again.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred. Please try again.')),
      );
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    double scalingFactor = getScalingFactor(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            Container(
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
            Column(
              children: [
                CustomAppBar(
                  onBackPressed: () {
                    Navigator.pop(context);
                  },
                  requireAuth: true,
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (isLandscape)
                        CustomSideNavBar(
                          onHomeTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => ModuleLibrary()
                              ),
                            );
                          },
                          onTrackerTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AuthGuard(child: CMETracker()),
                              ),
                            );
                          },
                          onMenuTap: () async {
                            bool isLoggedIn = await checkIfUserIsLoggedIn();
                            print("Navigating to menu. Logged in: $isLoggedIn");
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                              ),
                            );
                          },
                        ),
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(scalingFactor,)
                              : _buildPortraitLayout(scalingFactor,),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLandscape)
                  CustomBottomNavBar(
                    onHomeTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const MyHomePage()),
                      );
                    },
                    onLibraryTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => ModuleLibrary()),
                      );
                    },
                    onTrackerTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AuthGuard(
                                child: CMETracker(),
                              ),
                        ),
                      );
                    },
                    onMenuTap: () async {
                      bool isLoggedIn = await checkIfUserIsLoggedIn();
                      print("Navigating to menu. Logged in: $isLoggedIn");
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                        ),
                      );
                    },
                  ),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              child: CustomAppBar(
                onBackPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(scalingFactor) {
    return SingleChildScrollView(
      child : Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: scalingFactor * (isTablet(context) ? 20 : 20)),
            child: Text(
              "Submit CME Credits",
              style: TextStyle(
                fontSize: scalingFactor * (isTablet(context) ? 24 : 32),
                fontWeight: FontWeight.w500,
                color: Color(0xFF646BFF),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          //SizedBox(height: scalingFactor * (isTablet(context) ? 0.038 : 180)),

          // Box Container
          Padding(
            padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 5 : 25)),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(scalingFactor * (isTablet(context) ? 5 : 5)),
              decoration: BoxDecoration(
                color: Color(0xFFFFF5E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Color(0xFF9DA2FF),
                  width: scalingFactor * (isTablet(context) ? 1.5 : 2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 5,
                    offset: Offset(2, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Module Name
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          "Module Name: ",
                          style: TextStyle(
                            fontSize: scalingFactor * (isTablet(context) ? 18 : 28),
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF646BFF),
                          ),
                        ),
                      ),
                      Text(
                        widget.moduleName ?? 'Unknown',
                        style: TextStyle(
                          fontSize: scalingFactor * (isTablet(context) ? 16 : 24),
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                  SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
                  // Module ID
                  Column(
                    children: [
                      Text(
                        "Module Id: ",
                        style: TextStyle(
                          fontSize: scalingFactor * (isTablet(context) ? 18 : 28),
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF646BFF),
                        ),
                      ),
                      SizedBox(width: scalingFactor * (isTablet(context) ? 5 : 5)),
                      Text(
                        () {
                          if (widget.moduleId == null) {
                            return 'Unknown';
                          } else if (widget.moduleId!.length == 4) {
                            return widget.moduleId!; // Display full 4-digit ID
                          } else if (widget.moduleId!.length == 8) {
                            return '****${widget.moduleId!.substring(4)}'; // Mask first 4 digits, show last 4
                          } else {
                            return 'Unknown'; // Fallback for unexpected lengths
                          }
                        }(),
                        style: TextStyle(
                          fontSize: scalingFactor * (isTablet(context) ? 16 : 24),
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),

                  // Score Entry Section
                  Text(
                    'Score:',
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 18 : 28),
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF646BFF),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
                  Text(
                    _storedScore?.toStringAsFixed(2) ?? 'No Score',
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 18 : 22),
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
                ],
              ),
            ),
          ),

          // Submit Button (Now Outside the Box)
          Padding(
            padding: EdgeInsets.only(top: scalingFactor * (isTablet(context) ? 30 : 20)),
            child: Semantics(
              label: 'Submit Button',
              hint: 'Tap to submit the module',
              child: GestureDetector(
                onTap: () {
                  _handleSubmit(context);
                },
                child: Container(
                  width: scalingFactor * (isTablet(context) ? 150 : 180),
                  height: scalingFactor * (isTablet(context) ? 30 : 50),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF325BFF),
                        Color(0xFF5A88FE),
                        Color(0xFF69AEFE),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: Offset(1, 3),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Submit",
                            style: TextStyle(
                              fontSize: scalingFactor * (isTablet(context) ? 18 : 26),
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFE8E8E8),
                            ),
                          ),
                          SizedBox(width: scalingFactor * (isTablet(context) ? 4 : 4)),
                          Icon(
                            Icons.check_circle,
                            color: Color(0xFFE8E8E8),
                            size: scalingFactor * (isTablet(context) ? 18 : 26),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // Final spacing at bottom
          SizedBox(height: scalingFactor * (isTablet(context) ? 0.1 : 0.1)),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout(scalingFactor) {
    return SingleChildScrollView(
      child : Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: scalingFactor * (isTablet(context) ? 15 : 15)),
            child: Text(
              "Submit CME Credits",
              style: TextStyle(
                fontSize: scalingFactor * (isTablet(context) ? 22 : 28),
                fontWeight: FontWeight.w500,
                color: Color(0xFF646BFF),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          //SizedBox(height: scalingFactor * (isTablet(context) ? 0.038 : 180)),

          // Box Container
          Padding(
            padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 25 : 65)),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(scalingFactor * (isTablet(context) ? 5 : 5)),
              decoration: BoxDecoration(
                color: Color(0xFFFFF5E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Color(0xFF9DA2FF),
                  width: scalingFactor * (isTablet(context) ? 1.5 : 1.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 5,
                    offset: Offset(2, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Module Name
                  Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.only(bottom: scalingFactor * (isTablet(context) ? 5 : 5)),
                        child: Text(
                          "Module Name: ",
                          style: TextStyle(
                            fontSize: scalingFactor * (isTablet(context) ? 18 : 22),
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF646BFF),
                          ),
                        ),
                      ),
                      Text(
                        widget.moduleName ?? 'Unknown',
                        style: TextStyle(
                          fontSize: scalingFactor * (isTablet(context) ? 16 : 22),
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                  SizedBox(height: scalingFactor * (isTablet(context) ? 5 : 5)),
                  // Module ID
                  Column(
                    children: [
                      Text(
                        "Module Id: ",
                        style: TextStyle(
                          fontSize: scalingFactor * (isTablet(context) ? 18 : 22),
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF646BFF),
                        ),
                      ),
                      //SizedBox(width: scalingFactor * (isTablet(context) ? 0.05 : 5)),
                      Text(
                            () {
                          if (widget.moduleId == null) {
                            return 'Unknown';
                          } else if (widget.moduleId!.length == 4) {
                            return widget.moduleId!; // Display full 4-digit ID
                          } else if (widget.moduleId!.length == 8) {
                            return '****${widget.moduleId!.substring(4)}'; // Mask first 4 digits, show last 4
                          } else {
                            return 'Unknown'; // Fallback for unexpected lengths
                          }
                        }(),
                        style: TextStyle(
                          fontSize: scalingFactor * (isTablet(context) ? 16 : 22),
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),

                  // Score Entry Section
                  Text(
                    'Score:',
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 18 : 22),
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF646BFF),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
                  Text(
                    _storedScore?.toStringAsFixed(2) ?? 'No Score',
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 16 : 22),
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
                ],
              ),
            ),
          ),

          // Submit Button (Now Outside the Box)
          Padding(
            padding: EdgeInsets.only(top: scalingFactor * (isTablet(context) ? 30 : 20)),
            child: Semantics(
              label: 'Submit Button',
              hint: 'Tap to submit the module',
              child: GestureDetector(
                onTap: () {
                  _handleSubmit(context);
                },
                child: Container(
                  width: scalingFactor * (isTablet(context) ? 130 : 180),
                  height: scalingFactor * (isTablet(context) ? 30 : 50),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF325BFF),
                        Color(0xFF5A88FE),
                        Color(0xFF69AEFE),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: Offset(1, 3),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Submit",
                            style: TextStyle(
                              fontSize: scalingFactor * (isTablet(context) ? 18 : 26),
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFE8E8E8),
                            ),
                          ),
                          SizedBox(width: scalingFactor * (isTablet(context) ? 4 : 4)),
                          Icon(
                            Icons.check_circle,
                            color: Color(0xFFE8E8E8),
                            size: scalingFactor * (isTablet(context) ? 18 : 26),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // Final spacing at bottom
          SizedBox(height: scalingFactor * (isTablet(context) ? 30 : 30)),
        ],
      ),
    );
  }
}
