import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_guard.dart';
import '../../providers/auth_provider.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';
import '../../utils/webview_screen.dart';
import '../home_page.dart';
import '../menu/guestMenu.dart';
import '../menu/menu.dart';
import '../module_library.dart';
import 'cme_tracker.dart';
import 'enter_score.dart';



class SubmitCredits extends StatefulWidget {
  @override
  _SubmitCreditsState createState() => _SubmitCreditsState();
}

class ModuleFile {
  final FileSystemEntity file;
  final String path;
  final String title;
  final String? moduleId;


  ModuleFile({required this.file, required this.path, required this.title, this.moduleId,});
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
    futureModules = _fetchModules();
  }

  Future<List<ModuleFile>> _fetchModules() async {
    final directory = await getExternalStorageDirectory();
    if (directory != null) {
      final packagesDirectory = Directory('${directory.path}/packages');
      final modulesDirectory = Directory('${directory.path}/modules');

      List<ModuleFile> fetchedModules = [];

      // Function to extract module ID from HTML content
      String? extractModuleId(String content) {
        final regex = RegExp(r'content="0; url=files/(\d+)/story.html"');
        final match = regex.firstMatch(content);
        return match?.group(1); // Return the captured group (module ID)
      }

      // Process files in packages directory
      if (packagesDirectory.existsSync()) {
        final packageFiles = packagesDirectory.listSync().whereType<File>().toList();
        fetchedModules.addAll(packageFiles.map((file) {
          String fileName = file.path.split('/').last;
          if (fileName.endsWith('.htm')) {
            fileName = fileName.replaceAll('.htm', '');
          }

          String? moduleId;
          try {
            final content = file.readAsStringSync(); // Read file content
            moduleId = extractModuleId(content); // Extract module ID
          } catch (e) {
            print("Error reading file: ${file.path}, $e");
          }

          return ModuleFile(
            file: file,
            path: file.path,
            title: fileName,
            moduleId: moduleId, // Associate module ID
          );
        }).toList());
      }

      // Process files in modules directory
      if (modulesDirectory.existsSync()) {
        final moduleFiles = modulesDirectory.listSync().whereType<File>().toList();
        fetchedModules.addAll(moduleFiles.map((file) {
          String fileName = file.path.split('/').last;
          if (fileName.endsWith('.htm')) {
            fileName = fileName.replaceAll('.htm', '');
          }

          String? moduleId;
          try {
            final content = file.readAsStringSync(); // Read file content
            moduleId = extractModuleId(content); // Extract module ID
          } catch (e) {
            print("Error reading file: ${file.path}, $e");
          }

          return ModuleFile(
            file: file,
            path: file.path,
            title: fileName,
            moduleId: moduleId, // Associate module ID
          );
        }).toList());
      }

      fetchedModules.sort((a, b) => a.title.compareTo(b.title));

      setState(() {
        modules = fetchedModules;
      });

      return fetchedModules;
    } else {
      return [];
    }
  }

  void _showDeleteConfirmation(String fileName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Delete Module"),
          content: Text(
              "Are you sure you want to delete the module: $fileName?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the modal
              },
              child: Text("Do not delete"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the modal
                deleteFileAndAssociatedDirectory(
                    fileName); // Call the delete function after confirmation
              },
              child: Text("Yes, delete"),
            ),
          ],
        );
      },
    );
  }

  Future<void> deleteFileAndAssociatedDirectory(String fileName) async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        return;
      }
      // Define the path to the file
      final packagesFilePath = '${directory.path}/packages/$fileName';
      final modulesFilePath = '${directory.path}/modules/$fileName';

      // Determine which directory the file exists in
      String? filePath;
      if (File(packagesFilePath).existsSync()) {
        filePath = packagesFilePath;
      } else if (File(modulesFilePath).existsSync()) {
        filePath = modulesFilePath;
      }

      if (filePath == null) {
        print('File not found in either directory: $fileName');
        return;
      }

      final file = File(filePath);
      print('Attempting to delete file: $filePath');
      final fileContent = await file.readAsString();

      // Use RegEx to find the path to the associated directory
      final regEx = RegExp(r'files/(\d+(-[a-zA-Z0-9]+)*(-[A-Z]+)?)/');
      final match = regEx.firstMatch(fileContent);

      if (match != null) {
        final directoryName = match.group(1);
        final associatedDirectoryPath = '${directory
            .path}/files/$directoryName';

        // Delete the file
        await file.delete();
        print('Deleted file: $filePath');

        // Delete the associated directory
        final associatedDirectory = Directory(associatedDirectoryPath);
        if (associatedDirectory.existsSync()) {
          await associatedDirectory.delete(recursive: true);
          print('Deleted directory: $associatedDirectoryPath');
        } else {
          print('Associated directory not found: $associatedDirectoryPath');
        }

        // Update state to remove the deleted module
        setState(() {
          modules.removeWhere((module) => module.path == filePath);
        });
      } else {
        print('No associated directory found in file: $filePath');
      }
    } catch (e) {
      print('Error deleting file or directory: $e');
    }
  }

  Future<void> saveModuleId(String moduleId) async {
    await secureStorage.write(key: "module_id", value: moduleId);
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
                      print("Navigating to menu. Logged in: $isLoggedIn");
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
                          'You have not downloaded any modules yet. Please download the modules first.',
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
                                        color: Colors.black.withOpacity(0.3),
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
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Module Name: ",
                                            style: TextStyle(
                                              fontSize: scalingFactor * (isTablet(context) ? 14 : 16),
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF646BFF),
                                            ),
                                            textAlign: TextAlign.center, // Center the text
                                          ),
                                          SizedBox(width: scalingFactor * (isTablet(context) ? 5 : 7)), // Space between text and buttons
                                          Expanded(
                                            child: Text(
                                              moduleFile.title,
                                              style: TextStyle(
                                                fontSize: scalingFactor * (isTablet(context) ? 14 : 16),
                                                fontWeight: FontWeight.w500,
                                                color: Colors.black,
                                              ),
                                              //textAlign: TextAlign.start, // Center the text
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: scalingFactor * (isTablet(context) ? 0.04 : 0.04)), // Space between text and buttons
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Module Id: ",
                                            style: TextStyle(
                                              fontSize: scalingFactor * (isTablet(context) ? 14 : 16),
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF646BFF),
                                            ),
                                            textAlign: TextAlign.center, // Center the text
                                          ),
                                          SizedBox(width: scalingFactor * (isTablet(context) ? 5 : 7)), // Space between text and buttons
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
                                                fontSize: scalingFactor * (isTablet(context) ? 14 : 16),
                                                fontWeight: FontWeight.w500,
                                                color: Colors.black,
                                              ),
                                              //textAlign: TextAlign.start, // Center the text
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: scalingFactor * (isTablet(context) ? 20 : 20)), // Space between text and buttons
                                      // Buttons (Play and Delete)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          // Play Button
                                          Expanded(
                                            child: Semantics(
                                              label: 'Play Button',
                                              hint: 'Tap to play the module',
                                              child: GestureDetector(
                                                onTap: () {
                                                  saveModuleId(moduleFile.moduleId!);
                                                  print( "Saving module id: $moduleFile.moduleId");
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => WebViewScreen(
                                                        urlRequest: URLRequest(
                                                          url: Uri.file(moduleFile.path),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: FractionallySizedBox(
                                                  widthFactor: isTablet(context) ? 0.45 : 0.65,
                                                  child: Container(
                                                    height: scalingFactor * (isTablet(context) ? 34 : 54),
                                                    decoration: BoxDecoration(
                                                      gradient: const LinearGradient(
                                                        colors: [
                                                          Color(0xFF1A4314),
                                                          Color(0xFF3E8914),
                                                          Color(0xFF74B72E),
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
                                                        double fontSize = buttonWidth * 0.2;
                                                        double padding = buttonWidth * 0.02;
                                                        return Padding(
                                                          padding: EdgeInsets.all(padding),
                                                          child: Row(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Text(
                                                                "Play",
                                                                style: TextStyle(
                                                                  fontSize: fontSize,
                                                                  fontWeight: FontWeight.w500,
                                                                  color: Color(0xFFE8E8E8),
                                                                ),
                                                              ),
                                                              SizedBox(width: padding),
                                                              Icon(
                                                                Icons.play_arrow,
                                                                color: Color(0xFFE8E8E8),
                                                                size: fontSize * 1.4,
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

                                          // Submit Button
                                          Expanded(
                                            child: Semantics(
                                              label: 'Submit Button',
                                              hint: 'Tap to submit the module',
                                              child: GestureDetector(
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => AuthGuard(
                                                        child: EnterScore(
                                                          moduleId: moduleFile.moduleId,
                                                          moduleName: moduleFile.title,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: FractionallySizedBox(
                                                  widthFactor: isTablet(context) ? 0.45 : 0.65,
                                                  child: Container(
                                                    height: scalingFactor * (isTablet(context) ? 34 : 54),
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
                                                        double fontSize = buttonWidth * 0.2;
                                                        double padding = buttonWidth * 0.02;
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
                                                  _showDeleteConfirmation(moduleFile.file.path.split('/').last);
                                                },
                                                child: FractionallySizedBox(
                                                  widthFactor: isTablet(context) ? 0.45 : 0.65,
                                                  child: Container(
                                                    height: scalingFactor * (isTablet(context) ? 34 : 54),
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
                                                        double fontSize = buttonWidth * 0.2;
                                                        double padding = buttonWidth * 0.02;
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
                          'You have not downloaded any modules yet. Please download the modules first.',
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
                                        color: Colors.black.withOpacity(0.3),
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
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Module Name: ",
                                            style: TextStyle(
                                              fontSize: scalingFactor * (isTablet(context) ? 14 : 14),
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF646BFF),
                                            ),
                                            textAlign: TextAlign.center, // Center the text
                                          ),
                                          SizedBox(width: scalingFactor * (isTablet(context) ? 5 : 5)), // Space between text and buttons
                                          Expanded(
                                            child: Text(
                                              moduleFile.title,
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
                                      SizedBox(height: scalingFactor * (isTablet(context) ? 5 : 5)), // Space between text and buttons
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Module Id: ",
                                            style: TextStyle(
                                              fontSize: scalingFactor * (isTablet(context) ? 14 : 14),
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF646BFF),
                                            ),
                                            textAlign: TextAlign.center, // Center the text
                                          ),
                                          SizedBox(width: scalingFactor * (isTablet(context) ? 5 : 5)), // Space between text and buttons
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
                                      SizedBox(height: scalingFactor * (isTablet(context) ? 20 : 20)), // Space between text and buttons
                                      // Buttons (Play and Delete)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          // Play Button
                                          Expanded(
                                            child: Semantics(
                                              label: 'Play Button',
                                              hint: 'Tap to play the module',
                                              child: GestureDetector(
                                                onTap: () {
                                                  saveModuleId(moduleFile.moduleId!);
                                                  print( "Saving module id: $moduleFile.moduleId");
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => WebViewScreen(
                                                        urlRequest: URLRequest(
                                                          url: Uri.file(moduleFile.path),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: FractionallySizedBox(
                                                  widthFactor: isTablet(context) ? 0.45 : 0.45,
                                                  child: Container(
                                                    height: scalingFactor * (isTablet(context) ? 35 : 44),
                                                    decoration: BoxDecoration(
                                                      gradient: const LinearGradient(
                                                        colors: [
                                                          Color(0xFF1A4314),
                                                          Color(0xFF3E8914),
                                                          Color(0xFF74B72E),
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
                                                        double fontSize = buttonWidth * 0.2;
                                                        double padding = buttonWidth * 0.02;
                                                        return Padding(
                                                          padding: EdgeInsets.all(padding),
                                                          child: Row(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Text(
                                                                "Play",
                                                                style: TextStyle(
                                                                  fontSize: fontSize,
                                                                  fontWeight: FontWeight.w500,
                                                                  color: Color(0xFFE8E8E8),
                                                                ),
                                                              ),
                                                              SizedBox(width: padding),
                                                              Icon(
                                                                Icons.play_arrow,
                                                                color: Color(0xFFE8E8E8),
                                                                size: fontSize * 1.4,
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

                                          // Submit Button
                                          Expanded(
                                            child: Semantics(
                                              label: 'Submit Button',
                                              hint: 'Tap to submit the module',
                                              child: GestureDetector(
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => AuthGuard(
                                                        child: EnterScore(
                                                          moduleId: moduleFile.moduleId,
                                                          moduleName: moduleFile.title,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: FractionallySizedBox(
                                                  widthFactor: isTablet(context) ? 0.45 : 0.45,
                                                  child: Container(
                                                    height: scalingFactor * (isTablet(context) ? 35 : 44),
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
                                                        double fontSize = buttonWidth * 0.2;
                                                        double padding = buttonWidth * 0.02;
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
                                                  _showDeleteConfirmation(moduleFile.file.path.split('/').last);
                                                },
                                                child: FractionallySizedBox(
                                                  widthFactor: isTablet(context) ? 0.45 : 0.45,
                                                  child: Container(
                                                    height: scalingFactor * (isTablet(context) ? 35 : 44),
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
                                                        double fontSize = buttonWidth * 0.2;
                                                        double padding = buttonWidth * 0.02;
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
}
