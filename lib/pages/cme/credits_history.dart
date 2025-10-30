import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../providers/auth_guard.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/pdf_preview_screen.dart';
import '../../utils/pdf_utils.dart';
import '../../utils/side_nav_bar.dart';
import '../creditsTracker/credits_tracker.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import '../../models/user.dart';

class CreditsHistory extends StatefulWidget {
  const CreditsHistory({Key? key}) : super(key: key);

  @override
  State<CreditsHistory> createState() => _CreditsHistoryState();
}

class _CreditsHistoryState extends State<CreditsHistory> {
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

    final response = await http.get(
      Uri.parse('$apiBaseUrl/users/me'),
      headers: {
        'Authorization': 'Bearer $token', // Include the token in the header
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
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
    final baseSize = mediaQuery.size.shortestSide;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final isTabletDevice = isTablet(context);
    final scale = isTabletDevice ? 1.0 : 1.0;

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
            final quizScores = user.quizScores ?? [];
            final creditsEarned = user.creditsEarned ?? 0;

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
                Column(
                  children: [
                    CustomAppBar(
                      onBackPressed: () => Navigator.pop(context),
                      requireAuth: true,
                      scale: scale,
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          // 🟩 SideNav (Landscape only)
                          if (isLandscape)
                            CustomSideNavBar(
                              onHomeTap: () => _navigateTo(context, const MyHomePage()),
                              onLibraryTap: () => _navigateTo(context, ModuleLibrary()),
                              onTrackerTap: () =>
                                  _navigateTo(context, AuthGuard(child: const CreditsTracker())),
                              onMenuTap: () async {
                                bool isLoggedIn = await checkIfUserIsLoggedIn();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => isLoggedIn ? const Menu() : const GuestMenu(),
                                  ),
                                );
                              },
                              scale: scale,
                            ),

                          // 🟩 Main content
                          Expanded(
                            child: Center(
                              child: isLandscape
                                  ? _buildLandscapeLayout(context, user, quizScores,
                                  creditsEarned, baseSize, scale)
                                  : _buildPortraitLayout(context, user, quizScores,
                                  creditsEarned, baseSize, scale),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 🟩 Bottom Nav (portrait only)
                    if (!isLandscape)
                      CustomBottomNavBar(
                        onHomeTap: () => _navigateTo(context, const MyHomePage()),
                        onLibraryTap: () => _navigateTo(context, ModuleLibrary()),
                        onTrackerTap: () =>
                            _navigateTo(context, AuthGuard(child: const CreditsTracker())),
                        onMenuTap: () async {
                          bool isLoggedIn = await checkIfUserIsLoggedIn();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                              isLoggedIn ? const Menu() : const GuestMenu(),
                            ),
                          );
                        },
                        scale: scale,
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

// =====================================================
  // 📱 Portrait Layout
  // =====================================================
  Widget _buildPortraitLayout(
      BuildContext context,
      User user,
      List<dynamic> quizScores,
      int creditsEarned,
      double baseSize,
      double scale,
      ) {
    final dateFormatter = DateFormat('MMM dd, yyyy');
    quizScores.sort(
          (a, b) =>
          DateTime.parse(b['date_taken']).compareTo(DateTime.parse(a['date_taken'])),
    );
    final filtered = selectedYear == null
        ? quizScores
        : quizScores
        .where((q) => DateTime.parse(q['date_taken']).year == selectedYear)
        .toList();

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: baseSize * 0.07 * scale,
        vertical: baseSize * 0.03 * scale,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 Header
          Text(
            "Submitted CME History",
            style: TextStyle(
              fontSize: baseSize * 0.055 * scale,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: baseSize * 0.025 * scale),

          // 🔹 Top Button Row (All Years, Email, Select All)
          Padding(
            padding: EdgeInsets.symmetric(vertical: baseSize * 0.01 * scale),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // 🟢 All Years Dropdown
                  Container(
                    height: baseSize * 0.085,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: baseSize * 0.035 * scale),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: selectedYear,
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.black54),
                        onChanged: (int? year) => setState(() => selectedYear = year),
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
                                fontSize: baseSize * 0.034 * scale,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  SizedBox(width: baseSize * 0.03),

                  // 🟢 Email Button
                  ElevatedButton.icon(
                    onPressed: selectedCMEIndices.isNotEmpty
                        ? () async {
                      final pdfBytes = await generateCMEPdf(
                        firstName: user.firstName ?? '',
                        lastName: user.lastName ?? '',
                        email: user.email ?? '',
                        role: user.role ?? '',
                        country: user.country ?? '',
                        organization: user.organization ?? '',
                        quizScores: quizScores,
                        selectedIndices: selectedCMEIndices,
                      );

                      final file = await generateAndSavePdfToFile(
                          pdfBytes, 'cme_history.pdf');

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PdfPreviewScreen(pdfFile: file),
                        ),
                      );
                    }
                        : null,
                    icon: const Icon(Icons.email_outlined,
                        color: Colors.black87, size: 18),
                    label: Text(
                      "Email",
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: baseSize * 0.032 * scale,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(
                        horizontal: baseSize * 0.05 * scale,
                        vertical: baseSize * 0.018 * scale,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),

                  SizedBox(width: baseSize * 0.03),

                  // 🟢 Select / Deselect All Button
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        if (selectAll) {
                          selectedCMEIndices.clear();
                        } else {
                          selectedCMEIndices =
                          Set<int>.from(List.generate(quizScores.length, (i) => i));
                        }
                        selectAll = !selectAll;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(
                        horizontal: baseSize * 0.05 * scale,
                        vertical: baseSize * 0.018 * scale,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Text(
                      selectAll ? "Deselect All" : "Select All",
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: baseSize * 0.032 * scale,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: baseSize * 0.04 * scale),

          // 🟣 CME History List
          Expanded(
            child: filtered.isNotEmpty
                ? ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) => _buildCreditCard(
                context,
                filtered[index],
                index,
                dateFormatter,
                baseSize,
                scale,
              ),
            )
                : Center(
              child: Text(
                "No CME records found.",
                style: TextStyle(
                  fontSize: baseSize * 0.035 * scale,
                  color: Colors.black54,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // 💻 Landscape Layout
  // =====================================================
  Widget _buildLandscapeLayout(
      BuildContext context,
      User user,
      List<dynamic> quizScores,
      int creditsEarned,
      double baseSize,
      double scale,
      ) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: baseSize * 0.05,
        vertical: baseSize * 0.03,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 LEFT COLUMN — header + buttons
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header title
                Text(
                  "Submitted CME History",
                  style: TextStyle(
                    fontSize: baseSize * 0.05,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: baseSize * 0.03),

                // 🔸 First row: All Years + Email
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      // 🟢 All Years Dropdown
                      Container(
                        height: baseSize * 0.085,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: EdgeInsets.symmetric(
                            horizontal: baseSize * 0.035 * scale),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: selectedYear,
                            icon: const Icon(Icons.arrow_drop_down,
                                color: Colors.black54),
                            onChanged: (int? year) =>
                                setState(() => selectedYear = year),
                            items: [
                              null,
                              ...quizScores
                                  .map((q) =>
                              DateTime.parse(q['date_taken']).year)
                                  .toSet()
                                  .toList()
                                ..sort()
                            ].map<DropdownMenuItem<int>>((year) {
                              return DropdownMenuItem<int>(
                                value: year,
                                child: Text(
                                  year?.toString() ?? 'All Years',
                                  style: TextStyle(
                                    fontSize: baseSize * 0.034 * scale,
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),

                      SizedBox(width: baseSize * 0.03),

                      // 🟢 Email Button
                      ElevatedButton.icon(
                        onPressed: selectedCMEIndices.isNotEmpty
                            ? () async {
                          final pdfBytes = await generateCMEPdf(
                            firstName: user.firstName ?? '',
                            lastName: user.lastName ?? '',
                            email: user.email ?? '',
                            role: user.role ?? '',
                            country: user.country ?? '',
                            organization: user.organization ?? '',
                            quizScores: quizScores,
                            selectedIndices: selectedCMEIndices,
                          );

                          final file = await generateAndSavePdfToFile(
                            pdfBytes,
                            'cme_history.pdf',
                          );

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PdfPreviewScreen(pdfFile: file),
                            ),
                          );
                        }
                            : null,
                        icon: const Icon(Icons.email_outlined,
                            color: Colors.black87, size: 18),
                        label: Text(
                          "Email",
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: baseSize * 0.032 * scale,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(
                            horizontal: baseSize * 0.05 * scale,
                            vertical: baseSize * 0.018 * scale,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: baseSize * 0.025 * scale),

                // 🔸 Second row: Select All / Deselect All
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      if (selectAll) {
                        selectedCMEIndices.clear();
                      } else {
                        selectedCMEIndices =
                        Set<int>.from(List.generate(quizScores.length, (i) => i));
                      }
                      selectAll = !selectAll;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(
                      horizontal: baseSize * 0.05 * scale,
                      vertical: baseSize * 0.018 * scale,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Text(
                    selectAll ? "Deselect All" : "Select All",
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: baseSize * 0.032 * scale,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                SizedBox(height: baseSize * 0.05),
              ],
            ),
          ),

          SizedBox(width: baseSize * 0.05),

          // 🔹 RIGHT COLUMN — CME cards list
          Expanded(
            flex: 6,
            child: ListView.builder(
              itemCount: quizScores.length,
              itemBuilder: (context, index) => _buildCreditCard(
                context,
                quizScores[index],
                index,
                DateFormat('MMM dd, yyyy'),
                baseSize,
                scale,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // 🟩 Reusable Card
  // =====================================================
  Widget _buildCreditCard(BuildContext context, dynamic quiz, int index,
      DateFormat formatter, double baseSize, double scale) {
    final module = quiz['module'];
    final moduleName = module?['name'] ?? 'Unknown';
    final moduleId = module?['module_id']?.toString() ?? 'N/A';
    final date = formatter.format(DateTime.parse(quiz['date_taken']));
    final scoreVal = quiz['score'];
    final double score = (scoreVal is num)
        ? scoreVal.toDouble()
        : double.tryParse(scoreVal.toString()) ?? 0.0;

    return Container(
      margin: EdgeInsets.only(bottom: baseSize * 0.03 * scale),
      padding: EdgeInsets.all(baseSize * 0.035 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(baseSize * 0.03 * scale),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4 * scale,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Checkbox
          InkWell(
            onTap: () {
              setState(() {
                if (selectedCMEIndices.contains(index)) {
                  selectedCMEIndices.remove(index);
                } else {
                  selectedCMEIndices.add(index);
                }
              });
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: baseSize * 0.05 * scale,
              height: baseSize * 0.05 * scale,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selectedCMEIndices.contains(index)
                      ? const Color(0xFF22C55E)
                      : Colors.grey.shade400,
                  width: 1.8,
                ),
                color: selectedCMEIndices.contains(index)
                    ? const Color(0xFF22C55E)
                    : Colors.white,
              ),
              child: selectedCMEIndices.contains(index)
                  ? const Icon(
                Icons.check,
                color: Colors.white,
                size: 16,
              )
                  : null,
            ),
          ),
          SizedBox(width: baseSize * 0.02),
          // 🟢 Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  moduleName,
                  style: TextStyle(
                    fontSize: baseSize * 0.038 * scale,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: baseSize * 0.01 * scale),
                Text(
                  "Score: ${quiz['score'] ?? '--'}%",
                  style: TextStyle(
                    fontSize: baseSize * 0.033 * scale,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  "Module ID: $moduleId",
                  style: TextStyle(
                    fontSize: baseSize * 0.033 * scale,
                    color: const Color(0xFF047857),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  "Date Submitted: $date",
                  style: TextStyle(
                    fontSize: baseSize * 0.032 * scale,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // 🧭 Helper Navigation
  // =====================================================
  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}