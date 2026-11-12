import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_guard.dart';
import '../../providers/auth_provider.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/pdf_preview_screen.dart';
import '../../utils/pdf_utils.dart';
import '../../utils/side_nav_bar.dart';
import '../../utils/app_layout.dart';
import '../creditsTracker/credits_tracker.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import '../../models/user.dart';

enum _ProfileFailure { authentication, permission, server }

class CreditsHistory extends StatefulWidget {
  const CreditsHistory({Key? key}) : super(key: key);

  @override
  State<CreditsHistory> createState() => _CreditsHistoryState();
}

class _CreditsHistoryState extends State<CreditsHistory> {
  Future<User>? userData;
  AuthProvider? _auth;
  String? _sessionToken;
  int _session = 0;

  void _authChanged() {
    if (!mounted) return;
    final token = _auth!.isLoggedIn ? _auth!.authToken : null;
    if (token == _sessionToken) return;
    setState(() {
      _session++;
      _sessionToken = token;
      _selectedRecords.clear();
      userData = token == null ? null : fetchUserData();
    });
  }

  void _checkSession(int session) {
    if (!mounted || session != _session) {
      throw StateError('Profile request no longer belongs to this page session');
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_authChanged);
    _session++;
    super.dispose();
  }

  final _storage = const FlutterSecureStorage();
  bool showCreditsHistory = false;
  // Identity within this loaded snapshot distinguishes duplicate/missing IDs.
  final _selectedRecords = Set<Map>.identity();
  int? selectedYear;

  @override
  void initState() {
    super.initState();
    // Nullable lookup preserves standalone page previews/tests. Production
    // always supplies AuthProvider through the application provider tree.
    _auth = context.read<AuthProvider?>();
    _sessionToken = _auth?.isLoggedIn == true ? _auth!.authToken : null;
    _auth?.addListener(_authChanged);
    userData = _auth == null || _sessionToken != null ? fetchUserData() : null;

    // Default to current year
    selectedYear = DateTime.now().year;
  }

  Future<String?> getAuthToken() async {
    return await _storage.read(key: 'authToken');
  }

  Future<User> fetchUserData() {
    final load = _fetchUserData(_session, _sessionToken);
    // Observe promptly even when a session changes before the next build.
    load.ignore();
    return load;
  }

  Future<User> _fetchUserData(int session, String? sessionToken) async {
    final token = _auth == null ? await getAuthToken() : sessionToken;
    _checkSession(session);
    if (token == null) throw Exception('User not logged in');

    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final client = http.Client();
    final http.Response response;
    try {
      response = await client.get(
        Uri.parse('$apiBaseUrl/users/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));
    } finally {
      client.close();
    }

    _checkSession(session);
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return User.fromJson(json); // Parse the top-level response directly
    } else {
      if (response.statusCode == 401) throw _ProfileFailure.authentication;
      if (response.statusCode == 403) throw _ProfileFailure.permission;
      throw _ProfileFailure.server;
    }
  }

  Widget _profileError(Object? error) {
    final String message;
    if (error == _ProfileFailure.authentication) {
      message = 'Your session could not be verified. Please log in again.';
    } else if (error == _ProfileFailure.permission) {
      message =
          'You do not have permission to load this profile. Please contact support if this continues.';
    } else if (error is TimeoutException ||
        error is http.ClientException ||
        error is SocketException) {
      message =
          'Your profile could not be loaded. Check your connection and try again.';
    } else {
      message = 'Your profile could not be loaded. Please try again.';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(message, textAlign: TextAlign.center),
          TextButton(
            onPressed: refreshScores,
            child: const Text('Retry'),
          ),
        ]),
      ),
    );
  }

  void refreshScores() {
    if (!mounted || (_auth != null && _sessionToken == null)) return;
    setState(() {
      _selectedRecords.clear();
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

    return AppLayout(
      appBar: CustomAppBar(
        onBackPressed: () => Navigator.pop(context),
        requireAuth: true,
        scale: scale,
      ),

      bottomNav: CustomBottomNavBar(
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

      child: FutureBuilder<User>(
        key: ValueKey(_session),
        future: userData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return _profileError(snapshot.error);
          } else if (!snapshot.hasData) {
            return const Center(child: Text('No data available'));
          }

          final user = snapshot.data!;

          final allQuizScores = user.quizScores ?? [];

          final quizScores = allQuizScores
              .where(
                (q) =>
            q['module']?['credit_type']
                ?.toString()
                .toLowerCase() ==
                'cme',
          )
              .toList()
            ..sort((a, b) {
              final aDate = parseCreditHistoryDate(a['date_taken']);
              final bDate = parseCreditHistoryDate(b['date_taken']);
              if (aDate == null) return bDate == null ? 0 : 1;
              if (bDate == null) return -1;
              return bDate.compareTo(aDate);
            });
          final visibleScores = selectedYear == null
              ? quizScores
              : quizScores
                  .where((q) =>
                      parseCreditHistoryDate(q['date_taken'])?.year == selectedYear)
                  .toList();

          final creditsEarned = user.creditsEarned ?? 0;

          // ❗ IMPORTANT: no Center()
          return isLandscape
              ? Row(
            children: [
              CustomSideNavBar(
                onHomeTap: () =>
                    _navigateTo(context, const MyHomePage()),
                onLibraryTap: () =>
                    _navigateTo(context, ModuleLibrary()),
                onTrackerTap: () => _navigateTo(
                    context, AuthGuard(child: const CreditsTracker())),
                onMenuTap: () async {
                  bool isLoggedIn = await checkIfUserIsLoggedIn();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => isLoggedIn
                          ? const Menu()
                          : const GuestMenu(),
                    ),
                  );
                },
                scale: scale,
              ),

              Expanded(
                child: _buildLandscapeLayout(
                  context,
                  user,
                  quizScores,
                  visibleScores,
                  creditsEarned,
                  baseSize,
                  scale,
                ),
              ),
            ],
          )
              : _buildPortraitLayout(
            context,
            user,
            quizScores,
            visibleScores,
            creditsEarned,
            baseSize,
            scale,
          );
        },
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
      List<dynamic> visibleScores,
      int creditsEarned,
      double baseSize,
      double scale,
      ) {
    final dateFormatter = DateFormat('MMM dd, yyyy');
    // ✅ ADD THIS HERE
    final selectAll = visibleScores.isNotEmpty &&
        visibleScores.every(_selectedRecords.contains);
    final currentYear = DateTime.now().year;

    final years = {
      ...quizScores
          .map((q) => parseCreditHistoryDate(q['date_taken']))
          .whereType<DateTime>()
          .map((date) => date.year),
      currentYear,
    }.toList()
      ..sort((a, b) => b.compareTo(a)); // newest first

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
                          ...years,
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
                    onPressed: _selectedRecords.isNotEmpty
                        ? () async {
                      final session = _session;
                      late final File file;
                      try {
                        final selected = _selectedSnapshot(quizScores);
                        final pdfBytes = await generateCMEPdf(
                          firstName: user.firstName ?? '',
                          lastName: user.lastName ?? '',
                          email: user.email ?? '',
                          role: user.role ?? '',
                          country: user.country ?? '',
                          organization: user.organization ?? '',
                          quizScores: selected,
                          selectedIndices: Set<int>.from(
                              List.generate(selected.length, (i) => i)),
                        );

                        if (!context.mounted || !mounted || session != _session) return;
                        file = await generateAndSavePdfToFile(
                            pdfBytes, 'cme_history.pdf');
                      } catch (_) {
                        if (!mounted || session != _session) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(
                          content: Text(
                              'The PDF could not be created. Please try exporting again.'),
                        ));
                        return;
                      }
                      if (!context.mounted || !mounted || session != _session) return;

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
                        _toggleVisibleSelection(visibleScores, selectAll);
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
            child: visibleScores.isNotEmpty
                ? ListView.builder(
              itemCount: visibleScores.length,
              itemBuilder: (context, index) => _buildCreditCard(
                context,
                visibleScores[index],
                dateFormatter,
                baseSize,
                scale,
              ),
            )
                : Center(
              child: Text(
                "No CME records found for $selectedYear.",
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
      List<dynamic> visibleScores,
      int creditsEarned,
      double baseSize,
      double scale,
      ) {
    final selectAll = visibleScores.isNotEmpty &&
        visibleScores.every(_selectedRecords.contains);
    final currentYear = DateTime.now().year;

    final years = {
      ...quizScores
          .map((q) => parseCreditHistoryDate(q['date_taken']))
          .whereType<DateTime>()
          .map((date) => date.year),
      currentYear,
    }.toList()
      ..sort((a, b) => b.compareTo(a));
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
                              ...years,
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
                        onPressed: _selectedRecords.isNotEmpty
                            ? () async {
                          final session = _session;
                          late final File file;
                          try {
                            final selected = _selectedSnapshot(quizScores);
                            final pdfBytes = await generateCMEPdf(
                              firstName: user.firstName ?? '',
                              lastName: user.lastName ?? '',
                              email: user.email ?? '',
                              role: user.role ?? '',
                              country: user.country ?? '',
                              organization: user.organization ?? '',
                              quizScores: selected,
                              selectedIndices: Set<int>.from(
                                  List.generate(selected.length, (i) => i)),
                            );

                            if (!context.mounted || !mounted || session != _session) return;
                            file = await generateAndSavePdfToFile(
                              pdfBytes,
                              'cme_history.pdf',
                            );
                          } catch (_) {
                            if (!mounted || session != _session) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(
                              content: Text(
                                  'The PDF could not be created. Please try exporting again.'),
                            ));
                            return;
                          }
                          if (!context.mounted || !mounted || session != _session) return;

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
                      _toggleVisibleSelection(visibleScores, selectAll);
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
              itemCount: visibleScores.length,
              itemBuilder: (context, index) => _buildCreditCard(
                context,
                visibleScores[index],
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
  // Detach selected records before PDF generation awaits its asset read.
  List<dynamic> _selectedSnapshot(List<dynamic> orderedScores) =>
      List<dynamic>.unmodifiable(jsonDecode(jsonEncode(
          orderedScores.where(_selectedRecords.contains).toList())) as List);

  void _toggleVisibleSelection(List<dynamic> visibleScores, bool allSelected) {
    if (allSelected) {
      _selectedRecords.removeAll(visibleScores);
    } else {
      _selectedRecords
        ..clear()
        ..addAll(visibleScores.cast<Map>());
    }
  }

  Widget _buildCreditCard(BuildContext context, Map quiz,
      DateFormat formatter, double baseSize, double scale) {
    final module = quiz['module'];
    final moduleName = module?['name'] ?? 'Unknown';
    final moduleId = module?['module_id']?.toString() ?? 'N/A';
    final parsedDate = parseCreditHistoryDate(quiz['date_taken']);
    final date = parsedDate == null ? 'Invalid date' : formatter.format(parsedDate);
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
                if (_selectedRecords.contains(quiz)) {
                  _selectedRecords.remove(quiz);
                } else {
                  _selectedRecords.add(quiz);
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
                  color: _selectedRecords.contains(quiz)
                      ? const Color(0xFF22C55E)
                      : Colors.grey.shade400,
                  width: 1.8,
                ),
                color: _selectedRecords.contains(quiz)
                    ? const Color(0xFF22C55E)
                    : Colors.white,
              ),
              child: _selectedRecords.contains(quiz)
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
