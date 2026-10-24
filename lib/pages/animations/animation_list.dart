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
import 'animation_info.dart';

class AnimationList extends StatefulWidget {
  const AnimationList({super.key});

  @override
  State<AnimationList> createState() => _AnimationListState();
}

// Keep the existing model name and fields for compatibility.
class Animation {
  int? id;
  String? name;
  String? description;
  String? downloadLink;

  Animation({this.id, this.name, this.description, this.downloadLink});

  Animation.fromJson(Map<String, dynamic> json)
      : id = json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}'),
        name = json['name']?.toString(),
        description = json['description']?.toString(),
        downloadLink = json['downloadLink']?.toString();

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'downloadLink': downloadLink,
  };
}

class _AnimationListState extends State<AnimationList> {
  static const Color _blue = Color(0xFF0070C0);
  static const Color _darkBlue = Color(0xFF16466A);
  static const Color _border = Color(0xFFD7E4EA);

  late Future<List<Animation>> futureAnimations;

  @override
  void initState() {
    super.initState();
    futureAnimations = fetchAnimations();
  }

  Future<List<Animation>> fetchAnimations() async {
    final base = (dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000')
        .replaceFirst(RegExp(r'/$'), '');
    final response = await http
        .get(Uri.parse('$base/modules?type=animation'))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw Exception('Unable to load animations (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Unexpected animations response.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Animation.fromJson)
        .where((animation) => (animation.name ?? '').trim().isNotEmpty)
        .toList();
  }

  void _refresh() {
    setState(() => futureAnimations = fetchAnimations());
  }

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _openMenu() async {
    final loggedIn = await checkIfUserIsLoggedIn();
    if (!mounted) return;
    _open(loggedIn ? Menu() : GuestMenu());
  }

  void _openAnimation(Animation animation) {
    _open(AnimationInfo(
      animationId: animation.id ?? 0,
      animationName: animation.name ?? 'Unknown Animation',
      animationDescription: animation.description ?? '',
      downloadLink: animation.downloadLink ?? '',
    ));
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
    return SafeArea(
      top: false,
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
                child: Column(
                  children: [
                    const Text(
                      'Animations',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: _darkBlue,
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      'Explore health education through animated lessons.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: _darkBlue),
                    ),

                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Animation>>(
                  future: futureAnimations,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: _blue),
                      );
                    }
                    if (snapshot.hasError) {
                      return _messageState(
                        Icons.wifi_off_rounded,
                        'Unable to load animations',
                        'Check your connection and try again.',
                        showRetry: true,
                      );
                    }
                    final animations = snapshot.data ?? <Animation>[];
                    if (animations.isEmpty) {
                      return _messageState(
                        Icons.movie_outlined,
                        'No animations available',
                        'Check back later for new animated lessons.',
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      itemCount: animations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final animation = animations[index];
                        return Material(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _openAnimation(animation),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 17,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _border),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.play_circle_outline_rounded,
                                    color: _blue,
                                    size: 29,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      animation.name ?? '',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: _darkBlue,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: _blue,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageState(
      IconData icon,
      String title,
      String detail, {
        bool showRetry = false,
      }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _darkBlue, size: 42),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _darkBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
            if (showRetry) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
