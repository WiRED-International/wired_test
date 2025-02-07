import 'dart:convert';
import 'package:flutter/material.dart';
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
  List<TextEditingController> _controllers = List.generate(
      5, (index) => TextEditingController());

  // Example token that contains the user_id
  String token = 'your_encoded_jwt_token_here';

  // Decode the JWT token to extract the user_id
  String? _getUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      final payload = utf8.decode(
          base64Url.decode(base64Url.normalize(parts[1])));
      final payloadMap = json.decode(payload) as Map<String, dynamic>;

      return payloadMap['user_id']?.toString();
    } catch (e) {
      print('Error decoding token: $e');
      return null;
    }
  }

  Future<void> _handleSubmit(BuildContext context) async {
    // Get user input as a list of characters (keeping blank spaces)
    List<String> rawInputList = _controllers.map((controller) => controller.text.trim()).toList();

    print('Raw score input list: $rawInputList');

    // Ensure the list has exactly 5 elements (padding missing ones with "0")
    while (rawInputList.length < 5) {
      rawInputList.insert(0, "0"); // Insert "0" at the beginning for missing values
    }

    print('Corrected input list: $rawInputList');

    // **First three characters form the integer part**
    String integerPart = rawInputList.sublist(0, 3).join();
    // **Last two characters form the decimal part**
    String decimalPart = rawInputList.sublist(3, 5).join();

    // Remove non-numeric characters (just in case)
    integerPart = integerPart.replaceAll(RegExp(r'[^0-9]'), '');
    decimalPart = decimalPart.replaceAll(RegExp(r'[^0-9]'), '');

    // Ensure integer part is valid (default to "0" if empty)
    integerPart = integerPart.isEmpty ? "0" : integerPart;

    // Ensure decimal part is exactly two digits (default to "00" if empty)
    decimalPart = decimalPart.padRight(2, '0');

    // Construct final score string
    String formattedScore = '$integerPart.$decimalPart';

    print('Final formatted score: $formattedScore');

    // Convert to double
    double? parsedScore = double.tryParse(formattedScore);
    print('Parsed Score: $parsedScore, Type: ${parsedScore.runtimeType}');

    // **Reject scores greater than 100.00**
    if (parsedScore != null && parsedScore > 100.00) {
      print('Error: Score exceeds 100.00!');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Invalid score. The maximum allowed score is 100.00.'),
      ));
      return;
    }

    // Ensure valid range
    if (parsedScore != null && parsedScore >= 0.00 && parsedScore <= 100.00) {
      print('Valid score: $parsedScore');

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.authToken;
      final userId = authProvider.getUserIdFromToken();

      if (token == null || userId == null) {
        print('Token or user_id is missing');
        return;
      }

      try {
        print('Submitting module_id: ${widget.moduleId}, Type: ${widget.moduleId.runtimeType}');

        final response = await http.post(
          Uri.parse('http://widm.wiredhealthresources.net/apiv2/quiz-scores'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode({
            'module_id': widget.moduleId.toString().substring(widget.moduleId.toString().length - 4),
            'user_id': userId,
            'score': parsedScore,
            'date_taken': DateTime.now().toIso8601String(),
          }),
        );

        print('Server response: ${response.statusCode} - ${response.body}');

        if (response.statusCode == 201 || response.statusCode == 200) {
          print('Score submitted successfully: ${response.body}');

          // Show success alert
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
          print('Failed to submit score: ${response.statusCode} - ${response.body}');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to submit score. Please try again.'),
          ));
        }
      } catch (e) {
        print('Error submitting score: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('An error occurred. Please try again.'),
        ));
      }
    } else {
      print('Invalid score');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Invalid score. Please enter a valid score between 000.00 and 100.00.'),
      ));
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
    TextEditingController moduleIdController = TextEditingController();

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
            padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 5 : 5)),
            child: Container(
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
                    'Enter your quiz score',
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 18 : 24),
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ...List.generate(3, (index) {
                          return _buildScoreBox(context, index, scalingFactor);
                        }),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 5 : 5)),
                          child: Text(
                            '.',
                            style: TextStyle(
                              fontSize: scalingFactor * (isTablet(context) ? 20 : 24),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ...List.generate(2, (index) {
                          return _buildScoreBox(context, index + 3, scalingFactor);
                        }),
                      ],
                    ),
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

// Helper function to build a score input box
  Widget _buildScoreBox(BuildContext context, int index, double scalingFactor) {
    return Container(
      alignment: Alignment.center,
      margin: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 4 : 4)),
      width: scalingFactor * (isTablet(context) ? 35 : 45),
      height: scalingFactor * (isTablet(context) ? 35 : 45),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black),
        borderRadius: BorderRadius.circular(4),
        color: Colors.grey[300],
      ),
      child: TextField(
        controller: _controllers[index],
        keyboardType: TextInputType.number,
        maxLength: 1,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: scalingFactor * (isTablet(context) ? 16 : 18),
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          counterText: '',
          border: InputBorder.none,
        ),
        onChanged: (value) {
          if (value.length == 1) {
            FocusScope.of(context).nextFocus();
          } else if (value.isEmpty && index > 0) {
            FocusScope.of(context).previousFocus();
          }
        },
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
            padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 25 : 25)),
            child: Container(
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
                    'Enter your quiz score',
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 18 : 22),
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ...List.generate(3, (index) {
                          return _buildScoreBox(context, index, scalingFactor);
                        }),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 5 : 5)),
                          child: Text(
                            '.',
                            style: TextStyle(
                              fontSize: scalingFactor * (isTablet(context) ? 22 : 24),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ...List.generate(2, (index) {
                          return _buildScoreBox(context, index + 3, scalingFactor);
                        }),
                      ],
                    ),
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
