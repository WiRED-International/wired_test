import '../../models/quiz_result_validation.dart';
import '../../services/pending_quiz_score_repository.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:wired_test/pages/creditsTracker/credits_tracker.dart';
import '../../providers/auth_guard.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cme_award_provider.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../../utils/app_layout.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';

class SubmitCredits extends StatefulWidget {
  const SubmitCredits({
    super.key,
    this.submissionTimeout = const Duration(seconds: 30),
  }) : assert(submissionTimeout > Duration.zero);

  final Duration submissionTimeout;

  @override
  State<SubmitCredits> createState() => _SubmitCreditsState();
}

class ModuleFile {
  final FileSystemEntity? file;
  final String? path;
  final String moduleName;
  final String? moduleId;
  final double? score;
  final Map<String, dynamic> pendingEntry;

  ModuleFile({
    this.file,
    this.path,
    required this.moduleName,
    this.moduleId,
    this.score,
    required Map<String, dynamic> pendingEntry,
  }) : pendingEntry = Map.unmodifiable(
            jsonDecode(jsonEncode(pendingEntry)) as Map<String, dynamic>);
}

enum DisplayType { modules, resources }

class _SubmitCreditsState extends State<SubmitCredits> {
  late Future<List<ModuleFile>> futureModules;
  late Future<List<FileSystemEntity>> futureResources; // For PDF resources
  List<ModuleFile> modules = [];
  // List<FileSystemEntity> resources = []; // Store PDF files
  DisplayType selectedType =
      DisplayType.modules; // To track whether Modules or Resources are selected
  final secureStorage = const FlutterSecureStorage();
  late final PendingQuizScoreRepository _pendingScores;
  final _submittingIds = <String>{};
  final _submittedIds = <String>{};
  late final AuthProvider _auth;
  String? _sessionToken;
  int _session = 0;

  void _authChanged() {
    final token = _auth.isLoggedIn ? _auth.authToken : null;
    if (token == _sessionToken) return;
    _sessionToken = token;
    _session++;
  }

  @override
  void dispose() {
    _auth.removeListener(_authChanged);
    _session++;
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _sessionToken = _auth.isLoggedIn ? _auth.authToken : null;
    _auth.addListener(_authChanged);
    _pendingScores = context.read<PendingQuizScoreRepository>();
    futureModules = _loadPendingScores();
  }

  Future<List<ModuleFile>> _loadPendingScores() {
    final load = _fetchModulesFromSecureStorage();
    // A fast refresh failure can precede the next FutureBuilder build. Observe
    // it immediately; FutureBuilder still receives this same failed future.
    load.ignore();
    return load;
  }

  Future<List<ModuleFile>> _fetchModulesFromSecureStorage() async {
    try {
      final storedScores = await _pendingScores.readAll();
      if (storedScores.isNotEmpty) {
        List<ModuleFile> fetchedModules = [];

        storedScores.forEach((moduleId, moduleData) {
          if (moduleData is Map<String, dynamic>) {
            String moduleName = moduleData['module_name'] ?? 'Unknown Module';
            double? parsedScore = validQuizScore(moduleData['score']);

            fetchedModules.add(ModuleFile(
              moduleId: moduleId,
              moduleName: moduleName,
              score: parsedScore,
              pendingEntry: moduleData,
            ));
          }
        });
        print(
            "📦 Loaded ${storedScores.length} pending quiz scores from Secure Storage");
        fetchedModules.sort((a, b) => a.moduleName.compareTo(b.moduleName));

        if (mounted) {
          setState(() {
            modules = fetchedModules;
          });
        }

        return fetchedModules;
      } else {
        print("ℹ️ No stored modules found in Secure Storage.");
        return [];
      }
    } catch (e) {
      print("❌ Error fetching modules from Secure Storage: $e");
      rethrow;
    }
  }

  Future<void> _handleSubmit(
      BuildContext context, ModuleFile moduleFile) async {
    final id = moduleFile.moduleId;
    if (id == null ||
        _submittingIds.contains(id) ||
        _submittedIds.contains(id)) {
      return;
    }
    final score = validQuizScore(moduleFile.score);
    if (score == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('A valid score from 0 to 100 is required to submit.')),
      );
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final cmeAwardProvider = context.read<CmeAwardProvider>();
    final token = authProvider.authToken;

    if (token == null || token.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Please log in before submitting. Your score remains saved on this device.'),
      ));
      return;
    }

    final session = _session;
    bool ownsSession() => session == _session &&
        authProvider.isLoggedIn && authProvider.authToken == token;
    _submittingIds.add(id);
    var submissionAccepted = false;
    try {
      final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
      final apiEndpoint = '/quiz-scores';

      // 🔥 NORMALIZE MODULE ID (SAFE VERSION)
      final rawId = moduleFile.moduleId ?? "";

      final normalizedId = rawId.replaceAll(RegExp(r'[^0-9]'), '');

      final finalId = normalizedId.length > 4
          ? normalizedId.substring(normalizedId.length - 4)
          : normalizedId;

      print("📦 Raw ID: $rawId");
      print("📦 Normalized ID: $normalizedId");
      print("📦 Final ID (last 4): $finalId");

      final client = http.Client();
      final http.Response response;
      try {
        response = await client
            .post(
              Uri.parse('$apiBaseUrl$apiEndpoint'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: json.encode({
                'module_id': finalId,
                'score': score,
                'date_taken': DateTime.now().toIso8601String(),
              }),
            )
            .timeout(widget.submissionTimeout);
      } finally {
        client.close();
      }

      if (response.statusCode == 201 || response.statusCode == 200) {
        submissionAccepted = true;
        _submittedIds.add(id); // Preserve confirmed success through navigation.
        final cleanupOutcome =
            await _cleanupSubmittedScore(id, moduleFile.pendingEntry);
        final cleanupComplete = cleanupOutcome != null;
        if (cleanupOutcome == PendingScoreRemovalOutcome.changed) {
          _submittedIds
              .remove(id); // The preserved result has not been submitted.
        }
        if (!ownsSession()) return;
        unawaited(cmeAwardProvider.fetchAwardedModules(forceRefresh: true));
        if (!context.mounted) return;

        print(
            "✅ Submission confirmed for ${moduleFile.moduleName}; local cleanup complete: $cleanupComplete.");

        // Refresh the module list after deletion
        setState(() {
          futureModules = _loadPendingScores();
        });

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Success'),
              content: Text(cleanupComplete
                  ? (cleanupOutcome == PendingScoreRemovalOutcome.changed
                      ? 'Your score has been submitted successfully! A newer saved result was kept and remains available to submit.'
                      : 'Your score has been submitted successfully!')
                  : 'Your score has been submitted successfully! Local cleanup was incomplete. '
                      'The saved copy may still appear. Do not submit it again.'),
              actions: [
                TextButton(
                  onPressed: () {
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    if (!mounted || !ownsSession()) return;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AuthGuard(
                          child: CreditsTracker(),
                        ),
                      ),
                    );
                  },
                  child: Text('OK'),
                ),
              ],
            );
          },
        );
      } else {
        String? backendMessage;
        try {
          final responseData = jsonDecode(response.body);
          if (responseData is Map<String, dynamic>) {
            final message = responseData['message'];
            if (message is String && message.trim().isNotEmpty) {
              backendMessage = message.trim();
            }
          }
        } catch (e) {
          debugPrint('Could not parse quiz submission error response: $e');
        }

        final String errorMessage;
        switch (response.statusCode) {
          case 401:
            errorMessage =
                'Your session is no longer valid. Please log in again. '
                'Your score remains saved on this device.';
            break;
          case 403:
            errorMessage = 'This score could not be submitted. '
                '${backendMessage ?? "You do not currently have permission to submit it. Please contact support if this continues."} '
                'Your score remains saved on this device.';
            break;
          case 404:
            errorMessage =
                'The requested module could not be found or is unavailable. '
                'Your score remains saved on this device. Please contact support if this continues.';
            break;
          default:
            errorMessage =
                '${backendMessage ?? "Failed to submit score. Please try again."} '
                'Your score remains saved on this device.';
        }

        if (context.mounted && ownsSession()) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
            ),
          );
        }
      }
    } catch (e) {
      if (submissionAccepted) {
        debugPrint('Score submitted; subsequent operation failed: $e');
      } else if (context.mounted && ownsSession()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'The submission could not be confirmed. Your score remains saved on this device. Check your connection before trying again.')),
        );
      }
    } finally {
      _submittingIds.remove(id);
    }
  }

  void _retryLoad() {
    setState(() {
      futureModules = _loadPendingScores();
    });
  }

  Widget _loadError() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Saved scores could not be loaded. Please try again. Your saved data has not been reset.',
              textAlign: TextAlign.center),
          TextButton(onPressed: _retryLoad, child: const Text('Retry')),
        ]),
      );

  void _showDeleteConfirmation(String fileName, String moduleId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Delete Module"),
          content: Text(
              "Are you sure you want to remove this saved score for the module: $fileName? If you already submitted this score, it will still be stored in your account."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the modal
              },
              child: Text("Do not delete"),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close the modal

                final removed = await deleteStoredScore(moduleId);
                if (!context.mounted) return;
                if (!removed) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'The saved score could not be removed. Please try again.'),
                  ));
                }

                // 🔁 Force FutureBuilder + UI to rebuild
                setState(() {
                  futureModules = _loadPendingScores();
                });
              },
              child: Text("Yes, delete"),
            ),
          ],
        );
      },
    );
  }

  Future<PendingScoreRemovalOutcome?> _cleanupSubmittedScore(
      String moduleId, Map<String, dynamic> submittedEntry) async {
    try {
      return await _pendingScores.removeIfUnchanged(moduleId, submittedEntry);
    } catch (error) {
      debugPrint('Score submitted; local cleanup failed: $error');
      return null;
    }
  }

  Future<bool> deleteStoredScore(String moduleId) async {
    try {
      await _pendingScores.remove(moduleId);
      return true;
    } catch (e) {
      print("❌ Error deleting module score from SecureStorage: $e");
      return false;
    }
  }

  Future<void> saveModuleInfo(String moduleId, String moduleName) async {
    Map<String, String> moduleInfo = {
      "module_id": moduleId,
      "module_name": moduleName,
    };
    await secureStorage.write(
        key: "module_info", value: jsonEncode(moduleInfo));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final baseSize = mediaQuery.size.shortestSide;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final isTabletDevice = isTablet(context);

    final scale = isTabletDevice ? 1.0 : 1.0;

    return AppLayout(
      appBar: CustomAppBar(
        onBackPressed: () {
          Navigator.pop(context);
        },
        requireAuth: true, // ✅ keep this
        scale: scale,
      ),

      bottomNav: isLandscape
          ? null
          : CustomBottomNavBar(
              onHomeTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MyHomePage()),
                );
              },
              onLibraryTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ModuleLibrary()),
                );
              },
              onTrackerTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AuthGuard(
                      child: CreditsTracker(),
                    ),
                  ),
                );
              },
              onMenuTap: () async {
                bool isLoggedIn = await checkIfUserIsLoggedIn();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                  ),
                );
              },
              scale: scale,
            ),

      // ❗ IMPORTANT: no Center()
      child: isLandscape
          ? Row(
              children: [
                CustomSideNavBar(
                  onHomeTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const MyHomePage()),
                    );
                  },
                  onLibraryTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ModuleLibrary()),
                    );
                  },
                  onTrackerTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AuthGuard(
                          child: CreditsTracker(),
                        ),
                      ),
                    );
                  },
                  onMenuTap: () async {
                    bool isLoggedIn = await checkIfUserIsLoggedIn();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                      ),
                    );
                  },
                  scale: scale,
                ),
                Expanded(
                  child: _buildLandscapeLayout(
                    context,
                    screenWidth,
                    screenHeight,
                    baseSize,
                    scale,
                  ),
                ),
              ],
            )
          : _buildPortraitLayout(context),
    );
  }

  Widget _buildPortraitLayout(
    BuildContext context,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final baseSize = mediaQuery.size.shortestSide;
    final isTabletDevice = isTablet(context);
    final scale = isTabletDevice ? 1.0 : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: baseSize * 0.02 * scale),

        // 🔹 Header
        Center(
          child: Text(
            "Submit Quiz Scores",
            style: TextStyle(
              fontSize: baseSize * (isTabletDevice ? 0.045 : 0.055) * scale,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF325BFF),
            ),
          ),
        ),
        SizedBox(height: baseSize * 0.01 * scale),
        Center(
          child: Text(
            "Review and submit your pending quiz scores",
            style: TextStyle(
              fontSize: baseSize * (isTabletDevice ? 0.028 : 0.035) * scale,
              color: Colors.black87,
            ),
          ),
        ),
        SizedBox(height: baseSize * 0.03 * scale),

        // 🔹 List of Modules
        Expanded(
          child: FutureBuilder<List<ModuleFile>>(
            future: futureModules,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return _loadError();
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: baseSize * 0.05 * scale),
                    child: Text(
                      'No saved scores yet. Download a module, complete its quiz, and save your score for submission.',
                      style: TextStyle(
                        fontSize:
                            baseSize * (isTabletDevice ? 0.028 : 0.035) * scale,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF548235),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              } else {
                final modules = snapshot.data!;
                return ListView.builder(
                  padding: EdgeInsets.symmetric(
                      horizontal: baseSize * 0.04 * scale,
                      vertical: baseSize * 0.01 * scale),
                  itemCount: modules.length,
                  itemBuilder: (context, index) {
                    final moduleFile = modules[index];

                    return Container(
                      margin: EdgeInsets.only(bottom: baseSize * 0.03 * scale),
                      padding: EdgeInsets.all(baseSize * 0.035 * scale),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: Colors.grey.shade300, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(2, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Module info
                          _buildRow(
                            context,
                            label: "Module Name:",
                            value: moduleFile.moduleName,
                            baseSize: baseSize,
                            scale: scale,
                          ),
                          _buildRow(
                            context,
                            label: "Module ID:",
                            value: _formatModuleId(moduleFile.moduleId),
                            baseSize: baseSize,
                            scale: scale,
                          ),
                          _buildRow(
                            context,
                            label: "Score:",
                            value: moduleFile.score != null
                                ? moduleFile.score!.toStringAsFixed(2)
                                : 'No Score',
                            baseSize: baseSize,
                            scale: scale,
                          ),

                          SizedBox(height: baseSize * 0.03 * scale),

                          // Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildActionButton(
                                  context,
                                  label: "Submit",
                                  icon: Icons.check,
                                  backgroundColor: const Color(0xFF1976D2),
                                  onTap: () =>
                                      _handleSubmit(context, moduleFile),
                                  baseSize: baseSize,
                                  scale: scale,
                                ),
                              ),
                              SizedBox(width: baseSize * 0.03 * scale),
                              Expanded(
                                child: _buildActionButton(
                                  context,
                                  label: "Delete",
                                  icon: Icons.delete,
                                  backgroundColor: const Color(0xFFD32F2F),
                                  onTap: () => _showDeleteConfirmation(
                                    moduleFile.moduleName,
                                    moduleFile.moduleId!,
                                  ),
                                  baseSize: baseSize,
                                  scale: scale,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(
    BuildContext context,
    double screenWidth,
    double screenHeight,
    double baseSize,
    double scale,
  ) {
    final isTabletDevice = isTablet(context);
    final textScale = isTabletDevice ? 1.0 : 1.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🟣 Left Column — Info
        Expanded(
          flex: 4,
          child: Padding(
            padding: EdgeInsets.only(
              left: baseSize * 0.04 * scale,
              top: baseSize * 0.03 * scale,
              right: baseSize * 0.02 * scale,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Submit Quiz Scores",
                  style: TextStyle(
                    fontSize:
                        baseSize * (isTabletDevice ? 0.045 : 0.055) * textScale,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF325BFF),
                  ),
                ),
                SizedBox(height: baseSize * 0.02 * scale),
                Text(
                  "Review and submit your pending quiz scores",
                  style: TextStyle(
                    fontSize:
                        baseSize * (isTabletDevice ? 0.028 : 0.034) * textScale,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Spacer between columns
        SizedBox(width: baseSize * 0.03 * scale),

        // 🟢 Right Column — Scrollable List
        Expanded(
          flex: 6,
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(right: baseSize * 0.02 * scale),
                child: FutureBuilder<List<ModuleFile>>(
                  future: futureModules,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return _loadError();
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: baseSize * 0.02 * scale),
                          child: Text(
                            'You have not saved any score for submission yet. '
                            'Please download a module, complete the final quiz, and save your score for submission.',
                            style: TextStyle(
                              fontSize: baseSize *
                                  (isTabletDevice ? 0.028 : 0.034) *
                                  textScale,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF548235),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    } else {
                      final modules = snapshot.data!;
                      return ListView.builder(
                        itemCount: modules.length,
                        padding: EdgeInsets.symmetric(
                          horizontal: baseSize * 0.012 * scale,
                          vertical: baseSize * 0.01 * scale,
                        ),
                        itemBuilder: (context, index) {
                          final moduleFile = modules[index];
                          return Container(
                            margin: EdgeInsets.only(
                                bottom: baseSize * 0.03 * scale),
                            padding: EdgeInsets.all(baseSize * 0.035 * scale),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: Colors.grey.shade300, width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 8,
                                  offset: const Offset(2, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildRow(
                                  context,
                                  label: "Module Name:",
                                  value: moduleFile.moduleName,
                                  baseSize: baseSize,
                                  scale: scale,
                                ),
                                _buildRow(
                                  context,
                                  label: "Module ID:",
                                  value: _formatModuleId(moduleFile.moduleId),
                                  baseSize: baseSize,
                                  scale: scale,
                                ),
                                _buildRow(
                                  context,
                                  label: "Score:",
                                  value: moduleFile.score != null
                                      ? moduleFile.score!.toStringAsFixed(2)
                                      : 'No Score',
                                  baseSize: baseSize,
                                  scale: scale,
                                ),
                                SizedBox(height: baseSize * 0.03 * scale),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildActionButton(
                                        context,
                                        label: "Submit",
                                        icon: Icons.check,
                                        backgroundColor:
                                            const Color(0xFF1976D2),
                                        onTap: () =>
                                            _handleSubmit(context, moduleFile),
                                        baseSize: baseSize,
                                        scale: scale,
                                      ),
                                    ),
                                    SizedBox(width: baseSize * 0.03 * scale),
                                    Expanded(
                                      child: _buildActionButton(
                                        context,
                                        label: "Delete",
                                        icon: Icons.delete_outline,
                                        backgroundColor:
                                            const Color(0xFFD32F2F),
                                        onTap: () => _showDeleteConfirmation(
                                          moduleFile.moduleName,
                                          moduleFile.moduleId!,
                                        ),
                                        baseSize: baseSize,
                                        scale: scale,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }
                  },
                ),
              ),

              // 🌅 Fade overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: baseSize * 0.1 * scale,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 1.0],
                        colors: [
                          const Color(0xFFFECF97).withOpacity(0.0),
                          const Color(0xFFFECF97),
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
    );
  }

  // 🔹 Helper to format Module ID
  String _formatModuleId(String? id) {
    if (id == null) return 'Unknown';
    if (id.length == 4) return id;
    if (id.length == 8) return '****${id.substring(4)}';
    return 'Unknown';
  }

// 🔹 Helper for Label–Value Row
  Widget _buildRow(BuildContext context,
      {required String label,
      required String value,
      required double baseSize,
      required double scale}) {
    final isTabletDevice = isTablet(context);
    return Padding(
      padding: EdgeInsets.only(bottom: baseSize * 0.01 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: baseSize * (isTabletDevice ? 0.028 : 0.034) * scale,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF646BFF),
            ),
          ),
          SizedBox(width: baseSize * 0.01 * scale),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: baseSize * (isTabletDevice ? 0.028 : 0.034) * scale,
                fontWeight: FontWeight.w500,
                color: Colors.black,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

// 🔹 Helper for Gradient Buttons
  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color backgroundColor,
    required VoidCallback onTap,
    required double baseSize,
    required double scale,
  }) {
    final isTabletDevice = isTablet(context);
    final buttonHeight = baseSize * (isTabletDevice ? 0.075 : 0.085) * scale;
    final fontSize = baseSize * (isTabletDevice ? 0.026 : 0.032) * scale;

    return SizedBox(
      height: buttonHeight,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: fontSize * 1.2),
        label: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          shape: const StadiumBorder(),
          elevation: 1,
          padding: EdgeInsets.symmetric(horizontal: baseSize * 0.02 * scale),
        ),
      ),
    );
  }
}
