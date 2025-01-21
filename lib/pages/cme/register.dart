import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wired_test/pages/cme/registration_confirm.dart';
import 'package:wired_test/pages/policy.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../download_confirm.dart';
import '../home_page.dart';
import '../menu.dart';
import '../module_library.dart';
import 'cme_info.dart';
import 'login.dart';

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


  List<Map<String, dynamic>> _countrySuggestions = [];
  Map<String, dynamic>? _selectedCountry;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onCountryChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (query.isNotEmpty) {
        _fetchCountrySuggestions(query);
      } else {
        setState(() {
          _countrySuggestions = [];
        });
      }
    });
  }

  Future<void> _fetchCountrySuggestions(String query) async {
    final url = Uri.parse('http://10.0.2.2:3000/countries?query=$query');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _countrySuggestions = data.map((item) => {
            'id': item['id'],
            'name': item['name'],
          }).toList();
        });
      } else {
        print('Error fetching country suggestions');
      }
    } catch (error) {
      print('Error: $error');
    }
  }

  Widget _buildCountryField() {
    return Stack(
      children: [
        TextFormField(
          controller: _countryController,
          decoration: const InputDecoration(
            labelText: 'Country',
            hintText: 'Start typing your country',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            _onCountryChanged(value);
            // Reset _selectedCountry if user types manually
            if (_selectedCountry != value) {
              _selectedCountry = null;
            }
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your country';
            }
            if (_selectedCountry == null) {
              return 'Please select a valid country from the dropdown';
            }
            return null;
          },
        ),
        if (_countrySuggestions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 55.0),
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _countrySuggestions.length,
            itemBuilder: (context, index) {
              final suggestion = _countrySuggestions[index];
              return ListTile(
                title: Text(suggestion['name']),
                onTap: () {
                  setState(() {
                    _countryController.text = suggestion['name']; // Display name
                    _selectedCountry = suggestion; // Store id and name
                    _countrySuggestions = []; // Clear suggestions
                  });
                  print('Selected country: $_selectedCountry');
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showErrorAlert(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Invalid Country'),
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

  Future<bool> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      // Validate the country field
      if (_selectedCountry == null) {
        _showErrorAlert(
          "The country '${_countryController.text.trim()}' is not recognized. Please select a valid country from the dropdown.",
        );
        return false;
      }

      // Collect form data
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final email = _emailController.text.trim();
      final country = _selectedCountry!['id'];
      final city = _cityController.text.trim();
      final organization = _organizationController.text.trim();
      final password = _passwordController.text.trim();

      final userData = {
        "first_name": firstName,
        "last_name": lastName,
        "email": email,
        "country_id": country,
        "city": city,
        "organization": organization,
        "password": password,
      };

      print('User data being sent: $userData');

      final url = Uri.parse('http://10.0.2.2:3000/auth/register');

      try {
        final response = await http.post(
          url,
          headers: {
            "Content-Type": "application/json",
          },
          body: json.encode(userData),
        );

        print('Response status: ${response.statusCode}');
        print('Response body: ${response.body}');

        if (response.statusCode == 201) {
          // Successfully registered
          final responseData = json.decode(response.body);
          print('User registered: ${responseData['message']}');
          return true;
          // Navigate to a success page or show a success message
        } else {
          // Error occurred
          final errorData = json.decode(response.body);
          _showErrorAlert(errorData['message']);
          return false;
        }
      } catch (error) {
        _showErrorAlert('An unexpected error occurred. Please try again.');
        return false;
      }
    }
    return false;
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

  Widget _buildPortraitLayout(screenWidth, screenHeight, baseSize) {
    return Center(
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
                validator: _validateEmail,
              ),
              _buildCountryField(),
              // _buildCityField(),
              // _buildOrganizationField(),
              _buildTextField(
                controller: _passwordController,
                label: "Password",
                hintText: "Enter your password",
                validator: _validatePassword,
              ),
              _buildTextField(
                controller: _confirmPasswordController,
                label: "Confirm Password",
                hintText: "Confirm your password",
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Please confirm your password";
                  }
                  if (value != _passwordController.text) {
                    return "Passwords do not match";
                  }
                  return null;
                },
              ),
              SizedBox(
                height: baseSize * (isTablet(context) ? 0.02 : 0.1),
              ),
              Semantics(
                label: 'Register Button',
                hint: 'Tap to register',
                child: GestureDetector(
                  onTap: () async {
                    bool isSuccess = await _submitForm(); // Wait for submission result
                    if (isSuccess) {
                      // Navigate to RegistrationConfirm if successful
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => RegistrationConfirm()),
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
                                        "Register",
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
                    "Already have an account?",
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
                        MaterialPageRoute(builder: (context) => Login()),
                      );
                    },
                    child: Text(
                      "Login",
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

// String? _validateField(String? value) {
//   if (value == null || value.isEmpty) {
//     return "This field is required";
//   }
//   return null;
// }

String? _validateEmail(String? value) {
  if (value == null || value.isEmpty) {
    return "Please enter an email";
  }
  if (!RegExp(r"^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$").hasMatch(value)) {
    return "Please enter a valid email";
  }
  return null;
}

String? _validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return "Please enter a password";
  }
  if (value.length < 6) {
    return "Password must be at least 6 characters long";
  }
  return null;
}




