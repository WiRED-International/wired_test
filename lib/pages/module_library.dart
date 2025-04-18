import '.././utils/webview_screen.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/auth_guard.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'cme/cme_tracker.dart';
import 'home_page.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';


class ModuleLibrary extends StatefulWidget {

  @override
  _ModuleLibraryState createState() => _ModuleLibraryState();
}

class ModuleFile {
  final FileSystemEntity file;
  final String path;
  final String moduleName;
  final String moduleId;


  ModuleFile({required this.file, required this.path, required this.moduleName, required this.moduleId});
}

enum DisplayType { modules, resources }

class _ModuleLibraryState extends State<ModuleLibrary> {
  late Future<List<ModuleFile>> futureModules;
  late Future<List<FileSystemEntity>> futureResources; // For PDF resources
  List<ModuleFile> modules = [];
  List<FileSystemEntity> resources = []; // Store PDF files
  DisplayType selectedType = DisplayType.modules; // To track whether Modules or Resources are selected

  @override
  void initState() {
    super.initState();
    testStoragePath();
    futureModules = _fetchModules();
    futureResources = _fetchResources(); // Fetch the resources
  }

  String? extractModuleId(String content) {
    final regex = RegExp(r'content="0; url=files/(\d+)/story.html"'); // Adjust regex if needed
    final match = regex.firstMatch(content);
    return match?.group(1); // Return the captured group (module ID)
  }

  String? extractPackageModuleId(String content) {
    final regex = RegExp(r'content="0; url=files/(\d{4})/([^/]+)/story.html"');
    final match = regex.firstMatch(content);
    return match?.group(2); // Return the captured group (module ID)
  }

Future<void> testStoragePath() async {
  final directory = await getStoragePath();
  print("DEBUG: getStoragePath() returned -> $directory");
  if (directory == null) {
    print("ERROR: getStoragePath() returned NULL!");
  } else {
    print("DEBUG: directory.path -> ${directory.path}");
  }
}

Future<Directory> getStoragePath() async {
  Directory directory;

  if (Platform.isAndroid) {
    directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();  
  } else if (Platform.isIOS || Platform.isMacOS) {
    directory = await getApplicationSupportDirectory();
  } else if (Platform.isWindows || Platform.isLinux) {
    directory = await getApplicationDocumentsDirectory();
  } else {
    throw Exception("Unsupported platform");
  }

  print("DEBUG: getStoragePath() returning -> ${directory.path}");
  return directory;
}

  Future<List<ModuleFile>> _fetchModules() async {
    final directory = await getStoragePath();
    if (directory == null) {
    print("ERROR: getStoragePath() returned NULL in _fetchModules()");
    return [];
    }

      final packagesDirectory = Directory('${directory.path}/packages');
      final modulesDirectory = Directory('${directory.path}/modules');

      print("DEBUG: Checking directories -> Packages: ${packagesDirectory.path}, Modules: ${modulesDirectory.path}");

      List<ModuleFile> fetchedModules = [];

      // Process files in packages directory
      if (packagesDirectory.existsSync()) {
        final packageFiles = packagesDirectory.listSync().whereType<File>().toList();
        print("DEBUG: Found ${packageFiles.length} package files.");
        fetchedModules.addAll(packageFiles.map((file) {
          String fileName = file.path.split('/').last.replaceAll('.htm', '');

          String? moduleId;
          try {
            final content = file.readAsStringSync(); // Read file content
            moduleId = extractPackageModuleId(content); // Extract module ID
          } catch (e) {
            print("Error reading file: ${file.path}, $e");
          }

          return ModuleFile(
            file: file,
            path: file.path,
            moduleName: fileName,
            moduleId: moduleId ?? fileName, // Fallback to fileName if ID not found
          );
        }).toList());
      }

      // Process files in modules directory
      if (modulesDirectory.existsSync()) {
        final moduleFiles = modulesDirectory.listSync().whereType<File>().toList();
        print("DEBUG: Found ${moduleFiles.length} module files.");
        fetchedModules.addAll(moduleFiles.map((file) {
          String fileName = file.path.split('/').last.replaceAll('.htm', '');

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
            moduleName: fileName,
            moduleId: moduleId ?? fileName, // Fallback to fileName if ID not found
          );
        }).toList());
      }

      fetchedModules.sort((a, b) => a.moduleName.compareTo(b.moduleName));

      setState(() {
        modules = fetchedModules;
      });

      return fetchedModules;
  }

  Future<List<FileSystemEntity>> _fetchResources() async {
    final directory = await getStoragePath();
    if (directory != null) {
      final dir = Directory(directory.path);

      setState(() {
        resources = dir.listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.pdf')) // Only PDF files
            .toList();
      });
      return resources;
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
          content: Text("Are you sure you want to delete the module: $fileName?"),
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
                deleteFileAndAssociatedDirectory(fileName); // Call the delete function after confirmation
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
      final directory = await getStoragePath();
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
        final associatedDirectoryPath = '$directory/files/$directoryName';

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

  Future<void> saveModuleInfo(String moduleId, String moduleName) async {
    //await secureStorage.deleteAll();
    await secureStorage.write(key: "module_id", value: moduleId);
    await secureStorage.write(key: "module_name", value: moduleName);
    print("✅ Module Info Saved: ID: $moduleId, Name: $moduleName");

    String? savedModuleId = await secureStorage.read(key: "module_id");
    String? savedModuleName = await secureStorage.read(key: "module_name");
    print("🔍 Stored Module ID: $savedModuleId");
    print("🔍 Stored Module Name: $savedModuleName");
  }




  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    var baseSize = MediaQuery.of(context).size.shortestSide;
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

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
                  requireAuth: false,
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
                              MaterialPageRoute(builder: (context) => const MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            // Intentionally left blank
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
                              ? _buildLandscapeLayout(screenWidth, screenHeight, baseSize)
                              : _buildPortraitLayout(screenWidth, screenHeight, baseSize),
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
                      // Intentionally left blank
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

      Widget _buildPortraitLayout(screenWidth, screenHeight, baseSize) {
        return Column(
          children: [
            SizedBox(
              height: baseSize * (isTablet(context) ? 0.031 : 0.031),
            ),
            Text(
              "My Library",
              style: TextStyle(
                fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
                fontWeight: FontWeight.w500,
                color: Color(0xFF0070C0),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(
              height: baseSize * (isTablet(context) ? 0.02 : 0.02),
            ),
            // Display appropriate list based on selectedType
            SizedBox(
              height: baseSize * (isTablet(context) ? 0.02 : 0.02),
            ),
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(10), // Top left corner
                    topRight: Radius.circular(10), // Top right corne
                  ),
                  color: const Color(0x00000000),
                  border: Border(
                    top: BorderSide(color: Colors.black, width: 2), // Top border
                    left: BorderSide(color: Colors.black, width: 2), // Left border
                    right: BorderSide(color: Colors.black, width: 2), // Right border
                  ),
                ),
                child: Stack(
                  children: [
                    Container(
                      //height: baseSize * (isTablet(context) ? 0.97 : 1.1),
                      child: FutureBuilder<List<ModuleFile>>(
                        future: futureModules,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          } else if (snapshot.hasError) {
                            return const Center(child: Text('Error loading modules'));
                          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return const Center(
                                child: Text(
                                    'You have not downloaded any modules yet. Please download the modules first.',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF548235),
                                  ),
                                  textAlign: TextAlign.center,
                                ));
                          } else {
                            return ListView.builder(
                                itemCount: snapshot.data!.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == snapshot.data!.length) {

                                    return SizedBox(
                                      height: baseSize * (isTablet(context) ? 0.135 : 0.135),// This is the last item
                                    );
                                  }
                                  final moduleFile = snapshot.data![index];

                                  return Column(
                                    children: [
                                      Container(
                                        height: baseSize * (isTablet(context) ? 0.18 : 0.18),
                                        child: Padding(
                                          padding: EdgeInsets.all(baseSize * 0.02),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              // Module name text (Expanded to take available space)
                                              Expanded(
                                                child: Text(
                                                  moduleFile.moduleName,
                                                  style: TextStyle(
                                                    fontSize: baseSize * (isTablet(context) ? 0.0385 : 0.044),
                                                    fontWeight: FontWeight.w300,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                              ),
                                              // Buttons (Play and Delete)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SizedBox(width: baseSize * 0.02), // spacing between text and buttons
                                                  // Play button
                                                  Container(
                                                    height: baseSize * (isTablet(context) ? 0.09 : 0.11), // button height
                                                    width: baseSize * (isTablet(context) ? 0.13 : 0.13),   // button width
                                                    decoration: BoxDecoration(
                                                      gradient: const LinearGradient(
                                                        begin: Alignment.centerLeft,
                                                        end: Alignment.centerRight,
                                                        colors: [
                                                          Color(0xFF87C9F8),
                                                          Color(0xFF70E1F5),
                                                        ],
                                                      ),
                                                      borderRadius: BorderRadius.circular(5),
                                                    ),
                                                    child: GestureDetector(
                                                      onTap: () {
                                                        saveModuleInfo(moduleFile.moduleId, moduleFile.moduleName);
                                                        print( "Saving module id: $moduleFile.moduleId");
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (context) => WebViewScreen(
                                                              urlRequest: URLRequest(url: WebUri(Uri.file(moduleFile.path).toString())),
                                                              moduleId: moduleFile.moduleId, // ✅ Pass module ID
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                      child: FittedBox(
                                                        fit: BoxFit.scaleDown, // Ensures the content scales down if too large
                                                        child: Column(
                                                          mainAxisAlignment: MainAxisAlignment.center, // Center vertically
                                                          crossAxisAlignment: CrossAxisAlignment.center, // Center horizontally
                                                          children: [
                                                            Icon(
                                                              Icons.play_arrow,
                                                              color: Color(0xFF545454),
                                                              size: baseSize * (isTablet(context) ? 0.07 : 0.07),
                                                            ),
                                                            Text(
                                                              "Play",
                                                              style: TextStyle(
                                                                fontSize: baseSize * (isTablet(context) ? 0.04 : 0.04),
                                                                fontWeight: FontWeight.w500,
                                                                color: Color(0xFF545454),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(width: baseSize * 0.02), // Spacing between buttons

                                                  // Delete button
                                                  Container(
                                                    height: baseSize * (isTablet(context) ? 0.09 : 0.11), // Increase the button height
                                                    width: baseSize * (isTablet(context) ? 0.13 : 0.13),   // Increase the button width
                                                    decoration: BoxDecoration(
                                                      gradient: const LinearGradient(
                                                        begin: Alignment.centerLeft,
                                                        end: Alignment.centerRight,
                                                        colors: [
                                                          Color(0xFF70E1F5),
                                                          Color(0xFF86A8E7),
                                                        ],
                                                      ),
                                                      borderRadius: BorderRadius.circular(5),
                                                    ),
                                                    child: GestureDetector(
                                                      onTap: () {
                                                        print("Delete tapped");
                                                        _showDeleteConfirmation(moduleFile.file.path.split('/').last);
                                                      },
                                                      child: FittedBox(
                                                        child: Column(
                                                          mainAxisAlignment: MainAxisAlignment.center, // Center vertically
                                                          crossAxisAlignment: CrossAxisAlignment.center, // Center horizontally
                                                          children: [
                                                            Icon(
                                                              Icons.delete,
                                                              color: Color(0xFF545454),
                                                              size: baseSize * (isTablet(context) ? 0.07 : 0.07), // Adjust icon size
                                                            ),
                                                            Text(
                                                              "Delete",
                                                              style: TextStyle(
                                                                fontSize: baseSize * (isTablet(context) ? 0.04 : 0.04), // Adjust text size
                                                                fontWeight: FontWeight.w500,
                                                                color: Color(0xFF545454),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Container(
                                        height: 2,
                                        color: Colors.grey,
                                      )
                                    ],
                                  );

                                }
                            );
                          }
                        },
                      ),
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
            ),
          ],
        );
      }

Widget _buildLandscapeLayout(screenWidth, screenHeight, baseSize) {
    var baseSize = MediaQuery.of(context).size.shortestSide;
    return Column(
      children: [
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.03 : 0.03),
        ),
        Text(
          "My Library",
          style: TextStyle(
            fontSize: baseSize * (isTablet(context) ? 0.08 : 0.08),
            fontWeight: FontWeight.w500,
            color: Color(0xFF0070C0),
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.02 : 0.02),
        ),

        // Display appropriate list based on selectedType
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.02 : 0.02),
        ),
        Flexible(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10), // Top left corner
                topRight: Radius.circular(10), // Top right corne
              ),
              color: const Color(0x00000000),
              border: Border(
                top: BorderSide(color: Colors.black, width: 2), // Top border
                left: BorderSide(color: Colors.black, width: 2), // Left border
                right: BorderSide(color: Colors.black, width: 2), // Right border
              ),
            ),
            child: Stack(
              children: [
                Container(
                  //height: baseSize * (isTablet(context) ? 0.6 : 0.6),
                  child: FutureBuilder<List<ModuleFile>>(
                    future: futureModules,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return const Center(child: Text('Error loading modules'));
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(child: Text('No modules found'));
                      } else {
                        return ListView.builder(
                            itemCount: snapshot.data!.length + 1,
                            itemBuilder: (context, index) {
                              if (index == snapshot.data!.length) {

                                return SizedBox(
                                  //height: 120,// This is the last item
                                  height: baseSize * (isTablet(context) ? 0.135 : 0.135),
                                );
                              }
                              final moduleFile = snapshot.data![index];

                              return Column(
                                children: [
                                  Container(
                                    height: baseSize * (isTablet(context) ? 0.18 : 0.18), // height of the parent container
                                    child: Padding(
                                      padding: EdgeInsets.all(baseSize * 0.02),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center, // Align items to the center
                                        children: [
                                          // Module name text (Expanded to take available space)
                                          Expanded(
                                            child: Text(
                                              moduleFile.moduleName,
                                              style: TextStyle(
                                                fontSize: baseSize * (isTablet(context) ? 0.04 : 0.04),
                                                fontWeight: FontWeight.w300,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ),
                                          // Buttons (Play and Delete)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Play button
                                              Container(
                                                height: baseSize * (isTablet(context) ? 0.1 : 0.11), // button height
                                                width: baseSize * (isTablet(context) ? 0.14 : 0.14),   // button width
                                                decoration: BoxDecoration(
                                                  gradient: const LinearGradient(
                                                    begin: Alignment.centerLeft,
                                                    end: Alignment.centerRight,
                                                    colors: [
                                                      Color(0xFF87C9F8),
                                                      Color(0xFF70E1F5),
                                                    ],
                                                  ),
                                                  borderRadius: BorderRadius.circular(5),
                                                ),
                                                child: GestureDetector(
                                                  onTap: () {
                                                    saveModuleInfo(moduleFile.moduleId, moduleFile.moduleName);
                                                    print( "Saving module id: $moduleFile.moduleId");
                                                    // Play the module
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) => WebViewScreen(
                                                          urlRequest: URLRequest(url: WebUri(Uri.file(moduleFile.path).toString())),
                                                          moduleId: moduleFile.moduleId, // ✅ Pass module ID
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  child: FittedBox(
                                                    fit: BoxFit.scaleDown, // Ensures the content scales down if too large
                                                    child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.center, // Center vertically
                                                      crossAxisAlignment: CrossAxisAlignment.center, // Center horizontally
                                                      children: [
                                                        Icon(
                                                          Icons.play_arrow,
                                                          color: Color(0xFF545454),
                                                          size: baseSize * (isTablet(context) ? 0.07 : 0.07), // icon size
                                                        ),
                                                        Text(
                                                          "Play",
                                                          style: TextStyle(
                                                            fontSize: baseSize * (isTablet(context) ? 0.04 : 0.04),
                                                            fontWeight: FontWeight.w500,
                                                            color: Color(0xFF545454),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: baseSize * 0.02), // Spacing between buttons

                                              // Delete button
                                              Container(
                                                height: baseSize * (isTablet(context) ? 0.1 : 0.11), // button height
                                                width: baseSize * (isTablet(context) ? 0.14 : 0.14),   // button width
                                                decoration: BoxDecoration(
                                                  gradient: const LinearGradient(
                                                    begin: Alignment.centerLeft,
                                                    end: Alignment.centerRight,
                                                    colors: [
                                                      Color(0xFF70E1F5),
                                                      Color(0xFF86A8E7),
                                                    ],
                                                  ),
                                                  borderRadius: BorderRadius.circular(5),
                                                ),
                                                child: GestureDetector(
                                                  onTap: () {
                                                    print("Delete tapped");
                                                    _showDeleteConfirmation(moduleFile.file.path.split('/').last);
                                                  },
                                                  child: FittedBox(
                                                    child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.center, // Center vertically
                                                      crossAxisAlignment: CrossAxisAlignment.center, // Center horizontally
                                                      children: [
                                                        Icon(
                                                          Icons.delete,
                                                          color: Color(0xFF545454),
                                                          size: baseSize * (isTablet(context) ? 0.07 : 0.07),
                                                        ),
                                                        Text(
                                                          "Delete",
                                                          style: TextStyle(
                                                            fontSize: baseSize * (isTablet(context) ? 0.04 : 0.04),
                                                            fontWeight: FontWeight.w500,
                                                            color: Color(0xFF545454),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Container(
                                    height: 2,
                                    color: Colors.grey,
                                  )
                                ],
                              );

                            }
                        );
                      }
                    },
                  ),
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
        ),
      ],
    );
  }
}