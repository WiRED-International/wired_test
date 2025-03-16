import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../providers/auth_guard.dart';
import '../../providers/auth_provider.dart';
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
  final String? score;


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

  Future<List<ModuleFile>> _fetchModulesFromSecureStorage() async {
    final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
    try {
      // Retrieve stored modules from secure storage
      String? storedScoresJson = await secureStorage.read(key: "quiz_scores");

      if (storedScoresJson != null) {
        print("🔍 Raw Stored Data: $storedScoresJson");
        Map<String, dynamic> storedScores = jsonDecode(storedScoresJson);
        List<ModuleFile> fetchedModules = [];

        // Convert each stored module entry into a ModuleFile object
        storedScores.forEach((moduleId, moduleData) {
          if (moduleData is Map<String, dynamic>) {
            print("🔍 Module ID: $moduleId, Data: $moduleData");

            String moduleName = moduleData.containsKey('module_name')
                ? moduleData['module_name']
                : 'Unknown Module';

            String score = moduleData.containsKey('score')
                ? moduleData['score'].toString()
                : '0.0';

            fetchedModules.add(ModuleFile(
              moduleId: moduleId.isNotEmpty ? moduleId : 'null',
              moduleName: moduleName.isNotEmpty ? moduleName : 'Unknown Module',
              score: score,
            ));
          } else {
            print("⚠️ Invalid module data format: $moduleData");
          }
        });

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
    if (moduleFile.score == null || moduleFile.score!.isEmpty) {
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
          'score': double.tryParse(moduleFile.score!) ?? 0.0,
          'date_taken': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
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
                setState(() {
                  modules.removeWhere((module) => module.moduleId == moduleId);
                });
                await deleteStoredScore(moduleId);
                _refreshModules();
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
      final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

      // Retrieve stored modules from secure storage
      String? storedScoresJson = await secureStorage.read(key: "quiz_scores");

      if (storedScoresJson != null) {
        Map<String, dynamic> storedScores = jsonDecode(storedScoresJson);

        if (storedScores.containsKey(moduleId)) {
          storedScores.remove(moduleId); // Remove the module entry

          // Save the updated map back to SecureStorage
          await secureStorage.write(key: "quiz_scores", value: jsonEncode(storedScores));

          print("✅ Module score deleted successfully for ID: $moduleId");
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
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    double scalingFactor = getScalingFactor(context);


    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
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
                                  child: CMETracker(),
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
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(
                              scalingFactor, authProvider)
                              : _buildPortraitLayout(
                              scalingFactor, authProvider),
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
                            child: CMETracker(),
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
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(scalingFactor, authProvider) {
    return Column(
      children: [
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 5 : 5),
        ),
        Text(
          "Submit CME Credits",
          style: TextStyle(
            fontSize: scalingFactor * (isTablet(context) ? 24 : 32),
            fontWeight: FontWeight.w500,
            color: Color(0xFF646BFF),
          ),
          textAlign: TextAlign.center,
        ),
        // SizedBox(
        //   height: baseSize * (isTablet(context) ? 0.02 : 0.02),
        // ),

        SizedBox(
          height: scalingFactor * (isTablet(context) ? 10 : 10),
        ),
        Flexible(
          child: Stack(
            children: [
              FutureBuilder<List<ModuleFile>>(
                future: futureModules,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return const Center(child: Text(
                        'Error loading modules'));
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                        child: Text(
                          'You have not saved any score for submission yet. Please download a module, complete the final quiz and save your score for submission.',
                          style: TextStyle(
                            fontSize: scalingFactor * (isTablet(context) ? 24 : 24),
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF548235),
                          ),
                          textAlign: TextAlign.center,
                        ));
                  } else {
                    return ListView.builder(
                        itemCount: snapshot.data!.length + 1, // +1 for the extra space at the end
                        itemBuilder: (context, index) {
                          if (index == snapshot.data!.length) {
                            return SizedBox(
                              height: scalingFactor * (isTablet(context) ? 85 : 85), // This is the last item
                            );
                          }
                          final moduleFile = snapshot.data![index];

                          return Column(
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 7 : 7),),
                                child: Container(
                                  padding: EdgeInsets.all(scalingFactor * (isTablet(context) ? 6 : 6)),
                                  decoration: BoxDecoration(
                                      color: Color(0xFFFFF5E1),
                                    //color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Color(0xFF9DA2FF),
                                      width: scalingFactor * (isTablet(context) ? 1 : 2),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 5,
                                        offset: Offset(2, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min, // Shrink-wrap the column to its content
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Module name text
                                      Padding(
                                        padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 4 : 6)),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Module Name: ",
                                              style: TextStyle(
                                                fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF646BFF),
                                              ),
                                              //textAlign: TextAlign.center, // Center the text
                                            ),
                                            SizedBox(width: scalingFactor * (isTablet(context) ? 5 : 5)), // Space between text and value
                                            Expanded(
                                              child: Text(
                                                moduleFile.moduleName,
                                                style: TextStyle(
                                                  fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.black,
                                                ),
                                                //textAlign: TextAlign.start, // Center the text
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: scalingFactor * (isTablet(context) ? 7 : 7)),
                                      Padding(
                                        padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 4 : 6)),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Module Id: ",
                                              style: TextStyle(
                                                fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF646BFF),
                                              ),
                                              //textAlign: TextAlign.center, // Center the text
                                            ),
                                            SizedBox(width: scalingFactor * (isTablet(context) ? 5 : 5)), // Space between text and value
                                            Expanded(
                                              child: Text(
                                                () {
                                                  if (moduleFile.moduleId == null) {
                                                    return 'Unknown';
                                                  } else if (moduleFile.moduleId!.length == 4) {
                                                    return moduleFile.moduleId!; // Display full 4-digit ID
                                                  } else if (moduleFile.moduleId!.length == 8) {
                                                    return '****${moduleFile.moduleId!.substring(4)}'; // Mask first 4 digits, show last 4
                                                  } else {
                                                    return 'Unknown'; // Fallback for unexpected lengths
                                                  }
                                                }(),
                                                style: TextStyle(
                                                  fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.black,
                                                ),
                                                //textAlign: TextAlign.start, // Center the text
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: scalingFactor * (isTablet(context) ? 7 : 7)),
                                      Padding(
                                        padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 4 : 6)),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Score: ",
                                              style: TextStyle(
                                                fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF646BFF),
                                              ),
                                            ),
                                            SizedBox(width: scalingFactor * (isTablet(context) ? 5 : 5)),
                                            Expanded(
                                              child: Text(
                                                moduleFile.score ?? 'No Score',
                                                style: TextStyle(
                                                  fontSize: scalingFactor * (isTablet(context) ? 14 : 18),
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.black,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: scalingFactor * (isTablet(context) ? 20 : 20)), // Space between text and buttons
                                      // Buttons (Play and Delete)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          // Play Button
                                          // Expanded(
                                          //   child: Semantics(
                                          //     label: 'Play Button',
                                          //     hint: 'Tap to play the module',
                                          //     child: GestureDetector(
                                          //       onTap: () {
                                          //         String moduleId = moduleFile.moduleId ?? "Unknown"; // Ensure moduleId is always a non-null String
                                          //         String modulePath = moduleFile.path ?? "";
                                          //
                                          //         if (modulePath.isEmpty) {
                                          //           print("❌ ERROR: Module path is missing!");
                                          //           return; // Prevent navigation if the path is missing
                                          //         }
                                          //
                                          //         saveModuleInfo(moduleId, moduleFile.moduleName);
                                          //         print("Saving module id: $moduleId");
                                          //
                                          //         Navigator.push(
                                          //           context,
                                          //           MaterialPageRoute(
                                          //             builder: (context) => WebViewScreen(
                                          //               urlRequest: URLRequest(url: WebUri(Uri.file(modulePath).toString())), // ✅ Ensure modulePath is non-null
                                          //               moduleId: moduleId, // ✅ Ensure moduleId is non-null
                                          //             ),
                                          //           ),
                                          //         );
                                          //       },
                                          //
                                          //       child: FractionallySizedBox(
                                          //         widthFactor: isTablet(context) ? 0.45 : 0.65,
                                          //         child: Container(
                                          //           height: scalingFactor * (isTablet(context) ? 34 : 54),
                                          //           decoration: BoxDecoration(
                                          //             gradient: const LinearGradient(
                                          //               colors: [
                                          //                 Color(0xFF1A4314),
                                          //                 Color(0xFF3E8914),
                                          //                 Color(0xFF74B72E),
                                          //               ],
                                          //               begin: Alignment.topCenter,
                                          //               end: Alignment.bottomCenter,
                                          //             ),
                                          //             borderRadius: BorderRadius.circular(30),
                                          //             boxShadow: [
                                          //               BoxShadow(
                                          //                 color: Colors.black.withOpacity(0.5),
                                          //                 spreadRadius: 1,
                                          //                 blurRadius: 5,
                                          //                 offset: const Offset(1, 3),
                                          //               ),
                                          //             ],
                                          //           ),
                                          //           child: LayoutBuilder(
                                          //             builder: (context, constraints) {
                                          //               double buttonWidth = constraints.maxWidth;
                                          //               double fontSize = buttonWidth * 0.2;
                                          //               double padding = buttonWidth * 0.02;
                                          //               return Padding(
                                          //                 padding: EdgeInsets.all(padding),
                                          //                 child: Row(
                                          //                   mainAxisAlignment: MainAxisAlignment.center,
                                          //                   children: [
                                          //                     Text(
                                          //                       "Play",
                                          //                       style: TextStyle(
                                          //                         fontSize: fontSize,
                                          //                         fontWeight: FontWeight.w500,
                                          //                         color: Color(0xFFE8E8E8),
                                          //                       ),
                                          //                     ),
                                          //                     SizedBox(width: padding),
                                          //                     Icon(
                                          //                       Icons.play_arrow,
                                          //                       color: Color(0xFFE8E8E8),
                                          //                       size: fontSize * 1.4,
                                          //                     ),
                                          //                   ],
                                          //                 ),
                                          //               );
                                          //             },
                                          //           ),
                                          //         ),
                                          //       ),
                                          //     ),
                                          //   ),
                                          // ),

                                          // Submit Button
                                          Expanded(
                                            child: Semantics(
                                              label: 'Submit Button',
                                              hint: 'Tap to submit the module',
                                              child: GestureDetector(
                                                onTap: () {
                                                  _handleSubmit(context, moduleFile);
                                                },
                                                child: FractionallySizedBox(
                                                  widthFactor: isTablet(context) ? 0.45 : 0.55,
                                                  child: Container(
                                                    height: scalingFactor * (isTablet(context) ? 34 : 44),
                                                    decoration: BoxDecoration(
                                                      gradient: const LinearGradient(
                                                        colors: [
                                                          Color(0xFF325BFF),
                                                          Color(0xFF5A88FE),
                                                          Color(0xFF69AEFE),
                                                        ],
                                                        begin: Alignment.topCenter,
                                                        end: Alignment.bottomCenter,
                                                      ),
                                                      borderRadius: BorderRadius.circular(30),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black.withOpacity(0.5),
                                                          spreadRadius: 1,
                                                          blurRadius: 5,
                                                          offset: const Offset(1, 3),
                                                        ),
                                                      ],
                                                    ),
                                                    child: LayoutBuilder(
                                                      builder: (context, constraints) {
                                                        double buttonWidth = constraints.maxWidth;
                                                        double fontSize = buttonWidth * 0.17;
                                                        double padding = buttonWidth * 0.04;
                                                        return Padding(
                                                          padding: EdgeInsets.all(padding),
                                                          child: Row(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Text(
                                                                "Submit",
                                                                style: TextStyle(
                                                                  fontSize: fontSize,
                                                                  fontWeight: FontWeight.w500,
                                                                  color: Color(0xFFE8E8E8),
                                                                ),
                                                              ),
                                                              SizedBox(width: padding),
                                                              Icon(
                                                                Icons.check_circle,
                                                                color: Color(0xFFE8E8E8),
                                                                size: fontSize * 1.2,
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ), // Space between containers

                                          // Delete Button
                                          Expanded(
                                            child: Semantics(
                                              label: 'Delete Button',
                                              hint: 'Tap to delete the module',
                                              child: GestureDetector(
                                                onTap: () {
                                                  print("🔍 Checking values before deletion:");
                                                  print("File Path: ${moduleFile.file?.path}");
                                                  print("Module ID: ${moduleFile.moduleId}");
                                                  _showDeleteConfirmation(
                                                      moduleFile.moduleName,
                                                      moduleFile.moduleId!,
                                                  );
                                                },
                                                child: FractionallySizedBox(
                                                  widthFactor: isTablet(context) ? 0.45 : 0.55,
                                                  child: Container(
                                                    height: scalingFactor * (isTablet(context) ? 34 : 44),
                                                    decoration: BoxDecoration(
                                                      gradient: const LinearGradient(
                                                        colors: [
                                                          Color(0xFF790000),
                                                          Color(0xFFB71C1C),
                                                          Color(0xFFF05545),
                                                        ],
                                                        begin: Alignment.topCenter,
                                                        end: Alignment.bottomCenter,
                                                      ),
                                                      borderRadius: BorderRadius.circular(30),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black.withOpacity(0.5),
                                                          spreadRadius: 1,
                                                          blurRadius: 5,
                                                          offset: const Offset(1, 3),
                                                        ),
                                                      ],
                                                    ),
                                                    child: LayoutBuilder(
                                                      builder: (context, constraints) {
                                                        double buttonWidth = constraints.maxWidth;
                                                        double fontSize = buttonWidth * 0.17;
                                                        double padding = buttonWidth * 0.04;
                                                        return Padding(
                                                          padding: EdgeInsets.all(padding),
                                                          child: Row(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Text(
                                                                "Delete",
                                                                style: TextStyle(
                                                                  fontSize: fontSize,
                                                                  fontWeight: FontWeight.w500,
                                                                  color: Color(0xFFE8E8E8),
                                                                ),
                                                              ),
                                                              SizedBox(width: padding),
                                                              Icon(
                                                                Icons.delete,
                                                                color: Color(0xFFE8E8E8),
                                                                size: fontSize * 1.2,
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: scalingFactor * (isTablet(context) ? 10 : 10)),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: scalingFactor * (isTablet(context) ? 12 : 12)),
                            ],
                          );
                        }
                    );
                  }
                },
              ),
              // Fade in the module list
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.0, 1.0],
                          colors: [
                            // Colors.transparent,
                            // Color(0xFFFFF0DC),
                            //Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
                            Color(0xFFFECF97).withOpacity(0.0),
                            Color(0xFFFECF97),
                          ],
                        ),
                      )
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(scalingFactor, authProvider) {
    return Column(
      children: [
        SizedBox(
          height: scalingFactor * (isTablet(context) ? 3 : 3),
        ),
        Text(
          "Submit CME Credits",
          style: TextStyle(
            fontSize: scalingFactor * (isTablet(context) ? 22 : 24),
            fontWeight: FontWeight.w500,
            color: Color(0xFF646BFF),
          ),
          textAlign: TextAlign.center,
        ),
        // SizedBox(
        //   height: baseSize * (isTablet(context) ? 0.02 : 0.02),
        // ),

        SizedBox(
          height: scalingFactor * (isTablet(context) ? 7 : 7),
        ),
        Flexible(
          child: Stack(
            children: [
              FutureBuilder<List<ModuleFile>>(
                future: futureModules,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return const Center(child: Text(
                        'Error loading modules'));
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                        child: Text(
                          'You have not saved any score for submission yet. Please download a module, complete the final quiz and save your score for submission.',
                          style: TextStyle(
                            fontSize: scalingFactor * (isTablet(context) ? 16 : 20),
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF548235),
                          ),
                          textAlign: TextAlign.center,
                        ));
                  } else {
                    return ListView.builder(
                        itemCount: snapshot.data!.length + 1, // +1 for the extra space at the end
                        itemBuilder: (context, index) {
                          if (index == snapshot.data!.length) {
                            return SizedBox(
                              height: scalingFactor * (isTablet(context) ? 85 : 85), // This is the last item
                            );
                          }
                          final moduleFile = snapshot.data![index];

                          return Column(
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: scalingFactor * (isTablet(context) ? 77 : 47),),
                                child: Container(
                                  padding: EdgeInsets.all(scalingFactor * (isTablet(context) ? 4 : 4)),
                                  decoration: BoxDecoration(
                                    color: Color(0xFFFFF5E1),
                                    //color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Color(0xFF9DA2FF),
                                      width: scalingFactor * (isTablet(context) ? 1.5 : 1.5),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 5,
                                        offset: Offset(2, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min, // Shrink-wrap the column to its content
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Module name text
                                      Padding(
                                        padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 4 : 6)),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Module Name: ",
                                              style: TextStyle(
                                                fontSize: scalingFactor * (isTablet(context) ? 14 : 14),
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF646BFF),
                                              ),
                                              //textAlign: TextAlign.center, // Center the text
                                            ),
                                            SizedBox(width: scalingFactor * (isTablet(context) ? 5 : 5)), // Space between text and buttons
                                            Expanded(
                                              child: Text(
                                                moduleFile.moduleName,
                                                style: TextStyle(
                                                  fontSize: scalingFactor * (isTablet(context) ? 14 : 14),
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.black,
                                                ),
                                                //textAlign: TextAlign.start, // Center the text
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: scalingFactor * (isTablet(context) ? 5 : 5)),
                                      Padding(
                                        padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 4 : 6)),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Module Id: ",
                                              style: TextStyle(
                                                fontSize: scalingFactor * (isTablet(context) ? 14 : 14),
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF646BFF),
                                              ),
                                              //textAlign: TextAlign.center, // Center the text
                                            ),
                                            SizedBox(width: scalingFactor * (isTablet(context) ? 5 : 5)), // Space between text and value
                                            Expanded(
                                              child: Text(
                                                    () {
                                                  if (moduleFile.moduleId == null) {
                                                    return 'Unknown';
                                                  } else if (moduleFile.moduleId!.length == 4) {
                                                    return moduleFile.moduleId!; // Display full 4-digit ID
                                                  } else if (moduleFile.moduleId!.length == 8) {
                                                    return '****${moduleFile.moduleId!.substring(4)}'; // Mask first 4 digits, show last 4
                                                  } else {
                                                    return 'Unknown'; // Fallback for unexpected lengths
                                                  }
                                                }(),
                                                style: TextStyle(
                                                  fontSize: scalingFactor * (isTablet(context) ? 14 : 14),
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.black,
                                                ),
                                                //textAlign: TextAlign.start, // Center the text
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: scalingFactor * (isTablet(context) ? 5 : 5)),
                                      Padding(
                                        padding: EdgeInsets.only(left: scalingFactor * (isTablet(context) ? 4 : 6)),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Score: ",
                                              style: TextStyle(
                                                fontSize: scalingFactor * (isTablet(context) ? 14 : 14),
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF646BFF),
                                              ),
                                            ),
                                            SizedBox(width: scalingFactor * (isTablet(context) ? 5 : 5)),
                                            Expanded(
                                              child: Text(
                                                moduleFile.score ?? 'No Score',
                                                style: TextStyle(
                                                  fontSize: scalingFactor * (isTablet(context) ? 14 : 14),
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.black,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: scalingFactor * (isTablet(context) ? 20 : 20)), // Space between text and buttons
                                      // Buttons (Play and Delete)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          // Play Button
                                          // Expanded(
                                          //   child: Semantics(
                                          //     label: 'Play Button',
                                          //     hint: 'Tap to play the module',
                                          //     child: GestureDetector(
                                          //       onTap: () {
                                          //         String moduleId = moduleFile.moduleId ?? "Unknown"; // Ensure moduleId is always a non-null String
                                          //         String modulePath = moduleFile.path ?? "";
                                          //
                                          //         if (modulePath.isEmpty) {
                                          //           print("❌ ERROR: Module path is missing!");
                                          //           return; // Prevent navigation if the path is missing
                                          //         }
                                          //
                                          //         saveModuleInfo(moduleId, moduleFile.moduleName);
                                          //         print("Saving module id: $moduleId");
                                          //
                                          //         Navigator.push(
                                          //           context,
                                          //           MaterialPageRoute(
                                          //             builder: (context) => WebViewScreen(
                                          //               urlRequest: URLRequest(url: WebUri(Uri.file(modulePath).toString())), // ✅ Ensure modulePath is non-null
                                          //               moduleId: moduleId, // ✅ Ensure moduleId is non-null
                                          //             ),
                                          //           ),
                                          //         );
                                          //       },
                                          //
                                          //       child: FractionallySizedBox(
                                          //         widthFactor: isTablet(context) ? 0.45 : 0.45,
                                          //         child: Container(
                                          //           height: scalingFactor * (isTablet(context) ? 35 : 44),
                                          //           decoration: BoxDecoration(
                                          //             gradient: const LinearGradient(
                                          //               colors: [
                                          //                 Color(0xFF1A4314),
                                          //                 Color(0xFF3E8914),
                                          //                 Color(0xFF74B72E),
                                          //               ],
                                          //               begin: Alignment.topCenter,
                                          //               end: Alignment.bottomCenter,
                                          //             ),
                                          //             borderRadius: BorderRadius.circular(30),
                                          //             boxShadow: [
                                          //               BoxShadow(
                                          //                 color: Colors.black.withOpacity(0.5),
                                          //                 spreadRadius: 1,
                                          //                 blurRadius: 5,
                                          //                 offset: const Offset(1, 3),
                                          //               ),
                                          //             ],
                                          //           ),
                                          //           child: LayoutBuilder(
                                          //             builder: (context, constraints) {
                                          //               double buttonWidth = constraints.maxWidth;
                                          //               double fontSize = buttonWidth * 0.2;
                                          //               double padding = buttonWidth * 0.02;
                                          //               return Padding(
                                          //                 padding: EdgeInsets.all(padding),
                                          //                 child: Row(
                                          //                   mainAxisAlignment: MainAxisAlignment.center,
                                          //                   children: [
                                          //                     Text(
                                          //                       "Play",
                                          //                       style: TextStyle(
                                          //                         fontSize: fontSize,
                                          //                         fontWeight: FontWeight.w500,
                                          //                         color: Color(0xFFE8E8E8),
                                          //                       ),
                                          //                     ),
                                          //                     SizedBox(width: padding),
                                          //                     Icon(
                                          //                       Icons.play_arrow,
                                          //                       color: Color(0xFFE8E8E8),
                                          //                       size: fontSize * 1.4,
                                          //                     ),
                                          //                   ],
                                          //                 ),
                                          //               );
                                          //             },
                                          //           ),
                                          //         ),
                                          //       ),
                                          //     ),
                                          //   ),
                                          // ),

                                          // Submit Button
                                          Expanded(
                                            child: Semantics(
                                              label: 'Submit Button',
                                              hint: 'Tap to submit the module',
                                              child: GestureDetector(
                                                onTap: () {
                                                  _handleSubmit(context, moduleFile);
                                                },
                                                child: FractionallySizedBox(
                                                  widthFactor: isTablet(context) ? 0.45 : 0.45,
                                                  child: Container(
                                                    height: scalingFactor * (isTablet(context) ? 35 : 34),
                                                    decoration: BoxDecoration(
                                                      gradient: const LinearGradient(
                                                        colors: [
                                                          Color(0xFF325BFF),
                                                          Color(0xFF5A88FE),
                                                          Color(0xFF69AEFE),
                                                        ],
                                                        begin: Alignment.topCenter,
                                                        end: Alignment.bottomCenter,
                                                      ),
                                                      borderRadius: BorderRadius.circular(30),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black.withValues(alpha: 0.5),
                                                          spreadRadius: 1,
                                                          blurRadius: 5,
                                                          offset: const Offset(1, 3),
                                                        ),
                                                      ],
                                                    ),
                                                    child: LayoutBuilder(
                                                      builder: (context, constraints) {
                                                        double buttonWidth = constraints.maxWidth;
                                                        double fontSize = buttonWidth * 0.16;
                                                        double padding = buttonWidth * 0.04;
                                                        return Padding(
                                                          padding: EdgeInsets.all(padding),
                                                          child: Row(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Text(
                                                                "Submit",
                                                                style: TextStyle(
                                                                  fontSize: fontSize,
                                                                  fontWeight: FontWeight.w500,
                                                                  color: Color(0xFFE8E8E8),
                                                                ),
                                                              ),
                                                              SizedBox(width: padding),
                                                              Icon(
                                                                Icons.check_circle,
                                                                color: Color(0xFFE8E8E8),
                                                                size: fontSize * 1.2,
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ), // Space between containers

                                          // Delete Button
                                          Expanded(
                                            child: Semantics(
                                              label: 'Delete Button',
                                              hint: 'Tap to delete the module',
                                              child: GestureDetector(
                                                onTap: () {
                                                  _showDeleteConfirmation(moduleFile.file!.path.split('/').last, moduleFile.moduleId!);
                                                },
                                                child: FractionallySizedBox(
                                                  widthFactor: isTablet(context) ? 0.45 : 0.45,
                                                  child: Container(
                                                    height: scalingFactor * (isTablet(context) ? 35 : 34),
                                                    decoration: BoxDecoration(
                                                      gradient: const LinearGradient(
                                                        colors: [
                                                          Color(0xFF790000),
                                                          Color(0xFFB71C1C),
                                                          Color(0xFFF05545),
                                                        ],
                                                        begin: Alignment.topCenter,
                                                        end: Alignment.bottomCenter,
                                                      ),
                                                      borderRadius: BorderRadius.circular(30),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black.withValues(alpha: 0.5),
                                                          spreadRadius: 1,
                                                          blurRadius: 5,
                                                          offset: const Offset(1, 3),
                                                        ),
                                                      ],
                                                    ),
                                                    child: LayoutBuilder(
                                                      builder: (context, constraints) {
                                                        double buttonWidth = constraints.maxWidth;
                                                        double fontSize = buttonWidth * 0.16;
                                                        double padding = buttonWidth * 0.04;
                                                        return Padding(
                                                          padding: EdgeInsets.all(padding),
                                                          child: Row(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Text(
                                                                "Delete",
                                                                style: TextStyle(
                                                                  fontSize: fontSize,
                                                                  fontWeight: FontWeight.w500,
                                                                  color: Color(0xFFE8E8E8),
                                                                ),
                                                              ),
                                                              SizedBox(width: padding),
                                                              Icon(
                                                                Icons.delete,
                                                                color: Color(0xFFE8E8E8),
                                                                size: fontSize * 1.2,
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: scalingFactor * (isTablet(context) ? 7 : 7)),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: scalingFactor * (isTablet(context) ? 8 : 8)), // Space between containers
                            ],
                          );
                        }
                    );
                  }
                },
              ),
              // Fade in the module list
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.0, 1.0],
                          colors: [
                            // Colors.transparent,
                            // Color(0xFFFFF0DC),
                            //Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
                            Color(0xFFFECF97).withValues(alpha: 0.0),
                            Color(0xFFFECF97),
                          ],
                        ),
                      )
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
