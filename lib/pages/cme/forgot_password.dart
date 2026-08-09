import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../../providers/auth_guard.dart';
import '../../utils/app_layout.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';

import '../creditsTracker/credits_tracker.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key});

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submitResetRequest() async {
    if (_isSubmitting) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final apiBaseUrl =
        dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final url = Uri.parse(
      '$apiBaseUrl/auth/forgot-password',
    );

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'email': _emailController.text.trim(),
          'client': 'mobile',
        }),
      );

      final responseData = json.decode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200) {
        _showResultDialog(
          title: 'Check Your Email',
          message: responseData['message'] ??
              'If an account exists for this email, a password reset link has been sent.',
          returnToLogin: true,
        );
      } else {
        _showResultDialog(
          title: 'Unable to Send Link',
          message: responseData['message'] ??
              'Unable to process the password reset request.',
        );
      }
    } catch (error) {
      if (!mounted) return;

      _showResultDialog(
        title: 'Connection Error',
        message:
        'Unable to connect to the server. Please check your internet connection and try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showResultDialog({
    required String title,
    required String message,
    bool returnToLogin = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();

                if (returnToLogin) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isLandscape =
        MediaQuery
            .of(context)
            .orientation == Orientation.landscape;
    double scalingFactor = getScalingFactor(context);

    return AppLayout(
      appBar: CustomAppBar(
        onBackPressed: () {
          Navigator.pop(context);
        },
        requireAuth: false,
      ),

      bottomNav: isLandscape
          ? null
          : CustomBottomNavBar(
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
              builder: (context) =>
                  AuthGuard(
                    child: CreditsTracker(),
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
              builder: (context) =>
              isLoggedIn ? Menu() : GuestMenu(),
            ),
          );
        },
      ),

      // ❗ IMPORTANT: no Center()
      child: isLandscape
          ? Row(
        children: [
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
                        child: CreditsTracker(),
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
                  builder: (context) =>
                  isLoggedIn ? Menu() : GuestMenu(),
                ),
              );
            },
          ),

          Expanded(
            child: _buildLandscapeLayout(scalingFactor),
          ),
        ],
      )
          : _buildPortraitLayout(scalingFactor),
    );
  }

  Widget _buildPortraitLayout(double scalingFactor) {
    return Center(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [

              Text(
                "Forgot Password",
                style: TextStyle(
                  fontSize: scalingFactor * 28,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF548235),
                ),
              ),

              const SizedBox(height: 30),

              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: "Email",
                  hintText: "Enter your email",
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Please enter your email";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                height: 45,
                child: ElevatedButton(
                  onPressed: _isSubmitting
                      ? null
                      : _submitResetRequest,
                  child: _isSubmitting
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Text(
                    "Send Reset Link",
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }
  Widget _buildLandscapeLayout(double scalingFactor) {
    return _buildPortraitLayout(scalingFactor);
  }
}