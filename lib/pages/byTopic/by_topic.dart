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
import 'topic_list.dart';

class ByTopic extends StatefulWidget {
  const ByTopic({super.key});

  @override
  State<ByTopic> createState() => _ByTopicState();
}

class Category {
  final String? name;
  final int? id;

  const Category({this.name, this.id});

  factory Category.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    return Category(
      name: json['name']?.toString(),
      id: rawId is int ? rawId : int.tryParse(rawId?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'id': id};
}

class _ByTopicState extends State<ByTopic> {
  static const _blue = Color(0xFF16466A);
  static const _green = Color(0xFF358347);

  late Future<List<Category>> futureCategories;

  @override
  void initState() {
    super.initState();
    futureCategories = fetchCategories();
  }

  Future<List<Category>> fetchCategories() async {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r"/+$"), "")}/categories');
    final response = await http.get(uri).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw Exception('Unable to load topics (HTTP ${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Unexpected categories response.');
    }

    final categories = decoded
        .whereType<Map>()
        .map((item) => Category.fromJson(Map<String, dynamic>.from(item)))
        .where((category) =>
    category.name != null &&
        category.name!.trim().isNotEmpty)
        .toList();

    // Deduplicate by category ID, not object identity.
    final seenIds = <int>{};
    final seenNames = <String>{};
    categories.retainWhere((category) {
      if (category.id != null) return seenIds.add(category.id!);
      return seenNames.add(category.name!.trim().toLowerCase());
    });
    categories.sort((a, b) =>
        a.name!.toLowerCase().compareTo(b.name!.toLowerCase()));
    return categories;
  }

  void _reload() {
    setState(() => futureCategories = fetchCategories());
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
            onTrackerTap: () =>
                _open(AuthGuard(child: CreditsTracker())),
            onMenuTap: _openMenu,
          ),
          Expanded(child: _content()),
        ],
      )
          : _content(),
    );
  }

  Widget _content() {
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        try {
          await futureCategories;
        } catch (_) {
          // The error state displays a retry button.
        }
      },
      child: FutureBuilder<List<Category>>(
        future: futureCategories,
        builder: (context, snapshot) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(20, 26, 20, 20),
                      child: Column(
                        children: [
                          Text(
                            'Browse by Topic',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w700,
                              color: _blue,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Select a health topic to explore modules',
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
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _message(
                    Icons.wifi_off_rounded,
                    'Unable to load topics',
                    'Check your connection and try again.',
                    retry: true,
                  ),
                )
              else if ((snapshot.data ?? []).isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _message(
                      Icons.search_off_rounded,
                      'No topics available',
                      'There are no topics to display right now.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                            (context, index) => Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _topicCard(snapshot.data![index]),
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
    );
  }

  Widget _topicCard(Category category) {
    return Material(
      color: Colors.white,
      elevation: 1.5,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _open(TopicList(
          category: category.name!,
          categoryId: category.id ?? 0,
        )),
        child: Container(
          constraints: const BoxConstraints(minHeight: 86),
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
                child: const Icon(Icons.category_outlined, color: _green),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  category.name!,
                  style: const TextStyle(
                    color: _blue,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
