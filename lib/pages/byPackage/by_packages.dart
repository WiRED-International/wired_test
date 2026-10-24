import 'dart:convert';

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
import '../program_modules_page.dart';
import '../specialization_selection_page.dart';

class ByPackages extends StatefulWidget {
  const ByPackages({super.key});

  @override
  State<ByPackages> createState() => _ByPackagesState();
}

class _TrainingProgram {
  const _TrainingProgram({
    required this.id,
    required this.name,
    required this.trainingType,
    required this.description,
  });

  final int id;
  final String name;
  final String trainingType;
  final String description;

  factory _TrainingProgram.fromJson(Map<String, dynamic> json) {
    return _TrainingProgram(
      id: json['id'] as int,
      name: json['name'] as String,
      trainingType: json['training_type'] as String,
      description: json['description'] as String? ?? '',
    );
  }
}

class _Specialization {
  const _Specialization({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;

  factory _Specialization.fromJson(Map<String, dynamic> json) {
    return _Specialization(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }
}

class _Catalog {
  const _Catalog({
    required this.programs,
    required this.specializations,
  });

  final List<_TrainingProgram> programs;
  final List<_Specialization> specializations;
}

class _ByPackagesState extends State<ByPackages> {
  late Future<_Catalog> _catalog;

  static const _blue = Color(0xFF0070C0);
  static const _green = Color(0xFF548235);
  static const _navy = Color(0xFF183E59);

  @override
  void initState() {
    super.initState();
    _catalog = _fetchCatalog();
  }

  Future<List<dynamic>> _fetchList(String endpoint) async {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final response = await http
        .get(Uri.parse('$baseUrl$endpoint'))
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        'Catalog request failed (${response.statusCode})',
      );
    }

    final data = jsonDecode(response.body);

    if (data is! List) {
      throw const FormatException('Unexpected catalog response');
    }

    return data;
  }

  Future<_Catalog> _fetchCatalog() async {
    final results = await Future.wait([
      _fetchList('/learning-catalog/programs'),
      _fetchList('/learning-catalog/specializations'),
    ]);

    final programs = results[0]
        .map((item) => _TrainingProgram.fromJson(
              item as Map<String, dynamic>,
            ))
        .where((program) =>
            program.trainingType == 'basic' ||
            program.trainingType == 'act' ||
            program.trainingType == 'specialization')
        .toList();

    const order = {
      'basic': 0,
      'act': 1,
      'specialization': 2,
    };

    programs.sort((a, b) =>
        (order[a.trainingType] ?? 99).compareTo(order[b.trainingType] ?? 99));

    final specializations = results[1]
        .map((item) => _Specialization.fromJson(
              item as Map<String, dynamic>,
            ))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return _Catalog(
      programs: programs,
      specializations: specializations,
    );
  }

  void _open(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Future<void> _openMenu() async {
    final loggedIn = await checkIfUserIsLoggedIn();
    if (!mounted) return;

    _open(loggedIn ? Menu() : GuestMenu());
  }

  void _retry() {
    setState(() {
      _catalog = _fetchCatalog();
    });
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
              onHomeTap: () => _open(const MyHomePage()),
              onLibraryTap: () => _open(ModuleLibrary()),
              onTrackerTap: () => _open(AuthGuard(child: CreditsTracker())),
              onMenuTap: _openMenu,
            ),
      child: landscape
          ? Row(
              children: [
                CustomSideNavBar(
                  onHomeTap: () => _open(const MyHomePage()),
                  onLibraryTap: () => _open(ModuleLibrary()),
                  onTrackerTap: () => _open(AuthGuard(child: CreditsTracker())),
                  onMenuTap: _openMenu,
                ),
                Expanded(child: _buildContent()),
              ],
            )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return FutureBuilder<_Catalog>(
      future: _catalog,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 48,
                    color: _navy,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to load training programs',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          );
        }

        final catalog = snapshot.data!;

        return LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.school_outlined,
                        size: 54,
                        color: _blue,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Training Programs',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Explore community health worker training '
                        'programs and prepare modules for offline learning.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: Color(0xFF526B7C),
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (catalog.programs.isEmpty)
                        const Center(
                          child: Text('No training programs available'),
                        ),
                      for (final program in catalog.programs) ...[
                        _buildProgramCard(program),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProgramCard(_TrainingProgram program) {
    final isBasic = program.trainingType == 'basic';
    final isAct = program.trainingType == 'act';

    final color = isAct ? _green : _blue;
    final icon = isBasic
        ? Icons.school_outlined
        : isAct
            ? Icons.menu_book_outlined
            : Icons.layers_outlined;

    final title = isBasic
        ? 'Basic CHW Training'
        : isAct
            ? 'Advanced CHW Training (ACT)'
            : 'Specialization Programs';

    return InkWell(
      onTap: () {
        if (program.trainingType == 'specialization') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SpecializationSelectionPage(),
            ),
          );
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProgramModulesPage(
              title: program.trainingType == 'basic'
                  ? 'Basic CHW Training'
                  : 'Advanced CHW Training (ACT)',
              trainingType: program.trainingType,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: 0.22),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    program.description,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: Color(0xFF526B7C),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: color,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}
