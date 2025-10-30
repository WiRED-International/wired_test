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
import '../../providers/quiz_score_provider.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import 'cme_tracker.dart';

class SubmitCredits extends StatefulWidget {
  const SubmitCredits({super.key});

  @override
  State<SubmitCredits> createState() => _SubmitCreditsState();
}

class ModuleFile {
  final FileSystemEntity? file;
  final String? path;
  final String moduleName;
  final String? moduleId;
  final double? score;

  ModuleFile({
    this.file,
    this.path,
    required this.moduleName,
    this.moduleId,
    this.score,
  });
}

enum DisplayType { modules, resources }

class _SubmitCreditsState extends State<SubmitCredits> {
  late Future<List<ModuleFile>> futureModules;
  late Future<List<FileSystemEntity>> futureResources; // For PDF resources
  List<ModuleFile> modules = [];
  // List<FileSystemEntity> resources = []; // Store PDF files
  DisplayType selectedType = DisplayType.modules; // To track whether Modules or Resources are selected
  final secureStorage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    futureModules = _fetchModulesFromSecureStorage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshModules(); // Re-read SecureStorage each time page becomes active
  }

  Future<List<ModuleFile>> _fetchModulesFromSecureStorage() async {
    final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
    try {
      // 🧩 Optional debugging: check what's stored
      String? pendingScoresJson = await secureStorage.read(key: "pending_quiz_scores");
      String? quizScoresJson = await secureStorage.read(key: "quiz_scores");

      print("🗂 pending_quiz_scores: ${pendingScoresJson != null ? 'Exists' : 'None'}");
      print("🗂 quiz_scores (API cache): ${quizScoresJson != null ? 'Exists' : 'None'}");
      // Retrieve stored modules from secure storage
      String? storedScoresJson = await secureStorage.read(key: "pending_quiz_scores");

      if (storedScoresJson != null) {
        Map<String, dynamic> storedScores = jsonDecode(storedScoresJson);
        List<ModuleFile> fetchedModules = [];

        storedScores.forEach((moduleId, moduleData) {
          if (moduleData is Map<String, dynamic>) {
            String moduleName = moduleData['module_name'] ?? 'Unknown Module';
            double parsedScore = double.tryParse(moduleData['score']?.toString() ?? '0.0') ?? 0.0;

            fetchedModules.add(ModuleFile(
              moduleId: moduleId,
              moduleName: moduleName,
              score: parsedScore,
            ));
          }
        });
        print("📦 Loaded ${storedScores.length} pending quiz scores from Secure Storage");
        fetchedModules.sort((a, b) => a.moduleName.compareTo(b.moduleName));

        setState(() {
          modules = fetchedModules;
        });

        return fetchedModules;
      } else {
        print("ℹ️ No stored modules found in Secure Storage.");
        return [];
      }
    } catch (e) {
      print("❌ Error fetching modules from Secure Storage: $e");
      return [];
    }
  }

  Future<void> _handleSubmit(BuildContext context, ModuleFile moduleFile) async {
    if (moduleFile.score == null || moduleFile.score == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No score available to submit.')),
      );
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.authToken;
    final userId = authProvider.getUserIdFromToken();

    if (token == null || userId == null) {
      print('Token or user_id is missing');
      return;
    }

    try {
      final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

      final apiEndpoint = '/quiz-scores';


      final response = await http.post(
        Uri.parse('$apiBaseUrl$apiEndpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'module_id': moduleFile.moduleId!.substring(moduleFile.moduleId!.length - 4),
          'user_id': userId,
          'score': moduleFile.score ?? 0.0,
          'date_taken': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        // 🧹 Automatically remove the module’s stored score after successful submission
        await deleteStoredScore(moduleFile.moduleId!);
        print("✅ Successfully submitted and removed ${moduleFile.moduleName} from local storage.");

        // Refresh the module list after deletion
        final updatedModules = await _fetchModulesFromSecureStorage();
        if (mounted) setState(() => modules = updatedModules);

        print("✅ Successfully submitted and removed ${moduleFile.moduleName} from local storage.");

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Success'),
              content: Text('Your score has been submitted successfully!'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => CMETracker()),
                    );
                  },
                  child: Text('OK'),
                ),
              ],
            );
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit score. Please try again.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred. Please try again.')),
      );
    }
  }

  Future<void> _refreshModules() async {
    final updatedModules = await _fetchModulesFromSecureStorage();
    setState(() {
      modules = updatedModules;
    });
  }

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

                await deleteStoredScore(moduleId);

                // 🔁 Force FutureBuilder + UI to rebuild
                setState(() {
                  futureModules = _fetchModulesFromSecureStorage();
                });
              },
              child: Text("Yes, delete"),
            ),
          ],
        );
      },
    );
  }

  Future<void> deleteStoredScore(String moduleId) async {
    try {
      const FlutterSecureStorage secureStorage = FlutterSecureStorage();

      String? storedScoresJson = await secureStorage.read(key: "pending_quiz_scores");

      if (storedScoresJson != null && storedScoresJson.isNotEmpty) {
        Map<String, dynamic> storedScores = jsonDecode(storedScoresJson);

        if (storedScores.containsKey(moduleId)) {
          storedScores.remove(moduleId);
          print("🧹 Removing module ID $moduleId from SecureStorage...");

          if (storedScores.isEmpty) {
            await secureStorage.delete(key: "pending_quiz_scores");
            print("✅ All module scores deleted. Cleared quiz_scores key completely.");
          } else {
            await secureStorage.write(
              key: "pending_quiz_scores",
              value: jsonEncode(storedScores),
            );
            print("✅ Module score deleted successfully for ID: $moduleId");
          }
        } else {
          print("ℹ️ Module ID $moduleId not found in SecureStorage.");
        }
      } else {
        print("ℹ️ No stored modules found in SecureStorage.");
      }
    } catch (e) {
      print("❌ Error deleting module score from SecureStorage: $e");
    }
  }

  Future<void> saveModuleInfo(String moduleId, String moduleName) async {
    Map<String, String> moduleInfo = {
      "module_id": moduleId,
      "module_name": moduleName,
    };
    await secureStorage.write(key: "module_info", value: jsonEncode(moduleInfo));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final baseSize = mediaQuery.size.shortestSide;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final isTabletDevice = isTablet(context);

    // Consistent scaling across tablet and phone
    final scale = isTabletDevice ? 1.0 : 1.0;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // 🟠 Background Gradient
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
                // Custom AppBar
                CustomAppBar(
                  onBackPressed: () {
                    Navigator.pop(context);
                  },
                  requireAuth: true,
                  scale: scale,
                ),
                // Expanded layout for the main content
                Expanded(
                  child: Row(
                    children: [
                      if (isLandscape)
                        CustomSideNavBar(
                          onHomeTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            Navigator.push(context,
                                MaterialPageRoute(builder: (context) => ModuleLibrary()));
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
                            print("Navigating to menu. Logged in: $isLoggedIn");
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                              ),
                            );
                          },
                          scale: scale,
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(context, screenWidth, screenHeight, baseSize, scale)
                              : _buildPortraitLayout(context,),
                        ),
                      ),
                    ],
                  ),
                ),

                if (!isLandscape)
                  CustomBottomNavBar(
                    onHomeTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const MyHomePage()),
                      );
                    },
                    onLibraryTap: () {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (context) => ModuleLibrary()));
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(BuildContext context,) {
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
                return const Center(child: Text("Error loading modules"));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: baseSize * 0.05 * scale),
                    child: Text(
                      'No saved scores yet. Download a module, complete its quiz, and save your score for submission.',
                      style: TextStyle(
                        fontSize: baseSize * (isTabletDevice ? 0.028 : 0.035) * scale,
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
                        border: Border.all(color: Colors.grey.shade300, width: 1),
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
                                  onTap: () => _handleSubmit(context, moduleFile),
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

  Widget _buildLandscapeLayout(BuildContext context, double screenWidth, double screenHeight, double baseSize, double scale,) {
    final mediaQuery = MediaQuery.of(context);
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
                    fontSize: baseSize * (isTabletDevice ? 0.045 : 0.055) * textScale,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF325BFF),
                  ),
                ),
                SizedBox(height: baseSize * 0.02 * scale),
                Text(
                  "Review and submit your pending quiz scores",
                  style: TextStyle(
                    fontSize: baseSize * (isTabletDevice ? 0.028 : 0.034) * textScale,
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
                      return const Center(child: Text('Error loading modules'));
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: baseSize * 0.02 * scale),
                          child: Text(
                            'You have not saved any score for submission yet. '
                                'Please download a module, complete the final quiz, and save your score for submission.',
                            style: TextStyle(
                              fontSize:
                              baseSize * (isTabletDevice ? 0.028 : 0.034) * textScale,
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
                            margin:
                            EdgeInsets.only(bottom: baseSize * 0.03 * scale),
                            padding:
                            EdgeInsets.all(baseSize * 0.035 * scale),
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
                                Text(
                                  "CME Credits",
                                  style: TextStyle(
                                    fontSize: baseSize *
                                        (isTabletDevice ? 0.030 : 0.035) *
                                        textScale,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF2E7D32),
                                  ),
                                ),
                                SizedBox(height: baseSize * 0.015 * scale),

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
