import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wired_test/pages/policy.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../download_confirm.dart';
import '../home_page.dart';
import '../menu.dart';
import '../module_library.dart';

class Register extends StatefulWidget {
  @override
  _RegisterState createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _countryController = TextEditingController();
  final _cityController = TextEditingController();
  final _organizationController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      // Collect form data
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final email = _emailController.text.trim();
      final country = _countryController.text.trim();
      final city = _cityController.text.trim();
      final organization = _organizationController.text.trim();
      final password = _passwordController.text.trim();

      // Submit the data to your backend
      print({
        "firstName": firstName,
        "lastName": lastName,
        "email": email,
        "country": country,
        "city": city,
        "organization": organization,
        "password": password,
      });
      // You can make an API call here
    }
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

  String? _validateField(String? value) {
    if (value == null || value.isEmpty) {
      return "This field is required";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
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
                          onHelpTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const Policy()),
                            );
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(screenWidth, screenHeight, baseSize)
                              : _buildPortraitLayout(screenWidth, screenHeight, baseSize),
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
                      // Navigator.push(context, MaterialPageRoute(builder: (
                      //     context) => Policy()));
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

  Widget _buildPortraitLayout(screenWidth, screenHeight, baseSize) {
    return Expanded(
      child: Center(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(top: baseSize * (isTablet(context) ? 0.02 : 0.02)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                Text(
                  "Register",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF0070C0),
                  ),
                ),
                SizedBox(
                  height: baseSize * (isTablet(context) ? 0.02 : 0.02),
                ),
                _buildTextField(
                  controller: _firstNameController,
                  label: "First Name",
                  hintText: "Enter your first name",
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Please enter your first name";
                    }
                    return null;
                  },
                ),
                _buildTextField(
                  controller: _lastNameController,
                  label: "Last Name",
                  hintText: "Enter your last name",
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Please enter your last name";
                    }
                    return null;
                  },
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
                  controller: _countryController,
                  label: "Country",
                  hintText: "Enter your country",
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Please enter your country";
                    }
                    return null;
                  },
                ),
                _buildTextField(
                  controller: _cityController,
                  label: "City",
                  hintText: "Enter your city",
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Please enter your city";
                    }
                    return null;
                  },
                ),
                _buildTextField(
                  controller: _organizationController,
                  label: "Organization",
                  hintText: "Enter your organization",
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Please enter your organization";
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
                _buildTextField(
                  controller: _confirmPasswordController,
                  label: "Confirm Password",
                  hintText: "Confirm your password",
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Please confirm your password";
                    }
                    return null;
                  },
                ),
                SizedBox(
                  height: baseSize * (isTablet(context) ? 0.02 : 0.02),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight, baseSize) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Text(
          "Register",
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