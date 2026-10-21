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
import 'module_by_topic.dart';

class TopicList extends StatefulWidget {
  final String category;
  final int categoryId;

  const TopicList({super.key, required this.category, required this.categoryId});

  @override
  State<TopicList> createState() => _TopicListState();
}

class SubCategory {
  final String name;
  final int categoryId;
  final int subcategoryId;

  const SubCategory({
    required this.name,
    required this.categoryId,
    required this.subcategoryId,
  });

  factory SubCategory.fromJson(Map<String, dynamic> json) {
    int parseId(dynamic value) =>
        value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

    return SubCategory(
      name: json['name']?.toString().trim() ?? '',
      categoryId: parseId(json['category_id']),
      subcategoryId: parseId(json['id']),
    );
  }
}

class _TopicListState extends State<TopicList> {
  static const _blue = Color(0xFF16466A);
  static const _green = Color(0xFF358347);

  late Future<List<SubCategory>> _subcategories;

  @override
  void initState() {
    super.initState();
    _subcategories = _fetchSubcategories();
  }

  Future<List<SubCategory>> _fetchSubcategories() async {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final uri = Uri.parse(
      '${baseUrl.replaceAll(RegExp(r"/+$"), "")}/subCategories',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw Exception('Unable to load subcategories (HTTP ${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Unexpected subcategory response.');
    }

    final results = <SubCategory>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final subcategory = SubCategory.fromJson(Map<String, dynamic>.from(item));
      if (subcategory.categoryId == widget.categoryId &&
          subcategory.subcategoryId > 0 &&
          subcategory.name.isNotEmpty) {
        results.add(subcategory);
      }
    }
    results.sort((a, b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return results;
  }

  void _reload() {
    setState(() => _subcategories = _fetchSubcategories());
  }

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _openMenu() async {
    final loggedIn = await checkIfUserIsLoggedIn();
    if (!mounted) return;
    _open(loggedIn ? Menu() : GuestMenu());
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
          Expanded(child: _content()),
        ],
      )
          : _content(),
    );
  }

  Widget _content() {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {
            _reload();
            try {
              await _subcategories;
            } catch (_) {
              // The error state provides a retry button.
            }
          },
          child: FutureBuilder<List<SubCategory>>(
            future: _subcategories,
            builder: (context, snapshot) {
              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
                          child: Column(
                            children: [
                              Text(
                                widget.category,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.w700,
                                  color: _blue,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Select a subtopic to explore modules',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Color(0xFF607889),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (snapshot.connectionState != ConnectionState.done)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(color: Color(0xFF0070C0)),
                      ),
                    )
                  else if (snapshot.hasError)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _message(
                        Icons.wifi_off_rounded,
                        'Unable to load subtopics',
                        'Check your internet connection and try again.',
                        retry: true,
                      ),
                    )
                  else if ((snapshot.data ?? []).isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _message(
                          Icons.search_off_rounded,
                          'No subtopics available',
                          'There are no subtopics listed under this category.',
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (context, index) => Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 760),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _subcategoryCard(snapshot.data![index]),
                                ),
                              ),
                            ),
                            childCount: snapshot.data!.length,
                          ),
                        ),
                      ),
                ],
              );
            },
          ),
        ), // Closes RefreshIndicator before the fade overlay.
        // Subtle fade above the fixed navigation bar; scrolling remains interactive.
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
                  colors: [Color(0x00FFD09A), Color(0xFFFFD09A)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _subcategoryCard(SubCategory subcategory) {
    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _open(ModuleByTopic(
          subcategoryName: subcategory.name,
          subcategoryId: subcategory.subcategoryId,
        )),
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFD7E4EA)),
          ),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5EC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.topic_outlined, color: _green),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  subcategory.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _blue,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF0876D6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(IconData icon, String title, String detail,
      {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _green, size: 48),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: _blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF607889)),
            ),
            if (retry) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}