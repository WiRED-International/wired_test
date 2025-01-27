import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/pages/cme/cme_tracker.dart';

import '../../providers/auth_provider.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/profile_section.dart';
import '../../utils/side_nav_bar.dart';
import '../home_page.dart';
import '../menu.dart';
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
  List<TextEditingController> _controllers = List.generate(4, (index) => TextEditingController());

  // Example token that contains the user_id
  String token = 'your_encoded_jwt_token_here';

  // Decode the JWT token to extract the user_id
  String? _getUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payloadMap = json.decode(payload) as Map<String, dynamic>;

      return payloadMap['user_id']?.toString();
    } catch (e) {
      print('Error decoding token: $e');
      return null;
    }
  }

  Future<void> _handleSubmit(BuildContext context) async {
    String score = _controllers.map((controller) => controller.text).join();

    if (score.length == 4) {
      double? parsedScore = double.tryParse('${score[0]}${score[1]}.${score[2]}${score[3]}');
      if (parsedScore != null) {
        // Access AuthProvider
        final authProvider = Provider.of<AuthProvider>(context, listen: false);

        // Get the token and user ID
        final token = authProvider.authToken;
        print('Token in _handleSubmit: $token');

        final userId = authProvider.getUserIdFromToken();
        print('User ID in _handleSubmit: $userId');

        if (token == null || userId == null) {
          print('Token or user_id is missing');
          return;
        }

        try {
          // Use the token and user ID in the POST request
          final response = await http.post(
            Uri.parse('http://10.0.2.2:3000/quiz-scores'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'module_id': widget.moduleId,
              'user_id': userId,
              'score': parsedScore,
              'date_taken': DateTime.now().toIso8601String(),
            }),
          );

          if (response.statusCode == 201) {
            print('Score submitted successfully: ${response.body}');

            // Navigate to another page (e.g., a success page)
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CMETracker(), // Replace with your destination widget
              ),
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
          content: Text('Invalid score. Please enter a valid score.'),
        ));
      }
    } else {
      print('Please fill all boxes');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please fill all score boxes.'),
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
    var baseSize = MediaQuery.of(context).size.shortestSide;
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
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
                                      builder: (context) => MyHomePage()),
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
                                // Intentionally left blank
                              },
                              onMenuTap: () {
                                Navigator.push(context, MaterialPageRoute(
                                    builder: (context) => Menu()));
                              },
                            ),
                          Expanded(
                            child: Center(
                              child: isLandscape
                                  ? _buildLandscapeLayout(baseSize, )
                                  : _buildPortraitLayout(baseSize, ),
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
                                builder: (context) => MyHomePage()),
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
                          // Intentionally left blank
                        },
                        onMenuTap: () {
                          Navigator.push(context,
                              MaterialPageRoute(builder: (context) => Menu()));
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

  Widget _buildPortraitLayout(baseSize) {
    TextEditingController moduleIdController = TextEditingController();

    return Column(
      children: [
        SizedBox(height: baseSize * (isTablet(context) ? 0.038 : 0.04)),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Submit CME \n Credits',
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.08 : 0.1),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF646BFF),
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                'Module Id',
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.05 : 0.08),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF646BFF),
                ),
                textAlign: TextAlign.center,
              ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: baseSize * (isTablet(context) ? 0.05 : 0.03),
                children: (widget.moduleId ?? 'Unknown').split('').map((char) {
                  return Container(
                    width: baseSize * (isTablet(context) ? 0.05 : 0.15),
                    height: baseSize * (isTablet(context) ? 0.05 : 0.15),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black),
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.grey[300],
                    ),
                    child: Text(
                      char,
                      style: TextStyle(
                        fontSize: baseSize * (isTablet(context) ? 0.05 : 0.09),
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  );
                }).toList(),
              ),
              Text(
                'Module Name',
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.05 : 0.08),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF646BFF),
                ),
                textAlign: TextAlign.center,
              ),
              Container(
                width: baseSize * (isTablet(context) ? 0.05 : 0.85),
                padding: EdgeInsets.all(baseSize * 0.02),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.grey[300],
                ),
                child: Text(
                  widget.moduleName ?? 'Unknown',
                  style: TextStyle(
                    fontSize: baseSize * (isTablet(context) ? 0.05 : 0.06),
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Text(
                'Enter your quiz score for this module',
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.05 : 0.08),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF646BFF),
                ),
                textAlign: TextAlign.center,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  return Container(
                    margin: EdgeInsets.symmetric(horizontal: baseSize * 0.02),
                    width: baseSize * (isTablet(context) ? 0.06 : 0.15),
                    height: baseSize * (isTablet(context) ? 0.06 : 0.15),
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
                        fontSize: baseSize * (isTablet(context) ? 0.05 : 0.05),
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      onChanged: (value) {
                        if (value.length == 1 && index < 3) {
                          FocusScope.of(context).nextFocus();
                        } else if (value.isEmpty && index > 0) {
                          FocusScope.of(context).previousFocus();
                        }
                      },
                    ),
                  );
                }),
              ),
              Semantics(
                label: 'Submit Button',
                hint: 'Tap to submit the module',
                child: GestureDetector(
                  onTap: () {
                   _handleSubmit(context);
                  },
                  child: FractionallySizedBox(
                    widthFactor: isTablet(context) ? 0.33 : 0.5,
                    child: Container(
                      height: baseSize * (isTablet(context) ? 0.09 : 0.17),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF4361EE),
                            Color(0xFF4895EF),
                            Color(0xFF4CC9F0),
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
                            offset: const Offset(1, 3),
                          ),
                        ],
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          double buttonWidth = constraints.maxWidth;
                          double fontSize = buttonWidth * 0.2;
                          double padding = buttonWidth * 0.02;
                          return Padding(
                            padding: EdgeInsets.all(padding),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Submit",
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFFE8E8E8),
                                  ),
                                ),
                                SizedBox(width: padding),
                                Icon(
                                  Icons.check_circle,
                                  color: Color(0xFFE8E8E8),
                                  size: fontSize * 1.2,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: baseSize * (isTablet(context) ? 0.038 : 0.1)),
      ],
    );
  }

  Widget _buildLandscapeLayout(baseSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.038 : 0.0),
        ),
        Flexible(
          child: Hero(
            tag: 'search',
            child: Text(
              'Search Modules',
              style: TextStyle(
                fontSize: baseSize * (isTablet(context) ? 0.09 : 0.09),
                fontWeight: FontWeight.w500,
                color: Color(0xFF0070C0),
              ),
            ),
          ),
        ),
      ],
    );
  }
}