import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../providers/auth_guard.dart';
import '../utils/app_layout.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'creditsTracker/credits_tracker.dart';
import 'home_page.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
import 'module_library.dart';
import 'program_modules_page.dart';

class SpecializationSelectionPage extends StatefulWidget {
  const SpecializationSelectionPage({super.key});

  @override
  State<SpecializationSelectionPage> createState() =>
      _SpecializationSelectionPageState();
}

class _SpecializationSelectionPageState
    extends State<SpecializationSelectionPage> {
  late Future<List<String>> _specializations;

  static const _blue = Color(0xFF0070C0);
  static const _navy = Color(0xFF183E59);

  @override
  void initState() {
    super.initState();
    _specializations = _fetchSpecializations();
  }

  Future<List<String>> _fetchSpecializations() async {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final response = await http
        .get(Uri.parse('$baseUrl/learning-catalog/specializations'))
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Unable to load specializations');
    }

    final data = jsonDecode(response.body);

    if (data is! List) {
      throw const FormatException('Unexpected response');
    }

    return data
        .map((item) => item['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList()
      ..sort();
  }

  IconData _iconFor(String name) {
    switch (name.toLowerCase()) {
      case 'infectious diseases':
        return Icons.health_and_safety_outlined;
      case 'maternal & child health':
        return Icons.favorite_outline;
      case 'mental health':
        return Icons.psychology_outlined;
      case 'non-communicable diseases':
        return Icons.monitor_heart_outlined;
      default:
        return Icons.menu_book_outlined;
    }
  }

  void _openSpecialization(String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProgramModulesPage(
          title: name,
          trainingType: 'specialization',
          specializationName: name,
        ),
      ),
    );
  }

  void _openNavigationPage(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Future<void> _openNavigationMenu() async {
    final loggedIn = await checkIfUserIsLoggedIn();

    if (!mounted) return;

    _openNavigationPage(loggedIn ? Menu() : GuestMenu());
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return AppLayout(
      appBar: CustomAppBar(
        onBackPressed: () => Navigator.pop(context),
        requireAuth: false,
      ),
      bottomNav: landscape
          ? null
          : CustomBottomNavBar(
              onHomeTap: () => _openNavigationPage(const MyHomePage()),
              onLibraryTap: () => _openNavigationPage(ModuleLibrary()),
              onTrackerTap: () => _openNavigationPage(
                AuthGuard(child: CreditsTracker()),
              ),
              onMenuTap: _openNavigationMenu,
            ),
      child: landscape
          ? Row(
              children: [
                CustomSideNavBar(
                  onHomeTap: () => _openNavigationPage(const MyHomePage()),
                  onLibraryTap: () => _openNavigationPage(ModuleLibrary()),
                  onTrackerTap: () => _openNavigationPage(
                    AuthGuard(child: CreditsTracker()),
                  ),
                  onMenuTap: _openNavigationMenu,
                ),
                Expanded(child: _buildContent()),
              ],
            )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: FutureBuilder<List<String>>(
              future: _specializations,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(color: _blue),
                  );
                }

                if (snapshot.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Unable to load specializations. '
                        'Please check your connection.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final specializations = snapshot.data ?? [];

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 110),
                  children: [
                    const Icon(
                      Icons.layers_outlined,
                      size: 52,
                      color: _blue,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Specialization Programs',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.bold,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Choose a specialized area of community '
                      'health training.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Color(0xFF526B7C),
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (specializations.isEmpty)
                      const Center(
                        child: Text(
                          'No specializations available',
                        ),
                      ),
                    for (final name in specializations) ...[
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () => _openSpecialization(name),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFD7E4EA),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE7F1FA),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _iconFor(name),
                                    color: _blue,
                                    size: 27,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: _navy,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: _blue,
                                  size: 28,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 100,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00FFD09A),
                    Color(0xFFFFD09A),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
