import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:wired_test/pages/cme/registration_confirm.dart';
import '../../providers/auth_guard.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../creditsTracker/credits_tracker.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import 'cme_tracker.dart';
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
  List<Map<String, dynamic>> _organizations = [];
  List<Map<String, dynamic>> _filteredOrganizations = [];
  Map<String, dynamic>? _selectedOrganization;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchCountries();
    _fetchOrganizations();
  }

  Future<void> _fetchCountries() async {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final url = Uri.parse('$apiBaseUrl/countries');

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
        print('Error fetching countries: ${response.statusCode}');
      }
    } catch (error) {
      print('Error: $error');
    }
  }

  Widget _buildCountryDropdown() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity, // ✅ full width
        child: DropdownButtonFormField<Map<String, dynamic>>(
          value: _selectedCountry,
          isExpanded: true, // ✅ prevents overflow inside the Row
          decoration: const InputDecoration(
            labelText: 'Country',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          ),
          items: _countrySuggestions.map((country) {
            return DropdownMenuItem<Map<String, dynamic>>(
              value: country,
              child: Text(
                country['name'],
                overflow: TextOverflow.ellipsis, // ✅ handle long names gracefully
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedCountry = value;
              _countryController.text = value?['name'] ?? '';

              // 🔹 Filter organizations by selected country
              _filteredOrganizations = _organizations
                  .where((org) => org['country_id'] == _selectedCountry?['id'])
                  .toList();

              _selectedOrganization = null;
            });
          },
          validator: (value) {
            if (value == null) return 'Please select your country';
            return null;
          },
        ),
      ),
    );
  }

  Future<void> _fetchOrganizations() async {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final url = Uri.parse('$apiBaseUrl/organizations');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _organizations = data.map((item) => {
            'id': item['id'],
            'name': item['name'],
            'country_id': item['country_id'],
            'city_id': item['city_id'],
            'country_name': item['country']?['name'],
            'city_name': item['cities']?['name'],
          }).toList();
        });
      } else {
        print('Error fetching organizations: ${response.statusCode}');
      }
    } catch (error) {
      print('Error: $error');
    }
  }

  Widget _buildOrganizationDropdown() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity, // ✅ same width behavior
        child: DropdownButtonFormField<Map<String, dynamic>>(
          value: _selectedOrganization,
          isExpanded: true, // ✅ ensures icon + text never overflow
          decoration: const InputDecoration(
            labelText: 'Organization',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          ),
          items: _filteredOrganizations.map((org) {
            return DropdownMenuItem<Map<String, dynamic>>(
              value: org,
              child: Text(
                "${org['name']} (${org['city_name']})",
                overflow: TextOverflow.ellipsis, // ✅ keep text tidy in narrow layouts
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedOrganization = value;
              _organizationController.text = value?['name'] ?? '';
            });
          },
          validator: (value) {
            if (value == null) return 'Please select your organization';
            return null;
          },
        ),
      ),
    );
  }

  void _showErrorAlert(String message) {
    String title = "Error"; // Default title

    if (message.toLowerCase().contains("email")) {
      title = "Invalid Email"; // If the error is about email, set title accordingly
    } else if (message.toLowerCase().contains("country")) {
      title = "Invalid Country"; // If the error is about country, set title accordingly
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title), // ✅ Now the title matches the error type
          content: Text(message),
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
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final apiEndpoint = '/auth/register';

    // Validate the email field first
    if (_emailController.text.isEmpty || _validateEmail(_emailController.text) != null) {
      _showErrorAlert("Please enter a valid email address.");
      return false;
    }

    // Validate the full form (excluding email since it was already checked)
    if (!_formKey.currentState!.validate()) {
      return false;
    }

    // Validate the country field only if the email is valid
    if (_selectedCountry == null) {
      _showErrorAlert(
        "The country '${_countryController.text.trim()}' is not recognized. Please select a valid country from the dropdown.",
      );
      return false;
    }

    // Proceed with registration if all validations pass
    final userData = {
      "first_name": _firstNameController.text.trim(),
      "last_name": _lastNameController.text.trim(),
      "email": _emailController.text.trim(),
      "country_id": _selectedCountry!['id'],
      "city": _cityController.text.trim(),
      "organization_id": _selectedOrganization?['id'],
      "password": _passwordController.text.trim(),
    };

    final url = Uri.parse("$apiBaseUrl$apiEndpoint");

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode(userData),
      );

      final responseBody = json.decode(response.body);
      print('Response Status: ${response.statusCode}');
      print('Response Body: $responseBody');

      if (response.statusCode == 201) {
        return true;
      } else {
        final errorData = json.decode(response.body);
        if (errorData.containsKey('message')) {
          _showErrorAlert(errorData['message']);
        }
        return false;
      }
    } catch (error) {
      _showErrorAlert('An unexpected error occurred. Please try again.');
      return false;
    }
  }

  InputDecoration _inputDecoration(String label, {String? hintText}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 14,  // 🟢 Normalize vertical padding
        horizontal: 12,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double scalingFactor = getScalingFactor(context);
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
    final double fieldSpacing = scalingFactor * (isTablet(context) ? 12 : 15);
    return Center(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(top: scalingFactor * (isTablet(context) ? 10 : 10)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              // Title
              Text(
                "Register",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: scalingFactor * (isTablet(context) ? 28 : 32),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF0070C0),
                ),
              ),
              SizedBox(
                height: scalingFactor * (isTablet(context) ? 10 : 10),
              ),
              // First Name
              Padding(
                padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 10 : 10)),
                child: _buildTextField(
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
              ),
              // Last Name
              Padding(
                padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 10 : 10)),
                child: _buildTextField(
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
              ),
              // Email
              Padding(
                padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 10 : 10)),
                child: _buildTextField(
                  controller: _emailController,
                  label: "Email",
                  hintText: "Enter your email",
                  validator: _validateEmail,
                ),
              ),
              // Country
              Padding(
                padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 10 : 10)),
                child: _buildCountryDropdown(),
              ),
              // _buildCityField(),
              // Organization
              Padding(
                padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 10 : 10)),
                child: _buildOrganizationDropdown(),
              ),

              Padding(
                padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 10 : 10)),
                child: _buildTextField(
                  controller: _passwordController,
                  label: "Password",
                  hintText: "Enter your password",
                  validator: _validatePassword,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 10 : 10)),
                child: _buildTextField(
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
              ),
              SizedBox(
                height: scalingFactor * (isTablet(context) ? 25 : 25),
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
                    widthFactor: isTablet(context) ? 0.5 : 0.7,
                    child: Container(
                      height: scalingFactor * (isTablet(context) ? 30 : 40),
                      decoration: BoxDecoration(
                        color: Color(0xFF0070C0),
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
                height: scalingFactor * (isTablet(context) ? 35 : 35),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: scalingFactor * (isTablet(context) ? 55 : 55)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Already have an account?",
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
                          MaterialPageRoute(builder: (context) => Login()),
                        );
                      },
                      child: Text(
                        "Login",
                        style: TextStyle(
                          fontSize: scalingFactor * (isTablet(context) ? 16 : 18),
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

  Widget _buildLandscapeLayout(double scalingFactor) {
    final bool tablet = isTablet(context);
    final double fieldSpacing = scalingFactor * (tablet ? 12 : 15);

    return Center(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: scalingFactor * (tablet ? 20 : 15),
            vertical: scalingFactor * 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 🟦 Title
              Text(
                "Register",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: scalingFactor * (tablet ? 28 : 30),
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0070C0),
                ),
              ),
              SizedBox(height: fieldSpacing * 1.2),

              // 🟫 Two-column layout
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🟩 Left Column
                  Expanded(
                    flex: 1,
                    child: Column(
                      children: [
                        _buildTextField(
                          controller: _firstNameController,
                          label: "First Name",
                          hintText: "Enter your first name",
                          validator: (v) =>
                          v == null || v.isEmpty ? "Please enter your first name" : null,
                        ),
                        _buildTextField(
                          controller: _lastNameController,
                          label: "Last Name",
                          hintText: "Enter your last name",
                          validator: (v) =>
                          v == null || v.isEmpty ? "Please enter your last name" : null,
                        ),
                        _buildTextField(
                          controller: _emailController,
                          label: "Email",
                          hintText: "Enter your email",
                          validator: _validateEmail,
                        ),
                        _buildCountryDropdown(),
                      ],
                    ),
                  ),

                  SizedBox(width: fieldSpacing * 2), // spacing between columns

                  // 🟩 Right Column
                  Expanded(
                    flex: 1,
                    child: Column(
                      children: [
                        _buildOrganizationDropdown(),
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
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return "Please confirm your password";
                            }
                            if (v != _passwordController.text) {
                              return "Passwords do not match";
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(height: fieldSpacing * 2),

              // 🟩 Register button
              Semantics(
                label: 'Register Button',
                hint: 'Tap to register',
                child: GestureDetector(
                  onTap: () async {
                    bool isSuccess = await _submitForm();
                    if (isSuccess) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => RegistrationConfirm()),
                      );
                    }
                  },
                  child: FractionallySizedBox(
                    widthFactor: tablet ? 0.4 : 0.5,
                    child: Container(
                      height: scalingFactor * (tablet ? 35 : 45),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0070C0),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            spreadRadius: 1,
                            blurRadius: 5,
                            offset: const Offset(1, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          "Register",
                          style: TextStyle(
                            fontSize: scalingFactor * (tablet ? 18 : 20),
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: fieldSpacing * 2),

              // 🟨 Footer
              Padding(
                padding: EdgeInsets.only(bottom: scalingFactor * 25),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Already have an account?",
                      style: TextStyle(
                        fontSize: scalingFactor * (tablet ? 16 : 18),
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(width: scalingFactor * 10),
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
                          fontSize: scalingFactor * (tablet ? 16 : 18),
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0070C0),
                        ),
                      ),
                    ),
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

Widget _buildTextField({
  required TextEditingController controller,
  required String label,
  String? hintText,
  TextInputType keyboardType = TextInputType.text,
  bool obscureText = false,
  String? Function(String?)? validator,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12), // ✅ consistent vertical spacing between fields
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,  // ✅ normalize vertical height
          horizontal: 12,
        ),
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




