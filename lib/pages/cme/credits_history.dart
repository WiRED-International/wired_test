import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_guard.dart';
import '../../providers/auth_provider.dart';
import '../../utils/button.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/landscape_profile_section.dart';
import '../../utils/pdf_preview_screen.dart';
import '../../utils/pdf_utils.dart';
import '../../utils/profile_section.dart';
import '../../utils/side_nav_bar.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import 'cme_tracker.dart';
import 'package:printing/printing.dart';

class CreditsHistory extends StatefulWidget {

  @override
  _CreditsHistoryState createState() => _CreditsHistoryState();
}

class User {
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? role;
  final String? country;
  final String? organization;
  final String? dateJoined;
  final List<dynamic>? quizScores;
  final int creditsEarned;


  User({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.country,
    required this.organization,
    required this.dateJoined,
    required this.quizScores,
  }): creditsEarned = calculateCredits(quizScores ?? []);

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      firstName: json['first_name'] ?? 'Unknown',
      lastName: json['last_name'] ?? 'Unknown',
      email: json['email'] ?? 'No email',
      role: json['role']?['name'] ?? 'Unknown Role',
      country: json['country']?['name'] ?? 'Unknown',
      organization: json['organization']?['name'] ?? 'Unknown',
      dateJoined: json['createdAt'] ?? 'Unknown Date',
      quizScores: json['quizScores'] ?? [], // Provide an empty list for quizScores if null
    );
  }

  Map<String, dynamic> toJson() => {
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'role': role,
    "country": country,
    "organization": organization,
    'dateJoined': dateJoined,
    'quizScores': quizScores,
  };
}

class _CreditsHistoryState extends State<CreditsHistory> {
  final double circleDiameter = 130.0;
  final double circleDiameterSmall = 115.0;
  late Future<User> userData;
  final _storage = const FlutterSecureStorage();
  bool showCreditsHistory = false;
  Set<int> selectedCMEIndices = {};
  bool selectAll = false;
  int? selectedYear;

  @override
  void initState() {
    super.initState();
    userData = fetchUserData();
  }

  Future<String?> getAuthToken() async {
    return await _storage.read(key: 'authToken');
  }

  Future<User> fetchUserData() async {
    final token = await getAuthToken();
    if (token == null) {
      throw Exception('User is not logged in');
    }
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final apiEndpoint = '/users/me';


    final url = Uri.parse('$apiBaseUrl$apiEndpoint');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token', // Include the token in the header
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      print('API Response: $json');
      return User.fromJson(json); // Parse the top-level response directly
    } else {
      throw Exception('Failed to fetch user data: ${response.statusCode}');
    }
  }

  void refreshScores() {
    setState(() {
      userData = fetchUserData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    // final baseSize = screenSize.shortestSide;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final scalingFactor = getScalingFactor(context);
    final isTabletDevice = isTablet(context);

    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<User>(
          future: userData,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else if (!snapshot.hasData) {
              return const Center(child: Text('No data available'));
            }

            final user = snapshot.data!;
            final int creditsEarned = user.creditsEarned ?? 0;
            return Stack(
              children: [
                // Background Gradient
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
                isLandscape
                    ? Row(
                  children: [
                    // Side Navigation Bar for Landscape
                    SizedBox(
                      width: screenSize.width * 0.12, // Adjust width as needed
                      child: CustomSideNavBar(
                        onHomeTap: () => _navigateTo(context, const MyHomePage()),
                        onLibraryTap: () => _navigateTo(context, ModuleLibrary()),
                        onTrackerTap: () => _navigateTo(context, AuthGuard(child: CMETracker())),
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
                    ),
                    // Right Side Content
                    Expanded(
                      child: Column(
                        children: [
                          // LandscapeProfileSection(
                          //   firstName: user.firstName ?? 'Guest',
                          //   dateJoined: user.dateJoined ?? 'Unknown',
                          //   creditsEarned: creditsEarned,
                          // ),
                          Expanded(
                            child: Center(
                              child: _buildLandscapeLayout(
                                context,
                                scalingFactor,
                                user.firstName,
                                user.lastName,
                                user.email,
                                user.role,
                                user.country,
                                user.organization,
                                user.dateJoined,
                                user.quizScores,
                                creditsEarned,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
                    : Column(
                  children: [
                    // ProfileSection(
                    //   firstName: user.firstName ?? 'Guest',
                    //   dateJoined: user.dateJoined ?? 'Unknown',
                    //   creditsEarned: creditsEarned,
                    // ),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Center(
                              child: _buildPortraitLayout(
                                context,
                                scalingFactor,
                                user.firstName,
                                user.lastName,
                                user.email,
                                user.role,
                                user.country,
                                user.organization,
                                user.dateJoined,
                                user.quizScores,
                                creditsEarned,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Bottom Navigation Bar for Portrait
                    CustomBottomNavBar(
                      onHomeTap: () => _navigateTo(context, const MyHomePage()),
                      onLibraryTap: () => _navigateTo(context, ModuleLibrary()),
                      onTrackerTap: () => _navigateTo(context, AuthGuard(child: CMETracker())),
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
                // Custom AppBar
                Positioned(
                  top: 0,
                  left: 0,
                  child: CustomAppBar(
                    onBackPressed: () {
                      Navigator.pop(context);
                    },
                    requireAuth: true,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

// Navigation Helper Function
  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  Widget _buildPortraitLayout(BuildContext context, scalingFactor, firstName, lastName, email,
      role, country, organization, dateJoined, quizScores, creditsEarned,) {
    // Sort quizScores by date
    quizScores?.sort((a, b) => DateTime.parse(b['date_taken']).compareTo(DateTime.parse(a['date_taken'])));
    final dateFormatter = DateFormat('MMM dd, yyyy');
    final filteredQuizScores = selectedYear == null
        ? quizScores
        : quizScores.where((q) {
      final year = DateTime.parse(q['date_taken']).year;
      return year == selectedYear;
    }).toList();

    return SizedBox.expand(
      child: Stack(
        children: [
          Column(
            children: <Widget>[
              SizedBox(height: scalingFactor * (isTablet(context) ? 25 : 35)),
              Text(
                "Submitted CME History",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: scalingFactor * (isTablet(context) ? 22 : 28),
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF325BFF),
                ),
              ),
              SizedBox(height: scalingFactor * (isTablet(context) ? 7 : 5)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      left: scalingFactor * (isTablet(context) ? 16 : 16),
                      bottom: scalingFactor * (isTablet(context) ? 0 : 0),
                    ),
                    child: DropdownButton<int>(
                      value: selectedYear,
                      onChanged: (int? year) {
                        setState(() {
                          selectedYear = year;
                        });
                      },
                      items: [
                        null,
                        ...quizScores
                            .map((q) => DateTime.parse(q['date_taken']).year)
                            .toSet()
                            .toList()
                          ..sort()
                      ].map<DropdownMenuItem<int>>((year) {
                        return DropdownMenuItem<int>(
                          value: year,
                          child: Text(
                              year?.toString() ?? 'All Years',
                            style: TextStyle(
                              fontSize: scalingFactor * (isTablet(context) ? 11 : 14),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  // Email Button
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: scalingFactor * (isTablet(context) ? 6 : 0),
                    ),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.black,
                        backgroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                            horizontal: scalingFactor * (isTablet(context) ? 12 : 16),
                            vertical: scalingFactor * (isTablet(context) ? 6 : 6)
                        ),
                        minimumSize: Size(
                            scalingFactor * (isTablet(context) ? 0 : 0),
                            scalingFactor * (isTablet(context) ? 30 : 36)
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: selectedCMEIndices.isNotEmpty
                          ? () async {
                        final pdfBytes = await generateCMEPdf(
                          firstName: firstName,
                          lastName: lastName,
                          email: email,
                          role: role,
                          country: country,
                          organization: organization,
                          quizScores: quizScores,
                          selectedIndices: selectedCMEIndices,
                        );

                        final file = await generateAndSavePdfToFile(pdfBytes, 'cme_history.pdf');

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PdfPreviewScreen(pdfFile: file),
                          ),
                        );
                      }
                          : null, // Disabled if nothing is selected
                      icon: Icon(Icons.email),
                      label: Text(
                        "Email",
                        style: TextStyle(
                            fontSize: scalingFactor * (isTablet(context) ? 11 : 14),
                        ),
                      ),
                    ),
                  ),

                  Padding(
                    padding: EdgeInsets.only(
                      right: scalingFactor * (isTablet(context) ? 16 : 16),
                      bottom: scalingFactor * (isTablet(context) ? 6 : 0),
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.black,
                        backgroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                            horizontal: scalingFactor * (isTablet(context) ? 12 : 16),
                        ),
                        minimumSize: Size(
                            scalingFactor * (isTablet(context) ? 0 : 0), // Button Width
                            scalingFactor * (isTablet(context) ? 30 : 36) // Button Height
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        setState(() {
                          if (selectAll) {
                            selectedCMEIndices.clear();
                          } else {
                            selectedCMEIndices = Set<int>.from(
                              List.generate(quizScores.length, (index) => index),
                            );
                          }
                          selectAll = !selectAll;
                        });
                      },
                      child: Text(
                        selectAll ? "Deselect All" : "Select All",
                        style: TextStyle(
                            fontSize: scalingFactor * (isTablet(context) ? 11 : 14)
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 5 : 3)),
                      child: quizScores != null && quizScores.isNotEmpty
                          ? ListView.builder(
                        itemCount: filteredQuizScores.length + 1,
                        itemBuilder: (context, index) {
                          if (index == filteredQuizScores.length) {
                            return SizedBox(height: scalingFactor * 55);
                          }
                          final quiz = filteredQuizScores[index];
                          final module = quiz['module'];
                          final dateTaken = quiz['date_taken'];
                          final formattedDate = dateFormatter.format(DateTime.parse(dateTaken));

                          final scoreValue = quiz['score'];
                          final double score = (scoreValue is num)
                              ? scoreValue.toDouble()
                              : double.tryParse(scoreValue.toString()) ?? 0.0;

                          return Card(
                            margin: EdgeInsets.symmetric(
                                vertical: scalingFactor * (isTablet(context) ? 8 : 8),
                                horizontal: scalingFactor * (isTablet(context) ? 16 : 16)
                            ),
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey.shade300, width: 1),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(scalingFactor * (isTablet(context) ? 12 : 12)),
                              child: IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            module != null && module['name'] != null
                                                ? module['name']
                                                : 'Unknown',
                                            style: TextStyle(
                                              fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                              fontWeight: FontWeight.w500,
                                              color: Colors.black,
                                              decoration: TextDecoration.underline,
                                            ),
                                          ),
                                          SizedBox(height: scalingFactor * (isTablet(context) ? 4 : 8)),
                                          RichText(
                                            text: TextSpan(
                                              style: TextStyle(
                                                fontSize: scalingFactor * (isTablet(context) ? 12 : 16),
                                                color: Colors.black,
                                              ),
                                              children: [
                                                const TextSpan(
                                                  text: 'Score: ',
                                                  style: TextStyle(fontWeight: FontWeight.w500),
                                                ),
                                                TextSpan(
                                                  text: '${score.toStringAsFixed(2)}%\n',
                                                ),
                                                const TextSpan(
                                                  text: 'Module ID: ',
                                                  style: TextStyle(fontWeight: FontWeight.w500),
                                                ),
                                                TextSpan(
                                                  text: module != null && module['module_id'] != null
                                                      ? module['module_id'].toString()
                                                      : 'N/A',
                                                  style: const TextStyle(color: Color(0xFF325BFF)),
                                                ),
                                                const TextSpan(
                                                  text: '\nDate Submitted: ',
                                                  style: TextStyle(fontWeight: FontWeight.w500),
                                                ),
                                                TextSpan(text: formattedDate),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.only(
                                          left: scalingFactor * (isTablet(context) ? 4 : 4),
                                          right: scalingFactor * (isTablet(context) ? 4 : 4)
                                      ),
                                      child: Center(
                                        child: Checkbox(
                                          value: selectedCMEIndices.contains(index),
                                          onChanged: (bool? value) {
                                            setState(() {
                                              if (value == true) {
                                                selectedCMEIndices.add(index);
                                              } else {
                                                selectedCMEIndices.remove(index);
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      )
                          : Center(
                        child: Text(
                          "No CME records found for selected year.",
                          style: TextStyle(
                            fontSize: scalingFactor * (isTablet(context) ? 18 : 20),
                            fontWeight: FontWeight.w300,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    // Gradient fade overlay
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.0, 1.0],
                              colors: [
                                Color(0xFFFECF97).withOpacity(0.0),
                                Color(0xFFFECF97),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildLandscapeLayout(BuildContext context, scalingFactor, firstName, lastName, email, role,
      country, organization, dateJoined, quizScores, creditsEarned,) {
    quizScores?.sort((a, b) =>
        DateTime.parse(b['date_taken']).compareTo(DateTime.parse(a['date_taken'])));
    final dateFormatter = DateFormat('MMM dd, yyyy');

    final filteredQuizScores = selectedYear == null
        ? quizScores
        : quizScores.where((q) {
      final year = DateTime.parse(q['date_taken']).year;
      return year == selectedYear;
    }).toList();

    return SizedBox.expand(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 16 : 16)),
        child: Column(
          children: [
            SizedBox(height: scalingFactor * (isTablet(context) ? 20 : 20)),
            Text(
              "Submitted CME History",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: scalingFactor * (isTablet(context) ? 26 : 26),
                fontWeight: FontWeight.w400,
                color: Color(0xFF325BFF),
              ),
            ),
            SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),

            // Action Buttons Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    left: scalingFactor * (isTablet(context) ? 16 : 16),
                  ),
                  child: DropdownButton<int>(
                    value: selectedYear,
                    onChanged: (int? year) {
                      setState(() {
                        selectedYear = year;
                      });
                    },
                    items: [
                      null,
                      ...quizScores
                          .map((q) => DateTime.parse(q['date_taken']).year)
                          .toSet()
                          .toList()
                        ..sort()
                    ].map<DropdownMenuItem<int>>((year) {
                      return DropdownMenuItem<int>(
                        value: year,
                        child: Text(
                            year?.toString() ?? 'All Years',
                            style: TextStyle(
                              fontSize: scalingFactor * (isTablet(context) ? 10 : 14),
                            ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                Padding(
                  padding: EdgeInsets.only(
                    bottom: scalingFactor * (isTablet(context) ? 6 : 4),
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.black,
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                          horizontal: scalingFactor * (isTablet(context) ? 12 : 16),
                          vertical: scalingFactor * (isTablet(context) ? 6 : 6)
                      ),
                      minimumSize: Size(
                          scalingFactor * (isTablet(context) ? 0 : 0),
                          scalingFactor * (isTablet(context) ? 30 : 32)
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: selectedCMEIndices.isNotEmpty
                        ? () async {
                      final pdfBytes = await generateCMEPdf(
                        firstName: firstName,
                        lastName: lastName,
                        email: email,
                        role: role,
                        country: country,
                        organization: organization,
                        quizScores: quizScores,
                        selectedIndices: selectedCMEIndices,
                      );

                      final file =
                      await generateAndSavePdfToFile(pdfBytes, 'cme_history.pdf');

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PdfPreviewScreen(pdfFile: file),
                        ),
                      );
                    }
                        : null,
                    icon: Icon(Icons.email),
                    label: Text(
                      "Email",
                      style: TextStyle(
                        fontSize: scalingFactor * (isTablet(context) ? 10 : 14),
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: EdgeInsets.only(
                    right: scalingFactor * (isTablet(context) ? 16 : 16),
                    bottom: scalingFactor * (isTablet(context) ? 6 : 4),
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.black,
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: scalingFactor * (isTablet(context) ? 12 : 16),
                      ),
                      minimumSize: Size(
                          scalingFactor * (isTablet(context) ? 0 : 0), // Button Width
                          scalingFactor * (isTablet(context) ? 30 : 32) // Button Height
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      setState(() {
                        if (selectAll) {
                          selectedCMEIndices.clear();
                        } else {
                          selectedCMEIndices = Set<int>.from(
                            List.generate(quizScores.length, (index) => index),
                          );
                        }
                        selectAll = !selectAll;
                      });
                    },
                    child: Text(
                      selectAll ? "Deselect All" : "Select All",
                      style: TextStyle(
                          fontSize: scalingFactor * (isTablet(context) ? 10 : 14)
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 5 : 3)),
                    child: quizScores != null && quizScores.isNotEmpty
                        ? ListView.builder(
                      itemCount: filteredQuizScores.length + 1,
                      itemBuilder: (context, index) {
                        if (index == filteredQuizScores.length) {
                          return SizedBox(height: scalingFactor * 55);
                        }
                        final quiz = filteredQuizScores[index];
                        final module = quiz['module'];
                        final formattedDate = dateFormatter.format(
                            DateTime.parse(quiz['date_taken']));

                        final scoreValue = quiz['score'];
                        final double score = (scoreValue is num)
                            ? scoreValue.toDouble()
                            : double.tryParse(scoreValue.toString()) ?? 0.0;

                        return Card(
                          margin: EdgeInsets.symmetric(
                            vertical: scalingFactor * (isTablet(context) ? 8 : 8),
                            horizontal: scalingFactor * (isTablet(context) ? 16 : 16)
                          ),
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side:
                            BorderSide(color: Colors.grey.shade300, width: 1),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(scalingFactor * (isTablet(context) ? 12 : 12)),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          module != null && module['name'] != null
                                              ? module['name']
                                              : 'Unknown',
                                          style: TextStyle(
                                            fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                        SizedBox(height: scalingFactor * (isTablet(context) ? 8 : 8)),
                                        RichText(
                                          text: TextSpan(
                                            style: TextStyle(
                                              fontSize: scalingFactor * (isTablet(context) ? 12 : 16),
                                              color: Colors.black,
                                            ),
                                            children: [
                                              const TextSpan(
                                                text: 'Score: ',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w500),
                                              ),
                                              TextSpan(
                                                text: '${score.toStringAsFixed(2)}%\n',
                                              ),
                                              const TextSpan(
                                                text: 'Module ID: ',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w500),
                                              ),
                                              TextSpan(
                                                text: module != null &&
                                                    module['module_id'] != null
                                                    ? module['module_id'].toString()
                                                    : 'N/A',
                                                style: const TextStyle(
                                                    color: Color(0xFF325BFF)),
                                              ),
                                              const TextSpan(
                                                text: '\nDate Submitted: ',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w500),
                                              ),
                                              TextSpan(text: formattedDate),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.only(
                                        left: scalingFactor * (isTablet(context) ? 4 : 4),
                                        right: scalingFactor * (isTablet(context) ? 4 : 4)
                                    ),
                                    child: Center(
                                      child: Checkbox(
                                        value: selectedCMEIndices.contains(index),
                                        onChanged: (bool? value) {
                                          setState(() {
                                            if (value == true) {
                                              selectedCMEIndices.add(index);
                                            } else {
                                              selectedCMEIndices.remove(index);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    )
                        : Center(
                      child: Text(
                        "No CME records found for selected year.",
                        style: TextStyle(
                          fontSize: scalingFactor * (isTablet(context) ? 18 : 20),
                          fontWeight: FontWeight.w300,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),

                  // Fade Overlay
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.0, 1.0],
                            colors: [
                              Color(0xFFFECF97).withOpacity(0.0),
                              Color(0xFFFECF97),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}