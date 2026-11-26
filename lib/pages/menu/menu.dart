import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_guard.dart';
import '../../providers/auth_provider.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/landscape_profile_section.dart';
import '../../utils/profile_section.dart';
import '../../utils/side_nav_bar.dart';
import '../../utils/app_layout.dart';
import 'package:http/http.dart' as http;
import '../cme/login.dart';
import '../creditsTracker/credits_tracker.dart';
import '../exam/exam_start.dart';
import '../home_page.dart';
import '../module_library.dart';
import '../../models/user.dart';
import '../classes/classes_page.dart';

class Menu extends StatefulWidget {
  final void Function(Locale)? onLocaleChange;

  const Menu({Key? key, this.onLocaleChange}) : super(key: key);

  @override
  _MenuState createState() => _MenuState();
}

class _MenuState extends State<Menu> {
  late Future<User> userData;
  late final Future<String?> _installedVersion;
  final _storage = const FlutterSecureStorage();
  bool _isLoggingOut = false;
  bool _isDeletingAccount = false;
  AuthProvider? _deletionAuth;
  VoidCallback? _deletionAuthListener;
  VoidCallback? _invalidateDeletion;

  void _detachDeletionListener() {
    _invalidateDeletion?.call();
    _invalidateDeletion = null;
    final listener = _deletionAuthListener;
    if (listener != null) _deletionAuth?.removeListener(listener);
    _deletionAuth = null;
    _deletionAuthListener = null;
  }

  @override
  void dispose() {
    _detachDeletionListener();
    super.dispose();
  }

  bool isTablet(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final diagonal = sqrt(size.width * size.width + size.height * size.height);
    return diagonal > 1100;
  }

  double scaleForDevice(
    BuildContext context,
    double phoneValue,
    double tabletValue,
  ) {
    return isTablet(context) ? tabletValue : phoneValue;
  }

  @override
  void initState() {
    super.initState();
    userData = fetchUserData();
    _installedVersion = _loadInstalledVersion();
  }

  Future<String?> _loadInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (version.isEmpty || build.isEmpty) return null;
      return 'Version $version ($build)';
    } catch (_) {
      // Package metadata is optional and must not interrupt the menu.
      return null;
    }
  }

  Widget _buildVersionFooter() {
    return FutureBuilder<String?>(
      future: _installedVersion,
      builder: (context, snapshot) {
        final version = snapshot.data;
        if (version == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Center(
            child: Text(
              version,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    // AppLayout retains its light gradient in both themes.
                    color: Colors.black54,
                  ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusContent(Widget content) {
    // Keep local package information accessible even without a user response.
    return Center(
      child: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: content,
            ),
            _buildVersionFooter(),
          ],
        ),
      ),
    );
  }

  Future<String?> getAuthToken() async {
    return await _storage.read(key: 'authToken');
  }

  Future<User> fetchUserData() async {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final apiEndpoint = '/users/me';

    final token = await getAuthToken();
    if (token == null) {
      throw Exception('User is not logged in');
    }

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
      return User.fromJson(json); // Parse the top-level response directly
    } else {
      throw Exception('Failed to fetch user data: ${response.statusCode}');
    }
  }

  Future<void> deleteAccount() async {
    if (!mounted || _isDeletingAccount || _isLoggingOut) return;
    _isDeletingAccount = true;
    var deletionConfirmed = false;
    var invalidated = false;
    var signingOut = false;
    var logoutObserved = false;
    _invalidateDeletion = () => invalidated = true;
    try {
      final auth = context.read<AuthProvider>();
      final token = auth.authToken;
      if (!auth.isLoggedIn || token == null) return;
      String? observedToken = token;
      var observedLoggedIn = auth.isLoggedIn;
      _deletionAuth = auth;
      _deletionAuthListener = () {
        if (observedToken == auth.authToken &&
            observedLoggedIn == auth.isLoggedIn) {
          return;
        }
        observedToken = auth.authToken;
        observedLoggedIn = auth.isLoggedIn;
        // Our successful logout is the one expected session transition.
        if (signingOut &&
            !logoutObserved &&
            !auth.isLoggedIn &&
            auth.authToken == null) {
          logoutObserved = true;
        } else {
          invalidated = true;
        }
      };
      auth.addListener(_deletionAuthListener!);
      bool ownsSession() =>
          mounted && !invalidated && auth.isLoggedIn && auth.authToken == token;

      final decision = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text("Delete Account"),
          content: Text("Are you sure? This cannot be undone."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text("Delete"),
            ),
          ],
        ),
      );
      if (decision != true || !ownsSession()) return;
      final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
      final response = await http.delete(
        Uri.parse('$apiBaseUrl/auth/delete-account'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
      if (!mounted || !ownsSession()) return;
      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Failed to delete account. Please try again.")),
        );
        return;
      }
      deletionConfirmed = true;
      signingOut = true;
      final loggedOut = await auth.logOut(
        // Capture operation-local data, not the page State or BuildContext.
        ifOwned: () =>
            !invalidated && auth.isLoggedIn && auth.authToken == token,
      );
      if (!loggedOut) return;
      if (!mounted ||
          invalidated ||
          !logoutObserved ||
          auth.isLoggedIn ||
          auth.authToken != null) {
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => Login()),
      );
    } catch (_) {
      if (mounted && !invalidated) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(deletionConfirmed
                  ? "Account deletion was confirmed, but local sign-out failed. Please try signing out."
                  : "Unable to confirm account deletion. The request may have reached the server. Please check your connection and try again.")),
        );
      }
    } finally {
      _detachDeletionListener();
      _isDeletingAccount = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    return AppLayout(
      // 🔹 No AppBar on this page (you didn’t have one before)
      appBar: null,

      bottomNav: isLandscape
          ? null
          : CustomBottomNavBar(
              onHomeTap: () => _navigateTo(context, const MyHomePage()),
              onLibraryTap: () => _navigateTo(context, ModuleLibrary()),
              onTrackerTap: () => _openTracker(context),
              onMenuTap: () {},
            ),

      // ❗ IMPORTANT: no Center()
      child: FutureBuilder<User>(
        future: userData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildStatusContent(const CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return _buildStatusContent(
                Text('Error: ${snapshot.error}', textAlign: TextAlign.center));
          } else if (!snapshot.hasData) {
            return _buildStatusContent(const Text('No data available'));
          }

          final user = snapshot.data!;
          final int creditsEarned = user.creditsEarned ?? 0;

          return isLandscape
              ? Row(
                  children: [
                    // 🧭 Side Nav
                    SizedBox(
                      width: screenSize.width * 0.12,
                      child: CustomSideNavBar(
                        onHomeTap: () =>
                            _navigateTo(context, const MyHomePage()),
                        onLibraryTap: () =>
                            _navigateTo(context, ModuleLibrary()),
                        onTrackerTap: () => _openTracker(context),
                        onMenuTap: () {},
                      ),
                    ),

                    // 🧩 Content
                    Expanded(
                      child: Column(
                        children: [
                          LandscapeProfileSection(
                            firstName: user.firstName ?? 'Guest',
                            dateJoined: user.dateJoined ?? 'Unknown',
                            email: user.email ?? '',
                            creditsEarned: creditsEarned,
                          ),
                          SizedBox(
                            height: screenSize.height * 0.05,
                          ),
                          Expanded(
                            child: _buildLandscapeLayout(
                              context,
                              user,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    ProfileSection(
                      firstName: user.firstName ?? 'Guest',
                      dateJoined: user.dateJoined ?? 'Unknown',
                      email: user.email ?? '',
                      creditsEarned: creditsEarned,
                    ),
                    Expanded(
                      child: _buildPortraitLayout(
                        context,
                        user,
                      ),
                    ),
                  ],
                );
        },
      ),
    );
  }

// Navigation Helper
  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  void _openTracker(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AuthGuard(child: CreditsTracker()),
      ),
    );
  }

  Widget _buildPortraitLayout(
    BuildContext context,
    User user,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;

    double fontBase = screenWidth * scaleForDevice(context, 0.04, 0.032);
    double iconBase = screenWidth * scaleForDevice(context, 0.055, 0.04);
    double cardPadding = screenWidth * scaleForDevice(context, 0.045, 0.03);
    double titleSize = screenWidth * scaleForDevice(context, 0.05, 0.033);

    return _buildMenuContent(
      context,
      user,
      fontBase: fontBase,
      iconBase: iconBase,
      cardPadding: cardPadding,
      titleSize: titleSize,
      topSpacing: screenWidth * 0.08,
      sectionSpacing: screenWidth * 0.15,
      horizontalPadding: screenWidth * 0.06,
      headingSpacing: screenWidth * 0.03,
    );
  }

  Widget _buildTopButtons(
    BuildContext context,
    User user,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildInkWellButton(context, 'About WiRED', () async {
              final Uri url = Uri.parse(
                'https://sites.google.com/view/healthmap-about/home',
              );

              if (await canLaunchUrl(url)) {
                await launchUrl(
                  url,
                  mode: LaunchMode.externalApplication,
                );
              }
            }),
            _buildInkWellButton(context, 'Classes', () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ClassesPage(),
                ),
              );
            }),
          ],
        ),
        SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildInkWellButton(context, 'Privacy Policy', () async {
              final Uri url = Uri.parse(
                  'https://sites.google.com/view/healthmapprivacypolicy/home');
              if (await canLaunchUrl(url))
                await launchUrl(url, mode: LaunchMode.externalApplication);
            }),
            _buildInkWellButton(context, 'Exams', () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ExamStart(user: user)),
              );
            }),
          ],
        )
      ],
    );
  }

  Widget _buildAccountCard(
    BuildContext context,
    double fontBase,
    double iconBase,
    double padding,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCEDDA).withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 3),
          )
        ],
      ),
      child: Column(
        children: [
          _buildAccountRow(
            context,
            icon: Icons.download_outlined,
            label: "Request Data Deletion",
            color: Color(0xFF0070C0),
            fontSize: fontBase,
            iconSize: iconBase,
            padding: padding,
            onTap: () async {
              final Uri deleteAccountUri = Uri.parse(
                  "https://sites.google.com/view/wired-international-healthmap/home");
              if (await canLaunchUrl(deleteAccountUri)) {
                await launchUrl(deleteAccountUri,
                    mode: LaunchMode.externalApplication);
              } else {
                if (!context.mounted) return;
                _showCopyDeleteAccountDialog(context, deleteAccountUri);
              }
            },
          ),
          _responsiveDivider(),
          _buildAccountRow(
            context,
            icon: Icons.logout,
            label: "Log out",
            color: Color(0xFF0070C0),
            fontSize: fontBase,
            iconSize: iconBase,
            padding: padding,
            onTap: () async {
              if (_isLoggingOut || _isDeletingAccount) return;
              _isLoggingOut = true;
              try {
                await Provider.of<AuthProvider>(context, listen: false)
                    .logOut();
                if (!context.mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => Login()),
                );
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Unable to log out. Please try again.")),
                  );
                }
              } finally {
                _isLoggingOut = false;
              }
            },
          ),
          _responsiveDivider(),
          _buildAccountRow(
            context,
            icon: Icons.delete_outline,
            label: "Delete Account",
            color: Colors.red,
            fontSize: fontBase,
            iconSize: iconBase,
            padding: padding,
            onTap: deleteAccount,
          ),
        ],
      ),
    );
  }

  Widget _responsiveDivider() {
    return Container(
      height: 1,
      color: Colors.black.withOpacity(0.12),
      margin: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _buildAccountRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required double fontSize,
    required double iconSize,
    required double padding,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: padding * 0.8,
          horizontal: padding,
        ),
        child: Row(
          children: [
            Icon(icon, size: iconSize, color: color),
            SizedBox(width: padding * 0.6),
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                color: color,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInkWellButton(
    BuildContext context,
    String text,
    VoidCallback onTap,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    // Use height in landscape, width in portrait
    final base = isLandscape
        ? mediaQuery.size.height // prevent huge buttons
        : mediaQuery.size.width;

    // Fully responsive values
    double buttonWidth = base * scaleForDevice(context, 0.40, 0.28);
    double buttonHeight = base * scaleForDevice(context, 0.20, 0.14);
    double fontSize = base * scaleForDevice(context, 0.040, 0.026);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.grey.withOpacity(0.25),
        child: Container(
          width: buttonWidth,
          height: buttonHeight,
          decoration: BoxDecoration(
            color: const Color(0xFFFCEDDA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 6,
                offset: const Offset(3, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(
    BuildContext context,
    User user,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive values
    double fontBase = screenWidth * scaleForDevice(context, 0.026, 0.016);
    double iconBase = screenWidth * scaleForDevice(context, 0.034, 0.022);
    double cardPadding = screenWidth * scaleForDevice(context, 0.026, 0.018);
    double titleSize = screenWidth * scaleForDevice(context, 0.030, 0.020);

    return _buildMenuContent(
      context,
      user,
      fontBase: fontBase,
      iconBase: iconBase,
      cardPadding: cardPadding,
      titleSize: titleSize,
      topSpacing: screenHeight * 0.04,
      sectionSpacing: screenHeight * 0.08,
      horizontalPadding: screenWidth * 0.05,
      headingSpacing: screenHeight * 0.02,
    );
  }

  Widget _buildMenuContent(
    BuildContext context,
    User user, {
    required double fontBase,
    required double iconBase,
    required double cardPadding,
    required double titleSize,
    required double topSpacing,
    required double sectionSpacing,
    required double horizontalPadding,
    required double headingSpacing,
  }) {
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(height: topSpacing),
            _buildTopButtons(context, user),
            SizedBox(height: sectionSpacing),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Account Management",
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: headingSpacing),
                  _buildAccountCard(
                    context,
                    fontBase,
                    iconBase,
                    cardPadding,
                  ),
                ],
              ),
            ),
            SizedBox(height: sectionSpacing),
            _buildVersionFooter(),
          ],
        ),
      ),
    );
  }

  void _showCopyDeleteAccountDialog(
      BuildContext context, Uri deleteAccountUri) {
    final url = deleteAccountUri.toString();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Unable to Open Link"),
        content: SelectableText(
          "Please manually open this link in your browser:\n\n$url",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.of(context, rootNavigator: true).pop(); // Close dialog
            },
            child: Text("Copy Link"),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pop(); // Close dialog
            },
            child: Text("Close"),
          ),
        ],
      ),
    );
  }
}
