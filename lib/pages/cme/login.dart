import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:wired_test/pages/cme/register.dart';
import 'package:wired_test/providers/auth_provider.dart';
import '../../providers/auth_guard.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
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
  bool _isLoggingIn = false;

  Future<bool> hasNetworkConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      if (mounted) _showErrorAlert("No internet connection. Please connect and try again.");
      return false;
    }
    return true;
  }

  final _storage = const FlutterSecureStorage();

  Future<http.Response?> _submitForm() async {
    const remoteServer = 'http://widm.wiredhealthresources.net/apiv2/auth/login';
    const localServer = 'http://10.0.2.2:3000/auth/login';
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
      final url = Uri.parse(remoteServer);

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

        if (response.statusCode == 200) {
          // Successfully logged in
          final responseData = json.decode(response.body);
          final authToken = responseData['token'];
          final userId = responseData['user']['id'];

          if (authToken is String && authToken.isNotEmpty && userId != null) {
            try {
              await _storage.write(key: 'authToken', value: authToken);
              await _storage.write(key: 'user_id', value: userId.toString());
              print("Auth token and user_id successfully saved!");
            } catch (e) {
              print('SecureStorage Error: $e');
              if (mounted) _showErrorAlert("Failed to save login data securely.");
              return null;
            }
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

  Future<void> _handleLogin() async {
    if (_isLoggingIn) return; // Prevent multiple clicks

    setState(() {
      _isLoggingIn = true;
    });

    final response = await _submitForm();

    if (response != null) {
      // Parse the response
      final responseData = json.decode(response.body);
      final authToken = responseData['token'];
      final userId = responseData['user']['id'];

      if (authToken != null && authToken.isNotEmpty) {
        final normalizedTokenPayload = normalizeBase64(authToken.split('.')[1]);
        final decodedPayload = json.decode(utf8.decode(base64.decode(normalizedTokenPayload)));
        final expiryTimestamp = decodedPayload['exp'];
        final expiry = DateTime.fromMillisecondsSinceEpoch(expiryTimestamp * 1000);

        // Update AuthProvider
        Provider.of<AuthProvider>(context, listen: false).logIn(authToken, expiry);

        // Extract user data
        final user = responseData['user'] ?? {};
        String firstName = user['firstName'] ?? 'Unknown';
        String lastName = user['lastName'] ?? 'Unknown';
        String email = user['email'] ?? 'unknown@example.com';
        String dateJoined = user['createdAt'] ?? 'Unknown';

        debugPrint('User Data: firstName=$firstName, lastName=$lastName, email=$email, dateJoined=$dateJoined');

        // Store user_id securely
        await _storage.write(key: 'user_id', value: userId.toString());

        // Navigate to CMETracker screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => CMETracker()),
        );
      }
    }

    setState(() {
      _isLoggingIn = false; // Reset login state after completion
    });
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
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    // final authProvider = Provider.of<AuthProvider>(context, listen: false);
    double scalingFactor = getScalingFactor(context);

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
                  requireAuth: false,
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
                              MaterialPageRoute(builder: (context) => const MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ModuleLibrary()),
                            );
                          },
                          onTrackerTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AuthGuard(
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

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(scalingFactor)
                              : _buildPortraitLayout(scalingFactor),
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
                        MaterialPageRoute(builder: (context) => ModuleLibrary()),
                      );
                    },
                    onTrackerTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AuthGuard(
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
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(scalingFactor) {
    return Center(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(top: scalingFactor * (isTablet(context) ? 10 : 10)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              Text(
                "Start Tracking your CME Credits",
                style: TextStyle(
                  fontSize: scalingFactor * (isTablet(context) ? 24 : 32),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF548235),
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(
                height: scalingFactor * (isTablet(context) ? 20 : 10),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 5 : 5)),
                child: _buildTextField(
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
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 5 : 5)),
                child: _buildTextField(
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
              ),
              SizedBox(
                height: scalingFactor * (isTablet(context) ? 25 : 25),
              ),
              Semantics(
                label: 'Login Button',
                hint: 'Tap to login',
                child: GestureDetector(
                  onTap: _isLoggingIn ? null : _handleLogin,
                  child: FractionallySizedBox(
                    widthFactor: isTablet(context) ? 0.5 : 0.7,
                    child: Container(
                      height: scalingFactor * (isTablet(context) ? 30 : 40),
                      decoration: BoxDecoration(
                        color: _isLoggingIn ? Colors.grey : Color(0xFF0070C0),
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
                      child: _isLoggingIn
                          ? const Center(child: CircularProgressIndicator(color: Colors.white)) // Show spinner when logging in
                          : LayoutBuilder(
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
                height: scalingFactor * (isTablet(context) ? 35 : 25),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Not Registered yet?",
                    style: TextStyle(
                      fontSize: scalingFactor * (isTablet(context) ? 16 : 18),
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(
                    width: scalingFactor * (isTablet(context) ? 10 : 10),
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
                        fontSize: scalingFactor * (isTablet(context) ? 16 : 18),
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

  Widget _buildLandscapeLayout(scalingFactor) {
    return Center(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(top: scalingFactor * (isTablet(context) ? 0.02 : 10)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              Text(
                "Start Tracking your CME Credits",
                style: TextStyle(
                  fontSize: scalingFactor * (isTablet(context) ? 24 : 28),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF548235),
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(
                height: scalingFactor * (isTablet(context) ? 10 : 10),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 100 : 100)),
                child: _buildTextField(
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
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 100 : 100)),
                child: _buildTextField(
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
              ),
              SizedBox(
                height: scalingFactor * (isTablet(context) ? 20 : 20),
              ),
              Semantics(
                label: 'Login Button',
                hint: 'Tap to login',
                child: GestureDetector(
                  onTap: _isLoggingIn ? null : _handleLogin,
                  child: FractionallySizedBox(
                    widthFactor: isTablet(context) ? 0.3 : 0.3,
                    child: Container(
                      height: scalingFactor * (isTablet(context) ? 30 : 30),
                      decoration: BoxDecoration(
                        color: _isLoggingIn ? Colors.grey : Color(0xFF0070C0),
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
                      child: _isLoggingIn
                          ? const Center(child: CircularProgressIndicator(color: Colors.white)) // Show spinner when logging in
                          : LayoutBuilder(
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
              Padding(
                padding: EdgeInsets.symmetric(vertical: scalingFactor * (isTablet(context) ? 35 : 20)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Not Registered yet?",
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 16 : 16),
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(
                      width: scalingFactor * (isTablet(context) ? 10 : 10),
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
                          fontSize: scalingFactor * (isTablet(context) ? 16 : 16),
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0070C0),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}