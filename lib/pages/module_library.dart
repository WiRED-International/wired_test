import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_svg/svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wired_test/pages/policy.dart';
import '.././utils/webview_screen.dart';
import '../main.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'home_page.dart';


class ModuleLibrary extends StatefulWidget {

  @override
  _ModuleLibraryState createState() => _ModuleLibraryState();
}

class ModuleFile {
  final FileSystemEntity file;
  final String path;


  ModuleFile({required this.file, required this.path});
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
    futureModules = _fetchModules();
    futureResources = _fetchResources(); // Fetch the resources
  }

  Future<List<ModuleFile>> _fetchModules() async {
    final directory = await getExternalStorageDirectory();
    if (directory != null) {
      // Get all files from the directory
      setState(() {
        modules = directory
            .listSync()
            .whereType<File>()
            .map((file) => ModuleFile(file: file, path: file.path))
            .toList();
      });
      // check this later
      return modules;
    } else {
      return [];
    }
  }

  Future<List<FileSystemEntity>> _fetchResources() async {
    final directory = await getExternalStorageDirectory();
    if (directory != null) {
      setState(() {
        resources = directory
            .listSync()
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
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        return;
      }
      // Define the path to the file
      final filePath = '${directory.path}/$fileName';

      // Read the htm file
      final file = File(filePath);
      print('attempting to delete file: $filePath');
      if (!await file.exists()) {
        print('File not found: $filePath');
        return;
      }

      final fileContent = await file.readAsString();
      print('File content read successfully: ${fileContent.substring(0, 150)}...');

      // Use RegEx to find the path to the directory
      final regEx = RegExp(r'files/(\d+(-[a-zA-Z0-9]+(-\d+)?|\d+[a-zA-Z0-9])?)/');
      final match = regEx.firstMatch(fileContent);
      print('match: $match');
      if (match != null) {
        final directoryName = match.group(1);
        final directoryPath = '${directory.path}/files/$directoryName';
        print('directoryPath resolved to: $directoryPath');

        // Delete HTM file
        await file.delete();
        print('Deleted file: $filePath');

        // Delete directory
        final dir = Directory(directoryPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          print('Deleted directory: $directoryPath');

        } else {
          print('Directory not found: $directoryPath');
        }

        // Update the state to remove the deleted file from the list
        setState(() {
          modules.removeWhere((module) => module.path == filePath);
        });

      } else if (match == null) {
        print('No match found in file: $filePath');
        return;
      }
    } catch (e) {
      print('Error deleting file or directory: $e');
      return;
    }
  }


  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
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
                              MaterialPageRoute(builder: (context) => MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            print("library tapped");
                            // Navigator.push(
                            //   context,
                            //   MaterialPageRoute(builder: (context) => ModuleLibrary()),
                            // );
                          },
                          onHelpTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const Policy()),
                            );
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(screenWidth, screenHeight)
                              : _buildPortraitLayout(screenWidth, screenHeight),
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
                      print("Library tapped");
                      // Navigator.push(
                      //   context,
                      //   MaterialPageRoute(builder: (context) => ModuleLibrary()),
                      // );
                    },
                    onHelpTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const Policy()),
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

      Widget _buildPortraitLayout(screenWidth, screenHeight) {
        var baseSize = MediaQuery.of(context).size.shortestSide;
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
            // Display the modules or resources
            Container(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedType = DisplayType.modules;
                        });
                      },
                      child: Container(
                          height: baseSize * (isTablet(context) ? 0.075 : 0.075),
                          color: selectedType == DisplayType.modules
                              ? Colors.white
                              : Colors.grey[300],
                          child: Center(
                            child: Text(
                              "Modules",
                              style: TextStyle(
                                fontSize: baseSize * (isTablet(context) ? 0.0535 : 0.0535),
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                              ),
                            ),
                          )
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: baseSize * (isTablet(context) ? 0.075 : 0.075),
                    color: Colors.black,
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedType = DisplayType.resources;
                        });
                      },
                      child: Container(
                          height: baseSize * (isTablet(context) ? 0.075 : 0.075),
                          color: Colors.white,
                          child: Center(
                            child: Text(
                              "Resources",
                              style: TextStyle(
                                fontSize: baseSize * (isTablet(context) ? 0.0535 : 0.0535),
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                              ),
                            ),
                          )
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Display appropriate list based on selectedType
            SizedBox(
              height: baseSize * (isTablet(context) ? 0.02 : 0.02),
            ),
            Stack(
              children: [
                Container(
                  height: baseSize * (isTablet(context) ? 0.97 : 1.1),
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
                                  height: baseSize * (isTablet(context) ? 0.135 : 0.135),// This is the last item (the SizedBox or Container)
                                );
                              }
                              final moduleFile = snapshot.data![index];
                              // start here to add the fade functionality and scroll functionality. Use module info as reference.
                              return Column(
                                children: [
                                  Container(
                                    height: baseSize * (isTablet(context) ? 0.18 : 0.18), // Increased height of the parent container
                                    child: Padding(
                                      padding: EdgeInsets.all(baseSize * 0.02), // Adjust padding as needed
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center, // Align items to the center
                                        children: [
                                          // Module name text (Expanded to take available space)
                                          Expanded(
                                            child: Text(
                                              moduleFile.file.path.split('/').last,
                                              style: TextStyle(
                                                fontSize: baseSize * (isTablet(context) ? 0.0385 : 0.0485),
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
                                                height: baseSize * (isTablet(context) ? 0.09 : 0.09), // Increase the button height
                                                width: baseSize * (isTablet(context) ? 0.13 : 0.13),   // Increase the button width
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
                                                    // Play the module
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                          builder: (context) => WebViewScreen(
                                                            urlRequest: URLRequest(
                                                              url: Uri.file(moduleFile.path),
                                                            ),
                                                          )),
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
                                                          size: baseSize * (isTablet(context) ? 0.07 : 0.07), // Adjust icon size
                                                        ),
                                                        Text(
                                                          "Play",
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
                                              SizedBox(width: baseSize * 0.02), // Spacing between buttons

                                              // Delete button
                                              Container(
                                                height: baseSize * (isTablet(context) ? 0.09 : 0.09), // Increase the button height
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
          ],
        );
      }

Widget _buildLandscapeLayout(screenWidth, screenHeight) {
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
        // Display the modules or resources
        Container(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedType = DisplayType.modules;
                    });
                  },
                  child: Container(
                      height: baseSize * (isTablet(context) ? 0.075 : 0.075),
                      color: selectedType == DisplayType.modules
                          ? Colors.white
                          : Colors.grey[300],
                      child: Center(
                        child: Text(
                          "Modules",
                          style: TextStyle(
                            fontSize: baseSize * (isTablet(context) ? 0.0535 : 0.0535),
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      )
                  ),
                ),
              ),
              Container(
                width: 1,
                height: baseSize * (isTablet(context) ? 0.075 : 0.075),
                color: Colors.black,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedType = DisplayType.resources;
                    });
                  },
                  child: Container(
                      height: baseSize * (isTablet(context) ? 0.075 : 0.075),
                      color: Colors.white,
                      child: Center(
                        child: Text(
                          "Resources",
                          style: TextStyle(
                            fontSize: baseSize * (isTablet(context) ? 0.0535 : 0.0535),
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      )
                  ),
                ),
              ),
            ],
          ),
        ),
        // Display appropriate list based on selectedType
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.02 : 0.02),
        ),
        Stack(
          children: [
            Container(
              height: baseSize * (isTablet(context) ? 0.6 : 0.6),
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
                              //height: 120,// This is the last item (the SizedBox or Container)
                              height: baseSize * (isTablet(context) ? 0.135 : 0.135),
                            );
                          }
                          final moduleFile = snapshot.data![index];

                          return Column(
                            children: [
                              Container(
                                height: baseSize * (isTablet(context) ? 0.18 : 0.18), // Increased height of the parent container
                                child: Padding(
                                  padding: EdgeInsets.all(baseSize * 0.02), // Adjust padding as needed
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center, // Align items to the center
                                    children: [
                                      // Module name text (Expanded to take available space)
                                      Expanded(
                                        child: Text(
                                          moduleFile.file.path.split('/').last,
                                          style: TextStyle(
                                            fontSize: baseSize * (isTablet(context) ? 0.0485 : 0.0485),
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
                                            height: baseSize * (isTablet(context) ? 0.1 : 0.1), // Increase the button height
                                            width: baseSize * (isTablet(context) ? 0.14 : 0.14),   // Increase the button width
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
                                                // Play the module
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                      builder: (context) => WebViewScreen(
                                                        urlRequest: URLRequest(
                                                          url: Uri.file(moduleFile.path),
                                                        ),
                                                      )),
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
                                                      size: baseSize * (isTablet(context) ? 0.07 : 0.07), // Adjust icon size
                                                    ),
                                                    Text(
                                                      "Play",
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
                                          SizedBox(width: baseSize * 0.02), // Spacing between buttons

                                          // Delete button
                                          Container(
                                            height: baseSize * (isTablet(context) ? 0.1 : 0.1), // Increase the button height
                                            width: baseSize * (isTablet(context) ? 0.14 : 0.14),   // Increase the button width
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
      ],
    );
  }
}