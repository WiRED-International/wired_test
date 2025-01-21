import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:wired_test/pages/cme/register.dart';
import 'package:wired_test/providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../home_page.dart';
import '../menu.dart';
import '../module_library.dart';
import 'cme_info.dart';
import 'cme_tracker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Login extends StatefulWidget {
  @override
  _LoginState createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<bool> hasNetworkConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (!await hasNetworkConnection()) {
      if (mounted) _showErrorAlert("No internet connection. Please connect and try again.");
      return false;
    }
    return connectivityResult != ConnectivityResult.none;
  }

  final _storage = const FlutterSecureStorage();

  Future<http.Response?> _submitForm() async {
   print("Submitting form");

    if (_formKey.currentState!.validate()) {
      // Validate the email and password fields
      if (_emailController.text.isEmpty) {
        if (mounted) _showErrorAlert("Please enter your email");
        return null;
      }
      if (_passwordController.text.isEmpty) {
        if (mounted) _showErrorAlert("Please enter your password");
        return null;
      }

      // Collect form data
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      final url = Uri.parse('http://10.0.2.2:3000/auth/login');

      try {
        final response = await http.post(
          url,
          headers: {
            "Content-Type": "application/json",
          },
          body: json.encode({
            "email": email,
            "password": password,
          }),
        );

        print('Response status: ${response.statusCode}');
        print('Response body: ${response.body}');

        if (response.statusCode == 200) {
          // Successfully logged in
          final responseData = json.decode(response.body);
          final authToken = responseData['token'];
          if (authToken is! String) {
            print('Error: Token is not a string');
          }
          try {
            await _storage.write(key: 'authToken', value: authToken);
          } catch (e) {
            print('SecureStorage Error: $e');
            if (mounted) _showErrorAlert("Failed to save login data securely.");
          }


          return response;

        } else {
          if (mounted) _showErrorAlert("Unable to connect to the server. Please check your connection.");
        }
      } catch (error) {
        if (mounted) _showErrorAlert("An unexpected error occurred. Please try again.");
      }
    }
    return null;
  }

  void _showErrorAlert(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Invalid Email or Password'),
          content: Text(
            "$message\n\nSuggestions:\n- Ensure the spelling is correct.\n- Use the dropdown to select the correct country.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          border: OutlineInputBorder(),
        ),
        keyboardType: keyboardType,
        obscureText: obscureText,
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    var baseSize = MediaQuery.of(context).size.shortestSide;
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

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
                // Custom AppBar
                CustomAppBar(
                  onBackPressed: () {
                    Navigator.pop(context);
                  },
                ),
                // Expanded layout for the main content
                Expanded(
                  child: Row(
                    children: [
                      if (isLandscape)
                        CustomSideNavBar(
                          onHomeTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ModuleLibrary()),
                            );
                          },
                          onTrackerTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (
                                context) => CmeInfo()));
                          },
                          onMenuTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (
                                context) => Menu()));
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(screenWidth, screenHeight, baseSize, authProvider)
                              : _buildPortraitLayout(screenWidth, screenHeight, baseSize, authProvider),
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
                        MaterialPageRoute(builder: (context) => ModuleLibrary()),
                      );
                    },
                    onTrackerTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (
                          context) => CmeInfo()));
                    },
                    onMenuTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (
                          context) => Menu()));
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(screenWidth, screenHeight, baseSize, authProvider) {
    return Center(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(top: baseSize * (isTablet(context) ? 0.02 : 0.02)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              Text(
                "Start Tracking your CME Credits",
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF548235),
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(
                height: baseSize * (isTablet(context) ? 0.02 : 0.02),
              ),
              _buildTextField(
                controller: _emailController,
                label: "Email",
                hintText: "Enter your email",
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Please enter your email";
                  }
                  return null;
                },
              ),
              _buildTextField(
                controller: _passwordController,
                label: "Password",
                hintText: "Enter your password",
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Please enter your password";
                  }
                  return null;
                },
              ),
              SizedBox(
                height: baseSize * (isTablet(context) ? 0.02 : 0.1),
              ),
              Semantics(
                label: 'Login Button',
                hint: 'Tap to login',
                child: GestureDetector(
                  onTap: () async {
                    final response = await _submitForm(); // Wait for submission result
                    if (response != null) {
                      authProvider.logIn();

                      // Parse the response from the API to get user data
                      final responseData = json.decode(response.body);
                      final user = responseData['user'] ?? {};
                      String firstName = user['firstName'] ?? 'Unknown';
                      String lastName = user['lastName'] ?? 'Unknown';
                      String email = user['email'] ?? 'unknown@example.com';
                      String dateJoined = user['createdAt'] ?? 'Unknown';

                      // Log the user data for debugging
                      debugPrint('User Data: firstName=$firstName, lastName=$lastName, email=$email, dateJoined=$dateJoined');

                      // Save user data in the UserProvider
                      Provider.of<UserProvider>(context, listen: false).setUser(firstName, lastName, email, dateJoined);

                      // Navigate to RegistrationConfirm if successful
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CMETracker(
                              firstName: firstName,
                              lastName: lastName,
                              email: email,
                              dateJoined: dateJoined
                          )
                        ),
                      );
                    }
                  },
                  child: FractionallySizedBox(
                    widthFactor: isTablet(context) ? 0.33 : 0.7,
                    child: Container(
                      height: baseSize * (isTablet(context) ? 0.09 : 0.13),
                      decoration: BoxDecoration(
                        color: Color(0xFF0070C0),
                        // gradient: const LinearGradient(
                        //   colors: [
                        //     Color(0xFF0070C0),
                        //     Color(0xFF00C1FF),
                        //     Color(0xFF0070C0),
                        //   ], // Your gradient colors
                        //   begin: Alignment.topCenter,
                        //   end: Alignment.bottomCenter,
                        // ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            spreadRadius: 1,
                            blurRadius: 5,
                            offset: const Offset(
                                1, 3), // changes position of shadow
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
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.fitWidth,
                                      child: Text(
                                        "Login",
                                        style: TextStyle(
                                          fontSize: fontSize,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: baseSize * (isTablet(context) ? 0.02 : 0.1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Not Registered yet?",
                    style: TextStyle(
                      fontSize: baseSize * (isTablet(context) ? 0.03 : 0.05),
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(
                    width: baseSize * (isTablet(context) ? 0.02 : 0.02),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => Register()),
                      );
                    },
                    child: Text(
                      "Register here",
                      style: TextStyle(
                        fontSize: baseSize * (isTablet(context) ? 0.03 : 0.05),
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF0070C0),
                      ),
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight, baseSize, authProvider) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Text(
          "Start Tracking your CME Credits",
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
            fontWeight: FontWeight.w500,
            color: Color(0xFF548235),
          ),
        ),
      ],
    );
  }
}