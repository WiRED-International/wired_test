import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_guard.dart';
import '../utils/app_layout.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import '../utils/updateChecker.dart';
import 'creditsTracker/credits_tracker.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
import 'module_details_page.dart';
import '../services/module_catalog_service.dart';
import 'module_library.dart';
import 'search.dart';

const _ink = Color(0xFF16466A);
const _blue = Color(0xFF0070C0);
const _green = Color(0xFF358347);

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, this.title, this.onLocaleChange});

  final String? title;
  final void Function(Locale)? onLocaleChange;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class Alert {
  String? alert;
  bool? important;

  Alert({this.alert, this.important});

  Alert.fromJson(Map<String, dynamic> json)
      : alert = json['alert'] as String?,
        important = json['important'] as bool?;

  Map<String, dynamic> toJson() => {
    'alert': alert,
    'important': important,
  };
}

class _MyHomePageState extends State<MyHomePage> {
  String alert = '';
  bool isImportant = false;
  bool _loadingAlert = true;

  Future<Alert?> getAlert() async {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/alerts/latest'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return Alert.fromJson(data);
      } else {
        debugPrint('Failed to load alert: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching alert: $e');
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _refreshAlert();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateChecker.checkForUpdate(context);
    });
  }

  Future<void> _refreshAlert() async {
    final result = await getAlert();
    if (!mounted) return;
    setState(() {
      alert = result?.alert ?? '';
      isImportant = result?.important ?? false;
      _loadingAlert = false;
    });
  }

  void _openModules() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Search()));
  }

  void _openLibrary() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ModuleLibrary()));
  }

  void _openTracker() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AuthGuard(child: CreditsTracker())),
    );
  }

  Future<void> _openMenu() async {
    final loggedIn = await checkIfUserIsLoggedIn();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => loggedIn ? Menu() : GuestMenu()),
    );
  }

  Future<void> _handleAlertLink(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    if (uri.scheme == 'app') {
      if (uri.host != 'module' || uri.pathSegments.length != 1) {
        _showAlertMessage('This module link is not supported.');
        return;
      }

      final id = int.tryParse(uri.pathSegments.single);
      if (id == null || id <= 0) {
        _showAlertMessage('Invalid module link.');
        return;
      }

      try {
        final modules = await ModuleCatalogService().fetchModules();
        if (!mounted) return;

        final matches = modules.where((module) => module.id == id);
        if (matches.isEmpty) {
          _showAlertMessage('This module is currently unavailable.');
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ModuleDetailsPage(module: matches.first),
          ),
        );
      } catch (error) {
        debugPrint('Unable to open module from alert: $error');
        if (mounted) {
          _showAlertMessage(
            'Unable to load the module. Check your internet connection and try again.',
          );
        }
      }
      return;
    }

    if (uri.scheme != 'https' && uri.scheme != 'http') {
      _showAlertMessage('This link type is not supported.');
      return;
    }

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('Could not launch $url');
        if (mounted) _showAlertMessage('Unable to open this link.');
      }
    } catch (error) {
      debugPrint('Error opening alert link: $error');
      if (mounted) _showAlertMessage('Unable to open this link.');
    }
  }

  void _showAlertMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return AppLayout(
      bottomNav: landscape
          ? null
          : CustomBottomNavBar(
        onHomeTap: () {},
        onLibraryTap: _openLibrary,
        onTrackerTap: _openTracker,
        onMenuTap: _openMenu,
      ),
      child: landscape
          ? Row(
        children: [
          CustomSideNavBar(
            onHomeTap: () {},
            onLibraryTap: _openLibrary,
            onTrackerTap: _openTracker,
            onMenuTap: _openMenu,
          ),
          Expanded(child: _page()),
        ],
      )
          : _page(),
    );
  }

  Widget _page() {
    return RefreshIndicator(
      color: _green,
      onRefresh: _refreshAlert,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 680;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(wide ? 32 : 22, 20, wide ? 32 : 22, 46),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: wide ? 16 : 25),
                    Semantics(
                      label: 'WiRED International Community Health Education',
                      child: Image.asset(
                        'assets/images/wired-logo-home.webp',
                        width: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                        const Center(child: Text('WiRED INTERNATIONAL',
                            style: TextStyle(color: _ink, fontSize: 26,
                                fontWeight: FontWeight.bold))),
                      ),
                    ),
                    SizedBox(height: wide ? 42 : 54),
                    const Text(
                      'HealthMAP',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Community Health Worker Training & Continuing Medical Education',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _ink,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: FilledButton(
                          onPressed: _openModules,
                          style: FilledButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Explore Modules',
                                  style: TextStyle(fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                              SizedBox(width: 12),
                              Icon(Icons.arrow_forward_rounded, size: 19),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 52),
                    const Divider(color: Color(0xFFB9D9E9), thickness: 1),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('News & Updates',
                              style: TextStyle(color: _ink, fontSize: 19,
                                  fontWeight: FontWeight.w700)),
                        ),
                        IconButton(
                          tooltip: 'Refresh news',
                          onPressed: _refreshAlert,
                          icon: const Icon(Icons.refresh_rounded, color: _ink),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _updatesCard(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _updatesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9EAF7)),
      ),
      child: _loadingAlert
          ? const Center(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: CircularProgressIndicator(color: _green),
        ),
      )
          : MarkdownBody(
        data: alert.isNotEmpty ? alert : 'No updates available.',
        onTapLink: (text, url, title) => _handleAlertLink(url),
        styleSheet: MarkdownStyleSheet(
          a: const TextStyle(
            color: _blue,
            decoration: TextDecoration.underline,
            decorationColor: _blue,
            fontWeight: FontWeight.w700,
          ),
          p: TextStyle(
            color: isImportant ? const Color(0xFFB3261E) : _ink,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}


